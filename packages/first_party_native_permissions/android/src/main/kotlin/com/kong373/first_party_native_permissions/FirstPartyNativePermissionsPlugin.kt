package com.kong373.first_party_native_permissions

import android.Manifest
import android.app.Activity
import android.app.NotificationManager
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

/** First-party OS permission bridge. It never reports provider or SDK state. */
class FirstPartyNativePermissionsPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    ActivityAware,
    PluginRegistry.RequestPermissionsResultListener {
    companion object {
        private const val CHANNEL = "voice_social_app/system_permissions"
        private const val REQUEST_CODE = 4719
        private const val PREFERENCES = "voice_social_first_party_permissions"
    }

    private lateinit var context: Context
    private lateinit var channel: MethodChannel
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var pendingResult: MethodChannel.Result? = null
    private var pendingKind: String? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        pendingResult = null
        pendingKind = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        activity = binding.activity
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        detachActivity()
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivity() {
        detachActivity()
    }

    private fun detachActivity() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        activity = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "status" -> {
                val kind = kindArgument(call)
                if (kind == null) {
                    result.error("invalid_kind", "未知系统权限类型", null)
                } else {
                    result.success(status(kind))
                }
            }
            "request" -> {
                val kind = kindArgument(call)
                if (kind == null) {
                    result.error("invalid_kind", "未知系统权限类型", null)
                } else {
                    request(kind, result)
                }
            }
            "openAppSettings" -> openAppSettings(result)
            "openExternalUrl" -> openExternalUrl(call, result)
            else -> result.notImplemented()
        }
    }

    private fun kindArgument(call: MethodCall): String? {
        val arguments = call.arguments as? Map<*, *> ?: return null
        return arguments["kind"]?.toString()?.trim()?.lowercase()
    }

    private fun request(kind: String, result: MethodChannel.Result) {
        val permission = permissionFor(kind)
        val current = status(kind)
        if (current == "granted" || current == "restricted" || current == "permanentlyDenied") {
            result.success(current)
            return
        }
        val currentActivity = activity
        if (permission == null || currentActivity == null) {
            result.success("unavailable")
            return
        }
        if (pendingResult != null) {
            result.error("request_in_progress", "已有系统权限请求正在处理", null)
            return
        }
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(requestedKey(kind), true)
            .apply()
        pendingResult = result
        pendingKind = kind
        currentActivity.requestPermissions(arrayOf(permission), REQUEST_CODE)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != REQUEST_CODE) {
            return false
        }
        val result = pendingResult
        val kind = pendingKind
        pendingResult = null
        pendingKind = null
        if (result != null && kind != null) {
            result.success(status(kind))
        }
        return true
    }

    private fun status(kind: String): String {
        if (kind == "notifications" && Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            return if (manager == null || manager.areNotificationsEnabled()) {
                "granted"
            } else {
                "permanentlyDenied"
            }
        }
        val permission = permissionFor(kind) ?: return "unavailable"
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return "granted"
        }
        if (kind == "photos" && Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            if (context.checkSelfPermission(Manifest.permission.READ_MEDIA_IMAGES) == PackageManager.PERMISSION_GRANTED ||
                context.checkSelfPermission(Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED) == PackageManager.PERMISSION_GRANTED
            ) {
                return "granted"
            }
        } else if (context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED) {
            return "granted"
        }
        val requested = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .getBoolean(requestedKey(kind), false)
        if (!requested) {
            return "notDetermined"
        }
        val currentActivity = activity
        if (currentActivity != null && currentActivity.shouldShowRequestPermissionRationale(permission)) {
            return "denied"
        }
        return "permanentlyDenied"
    }

    private fun permissionFor(kind: String): String? = when (kind) {
        "microphone" -> Manifest.permission.RECORD_AUDIO
        "notifications" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            Manifest.permission.POST_NOTIFICATIONS
        } else {
            null
        }
        "photos" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            Manifest.permission.READ_MEDIA_IMAGES
        } else {
            Manifest.permission.READ_EXTERNAL_STORAGE
        }
        else -> null
    }

    private fun requestedKey(kind: String): String = "requested_$kind"

    private fun openAppSettings(result: MethodChannel.Result) {
        val currentActivity = activity
        if (currentActivity == null) {
            result.success(false)
            return
        }
        val intent = Intent(
            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.parse("package:${context.packageName}"),
        )
        currentActivity.startActivity(intent)
        result.success(true)
    }

    private fun openExternalUrl(call: MethodCall, result: MethodChannel.Result) {
        val rawUrl = (call.arguments as? Map<*, *>)?.get("url")?.toString()?.trim()
        val uri = rawUrl?.let { Uri.parse(it) }
        if (uri == null || uri.scheme?.lowercase() != "https" || uri.host.isNullOrBlank() ||
            !uri.userInfo.isNullOrEmpty()
        ) {
            result.success(false)
            return
        }
        val currentActivity = activity
        if (currentActivity == null) {
            result.success(false)
            return
        }
        val intent = Intent(Intent.ACTION_VIEW, uri).apply {
            addCategory(Intent.CATEGORY_BROWSABLE)
        }
        try {
            currentActivity.startActivity(intent)
            result.success(true)
        } catch (_: ActivityNotFoundException) {
            result.success(false)
        } catch (_: RuntimeException) {
            result.success(false)
        }
    }
}
