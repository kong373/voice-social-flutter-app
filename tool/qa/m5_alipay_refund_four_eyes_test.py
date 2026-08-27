#!/usr/bin/env python3
"""Offline behaviour tests for the M5 Alipay Finance refund harness.

These tests never open a socket, start Docker, or invoke a payment provider.
They exercise the protected-input gate, the redacted flow state machine, and
the same-id idempotency contract with in-memory doubles.
"""

from __future__ import annotations

import hashlib
import json
import unittest

from m5_alipay_refund_four_eyes import (
    EXPECTED_CONFIRMATION,
    EXPECTED_CONFIRMATION_2,
    FLOW_SCHEMA_VERSION,
    LedgerPort,
    RefundApiClient,
    RefundHarnessConfig,
    RefundHarnessError,
    authorize_provider,
    build_safe_summary,
    run_flow,
    sanitize_response,
    _validate_provider_result,
    _validate_review,
)


ORDER_NO = "202608280001234"
REFUND_ID = "00000000-0000-4000-8000-000000000001"
REVIEWER_ID = 101
EXECUTOR_ID = 202
OWNER_ID = 303


def _config(*, confirmations: bool = True) -> RefundHarnessConfig:
    return RefundHarnessConfig(
        base_url="https://backend.example.test/",
        order_no=ORDER_NO,
        user_bearer="user-token-value",
        reviewer_bearer="reviewer-token-value",
        executor_bearer="executor-token-value",
        reason="QA sandbox refund",
        run_id="m5-refund-offline-test",
        mysql_container="mysql",
        state_dir="/private/tmp/m5-refund-state",
        allow_provider=confirmations,
        confirmation=EXPECTED_CONFIRMATION if confirmations else "",
        confirmation_2=EXPECTED_CONFIRMATION_2 if confirmations else "",
        artifact_dir=None,
        allow_insecure_http=False,
    )


class FakeApi(RefundApiClient):
    def __init__(self, *, execute_status: str = "PENDING") -> None:
        self.calls: list[tuple[str, str, str | None]] = []
        self.execute_status = execute_status
        self.provider_calls = 0
        self.reconcile_calls = 0

    def order_status(self, order_no: str, bearer: str) -> dict[str, object]:
        self.calls.append(("order_status", order_no, None))
        return {
            "orderNo": order_no,
            "status": "SUCCEEDED",
            "provider": "alipay-sandbox",
            "providerStatus": "TRADE_SUCCESS",
            "bool": True,
            "providerInvocation": False,
        }

    def apply_refund(
        self, order_no: str, reason: str, bearer: str, request_id: str
    ) -> dict[str, object]:
        self.calls.append(("apply", order_no, request_id))
        return {
            "refundId": REFUND_ID,
            "orderNo": order_no,
            "status": "SUBMITTED",
            "completed": False,
        }

    def approve_refund(
        self, refund_id: str, bearer: str, request_id: str
    ) -> dict[str, object]:
        self.calls.append(("approve", refund_id, request_id))
        return {
            "refundId": refund_id,
            "orderNo": ORDER_NO,
            "userId": OWNER_ID,
            "status": "APPROVED",
            "providerStatus": "APPROVED",
            "reviewedByUserId": REVIEWER_ID,
            "executedByUserId": None,
            "fourEyesRequired": True,
            "providerInvocation": False,
        }

    def execute_refund(
        self, refund_id: str, bearer: str, request_id: str
    ) -> dict[str, object]:
        self.calls.append(("execute", refund_id, request_id))
        # A repeat with the same request id is a backend idempotency replay and
        # must not be counted as a second provider request.
        if sum(call[0] == "execute" for call in self.calls) == 1:
            self.provider_calls += 1
        status = self.execute_status
        return {
            "refundId": refund_id,
            "orderNo": ORDER_NO,
            "userId": OWNER_ID,
            "status": "COMPLETED" if status == "REFUNDED" else "APPROVED",
            "providerStatus": status,
            "completed": status == "REFUNDED",
            "reviewedByUserId": REVIEWER_ID,
            "executedByUserId": EXECUTOR_ID,
            "fourEyesRequired": True,
            "providerInvocation": True,
        }

    def reconcile_refund(
        self, refund_id: str, bearer: str, request_id: str
    ) -> dict[str, object]:
        self.calls.append(("reconcile", refund_id, request_id))
        if sum(call[0] == "reconcile" for call in self.calls) == 1:
            self.reconcile_calls += 1
        return {
            "refundId": refund_id,
            "orderNo": ORDER_NO,
            "userId": OWNER_ID,
            "status": "COMPLETED",
            "providerStatus": "REFUNDED",
            "completed": True,
            "reviewedByUserId": REVIEWER_ID,
            "executedByUserId": EXECUTOR_ID,
            "fourEyesRequired": True,
            "providerInvocation": True,
        }

    def refund_result(self, refund_id: str, bearer: str) -> dict[str, object]:
        self.calls.append(("result", refund_id, None))
        return {
            "refundId": refund_id,
            "orderNo": ORDER_NO,
            "userId": OWNER_ID,
            "status": "COMPLETED",
            "providerStatus": "REFUNDED",
            "completed": True,
        }


class FakeLedger(LedgerPort):
    def __init__(self, *, reconcile: bool = True) -> None:
        self.started: list[str] = []
        self.collected: list[tuple[str, str]] = []
        self.reconcile = reconcile

    def start(self, order_no: str) -> None:
        self.started.append(order_no)

    def collect(self, order_no: str, refund_id: str) -> dict[str, object]:
        self.collected.append((order_no, refund_id))
        return {
            "reserveDebitCount": 1,
            "reserveReleaseCreditCount": 0,
            "reserveJournalCount": 1,
            "reservePostingCount": 2,
            "reserveUnbalancedCount": 0,
            "executeIdempotencyRows": 1,
            "reconcileIdempotencyRows": 1 if self.reconcile else 0,
            "executeFingerprintCount": 1,
            "reconcileFingerprintCount": 1 if self.reconcile else 0,
            "operationIdempotencyRows": 2 if self.reconcile else 1,
            "reviewedActorCount": 1,
            "executedActorCount": 1,
            "distinctFinanceActorCount": 1,
            "ownerDistinctReviewerCount": 1,
            "ownerDistinctExecutorCount": 1,
            "outRequestMatchCount": 1,
            "reserveAmountMatchCount": 1,
            "refundProviderOrderMatchCount": 1,
            "refundAmountMatchCount": 1,
            "balancedReserveJournalCount": 1,
            "ledgerImbalanceCount": 0,
        }


class M5AlipayRefundHarnessTest(unittest.TestCase):
    def test_provider_is_disabled_without_both_exact_confirmations(self) -> None:
        config = _config(confirmations=False)
        with self.assertRaisesRegex(RefundHarnessError, "PROVIDER_CONFIRMATION_REQUIRED"):
            authorize_provider(config)

    def test_response_sanitizer_drops_identifier_and_amount_fields(self) -> None:
        value = sanitize_response(
            {
                "refundId": REFUND_ID,
                "orderNo": ORDER_NO,
                "userId": OWNER_ID,
                "amountMinor": 600,
                "provider": "alipay-sandbox",
                "status": "COMPLETED",
                "providerStatus": "REFUNDED",
                "completed": True,
                "providerInvocation": True,
            }
        )
        encoded = json.dumps(value, sort_keys=True)
        self.assertNotIn(REFUND_ID, encoded)
        self.assertNotIn(ORDER_NO, encoded)
        self.assertNotIn("600", encoded)
        self.assertEqual(value["status"], "COMPLETED")
        self.assertTrue(value["completed"])

    def test_pending_execute_reconciles_with_same_refund_id_and_replays(self) -> None:
        api = FakeApi(execute_status="PENDING")
        ledger = FakeLedger()
        result = run_flow(_config(), api=api, ledger=ledger)
        self.assertEqual(result["status"], "PASS")
        self.assertTrue(result["idempotency"]["sameRefundId"])
        self.assertTrue(result["idempotency"]["sameOutRequestNo"])
        self.assertTrue(result["idempotency"]["executeReplay"])
        self.assertTrue(result["idempotency"]["reconcileReplay"])
        self.assertEqual(api.provider_calls, 1)
        self.assertEqual(api.reconcile_calls, 1)
        execute_ids = [item[1] for item in api.calls if item[0] == "execute"]
        reconcile_ids = [item[1] for item in api.calls if item[0] == "reconcile"]
        self.assertEqual(execute_ids, [REFUND_ID, REFUND_ID])
        self.assertEqual(reconcile_ids, [REFUND_ID, REFUND_ID])
        self.assertEqual(ledger.started, [ORDER_NO])
        self.assertEqual(ledger.collected, [(ORDER_NO, REFUND_ID)])
        encoded = json.dumps(result, sort_keys=True)
        self.assertNotIn(REFUND_ID, encoded)
        self.assertNotIn(ORDER_NO, encoded)
        self.assertNotIn("userId", encoded)
        self.assertNotIn("amountMinor", encoded)

    def test_terminal_execute_uses_idempotent_replay_without_second_provider_query(self) -> None:
        api = FakeApi(execute_status="REFUNDED")
        result = run_flow(_config(), api=api, ledger=FakeLedger(reconcile=False))
        self.assertEqual(result["status"], "PASS")
        self.assertFalse(result["idempotency"]["reconcileRequired"])
        self.assertTrue(result["idempotency"]["executeReplay"])
        self.assertEqual(api.provider_calls, 1)
        self.assertFalse(any(call[0] == "reconcile" for call in api.calls))

    def test_review_rejects_owner_as_reviewer(self) -> None:
        with self.assertRaisesRegex(RefundHarnessError, "INVARIANT_VIOLATION"):
            _validate_review(
                {
                    "refundId": REFUND_ID,
                    "status": "APPROVED",
                    "providerStatus": "APPROVED",
                    "fourEyesRequired": True,
                    "providerInvocation": False,
                    "userId": OWNER_ID,
                    "reviewedByUserId": OWNER_ID,
                },
                REFUND_ID,
            )

    def test_execute_rejects_reviewer_or_owner_as_executor(self) -> None:
        base = {
            "refundId": REFUND_ID,
            "status": "COMPLETED",
            "providerStatus": "REFUNDED",
            "providerInvocation": True,
            "completed": True,
            "fourEyesRequired": True,
            "userId": OWNER_ID,
            "reviewedByUserId": REVIEWER_ID,
        }
        for actor_id in (REVIEWER_ID, OWNER_ID):
            with self.subTest(actor_id=actor_id):
                row = dict(base, executedByUserId=actor_id)
                with self.assertRaisesRegex(RefundHarnessError, "INVARIANT_VIOLATION"):
                    _validate_provider_result(
                        row,
                        REFUND_ID,
                        OWNER_ID,
                        REVIEWER_ID,
                    )

    def test_summary_contains_only_fixed_safe_shapes_and_hashes(self) -> None:
        summary = build_safe_summary(
            order_no=ORDER_NO,
            refund_id=REFUND_ID,
            order_status="SUCCEEDED",
            refund_status="COMPLETED",
            provider_status="REFUNDED",
            ledger={"reserveDebitCount": 1},
            idempotency={"sameRefundId": True},
        )
        self.assertEqual(summary["schemaVersion"], FLOW_SCHEMA_VERSION)
        self.assertEqual(summary["hashes"]["orderRefSha256"], hashlib.sha256(ORDER_NO.encode()).hexdigest())
        self.assertEqual(summary["hashes"]["refundRefSha256"], hashlib.sha256(REFUND_ID.encode()).hexdigest())
        encoded = json.dumps(summary, sort_keys=True)
        for forbidden in (ORDER_NO, REFUND_ID, "amountMinor", "providerRefundId", "userId", "Bearer"):
            self.assertNotIn(forbidden, encoded)


if __name__ == "__main__":
    unittest.main()
