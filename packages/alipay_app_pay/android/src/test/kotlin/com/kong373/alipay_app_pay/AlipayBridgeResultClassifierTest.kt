package com.kong373.alipay_app_pay

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class AlipayBridgeResultClassifierTest {
    @Test
    fun payTaskReturnKeepsAStableMarkerForMissingStatus() {
        val result = AlipayBridgeResultClassifier.payTaskReturned(null)

        assertEquals("failed", result.reducedStatus)
        assertNull(result.resultStatus)
        assertEquals(false, result.sdkCompleted)
        assertEquals(
            AlipayBridgeResultClassifier.PAY_TASK_RETURNED,
            result.bridgeOutcome,
        )
    }

    @Test
    fun watchdogTimeoutHasNoPayTaskResultMarker() {
        val result = AlipayBridgeResultClassifier.nativeWatchdogTimeout()

        assertEquals("processing", result.reducedStatus)
        assertNull(result.resultStatus)
        assertEquals(false, result.sdkCompleted)
        assertEquals(
            AlipayBridgeResultClassifier.NATIVE_WATCHDOG_TIMEOUT,
            result.bridgeOutcome,
        )
    }

    @Test
    fun nativeStatusesAreBoundedAndRetainThePayTaskMarker() {
        val result = AlipayBridgeResultClassifier.payTaskReturned("6001")

        assertEquals("user_canceled", result.reducedStatus)
        assertEquals("6001", result.resultStatus)
        assertEquals(false, result.sdkCompleted)
        assertEquals(
            AlipayBridgeResultClassifier.PAY_TASK_RETURNED,
            result.bridgeOutcome,
        )
    }
}
