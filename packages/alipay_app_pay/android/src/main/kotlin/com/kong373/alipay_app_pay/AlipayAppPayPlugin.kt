package com.kong373.alipay_app_pay

import android.app.Activity
import android.os.Handler
import android.os.Looper
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
        private const val PAY_TIMEOUT_SECONDS = 120L
    }

    private lateinit var channel: MethodChannel
    private val executor: ExecutorService = Executors.newSingleThreadExecutor()
    private val timeoutExecutor: ScheduledExecutorService =
        Executors.newSingleThreadScheduledExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var activity: Activity? = null
    private var active = false
    private var detachedFromEngine = false

    @Synchronized
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        detachedFromEngine = false
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    @Synchronized
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        detachedFromEngine = true
        channel.setMethodCallHandler(null)
        activity = null
        executor.shutdownNow()
        timeoutExecutor.shutdownNow()
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "pay") {
            result.notImplemented()
            return
        }
        val orderString = orderStringArgument(call)
        if (orderString == null) {
            result.error("invalid_request", "服务端支付串无效", null)
            return
        }
        val currentActivity = activity
        if (currentActivity == null) {
            result.error("activity_unavailable", "当前没有可用的支付页面", null)
            return
        }
        synchronized(this) {
            if (detachedFromEngine) {
                result.error("activity_unavailable", "支付桥接未就绪", null)
                return
            }
            if (active) {
                result.error("payment_in_progress", "已有支付宝支付正在处理", null)
                return
            }
            active = true
        }

        // PayTask.payV2 performs network and app-switch work. Keep it off the
        // Flutter/UI thread, then send only a small status classification back
        // on the main thread. Never forward the SDK's memo/result strings.
        val completion = AtomicBoolean(false)
        val timeout: ScheduledFuture<*> = try {
            timeoutExecutor.schedule(
                {
                    if (completion.compareAndSet(false, true)) {
                        // Deliver a provisional timeout, but keep `active`
                        // locked until the original PayTask worker returns.
                        // A retry must receive payment_in_progress rather than
                        // queueing a second SDK invocation.
                        deliver(result, "processing")
                    }
                },
                PAY_TIMEOUT_SECONDS,
                TimeUnit.SECONDS,
            )
        } catch (_: RejectedExecutionException) {
            clearActive()
            result.error("unavailable", "支付宝支付桥接当前不可用", null)
            return
        }
        try {
            executor.execute {
                val status = try {
                    val raw = PayTask(currentActivity).payV2(orderString, true)
                    classify(raw["resultStatus"])
                } catch (_: RuntimeException) {
                    "failed"
                } catch (_: LinkageError) {
                    "unavailable"
                }
                if (completion.compareAndSet(false, true)) {
                    timeout.cancel(false)
                    deliver(result, status)
                }
                clearActive()
            }
        } catch (_: RejectedExecutionException) {
            timeout.cancel(false)
            if (completion.compareAndSet(false, true)) {
                clearActive()
                result.error("unavailable", "支付宝支付桥接当前不可用", null)
            }
        }
    }

    @Synchronized
    private fun clearActive() {
        active = false
    }

    private fun deliver(result: MethodChannel.Result, status: String) {
        mainHandler.post {
            val shouldDeliver = synchronized(this) { !detachedFromEngine }
            if (!shouldDeliver) {
                result.error("activity_unavailable", "支付桥接未就绪", null)
                return@post
            }
            result.success(mapOf("status" to status))
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

    private fun classify(raw: Any?): String = when (raw?.toString()?.trim()) {
        "9000" -> "success"
        "8000", "6004" -> "processing"
        "6001" -> "user_canceled"
        "6002" -> "network_error"
        "4000" -> "failed"
        else -> "failed"
    }
}
