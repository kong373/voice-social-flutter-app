package com.kong373.alipay_app_pay

import android.app.Activity
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.alipay.sdk.app.EnvUtils
import com.alipay.sdk.app.PayTask
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.nio.charset.StandardCharsets
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Debug-only, same-application isolation lane for the official Alipay PayTask.
 *
 * The signed order is accepted only through a strict app-private one-shot
 * file. It is deleted before PayTask is invoked and is never placed in an
 * Intent, log, result file, exception message, or evidence artifact.
 */
class NativeAlipayIsolationActivity : Activity() {
    companion object {
        private const val TAG = "VoiceAlipayIsolation"
        private const val RUN_ID_EXTRA = "runId"
        private const val LEASE_ID_EXTRA = "alipayLeaseId"
        internal const val PAYLOAD_FILE_NAME = "m5-alipay-native-isolation.json"
        internal const val RESULT_FILE_NAME = "m5-alipay-native-isolation-result.json"
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val resultWriteGate = AlipaySingleWriteGate()
    private val finishPosted = AtomicBoolean(false)
    private var workerExecutor: ExecutorService? = null
    private var watchdogExecutor: ScheduledExecutorService? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val requestedRunId = intent?.getStringExtra(RUN_ID_EXTRA)
        val safeRunId = NativeAlipayIsolationContract.safeRunId(requestedRunId)
        val requestedWireId = AlipayPaymentGate.safeWireId(
            intent?.getStringExtra(LEASE_ID_EXTRA),
        )
        if (safeRunId == null || requestedWireId == null || !isDebuggable()) {
            if (safeRunId != null && requestedWireId != null) {
                AlipayNativeIsolationLaunchRegistry.completeFailed(
                    requestedWireId,
                    safeRunId,
                )
            }
            failClosed(safeRunId, "INVALID_LAUNCH")
            return
        }
        val owner = AlipayProcessPaymentGate.claim(
                requestedWireId,
                safeRunId,
                AlipayPaymentLane.NATIVE_ISOLATION,
            )
        if (owner == null) {
            // A duplicate Activity instance/reentry must not release the
            // lease owned by the original worker.
            failClosed(safeRunId, "ALREADY_ACTIVE")
            return
        }
        val resultFile = File(filesDir, RESULT_FILE_NAME)
        if (resultFile.exists() && !resultFile.delete()) {
            rejectAfterClaim(
                safeRunId,
                "STALE_RESULT",
                requestedWireId,
                owner,
            )
            return
        }

        val payloadFile = File(filesDir, PAYLOAD_FILE_NAME)
        val payload = readOneShotPayload(payloadFile, safeRunId)
        if (payload == null) {
            rejectAfterClaim(
                safeRunId,
                "PAYLOAD_REJECTED",
                requestedWireId,
                owner,
            )
            return
        }

        fixedMarker("START", safeRunId)
        var worker: ExecutorService? = null
        var watchdog: ScheduledExecutorService? = null
        try {
            worker = Executors.newSingleThreadExecutor()
            watchdog = Executors.newSingleThreadScheduledExecutor()
        } catch (_: RuntimeException) {
            worker?.shutdownNow()
            watchdog?.shutdownNow()
            rejectAfterClaim(
                safeRunId,
                "EXECUTOR_UNAVAILABLE",
                requestedWireId,
                owner,
            )
            return
        }
        val workerThread = worker
        if (workerThread == null) {
            rejectAfterClaim(
                safeRunId,
                "EXECUTOR_UNAVAILABLE",
                requestedWireId,
                owner,
            )
            return
        }
        val watchdogThread = watchdog
        if (watchdogThread == null) {
            workerThread.shutdownNow()
            rejectAfterClaim(
                safeRunId,
                "EXECUTOR_UNAVAILABLE",
                requestedWireId,
                owner,
            )
            return
        }
        workerExecutor = workerThread
        watchdogExecutor = watchdogThread
        val watchdogFuture: ScheduledFuture<*> = try {
            watchdogThread.schedule(
                {
                    publishWatchdogTimeout(resultFile, safeRunId)
                },
                AlipayPaymentTimeout.PAY_TIMEOUT_SECONDS,
                TimeUnit.SECONDS,
            )
        } catch (_: RejectedExecutionException) {
            workerThread.shutdownNow()
            watchdogThread.shutdownNow()
            workerExecutor = null
            watchdogExecutor = null
            completeWithoutWorker(
                resultFile,
                safeRunId,
                requestedWireId,
                owner,
                NativeAlipayIsolationResult.nativeUnavailable(),
            )
            return
        }
        try {
            workerThread.execute {
                var result = NativeAlipayIsolationResult.nativeUnavailable()
                try {
                    result = try {
                        EnvUtils.setEnv(EnvUtils.EnvEnum.SANDBOX)
                        val raw = PayTask(this).payV2(payload.orderString, true)
                        NativeAlipayIsolationContract.classifyPayTaskReturn(raw["resultStatus"])
                    } catch (_: RuntimeException) {
                        NativeAlipayIsolationResult.nativeException()
                    } catch (_: LinkageError) {
                        NativeAlipayIsolationResult.nativeUnavailable()
                    }
                } finally {
                    // Even an unexpected Error must not strand the global
                    // payment gate. The default safe result contains no SDK
                    // payload and cannot authorize payment or cancellation.
                    completeWorker(
                        watchdogFuture,
                        resultFile,
                        safeRunId,
                        owner,
                        result,
                    )
                }
            }
            AlipayNativeIsolationLaunchRegistry.completeStarted(
                requestedWireId,
                safeRunId,
            )
        } catch (_: RejectedExecutionException) {
            watchdogFuture.cancel(false)
            workerThread.shutdownNow()
            watchdogThread.shutdownNow()
            workerExecutor = null
            watchdogExecutor = null
            completeWithoutWorker(
                resultFile,
                safeRunId,
                requestedWireId,
                owner,
                NativeAlipayIsolationResult.nativeUnavailable(),
            )
        }
    }

    /** singleTask must not turn a second launch into a silent no-op. */
    override fun onNewIntent(intent: Intent?) {
        super.onNewIntent(intent)
        val safeRunId = NativeAlipayIsolationContract.safeRunId(
            intent?.getStringExtra(RUN_ID_EXTRA),
        )
        if (safeRunId == null) {
            Log.e(TAG, "M5_ALIPAY_NATIVE_ISOLATION::REENTRY_REJECTED")
        } else {
            failMarker(safeRunId, "REENTRY_REJECTED")
        }
        // Keep the original intent and worker untouched. No second PayTask is
        // started, and the original lease remains held until its worker
        // returns.
    }

    private fun rejectAfterClaim(
        runId: String,
        reason: String,
        wireId: String,
        owner: AlipayPaymentGate.ClaimedHandle,
    ) {
        AlipayNativeIsolationLaunchRegistry.completeFailed(wireId, runId)
        failMarker(runId, reason)
        finishAndRelease(owner)
    }

    private fun publishWatchdogTimeout(
        resultFile: File,
        runId: String,
    ) {
        val timeoutResult = NativeAlipayIsolationResult.nativeWatchdogTimeout()
        if (resultWriteGate.tryClaim()) {
            if (!writeResultFile(resultFile, runId, timeoutResult)) {
                failMarker(runId, "RESULT_WRITE_FAILED")
            } else {
                fixedMarker("WATCHDOG_TIMEOUT", runId)
            }
        }
        // Do not release the process lease here. PayTask may still be inside
        // the provider; completeWorker releases it only after that call
        // returns. The claimed owner capability remains private to this
        // Activity and worker.
        watchdogExecutor?.shutdown()
        finishOnce()
    }

    private fun completeWorker(
        watchdogFuture: ScheduledFuture<*>,
        resultFile: File,
        runId: String,
        owner: AlipayPaymentGate.ClaimedHandle,
        result: NativeAlipayIsolationResult,
    ) {
        try {
            watchdogFuture.cancel(false)
            if (resultWriteGate.tryClaim()) {
                val resultWritten = writeResultFile(resultFile, runId, result)
                if (!resultWritten) {
                    failMarker(runId, "RESULT_WRITE_FAILED")
                } else if (result.bridgeOutcome == "pay_task_returned") {
                    Log.i(
                        TAG,
                        "M5_ALIPAY_NATIVE_ISOLATION::PAYTASK_RETURN::$runId::" +
                            "resultStatus=${result.resultStatus}::" +
                            "sdkCompleted=${if (result.sdkCompleted) 1 else 0}",
                    )
                } else {
                    failMarker(runId, result.bridgeOutcome.uppercase())
                }
            }
        } finally {
            // This is deliberately after PayTask returns. If watchdog won the
            // result race, the late worker only releases the lease and never
            // overwrites the timeout file.
            workerExecutor?.shutdown()
            // Allow an already-running watchdog write to finish; the single
            // write gate still makes either side's result authoritative.
            watchdogExecutor?.shutdown()
            workerExecutor = null
            watchdogExecutor = null
            finishAndRelease(owner)
        }
    }

    private fun completeWithoutWorker(
        resultFile: File,
        runId: String,
        wireId: String,
        owner: AlipayPaymentGate.ClaimedHandle,
        result: NativeAlipayIsolationResult,
    ) {
        try {
            AlipayNativeIsolationLaunchRegistry.completeFailed(wireId, runId)
            if (resultWriteGate.tryClaim() && !writeResultFile(resultFile, runId, result)) {
                failMarker(runId, "RESULT_WRITE_FAILED")
            }
        } finally {
            finishAndRelease(owner)
        }
    }

    private fun finishOnce() {
        if (finishPosted.compareAndSet(false, true)) {
            mainHandler.post { finish() }
        }
    }

    /**
     * Keep the process gate held through the Activity finish call so a new
     * singleTask launch cannot be routed to an instance that is still closing.
     */
    private fun finishAndRelease(owner: AlipayPaymentGate.ClaimedHandle) {
        if (finishPosted.compareAndSet(false, true)) {
            val posted = mainHandler.post {
                finish()
                AlipayProcessPaymentGate.release(owner)
            }
            if (!posted) {
                // There is no runnable main loop left to process finish. Do
                // not strand the process gate in that terminal state.
                AlipayProcessPaymentGate.release(owner)
            }
        } else {
            // A watchdog may already have posted finish but not executed it.
            // Queue release behind that finish callback so a new singleTask
            // launch cannot reach an Activity that is still closing.
            val posted = mainHandler.post {
                AlipayProcessPaymentGate.release(owner)
            }
            if (!posted) {
                AlipayProcessPaymentGate.release(owner)
            }
        }
    }

    private fun readOneShotPayload(file: File, expectedRunId: String): NativeAlipayIsolationPayload? {
        val canonicalParent = try {
            file.canonicalFile.parentFile
        } catch (_: RuntimeException) {
            null
        }
        val expectedParent = try {
            filesDir.canonicalFile
        } catch (_: RuntimeException) {
            null
        }
        if (canonicalParent == null || canonicalParent != expectedParent ||
            !file.isFile || file.length() !in 1..NativeAlipayIsolationContract.MAX_PAYLOAD_BYTES) {
            return null
        }
        val raw = try {
            file.readText(StandardCharsets.UTF_8)
        } catch (_: RuntimeException) {
            return null
        }
        val payload = NativeAlipayIsolationContract.parsePayload(raw, expectedRunId)
        if (!file.delete()) {
            return null
        }
        return payload
    }

    private fun writeResultFile(
        file: File,
        runId: String,
        result: NativeAlipayIsolationResult,
    ): Boolean {
        val temporary = File(filesDir, "$RESULT_FILE_NAME.tmp")
        if (temporary.exists() && !temporary.delete()) {
            return false
        }
        val encoded = NativeAlipayIsolationContract.resultJson(runId, result)
        try {
            FileOutputStream(temporary, false).use { output ->
                output.write(encoded.toByteArray(StandardCharsets.UTF_8))
                output.fd.sync()
            }
            temporary.setReadable(false, false)
            temporary.setWritable(false, false)
            temporary.setReadable(true, true)
            temporary.setWritable(true, true)
            if (!temporary.renameTo(file)) {
                temporary.delete()
                return false
            }
            return true
        } catch (_: RuntimeException) {
            temporary.delete()
            return false
        }
    }

    private fun isDebuggable(): Boolean =
        applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0

    private fun failClosed(runId: String?, reason: String) {
        if (runId != null) {
            failMarker(runId, reason)
        }
        finishOnce()
    }

    private fun fixedMarker(stage: String, runId: String) {
        Log.i(TAG, "M5_ALIPAY_NATIVE_ISOLATION::$stage::$runId")
    }

    private fun failMarker(runId: String, reason: String) {
        Log.e(TAG, "M5_ALIPAY_NATIVE_ISOLATION::FAIL::$runId::reason=$reason")
    }
}

internal data class NativeAlipayIsolationPayload(
    val runId: String,
    val orderString: String,
)

internal data class NativeAlipayIsolationResult(
    val sdkCompleted: Boolean,
    val resultStatus: String,
    val bridgeOutcome: String,
) {
    companion object {
        fun nativeException() = NativeAlipayIsolationResult(false, "none", "native_exception")
        fun nativeUnavailable() = NativeAlipayIsolationResult(false, "none", "native_unavailable")
        fun nativeWatchdogTimeout() =
            NativeAlipayIsolationResult(false, "none", "native_watchdog_timeout")
    }
}

internal object NativeAlipayIsolationContract {
    const val MAX_ORDER_STRING_LENGTH = 64 * 1024
    const val MAX_PAYLOAD_BYTES = 70 * 1024L
    private val runIdPattern = Regex("^[a-f0-9]{32}$")
    private val allowedStatuses = setOf("9000", "8000", "6004", "6002", "6001", "4000")
    private val payloadKeys = setOf("runId", "sandbox", "orderStr")

    fun safeRunId(raw: String?): String? = raw?.takeIf(runIdPattern::matches)

    fun parsePayload(raw: String, expectedRunId: String): NativeAlipayIsolationPayload? {
        val objectValue = try {
            JSONObject(raw)
        } catch (_: RuntimeException) {
            return null
        }
        val keys = mutableSetOf<String>()
        val iterator = objectValue.keys()
        while (iterator.hasNext()) {
            keys.add(iterator.next())
        }
        if (keys != payloadKeys || safeRunId(expectedRunId) == null) {
            return null
        }
        val runId = objectValue.optString("runId", "")
        val sandbox = objectValue.opt("sandbox")
        val orderString = objectValue.opt("orderStr")
        if (runId != expectedRunId || sandbox !is Boolean || !sandbox || orderString !is String) {
            return null
        }
        if (orderString.isEmpty() || orderString.length > MAX_ORDER_STRING_LENGTH ||
            orderString.trim() != orderString ||
            orderString.any { it.code < 0x20 || it.code == 0x7f }) {
            return null
        }
        return NativeAlipayIsolationPayload(runId, orderString)
    }

    fun classifyPayTaskReturn(rawStatus: Any?): NativeAlipayIsolationResult {
        val status = (rawStatus as? String)?.takeIf(allowedStatuses::contains) ?: "none"
        return NativeAlipayIsolationResult(
            sdkCompleted = status == "9000",
            resultStatus = status,
            bridgeOutcome = "pay_task_returned",
        )
    }

    fun resultJson(runId: String, result: NativeAlipayIsolationResult): String =
        JSONObject(
            linkedMapOf(
                "runId" to runId,
                "sdkCompleted" to result.sdkCompleted,
                "resultStatus" to result.resultStatus,
                "bridgeOutcome" to result.bridgeOutcome,
            ),
        ).toString()
}
