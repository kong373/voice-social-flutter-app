package com.kong373.alipay_app_pay

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AlipaySingleWriteGateTest {
    @Test
    fun watchdogResultWinsAndLateWorkerCannotOverwriteIt() {
        val writes = mutableListOf<String>()
        val gate = AlipaySingleWriteGate()

        assertTrue(gate.tryClaim())
        writes += "native_watchdog_timeout"
        if (gate.tryClaim()) {
            writes += "pay_task_returned"
        }

        assertEquals(listOf("native_watchdog_timeout"), writes)
    }

    @Test
    fun onlyOneResultWriterCanClaimTheResult() {
        val gate = AlipaySingleWriteGate()

        assertTrue(gate.tryClaim())
        assertFalse(gate.tryClaim())
        assertFalse(gate.tryClaim())
    }
}
