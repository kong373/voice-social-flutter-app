package com.kong373.first_party_room_audio

/** Main-thread confined; no Android dependencies. */
internal class AudioLease {
    var session: String? = null
        private set
    var microphone = false
        private set
    fun permits(id: String, mic: Boolean, foreground: Boolean, permission: Boolean): Boolean {
        if (session != null && session != id) return false
        if (session == null && !foreground) return false
        if (mic && !permission) return false
        if (mic && !microphone && !foreground) return false
        return true
    }
    fun commit(id: String, mic: Boolean) { session = id; microphone = mic }
    fun stop(id: String): Boolean {
        if (session != id) return false
        session = null
        microphone = false
        return true
    }
    companion object {
        private val uuid = Regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")
        fun arguments(method: String, value: Any?): Map<*, *>? {
            val map = value as? Map<*, *> ?: return null
            val keys = if (method == "start") setOf("sessionId", "microphone") else setOf("sessionId")
            if (map.keys != keys || map["sessionId"] !is String) return null
            if (!uuid.matches(map["sessionId"] as String)) return null
            if (method == "start" && map["microphone"] !is Boolean) return null
            return map
        }
    }
}
