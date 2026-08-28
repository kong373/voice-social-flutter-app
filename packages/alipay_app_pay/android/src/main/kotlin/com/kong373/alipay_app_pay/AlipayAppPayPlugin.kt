package com.kong373.alipay_app_pay

import android.app.Activity
import android.content.pm.ApplicationInfo
import android.os.Handler
import android.os.Looper
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
        private const val MAX_RESULT_STATUS_LENGTH = 32
        private const val PAY_TIMEOUT_SECONDS = 120L
    }

    private lateinit var channel: MethodChannel
    private var executor: ExecutorService? = null
    private var timeoutExecutor: ScheduledExecutorService? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    @Volatile
    private var activity: Activity? = null
    @Volatile
    private var active = false
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
        executor?.shutdownNow()
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
            if (active) {
                result.error("payment_in_progress", "已有支付宝支付正在处理", null)
                return
            }
            active = true
            engineGeneration += 1
            invocationToken = engineGeneration
            activeInvocation = invocationToken
            currentActivity = attachedActivity
        }

        // PayTask.payV2 performs network and app-switch work. Keep it off the
        // Flutter/UI thread, then send only a small status classification back
        // on the main thread. Never forward the SDK's memo/result strings.
        val completion = AtomicBoolean(false)
        val timeoutExecutor = this.timeoutExecutor
        val workerExecutor = this.executor
        if (timeoutExecutor == null || workerExecutor == null) {
            clearActive(invocationToken)
            result.error("unavailable", "支付宝支付桥接当前不可用", null)
            return
        }
        val timeout: ScheduledFuture<*> = try {
            timeoutExecutor.schedule(
                {
                    if (completion.compareAndSet(false, true)) {
                        // Deliver a provisional timeout, but keep `active`
                        // locked until the original PayTask worker returns.
                        // A retry must receive payment_in_progress rather than
                        // queueing a second SDK invocation.
                        deliver(
                            result,
                            ClassifiedStatus(
                                reducedStatus = "processing",
                                resultStatus = null,
                                sdkCompleted = false,
                            ),
                            invocationToken,
                        )
                    }
                },
                PAY_TIMEOUT_SECONDS,
                TimeUnit.SECONDS,
            )
        } catch (_: RejectedExecutionException) {
            clearActive(invocationToken)
            result.error("unavailable", "支付宝支付桥接当前不可用", null)
            return
        }
        try {
            workerExecutor.execute {
                val status = try {
                    val activityStillAttached = synchronized(this) {
                        !detachedFromEngine && activity === currentActivity &&
                            !currentActivity.isFinishing && !currentActivity.isDestroyed
                    }
                    if (!activityStillAttached) {
                        ClassifiedStatus(
                            reducedStatus = "unavailable",
                            resultStatus = null,
                            sdkCompleted = false,
                        )
                    } else {
                        if (sandbox) {
                            EnvUtils.setEnv(EnvUtils.EnvEnum.SANDBOX)
                        }
                        val raw = PayTask(currentActivity).payV2(orderString, true)
                        classify(raw["resultStatus"])
                    }
                } catch (_: RuntimeException) {
                    ClassifiedStatus(
                        reducedStatus = "failed",
                        resultStatus = null,
                        sdkCompleted = false,
                    )
                } catch (_: LinkageError) {
                    ClassifiedStatus(
                        reducedStatus = "unavailable",
                        resultStatus = null,
                        sdkCompleted = false,
                    )
                }
                if (completion.compareAndSet(false, true)) {
                    timeout.cancel(false)
                    deliver(result, status, invocationToken)
                }
                clearActive(invocationToken)
            }
        } catch (_: RejectedExecutionException) {
            timeout.cancel(false)
            if (completion.compareAndSet(false, true)) {
                result.error("unavailable", "支付宝支付桥接当前不可用", null)
            }
            clearActive(invocationToken)
        }
    }

    @Synchronized
    private fun clearActive(invocationToken: Long) {
        if (activeInvocation == invocationToken) {
            active = false
            activeInvocation = null
        }
    }

    private fun deliver(
        result: MethodChannel.Result,
        classified: ClassifiedStatus,
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

    private data class ClassifiedStatus(
        val reducedStatus: String,
        val resultStatus: String?,
        val sdkCompleted: Boolean,
    )

    private fun classify(raw: Any?): ClassifiedStatus {
        val resultStatus = boundedResultStatus(raw)
        return when (resultStatus) {
            "9000" -> ClassifiedStatus("success", resultStatus, true)
            "8000", "6004" -> ClassifiedStatus("processing", resultStatus, false)
            "6001" -> ClassifiedStatus("user_canceled", resultStatus, false)
            "6002" -> ClassifiedStatus("network_error", resultStatus, false)
            "4000" -> ClassifiedStatus("failed", resultStatus, false)
            else -> ClassifiedStatus("failed", resultStatus, false)
        }
    }

    private fun boundedResultStatus(raw: Any?): String? {
        val value = raw?.toString()?.trim() ?: return null
        if (value.isEmpty() || value.length > MAX_RESULT_STATUS_LENGTH) {
            return null
        }
        if (!value.matches(Regex("^[A-Za-z0-9_.-]+$"))) {
            return null
        }
        return value
    }
}
