package com.kong373.first_party_room_audio

/** Standalone small JVM test, no Android runtime or Gradle invocation required. */
fun main() {
    val id = "12345678-1234-4234-8234-123456789abc"
    val next = "12345678-1234-4234-8234-123456789abd"
    val lease = AudioLease()
    check(!lease.permits(id, false, false, false))
    check(lease.permits(id, false, true, false))
    check(!lease.permits(id, true, true, false))
    check(lease.session == null) // Permission check/launch intent alone cannot activate.
    lease.commit(id, false)
    check(!lease.permits(next, false, true, true))
    check(!lease.stop(next))
    check(lease.session == id)
    check(!lease.permits(id, true, false, true))
    check(!lease.microphone)
    check(lease.permits(id, true, true, true))
    lease.commit(id, true)
    check(lease.permits(id, true, false, true))
    check(!lease.permits(id, true, false, false))
    check(lease.permits(id, false, false, false))
    lease.commit(id, false)
    check(!lease.microphone)
    check(lease.stop(id))
    lease.commit(next, false)
    check(!lease.stop(id) && lease.session == next)
    check(AudioLease.arguments("start", mapOf("sessionId" to id, "microphone" to false)) != null)
    for (bad in listOf(null, "token", mapOf("sessionId" to "token"),
        mapOf("sessionId" to "$id\n"), mapOf("sessionId" to id, "extra" to true))) {
        check(AudioLease.arguments("stop", bad) == null)
    }
    for (bad in listOf(0, 1, "true", null)) {
        check(AudioLease.arguments("start", mapOf("sessionId" to id, "microphone" to bad)) == null)
    }
    check(AudioLease.arguments("start", mapOf("sessionId" to id)) == null)
    println("AudioLease boundary checks passed")
}
