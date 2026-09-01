package com.kong373.alipay_app_pay

import java.security.SecureRandom
import java.util.concurrent.atomic.AtomicBoolean

/** The only provider lanes allowed to hold the process payment gate. */
internal enum class AlipayPaymentLane {
    NORMAL,
    NATIVE_ISOLATION,
}

/**
 * A process-wide payment gate with object capabilities for ownership.
 *
 * Isolation launchers receive a reservation handle. Its high-entropy wire ID
 * is copied into the Intent, but the ID alone can only be used to attempt a
 * claim; it can never release an active lease. After claim, only the returned
 * owner handle can release the worker-owned lease.
 */
internal class AlipayPaymentGate {
    private enum class State {
        RESERVED,
        CLAIMED,
        RELEASED,
    }

    private class LeaseState(
        val wireId: String?,
        val runId: String?,
        val lane: AlipayPaymentLane,
    ) {
        var state: State = State.RESERVED
    }

    /** Capability held by the Flutter launcher until Activity claims it. */
    internal class ReservationHandle private constructor(
        internal val wireId: String,
        internal val runId: String,
        internal val lane: AlipayPaymentLane,
        private val capability: Any,
    ) {
        internal fun matches(candidate: Any): Boolean = capability === candidate

        companion object {
            internal fun create(
                wireId: String,
                runId: String,
                lane: AlipayPaymentLane,
                capability: Any,
            ): ReservationHandle = ReservationHandle(wireId, runId, lane, capability)
        }
    }

    /** Capability held by the PayTask owner until the worker has returned. */
    internal class ClaimedHandle private constructor(
        private val capability: Any,
    ) {
        internal fun matches(candidate: Any): Boolean = capability === candidate

        companion object {
            internal fun create(capability: Any): ClaimedHandle = ClaimedHandle(capability)
        }
    }

    private val random = SecureRandom()
    private val issuedWireIds = mutableSetOf<String>()
    private var active: LeaseState? = null

    /** Acquires a claimed owner directly for the normal plugin lane. */
    @Synchronized
    fun acquire(lane: AlipayPaymentLane): ClaimedHandle? {
        if (active != null) {
            return null
        }
        val state = LeaseState(wireId = null, runId = null, lane = lane)
        state.state = State.CLAIMED
        active = state
        return ClaimedHandle.create(state)
    }

    /** Reserves an isolation launch, binding the wire capability to runId. */
    @Synchronized
    fun reserveIsolation(runId: String): ReservationHandle? {
        if (active != null || runId.isEmpty()) {
            return null
        }
        val wireId = nextWireId()
        val state = LeaseState(
            wireId = wireId,
            runId = runId,
            lane = AlipayPaymentLane.NATIVE_ISOLATION,
        )
        active = state
        return ReservationHandle.create(
            wireId = wireId,
            runId = runId,
            lane = AlipayPaymentLane.NATIVE_ISOLATION,
            capability = state,
        )
    }

    /**
     * Claims a reservation using the untrusted Intent wire data. A claim
     * succeeds once and returns the only handle accepted by [release].
     */
    @Synchronized
    fun claim(
        wireId: String,
        runId: String,
        lane: AlipayPaymentLane,
    ): ClaimedHandle? {
        val state = active ?: return null
        if (state.state != State.RESERVED ||
            state.wireId != wireId ||
            state.runId != runId ||
            state.lane != lane
        ) {
            return null
        }
        state.state = State.CLAIMED
        return ClaimedHandle.create(state)
    }

    /** Releases only a claimed object capability. */
    @Synchronized
    fun release(owner: ClaimedHandle): Boolean {
        val state = active ?: return false
        if (state.state != State.CLAIMED || !owner.matches(state)) {
            return false
        }
        state.state = State.RELEASED
        active = null
        return true
    }

    /**
     * Expires only this exact, still-reserved launcher capability. A late
     * Activity claim and any claimed owner cannot use this operation.
     */
    @Synchronized
    fun releaseIfUnclaimed(reservation: ReservationHandle): Boolean {
        val state = active ?: return false
        if (state.state != State.RESERVED || !reservation.matches(state)) {
            return false
        }
        state.state = State.RELEASED
        active = null
        return true
    }

    @Synchronized
    fun activeLane(): AlipayPaymentLane? = active?.lane

    private fun nextWireId(): String {
        val bytes = ByteArray(WIRE_ID_BYTES)
        var encoded: String
        do {
            random.nextBytes(bytes)
            encoded = bytes.joinToString(separator = "") { byte ->
                "%02x".format(byte.toInt() and 0xff)
            }
        } while (!issuedWireIds.add(encoded))
        return encoded
    }

    companion object {
        private const val WIRE_ID_BYTES = 16
        private val wireIdPattern = Regex("^[a-f0-9]{32}$")

        fun safeWireId(raw: String?): String? = raw?.takeIf(wireIdPattern::matches)
    }
}

/** The one gate shared by every plugin instance and debug Activity in a process. */
internal object AlipayProcessPaymentGate {
    fun acquire(lane: AlipayPaymentLane): AlipayPaymentGate.ClaimedHandle? =
        INSTANCE.acquire(lane)

    fun reserveIsolation(runId: String): AlipayPaymentGate.ReservationHandle? =
        INSTANCE.reserveIsolation(runId)

    fun claim(
        wireId: String,
        runId: String,
        lane: AlipayPaymentLane,
    ): AlipayPaymentGate.ClaimedHandle? = INSTANCE.claim(wireId, runId, lane)

    fun release(owner: AlipayPaymentGate.ClaimedHandle): Boolean = INSTANCE.release(owner)

    fun releaseIfUnclaimed(reservation: AlipayPaymentGate.ReservationHandle): Boolean =
        INSTANCE.releaseIfUnclaimed(reservation)

    fun activeLane(): AlipayPaymentLane? = INSTANCE.activeLane()

    private val INSTANCE = AlipayPaymentGate()
}

/**
 * One-shot handoff between the Flutter launcher and the debug Activity.
 * MethodChannel success is sent only after the Activity has accepted the
 * payload and submitted its PayTask worker.
 */
internal object AlipayNativeIsolationLaunchRegistry {
    private data class Key(val wireId: String, val runId: String)

    private val callbacks = mutableMapOf<Key, (Boolean) -> Unit>()

    @Synchronized
    fun register(wireId: String, runId: String, callback: (Boolean) -> Unit): Boolean {
        val key = Key(wireId, runId)
        if (callbacks.containsKey(key)) {
            return false
        }
        callbacks[key] = callback
        return true
    }

    fun completeStarted(wireId: String, runId: String): Boolean =
        complete(Key(wireId, runId), true)

    fun completeFailed(wireId: String, runId: String): Boolean =
        complete(Key(wireId, runId), false)

    private fun complete(key: Key, started: Boolean): Boolean {
        val callback = synchronized(this) { callbacks.remove(key) } ?: return false
        callback(started)
        return true
    }
}

internal object AlipayPaymentTimeout {
    const val PAY_TIMEOUT_SECONDS = 120L
}

/** One-shot result arbitration shared by watchdog and PayTask worker. */
internal class AlipaySingleWriteGate {
    private val claimed = AtomicBoolean(false)

    fun tryClaim(): Boolean = claimed.compareAndSet(false, true)
}
