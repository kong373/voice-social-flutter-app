package com.kong373.first_party_room_audio

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

class RoomAudioService : Service() {
    private var leaseOwner: FirstPartyRoomAudioPlugin? = null
    override fun onBind(intent: Intent?): IBinder? = null
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val owner = FirstPartyRoomAudioPlugin.owner
        if (owner?.service === this) return START_NOT_STICKY
        leaseOwner = owner
        if (owner == null || !owner.establish(this, intent?.getStringExtra("requestId"))) finish()
        return START_NOT_STICKY
    }
    internal fun promote(microphone: Boolean): Boolean = try {
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(NotificationChannel(CHANNEL, "Room audio", NotificationManager.IMPORTANCE_LOW))
        }
        val launch = packageManager.getLaunchIntentForPackage(packageName)
            ?: throw IllegalStateException()
        launch.replaceExtras(null as android.os.Bundle?)
        val pending = PendingIntent.getActivity(this, 0, launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL) else Notification.Builder(this)
        val notification = builder.setSmallIcon(android.R.drawable.ic_lock_silent_mode_off)
            .setContentTitle("Room audio").setContentText("Tap to return to app")
            .setContentIntent(pending).setOngoing(true).setOnlyAlertOnce(true)
            .setVisibility(Notification.VISIBILITY_SECRET).build()
        if (Build.VERSION.SDK_INT >= 29) {
            val type = ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK or
                (if (microphone && Build.VERSION.SDK_INT >= 30) ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE else 0)
            startForeground(7341, notification, type)
        } else startForeground(7341, notification)
        true
    } catch (_: Exception) { false }
    internal fun finish() { retiring = true; stopForeground(STOP_FOREGROUND_REMOVE); stopSelf() }
    override fun onTaskRemoved(rootIntent: Intent?) {
        if (leaseOwner?.service === this) leaseOwner?.clear()
        finish()
        super.onTaskRemoved(rootIntent)
    }
    override fun onDestroy() {
        if (leaseOwner?.service === this) leaseOwner?.clear()
        leaseOwner = null
        retiring = false
        super.onDestroy()
    }
    companion object {
        private const val CHANNEL = "voice_social_room_audio"
        internal var retiring = false
    }
}
