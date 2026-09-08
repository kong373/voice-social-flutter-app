package com.kong373.first_party_room_audio

import android.app.Activity
import android.app.Application
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class FirstPartyRoomAudioPlugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler, Application.ActivityLifecycleCallbacks {
    private lateinit var application: Application
    private lateinit var methods: MethodChannel
    private lateinit var events: EventChannel
    private var sink: EventChannel.EventSink? = null
    private var activity: Activity? = null
    private var resumed = false
    internal val lease = AudioLease()
    internal var service: RoomAudioService? = null
    private val handler = Handler(Looper.getMainLooper())
    private var pending: MethodChannel.Result? = null
    private val pendingReplies = mutableListOf<MethodChannel.Result>()
    private var pendingId: String? = null
    private var pendingMic = false
    private var requestId: String? = null
    private var deadline = 0L
    private val expiry = Runnable { clear() }
    private val launchTimeout = Runnable { clear() }

    internal fun foreground() = resumed && activity?.hasWindowFocus() == true && activity?.isFinishing == false
    internal fun permission() = application.checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
    private fun emit(id: String, active: Boolean) { sink?.success(mapOf("sessionId" to id, "active" to active)) }
    private fun renew() {
        deadline = SystemClock.elapsedRealtime() + 45000
        handler.removeCallbacks(expiry)
        handler.postDelayed(expiry, 45000)
    }
    internal fun clear() {
        val id = lease.session ?: pendingId
        handler.removeCallbacks(expiry)
        handler.removeCallbacks(launchTimeout)
        val reply = pending
        val duplicates = pendingReplies.toList()
        pendingReplies.clear()
        pending = null; pendingId = null; requestId = null; deadline = 0
        if (id != null) lease.stop(id)
        val current = service
        service = null
        current?.finish()
        if (owner === this) owner = null
        if (id != null) emit(id, false)
        reply?.success(false)
        duplicates.forEach { it.success(false) }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        application = binding.applicationContext as Application
        application.registerActivityLifecycleCallbacks(this)
        methods = MethodChannel(binding.binaryMessenger, "voice_social_app/room_audio")
        methods.setMethodCallHandler(this)
        events = EventChannel(binding.binaryMessenger, "voice_social_app/room_audio/events")
        events.setStreamHandler(this)
    }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        clear()
        methods.setMethodCallHandler(null); events.setStreamHandler(null)
        sink = null
        application.unregisterActivityLifecycleCallbacks(this)
    }
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method !in setOf("start", "stop", "isActive", "renew")) { result.notImplemented(); return }
        val args = AudioLease.arguments(call.method, call.arguments)
        if (args == null) { result.error("invalid_arguments", "Invalid room audio arguments", null); return }
        val id = args["sessionId"] as String
        if (lease.session != null && SystemClock.elapsedRealtime() >= deadline) clear()
        when (call.method) {
            "stop" -> { if (lease.session == id || pendingId == id) clear(); result.success(null) }
            "isActive", "renew" -> {
                if (lease.microphone && !permission()) clear()
                val active = lease.session == id && service != null
                if (active && call.method == "renew") renew()
                result.success(active)
            }
            "start" -> {
                val mic = args["microphone"] as Boolean
                if (pending != null) {
                    if (pendingId == id && pendingMic == mic) pendingReplies.add(result)
                    else result.success(false)
                    return
                }
                if ((owner != null && owner !== this) || RoomAudioService.retiring || !lease.permits(id, mic, foreground(), permission())) {
                    result.success(false); return
                }
                if (lease.session == id && lease.microphone == mic && service != null) {
                    renew(); result.success(true); return
                }
                if (service != null) {
                    val ok = service!!.promote(mic)
                    if (ok) { lease.commit(id, mic); renew(); emit(id, true) }
                    // Failure to remove microphone privileges must not leave a mic lease behind.
                    else if (!mic) clear()
                    result.success(ok); return
                }
                owner = this; pending = result; pendingId = id; pendingMic = mic
                requestId = java.util.UUID.randomUUID().toString()
                handler.postDelayed(launchTimeout, 4000)
                try {
                    val intent = Intent(application, RoomAudioService::class.java)
                        .putExtra("requestId", requestId)
                    if (Build.VERSION.SDK_INT >= 26) application.startForegroundService(intent) else application.startService(intent)
                } catch (_: Exception) { clear() }
            }
        }
    }
    internal fun establish(value: RoomAudioService, request: String?): Boolean {
        if (RoomAudioService.retiring || request == null || request != requestId) return false
        val id = pendingId ?: return false
        if (!foreground() || (pendingMic && !permission())) { clear(); return false }
        if (!value.promote(pendingMic)) { clear(); return false }
        service = value
        lease.commit(id, pendingMic)
        val reply = pending
        val duplicates = pendingReplies.toList()
        pendingReplies.clear()
        pending = null; pendingId = null; requestId = null
        handler.removeCallbacks(launchTimeout)
        renew(); emit(id, true)
        reply?.success(true)
        duplicates.forEach { it.success(true) }
        return true
    }
    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        if (arguments != null) { events.error("invalid_arguments", "No event arguments allowed", null); return }
        sink = events
        lease.session?.let { emit(it, service != null) }
    }
    override fun onCancel(arguments: Any?) { clear(); sink = null }
    override fun onAttachedToActivity(binding: ActivityPluginBinding) { activity = binding.activity; resumed = false }
    override fun onDetachedFromActivity() { clear(); activity = null; resumed = false }
    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)
    override fun onActivityResumed(value: Activity) { if (activity === value) resumed = true }
    override fun onActivityPaused(value: Activity) { if (activity === value) resumed = false }
    override fun onActivityDestroyed(value: Activity) { if (activity === value) onDetachedFromActivity() }
    override fun onActivityCreated(a: Activity, b: Bundle?) {}
    override fun onActivityStarted(a: Activity) {}
    override fun onActivityStopped(a: Activity) {}
    override fun onActivitySaveInstanceState(a: Activity, b: Bundle) {}
    companion object { internal var owner: FirstPartyRoomAudioPlugin? = null }
}
