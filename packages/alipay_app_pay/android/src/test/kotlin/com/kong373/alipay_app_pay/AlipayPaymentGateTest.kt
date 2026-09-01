package com.kong373.alipay_app_pay

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AlipayPaymentGateTest {
    private val runId = "0123456789abcdef0123456789abcdef"

    @Test
    fun normalAndIsolationShareOneProcessLease() {
        val gate = AlipayPaymentGate()

        val normal = gate.acquire(AlipayPaymentLane.NORMAL)
        assertNotNull(normal)
        assertNull(gate.reserveIsolation(runId))

        assertTrue(gate.release(normal!!))
        val reservation = gate.reserveIsolation(runId)
        assertNotNull(reservation)
        assertNull(gate.acquire(AlipayPaymentLane.NORMAL))
        val owner = gate.claim(
            reservation!!.wireId,
            runId,
            AlipayPaymentLane.NATIVE_ISOLATION,
        )
        assertNotNull(owner)
        assertTrue(gate.release(owner!!))
    }

    @Test
    fun aSecondIsolationLaunchAndLeaseReentryAreRejected() {
        val gate = AlipayPaymentGate()
        val first = gate.reserveIsolation(runId)
        assertNotNull(first)

        assertNull(gate.reserveIsolation(runId))
        val owner = gate.claim(
            first!!.wireId,
            runId,
            AlipayPaymentLane.NATIVE_ISOLATION,
        )
        assertNotNull(owner)
        assertNull(gate.claim(first.wireId, runId, AlipayPaymentLane.NATIVE_ISOLATION))
        assertFalse(gate.releaseIfUnclaimed(first))
        assertTrue(gate.release(owner!!))
    }

    @Test
    fun unclaimedReservationExpiresAndLateClaimIsRejected() {
        val gate = AlipayPaymentGate()
        val reservation = gate.reserveIsolation(runId)
        assertNotNull(reservation)
        val wireId = reservation!!.wireId

        assertTrue(gate.releaseIfUnclaimed(reservation))
        assertNull(gate.activeLane())
        assertNull(gate.claim(wireId, runId, AlipayPaymentLane.NATIVE_ISOLATION))
        assertFalse(gate.releaseIfUnclaimed(reservation))
    }

    @Test
    fun quickCompletionCannotBeMisclassifiedByAStaleLaunchWatchdog() {
        val gate = AlipayPaymentGate()
        val reservation = gate.reserveIsolation(runId)
        assertNotNull(reservation)
        val owner = gate.claim(
            reservation!!.wireId,
            runId,
            AlipayPaymentLane.NATIVE_ISOLATION,
        )
        assertNotNull(owner)
        assertTrue(gate.release(owner!!))

        // The launch watchdog belongs to the old reservation. It cannot
        // release a newer launch, even after the first worker completed fast.
        val next = gate.reserveIsolation("fedcba9876543210fedcba9876543210")
        assertNotNull(next)
        assertFalse(gate.releaseIfUnclaimed(reservation))
        assertEquals(AlipayPaymentLane.NATIVE_ISOLATION, gate.activeLane())
        assertTrue(gate.releaseIfUnclaimed(next!!))
    }

    @Test
    fun guessedOrCrossGateReservationCannotReleaseAnActiveLease() {
        val gate = AlipayPaymentGate()
        val active = gate.acquire(AlipayPaymentLane.NORMAL)
        assertNotNull(active)

        val otherGate = AlipayPaymentGate()
        val foreignReservation = otherGate.reserveIsolation(runId)
        assertNotNull(foreignReservation)
        assertFalse(gate.releaseIfUnclaimed(foreignReservation!!))
        assertNull(gate.claim("00000000000000000000000000000000", runId, AlipayPaymentLane.NATIVE_ISOLATION))
        assertFalse(gate.release(AlipayPaymentGate.ClaimedHandle.create(Any())))
        assertEquals(AlipayPaymentLane.NORMAL, gate.activeLane())
        assertTrue(gate.release(active!!))
        assertTrue(otherGate.releaseIfUnclaimed(foreignReservation))
    }

    @Test
    fun reservationIsBoundToBothRunIdAndIsolationLane() {
        val gate = AlipayPaymentGate()
        val reservation = gate.reserveIsolation(runId)
        assertNotNull(reservation)

        assertNull(
            gate.claim(
                reservation!!.wireId,
                "fedcba9876543210fedcba9876543210",
                AlipayPaymentLane.NATIVE_ISOLATION,
            ),
        )
        assertNull(
            gate.claim(
                reservation.wireId,
                runId,
                AlipayPaymentLane.NORMAL,
            ),
        )
        val owner = gate.claim(
            reservation.wireId,
            runId,
            AlipayPaymentLane.NATIVE_ISOLATION,
        )
        assertNotNull(owner)
        assertTrue(gate.release(owner!!))
    }

    @Test
    fun aTimedOutWorkerKeepsTheLeaseUntilItsLateReturn() {
        val gate = AlipayPaymentGate()
        val owner = gate.acquire(AlipayPaymentLane.NORMAL)
        assertNotNull(owner)

        // The watchdog reports timeout independently; only the PayTask owner
        // may release the process gate when it actually returns.
        assertNull(gate.reserveIsolation(runId))
        assertEquals(AlipayPaymentLane.NORMAL, gate.activeLane())

        assertTrue(gate.release(owner!!))
        assertNotNull(gate.reserveIsolation(runId))
    }

    @Test
    fun wireIdsAreHighEntropyAndNotReused() {
        val gate = AlipayPaymentGate()
        val first = gate.reserveIsolation(runId)
        assertNotNull(first)
        assertEquals(32, first!!.wireId.length)
        assertTrue(first.wireId.matches(Regex("^[a-f0-9]{32}$")))
        assertTrue(gate.releaseIfUnclaimed(first))

        val second = gate.reserveIsolation(runId)
        assertNotNull(second)
        assertNotEquals(first.wireId, second!!.wireId)
        assertTrue(gate.releaseIfUnclaimed(second))
    }

    @Test
    fun launchRegistryCanCompleteOnlyOnce() {
        val outcomes = mutableListOf<Boolean>()
        assertTrue(
            AlipayNativeIsolationLaunchRegistry.register("wire-77", runId) { started ->
                outcomes += started
            },
        )

        assertTrue(AlipayNativeIsolationLaunchRegistry.completeStarted("wire-77", runId))
        assertFalse(AlipayNativeIsolationLaunchRegistry.completeFailed("wire-77", runId))
        assertEquals(listOf(true), outcomes)
    }
}
