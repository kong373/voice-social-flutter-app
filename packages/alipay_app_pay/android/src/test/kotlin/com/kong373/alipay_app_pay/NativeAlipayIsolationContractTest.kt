package com.kong373.alipay_app_pay

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class NativeAlipayIsolationContractTest {
    private val runId = "0123456789abcdef0123456789abcdef"

    @Test
    fun acceptsOnlyExactSandboxPayload() {
        val payload = NativeAlipayIsolationContract.parsePayload(
            """{"runId":"$runId","sandbox":true,"orderStr":"signed-value"}""",
            runId,
        )
        assertEquals(runId, payload?.runId)
        assertEquals("signed-value", payload?.orderString)
    }

    @Test
    fun rejectsMismatchedStaleOrExpandedPayloads() {
        assertNull(
            NativeAlipayIsolationContract.parsePayload(
                """{"runId":"$runId","sandbox":true,"orderStr":"signed-value"}""",
                "abcdef0123456789abcdef0123456789",
            ),
        )
        assertNull(
            NativeAlipayIsolationContract.parsePayload(
                """{"runId":"$runId","sandbox":true,"orderStr":"signed-value","extra":1}""",
                runId,
            ),
        )
        assertNull(
            NativeAlipayIsolationContract.parsePayload(
                """{"runId":"$runId","sandbox":false,"orderStr":"signed-value"}""",
                runId,
            ),
        )
    }

    @Test
    fun rejectsControlCharactersWhitespaceAndOversizeOrderStrings() {
        for (value in listOf("", " signed", "signed ", "signed\nvalue", "signed\u007fvalue")) {
            val raw = JSONObject(
                mapOf("runId" to runId, "sandbox" to true, "orderStr" to value),
            ).toString()
            assertNull(NativeAlipayIsolationContract.parsePayload(raw, runId))
        }
        val oversized = "x".repeat(NativeAlipayIsolationContract.MAX_ORDER_STRING_LENGTH + 1)
        val raw = JSONObject(
            mapOf("runId" to runId, "sandbox" to true, "orderStr" to oversized),
        ).toString()
        assertNull(NativeAlipayIsolationContract.parsePayload(raw, runId))
    }

    @Test
    fun boundsNativeStatusAndNeverTreatsUnknownAsCompletion() {
        val canceled = NativeAlipayIsolationContract.classifyPayTaskReturn("6001")
        assertFalse(canceled.sdkCompleted)
        assertEquals("6001", canceled.resultStatus)
        assertEquals("pay_task_returned", canceled.bridgeOutcome)

        val success = NativeAlipayIsolationContract.classifyPayTaskReturn("9000")
        assertTrue(success.sdkCompleted)

        val unknown = NativeAlipayIsolationContract.classifyPayTaskReturn("secret-status")
        assertFalse(unknown.sdkCompleted)
        assertEquals("none", unknown.resultStatus)
    }

    @Test
    fun resultJsonContainsOnlySafeFixedFields() {
        val encoded = NativeAlipayIsolationContract.resultJson(
            runId,
            NativeAlipayIsolationContract.classifyPayTaskReturn("6001"),
        )
        val parsed = JSONObject(encoded)
        assertEquals(
            setOf("runId", "sdkCompleted", "resultStatus", "bridgeOutcome"),
            parsed.keys().asSequence().toSet(),
        )
        assertFalse(encoded.contains("orderStr", ignoreCase = true))
        assertFalse(encoded.contains("memo", ignoreCase = true))
        assertFalse(encoded.contains("sign", ignoreCase = true))
    }

    @Test
    fun watchdogTimeoutUsesFixedSafeResult() {
        val timeout = NativeAlipayIsolationResult.nativeWatchdogTimeout()

        assertFalse(timeout.sdkCompleted)
        assertEquals("none", timeout.resultStatus)
        assertEquals("native_watchdog_timeout", timeout.bridgeOutcome)

        val encoded = NativeAlipayIsolationContract.resultJson(runId, timeout)
        assertFalse(encoded.contains("orderStr", ignoreCase = true))
        assertFalse(encoded.contains("sign", ignoreCase = true))
        assertFalse(encoded.contains("secret", ignoreCase = true))
        assertFalse(encoded.contains("token", ignoreCase = true))
    }

    @Test
    fun launcherAcceptsOnlyOneStrictRunId() {
        assertEquals(
            runId,
            AlipayNativeIsolationLaunchContract.parseRunId(mapOf("runId" to runId)),
        )
        assertNull(AlipayNativeIsolationLaunchContract.parseRunId(null))
        assertNull(
            AlipayNativeIsolationLaunchContract.parseRunId(
                mapOf("runId" to runId, "extra" to true),
            ),
        )
        assertNull(
            AlipayNativeIsolationLaunchContract.parseRunId(
                mapOf("runId" to "ABCDEF0123456789ABCDEF0123456789"),
            ),
        )
    }
}
