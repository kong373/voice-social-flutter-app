package com.kong373.alipay_app_pay

import android.app.Activity
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
import java.util.concurrent.Executors
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
        internal const val PAYLOAD_FILE_NAME = "m5-alipay-native-isolation.json"
        internal const val RESULT_FILE_NAME = "m5-alipay-native-isolation-result.json"
        private val active = AtomicBoolean(false)
    }

    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val requestedRunId = intent?.getStringExtra(RUN_ID_EXTRA)
        val safeRunId = NativeAlipayIsolationContract.safeRunId(requestedRunId)
        if (safeRunId == null || !isDebuggable()) {
            failClosed(safeRunId, "INVALID_LAUNCH")
            return
        }
        if (!active.compareAndSet(false, true)) {
            failClosed(safeRunId, "ALREADY_ACTIVE")
            return
        }

        val resultFile = File(filesDir, RESULT_FILE_NAME)
        if (resultFile.exists() && !resultFile.delete()) {
            active.set(false)
            failClosed(safeRunId, "STALE_RESULT")
            return
        }

        val payloadFile = File(filesDir, PAYLOAD_FILE_NAME)
        val payload = readOneShotPayload(payloadFile, safeRunId)
        if (payload == null) {
            active.set(false)
            failClosed(safeRunId, "PAYLOAD_REJECTED")
            return
        }

        fixedMarker("START", safeRunId)
        val executor = Executors.newSingleThreadExecutor()
        executor.execute {
            val result = try {
                EnvUtils.setEnv(EnvUtils.EnvEnum.SANDBOX)
                val raw = PayTask(this).payV2(payload.orderString, true)
                NativeAlipayIsolationContract.classifyPayTaskReturn(raw["resultStatus"])
            } catch (_: RuntimeException) {
                NativeAlipayIsolationResult.nativeException()
            } catch (_: LinkageError) {
                NativeAlipayIsolationResult.nativeUnavailable()
            }
            val resultWritten = writeResultFile(resultFile, safeRunId, result)
            if (!resultWritten) {
                failMarker(safeRunId, "RESULT_WRITE_FAILED")
            } else if (result.bridgeOutcome == "pay_task_returned") {
                Log.i(
                    TAG,
                    "M5_ALIPAY_NATIVE_ISOLATION::PAYTASK_RETURN::$safeRunId::" +
                        "resultStatus=${result.resultStatus}::" +
                        "sdkCompleted=${if (result.sdkCompleted) 1 else 0}",
                )
            } else {
                failMarker(safeRunId, result.bridgeOutcome.uppercase())
            }
            active.set(false)
            executor.shutdown()
            mainHandler.post { finish() }
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
        finish()
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
