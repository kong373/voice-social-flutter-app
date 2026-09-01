package com.kong373.alipay_app_pay

import android.app.Activity
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.alipay.sdk.app.EnvUtils
import com.alipay.sdk.app.PayTask
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/**
 * First-party bridge for the official Alipay App Pay Android SDK.
 *
 * This class accepts only a server-issued signed order string. It never
 * accepts or stores an app key, private key, public key, certificate, amount,
 * or order status authority. The reduced result map is provisional UI data;
 * the Flutter client must query its first-party backend afterwards.
 */
class AlipayAppPayPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    ActivityAware {
    companion object {
        private const val CHANNEL = "voice_social_app/alipay_app_pay"
        private const val MAX_ORDER_STRING_LENGTH = 64 * 1024
        private const val NATIVE_ISOLATION_TAG = "VoiceAlipayIsolation"
        private const val NATIVE_LAUNCH_CLAIM_TIMEOUT_MILLIS = 5_000L
    }

    private lateinit var channel: MethodChannel
    private var executor: ExecutorService? = null
    private var timeoutExecutor: ScheduledExecutorService? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    @Volatile
    private var activity: Activity? = null
    private var activeInvocation: Long? = null
    private var engineGeneration = 0L
    private var detachedFromEngine = false

    @Synchronized
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        detachedFromEngine = false
        engineGeneration += 1
        // A plugin instance can be detached and attached to another engine
        // during host recreation. Recreate the worker pools after detach;
        // never submit work to an executor that was shut down with the old
        // engine.
        if (executor == null || executor!!.isShutdown) {
            executor = Executors.newSingleThreadExecutor()
        }
        if (timeoutExecutor == null || timeoutExecutor!!.isShutdown) {
            timeoutExecutor = Executors.newSingleThreadScheduledExecutor()
        }
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    @Synchronized
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        detachedFromEngine = true
        engineGeneration += 1
        channel.setMethodCallHandler(null)
        activity = null
        // Let an accepted-but-queued worker run its attached=false path and
        // finally release the process gate. Interrupting/removing it here
        // could strand the lease forever; a running PayTask is likewise
        // allowed to return before the gate is released.
        executor?.shutdown()
        timeoutExecutor?.shutdownNow()
        executor = null
        timeoutExecutor = null
    }

    @Synchronized
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        // Invalidate a result produced by a previous Activity instance. The
        // Flutter engine can survive an Activity recreation, so engine
        // generation alone is not enough to identify a current UI owner.
        engineGeneration += 1
        activity = binding.activity
    }

    @Synchronized
    override fun onDetachedFromActivityForConfigChanges() {
        engineGeneration += 1
        activity = null
    }

    @Synchronized
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    @Synchronized
    override fun onDetachedFromActivity() {
        engineGeneration += 1
        activity = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == AlipayNativeIsolationLaunchContract.METHOD) {
            launchNativeIsolation(call, result)
            return
        }
        if (call.method == AlipayNativeIsolationLaunchContract.FILES_DIRECTORY_METHOD) {
            nativeIsolationFilesDirectory(call, result)
            return
        }
        if (call.method != "pay") {
            result.notImplemented()
            return
        }
        val orderString = orderStringArgument(call)
        val sandbox = sandboxArgument(call)
        if (orderString == null || sandbox == null) {
            result.error("invalid_request", "服务端支付串无效", null)
            return
        }
        val currentActivity: Activity
        val invocationToken: Long
        val normalPaymentLease: AlipayPaymentGate.ClaimedHandle
        synchronized(this) {
            if (detachedFromEngine) {
                result.error("activity_unavailable", "支付桥接未就绪", null)
                return
            }
            val attachedActivity = activity
            if (attachedActivity == null || attachedActivity.isFinishing || attachedActivity.isDestroyed) {
                result.error("activity_unavailable", "当前没有可用的支付页面", null)
                return
            }
            if (sandbox && !isDebuggable(attachedActivity)) {
                result.error("sandbox_not_debuggable", "沙箱支付仅允许在可调试构建中运行", null)
                return
            }
            val lease = AlipayProcessPaymentGate.acquire(AlipayPaymentLane.NORMAL)
            if (lease == null) {
                result.error("payment_in_progress", "已有支付宝支付正在处理", null)
                return
            }
            engineGeneration += 1
            invocationToken = engineGeneration
            activeInvocation = invocationToken
            currentActivity = attachedActivity

            // The lease is process-wide and remains held until PayTask's
            // worker actually returns, even when the channel watchdog fires.
            // Keep it in the local invocation closure from this point on.
            normalPaymentLease = lease
        }

        // PayTask.payV2 performs network and app-switch work. Keep it off the
        // Flutter/UI thread, then send only a small status classification back
        // on the main thread. Never forward the SDK's memo/result strings.
        val completion = AtomicBoolean(false)
        val lease = normalPaymentLease
        val timeoutExecutor = this.timeoutExecutor
        val workerExecutor = this.executor
        if (timeoutExecutor == null || workerExecutor == null) {
            clearActive(invocationToken, lease)
            result.error("unavailable", "支付宝支付桥接当前不可用", null)
            return
        }
        val timeout: ScheduledFuture<*> = try {
            timeoutExecutor.schedule(
                {
                    if (completion.compareAndSet(false, true)) {
                        // Deliver a provisional timeout, but keep the process
                        // gate locked until the original PayTask worker returns.
                        // A retry must receive payment_in_progress rather than
                        // queueing a second SDK invocation.
                        deliver(
                            result,
                            AlipayBridgeResultClassifier.nativeWatchdogTimeout(),
                            invocationToken,
                        )
                    }
                },
                AlipayPaymentTimeout.PAY_TIMEOUT_SECONDS,
                TimeUnit.SECONDS,
            )
        } catch (_: RejectedExecutionException) {
            clearActive(invocationToken, lease)
            result.error("unavailable", "支付宝支付桥接当前不可用", null)
            return
        }
        try {
            workerExecutor.execute {
                try {
                    val status = try {
                        val activityStillAttached = synchronized(this) {
                            !detachedFromEngine && activity === currentActivity &&
                                !currentActivity.isFinishing && !currentActivity.isDestroyed
                        }
                        if (!activityStillAttached) {
                            AlipayBridgeResultClassifier.nativeNotInvoked()
                        } else {
                            AlipaySdkEnvironment.setForPay(sandbox)
                            val raw = PayTask(currentActivity).payV2(orderString, true)
                            AlipayBridgeResultClassifier.payTaskReturned(raw["resultStatus"])
                        }
                    } catch (_: RuntimeException) {
                        AlipayBridgeResultClassifier.nativeException()
                    } catch (_: LinkageError) {
                        AlipayBridgeResultClassifier.nativeUnavailable()
                    }
                    if (completion.compareAndSet(false, true)) {
                        timeout.cancel(false)
                        deliver(result, status, invocationToken)
                    }
                } finally {
                    // A late worker return is the only point at which this
                    // process lease may be released after a watchdog timeout.
                    clearActive(invocationToken, lease)
                }
            }
        } catch (_: RejectedExecutionException) {
            timeout.cancel(false)
            if (completion.compareAndSet(false, true)) {
                result.error("unavailable", "支付宝支付桥接当前不可用", null)
            }
            clearActive(invocationToken, lease)
        }
    }

    private fun launchNativeIsolation(call: MethodCall, result: MethodChannel.Result) {
        val runId = AlipayNativeIsolationLaunchContract.parseRunId(call.arguments)
        if (runId == null) {
            result.error("invalid_request", "原生隔离请求无效", null)
            return
        }
        val currentActivity: Activity
        val isolationReservation: AlipayPaymentGate.ReservationHandle
        synchronized(this) {
            if (detachedFromEngine) {
                result.error("activity_unavailable", "原生隔离页面当前不可用", null)
                return
            }
            val attachedActivity = activity
            if (attachedActivity == null ||
                attachedActivity.isFinishing ||
                attachedActivity.isDestroyed
            ) {
                result.error("activity_unavailable", "原生隔离页面当前不可用", null)
                return
            }
            if (!isDebuggable(attachedActivity)) {
                result.error("debug_only", "原生隔离页面仅允许在可调试构建中运行", null)
                return
            }
            isolationReservation = AlipayProcessPaymentGate.reserveIsolation(runId) ?: run {
                result.error("payment_in_progress", "已有支付宝支付正在处理", null)
                return
            }
            currentActivity = attachedActivity
        }
        Log.i(NATIVE_ISOLATION_TAG, "M5_ALIPAY_NATIVE_ISOLATION::LAUNCH_REQUEST::$runId")
        if (!AlipayNativeIsolationLaunchRegistry.register(
                isolationReservation.wireId,
                isolationReservation.runId,
            ) { started ->
                mainHandler.post {
                    if (started) {
                        Log.i(
                            NATIVE_ISOLATION_TAG,
                            "M5_ALIPAY_NATIVE_ISOLATION::LAUNCH_SUCCESS::$runId",
                        )
                        result.success(true)
                    } else {
                        result.error("debug_unavailable", "原生隔离页面当前不可用", null)
                    }
                }
            }
        ) {
            AlipayProcessPaymentGate.releaseIfUnclaimed(isolationReservation)
            result.error("debug_unavailable", "原生隔离页面当前不可用", null)
            return
        }
        val claimWatchdog = Runnable {
            // startActivity can return before Android delivers onCreate (or
            // never deliver it at all). Expire only an unclaimed reservation;
            // a claimed PayTask lease must remain protected until it returns.
            if (AlipayProcessPaymentGate.releaseIfUnclaimed(isolationReservation)) {
                AlipayNativeIsolationLaunchRegistry.completeFailed(
                    isolationReservation.wireId,
                    isolationReservation.runId,
                )
            }
        }
        mainHandler.postDelayed(claimWatchdog, NATIVE_LAUNCH_CLAIM_TIMEOUT_MILLIS)
        try {
            val intent = Intent().apply {
                setClassName(
                    currentActivity.packageName,
                    AlipayNativeIsolationLaunchContract.ACTIVITY_CLASS,
                )
                putExtra(AlipayNativeIsolationLaunchContract.RUN_ID_EXTRA, runId)
                putExtra(
                    AlipayNativeIsolationLaunchContract.LEASE_ID_EXTRA,
                    isolationReservation.wireId,
                )
            }
            currentActivity.startActivity(intent)
        } catch (_: RuntimeException) {
            mainHandler.removeCallbacks(claimWatchdog)
            AlipayNativeIsolationLaunchRegistry.completeFailed(
                isolationReservation.wireId,
                isolationReservation.runId,
            )
            AlipayProcessPaymentGate.releaseIfUnclaimed(isolationReservation)
            Log.e(NATIVE_ISOLATION_TAG, "M5_ALIPAY_NATIVE_ISOLATION::LAUNCH_FAIL::$runId")
        }
    }

    private fun nativeIsolationFilesDirectory(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        if (AlipayNativeIsolationLaunchContract.parseRunId(call.arguments) == null) {
            result.error("invalid_request", "原生隔离请求无效", null)
            return
        }
        val currentActivity = synchronized(this) {
            if (detachedFromEngine || AlipayProcessPaymentGate.activeLane() != null) {
                null
            } else {
                activity?.takeUnless { it.isFinishing || it.isDestroyed }
            }
        }
        if (currentActivity == null) {
            result.error("activity_unavailable", "原生隔离页面当前不可用", null)
            return
        }
        if (!isDebuggable(currentActivity)) {
            result.error("debug_only", "原生隔离页面仅允许在可调试构建中运行", null)
            return
        }
        try {
            val files = currentActivity.filesDir.canonicalFile
            if (files.name != "files" || files.parentFile?.name != currentActivity.packageName) {
                result.error("debug_unavailable", "原生隔离目录当前不可用", null)
                return
            }
            result.success(files.absolutePath)
        } catch (_: RuntimeException) {
            result.error("debug_unavailable", "原生隔离目录当前不可用", null)
        }
    }

    @Synchronized
    private fun clearActive(
        invocationToken: Long,
        lease: AlipayPaymentGate.ClaimedHandle,
    ) {
        if (activeInvocation == invocationToken) {
            activeInvocation = null
        }
        // The capability is bound to this exact worker lease. Releasing it
        // outside the invocation-token branch is harmless if a stale
        // callback races a later engine generation, while avoiding a gate
        // wedge if bookkeeping was already cleared.
        AlipayProcessPaymentGate.release(lease)
    }

    private fun deliver(
        result: MethodChannel.Result,
        classified: AlipayBridgeClassifiedStatus,
        invocationToken: Long,
    ) {
        mainHandler.post {
            // A result from an old engine must never be delivered after a
            // detach/reattach cycle. The Dart future on that engine will
            // expire and reconcile the backend order instead.
            val shouldDeliver = synchronized(this) {
                !detachedFromEngine && engineGeneration == invocationToken
            }
            if (!shouldDeliver) {
                return@post
            }
            val status = classified.reducedStatus
            // Keep the established reduced status field while adding only
            // bounded, structured evidence. Never forward PayTask's memo or
            // result text, signed order data, or any account/payment fields.
            val reduced = mapOf("status" to status)
            result.success(
                reduced +
                    mapOf(
                        "sdkCompleted" to classified.sdkCompleted,
                        "resultStatus" to classified.resultStatus,
                        "bridgeOutcome" to classified.bridgeOutcome,
                    ),
            )
        }
    }

    private fun orderStringArgument(call: MethodCall): String? {
        val arguments = call.arguments as? Map<*, *> ?: return null
        val value = arguments["orderStr"] as? String ?: return null
        if (value.isEmpty() || value.length > MAX_ORDER_STRING_LENGTH ||
            value.trim() != value || value.any { it.code < 0x20 || it.code == 0x7f }) {
            return null
        }
        return value
    }

    /**
     * The sandbox switch is a typed, explicit bridge argument. Android's
     * MethodChannel codec can decode Dart booleans as [Boolean], but it must
     * not silently accept string values such as "true" or "1".
     */
    private fun sandboxArgument(call: MethodCall): Boolean? {
        val arguments = call.arguments as? Map<*, *> ?: return null
        return arguments["sandbox"] as? Boolean
    }

    private fun isDebuggable(activity: Activity): Boolean =
        activity.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0

}

/**
 * Strict, non-sensitive contract for launching the debug-only same-application
 * isolation Activity. The Activity remains non-exported and is absent from
 * release manifests; this MethodChannel call can only originate in the app's
 * Flutter engine.
 */
internal object AlipayNativeIsolationLaunchContract {
    const val METHOD = "launchNativeIsolation"
    const val FILES_DIRECTORY_METHOD = "nativeIsolationFilesDirectory"
    const val ACTIVITY_CLASS =
        "com.kong373.alipay_app_pay.NativeAlipayIsolationActivity"
    const val RUN_ID_EXTRA = "runId"
    const val LEASE_ID_EXTRA = "alipayLeaseId"
    private val RUN_ID_PATTERN = Regex("^[a-f0-9]{32}$")

    fun parseRunId(arguments: Any?): String? {
        val values = arguments as? Map<*, *> ?: return null
        if (values.size != 1 || values.keys != setOf(RUN_ID_EXTRA)) {
            return null
        }
        val runId = values[RUN_ID_EXTRA] as? String ?: return null
        return runId.takeIf(RUN_ID_PATTERN::matches)
    }
}

/**
 * PayTask reads a process-wide SDK environment. Set it for every invocation
 * so a previous sandbox call can never bleed into an online call (or vice
 * versa) when the Flutter engine stays alive.
 */
internal object AlipaySdkEnvironment {
    fun setForPay(sandbox: Boolean) {
        if (sandbox) {
            EnvUtils.setEnv(EnvUtils.EnvEnum.SANDBOX)
        } else {
            EnvUtils.setEnv(EnvUtils.EnvEnum.ONLINE)
        }
    }
}

/**
 * Fixed-vocabulary, non-sensitive provenance for the bridge result. These
 * markers are diagnostic evidence only and never authorize payment or wallet
 * mutations.
 */
internal data class AlipayBridgeClassifiedStatus(
    val reducedStatus: String,
    val resultStatus: String?,
    val sdkCompleted: Boolean,
    val bridgeOutcome: String,
)

internal object AlipayBridgeResultClassifier {
    const val PAY_TASK_RETURNED = "pay_task_returned"
    const val NATIVE_WATCHDOG_TIMEOUT = "native_watchdog_timeout"
    const val NATIVE_NOT_INVOKED = "native_not_invoked"
    const val NATIVE_EXCEPTION = "native_exception"
    const val NATIVE_UNAVAILABLE = "native_unavailable"

    private const val MAX_RESULT_STATUS_LENGTH = 32
    private val RESULT_STATUS_PATTERN = Regex("^[A-Za-z0-9_.-]+$")

    fun nativeWatchdogTimeout(): AlipayBridgeClassifiedStatus =
        AlipayBridgeClassifiedStatus(
            reducedStatus = "processing",
            resultStatus = null,
            sdkCompleted = false,
            bridgeOutcome = NATIVE_WATCHDOG_TIMEOUT,
        )

    fun nativeNotInvoked(): AlipayBridgeClassifiedStatus =
        AlipayBridgeClassifiedStatus(
            reducedStatus = "unavailable",
            resultStatus = null,
            sdkCompleted = false,
            bridgeOutcome = NATIVE_NOT_INVOKED,
        )

    fun nativeException(): AlipayBridgeClassifiedStatus =
        AlipayBridgeClassifiedStatus(
            reducedStatus = "failed",
            resultStatus = null,
            sdkCompleted = false,
            bridgeOutcome = NATIVE_EXCEPTION,
        )

    fun nativeUnavailable(): AlipayBridgeClassifiedStatus =
        AlipayBridgeClassifiedStatus(
            reducedStatus = "unavailable",
            resultStatus = null,
            sdkCompleted = false,
            bridgeOutcome = NATIVE_UNAVAILABLE,
        )

    fun payTaskReturned(raw: Any?): AlipayBridgeClassifiedStatus {
        val resultStatus = boundedResultStatus(raw)
        return when (resultStatus) {
            "9000" -> result("success", resultStatus, true)
            "8000", "6004" -> result("processing", resultStatus, false)
            "6001" -> result("user_canceled", resultStatus, false)
            "6002" -> result("network_error", resultStatus, false)
            "4000" -> result("failed", resultStatus, false)
            else -> result("failed", resultStatus, false)
        }
    }

    private fun result(
        reducedStatus: String,
        resultStatus: String?,
        sdkCompleted: Boolean,
    ): AlipayBridgeClassifiedStatus = AlipayBridgeClassifiedStatus(
        reducedStatus = reducedStatus,
        resultStatus = resultStatus,
        sdkCompleted = sdkCompleted,
        bridgeOutcome = PAY_TASK_RETURNED,
    )

    private fun boundedResultStatus(raw: Any?): String? {
        val value = raw?.toString()?.trim() ?: return null
        if (value.isEmpty() || value.length > MAX_RESULT_STATUS_LENGTH) {
            return null
        }
        if (!RESULT_STATUS_PATTERN.matches(value)) {
            return null
        }
        return value
    }
}
