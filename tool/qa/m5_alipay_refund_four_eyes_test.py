#!/usr/bin/env python3
"""Offline behaviour tests for the M5 Alipay Finance refund harness.

These tests never open a socket, start Docker, or invoke a payment provider.
They exercise the protected-input gate, the redacted flow state machine, and
the same-id idempotency contract with in-memory doubles.
"""

from __future__ import annotations

import hashlib
import dataclasses
import io
import json
import os
from pathlib import Path
import stat
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from unittest.mock import patch

from m5_alipay_refund_four_eyes import (
    EXPECTED_CONFIRMATION,
    EXPECTED_CONFIRMATION_2,
    FLOW_SCHEMA_VERSION,
    LedgerPort,
    RefundApiClient,
    RefundHarnessConfig,
    RefundHarnessError,
    authorize_provider,
    _validate_development_mysql_container,
    build_safe_summary,
    main,
    run_flow,
    sanitize_response,
    validate_base_url,
    _validate_refund_reason,
    _validate_provider_result,
    _validate_review,
    _read_protected_refund_state,
    read_config,
)


ORDER_NO = "202608280001234"
REFUND_ID = "00000000-0000-4000-8000-000000000001"
REVIEWER_ID = 101
EXECUTOR_ID = 202
OWNER_ID = 303
BACKEND_SHA = "a" * 40
FIXTURE_ID = "m5-fresh-refund-test"


def _config(*, confirmations: bool = True) -> RefundHarnessConfig:
    return RefundHarnessConfig(
        base_url="https://backend.example.test/",
        fixture_id=FIXTURE_ID,
        order_no=ORDER_NO,
        user_bearer="user-token-value",
        reviewer_bearer="reviewer-token-value",
        executor_bearer="executor-token-value",
        reason="QA sandbox refund",
        run_id="m5-refund-offline-test",
        mysql_container="mysql",
        state_dir="/private/tmp/m5-refund-state",
        expected_customer_user_id=OWNER_ID,
        expected_reviewer_user_id=REVIEWER_ID,
        expected_executor_user_id=EXECUTOR_ID,
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
    def setUp(self) -> None:
        temporary_root = "/private/tmp" if os.path.isdir("/private/tmp") else None
        self._temporary = tempfile.TemporaryDirectory(
            prefix="m5-refund-protected-state-test-", dir=temporary_root
        )
        self.protected_dir = Path(self._temporary.name)
        os.chmod(self.protected_dir, 0o700)
        self.protected_state = self.protected_dir / "fixture.json"
        self.protected_state.write_text(
            json.dumps(
                {
                    "schemaVersion": 2,
                    "fixtureId": FIXTURE_ID,
                    "runId": "m5-refund-protected-test",
                    "backendSha": BACKEND_SHA,
                    "customerPhone": "fixture-customer-phone",
                    "customerBearer": "Bearer customer-token-value",
                    "customerUserId": 11,
                    "reviewerBearer": "Bearer reviewer-token-value",
                    "reviewerUserId": 22,
                    "executorBearer": "Bearer executor-token-value",
                    "executorUserId": 33,
                    "orderBaselineId": 100,
                    "orderNo": ORDER_NO,
                }
            ),
            encoding="utf-8",
        )
        os.chmod(self.protected_state, 0o600)

    def tearDown(self) -> None:
        self._temporary.cleanup()

    def test_refund_reason_matches_backend_256_character_limit(self) -> None:
        self.assertEqual(_validate_refund_reason("r" * 256), "r" * 256)
        with self.assertRaisesRegex(RefundHarnessError, "CONFIGURATION"):
            _validate_refund_reason("r" * 257)

    def test_protected_state_loads_order_and_three_distinct_bearers(self) -> None:
        values = _read_protected_refund_state(
            {
                "QA_M5_REFUND_PROTECTED_STATE_FILE": str(self.protected_state),
                "QA_M5_REFUND_BACKEND_SHA": BACKEND_SHA,
                "QA_M5_FINANCE_FIXTURE_ID": FIXTURE_ID,
            },
            run_id="m5-refund-protected-test",
        )
        self.assertEqual(values[0], ORDER_NO)
        self.assertEqual(values[1], "Bearer customer-token-value")
        self.assertEqual(values[2], "Bearer reviewer-token-value")
        self.assertEqual(values[3], "Bearer executor-token-value")
        self.assertEqual(values[4:7], (11, 22, 33))
        self.assertEqual(values[-1], FIXTURE_ID)
        self.assertNotIn("fixture-customer-phone", json.dumps(values))

    def test_protected_state_conflicts_with_any_legacy_input(self) -> None:
        environment = {
            "QA_M5_REFUND_PROTECTED_STATE_FILE": str(self.protected_state),
            "QA_M5_REFUND_BACKEND_SHA": BACKEND_SHA,
            "QA_M5_FINANCE_FIXTURE_ID": FIXTURE_ID,
            "QA_M5_REFUND_ORDER_NO": ORDER_NO,
        }
        with self.assertRaisesRegex(RefundHarnessError, "CONFIGURATION"):
            _read_protected_refund_state(
                environment, run_id="m5-refund-protected-test"
            )

    def test_protected_state_rejects_bad_path_permissions_and_symlink(self) -> None:
        os.chmod(self.protected_state, 0o640)
        with self.assertRaisesRegex(RefundHarnessError, "STATE"):
            _read_protected_refund_state(
                {
                    "QA_M5_REFUND_PROTECTED_STATE_FILE": str(self.protected_state),
                    "QA_M5_REFUND_BACKEND_SHA": BACKEND_SHA,
                    "QA_M5_FINANCE_FIXTURE_ID": FIXTURE_ID,
                },
                run_id="m5-refund-protected-test",
            )
        os.chmod(self.protected_state, 0o600)
        symlink = self.protected_dir / "symlink.json"
        symlink.symlink_to(self.protected_state)
        with self.assertRaisesRegex(RefundHarnessError, "STATE"):
            _read_protected_refund_state(
                {
                    "QA_M5_REFUND_PROTECTED_STATE_FILE": str(symlink),
                    "QA_M5_REFUND_BACKEND_SHA": BACKEND_SHA,
                    "QA_M5_FINANCE_FIXTURE_ID": FIXTURE_ID,
                },
                run_id="m5-refund-protected-test",
            )

    def test_protected_state_rejects_schema_run_backend_and_actor_mismatch(self) -> None:
        base = json.loads(self.protected_state.read_text(encoding="utf-8"))
        cases = (
            ("schemaVersion", 1),
            ("schemaVersion", "v2"),
            ("fixtureId", "m5-fresh-another-fixture"),
            ("runId", "another-run"),
            ("backendSha", "b" * 40),
            ("executorUserId", 22),
        )
        for key, value in cases:
            with self.subTest(key=key):
                candidate = dict(base, **{key: value})
                self.protected_state.write_text(json.dumps(candidate), encoding="utf-8")
                os.chmod(self.protected_state, 0o600)
                with self.assertRaisesRegex(RefundHarnessError, "STATE"):
                    _read_protected_refund_state(
                        {
                            "QA_M5_REFUND_PROTECTED_STATE_FILE": str(self.protected_state),
                            "QA_M5_REFUND_BACKEND_SHA": BACKEND_SHA,
                            "QA_M5_FINANCE_FIXTURE_ID": FIXTURE_ID,
                        },
                        run_id="m5-refund-protected-test",
                    )
        self.protected_state.write_text(json.dumps(base), encoding="utf-8")
        os.chmod(self.protected_state, 0o600)

    def test_read_config_uses_protected_state_without_legacy_values(self) -> None:
        environment = {
            "QA_M5_REFUND_BASE_URL": "https://backend.example.test/",
            "QA_M5_REFUND_PROTECTED_STATE_FILE": str(self.protected_state),
            "QA_M5_REFUND_BACKEND_SHA": BACKEND_SHA,
            "QA_M5_FINANCE_FIXTURE_ID": FIXTURE_ID,
            "QA_M5_REFUND_RUN_ID": "m5-refund-protected-test",
            "QA_M5_REFUND_MYSQL_CONTAINER": "voice-social-m3-development-mysql-1",
            "QA_M5_REFUND_LEDGER_STATE_DIR": str(self.protected_dir),
        }
        with patch(
            "m5_alipay_refund_four_eyes.read_ledger_config", return_value=None
        ):
            config = read_config(environment)
        self.assertEqual(config.order_no, ORDER_NO)
        self.assertEqual(config.fixture_id, FIXTURE_ID)
        self.assertEqual(config.user_bearer, "Bearer customer-token-value")
        self.assertEqual(config.expected_customer_user_id, 11)
        self.assertEqual(config.expected_reviewer_user_id, 22)
        self.assertEqual(config.expected_executor_user_id, 33)
        self.assertEqual(config.protected_state_file, str(self.protected_state))

    def test_read_config_rejects_legacy_order_and_bearer_inputs(self) -> None:
        environment = {
            "QA_M5_REFUND_BASE_URL": "https://backend.example.test/",
            "QA_M5_REFUND_RUN_ID": "m5-refund-protected-test",
            "QA_M5_REFUND_ORDER_NO": ORDER_NO,
            "QA_M5_REFUND_USER_BEARER": "Bearer customer-token-value",
            "QA_M5_REFUND_REVIEWER_BEARER": "Bearer reviewer-token-value",
            "QA_M5_REFUND_EXECUTOR_BEARER": "Bearer executor-token-value",
            "QA_M5_REFUND_MYSQL_CONTAINER": "voice-social-m3-development-mysql-1",
            "QA_M5_REFUND_LEDGER_STATE_DIR": str(self.protected_dir),
        }
        with self.assertRaisesRegex(RefundHarnessError, "CONFIGURATION"):
            read_config(environment)

    def test_provider_is_disabled_without_both_exact_confirmations(self) -> None:
        config = _config(confirmations=False)
        with self.assertRaisesRegex(RefundHarnessError, "PROVIDER_CONFIRMATION_REQUIRED"):
            authorize_provider(config)

    def test_authorized_failure_never_claims_zero_provider_calls(self) -> None:
        output = io.StringIO()
        environment = {
            "QA_M5_REFUND_ALLOW_PROVIDER": "true",
            "QA_M5_REFUND_CONFIRMATION": EXPECTED_CONFIRMATION,
            "QA_M5_REFUND_CONFIRMATION_2": EXPECTED_CONFIRMATION_2,
            # Leave all protected runtime inputs absent so configuration
            # fails before opening a socket.  The authorized failure shape is
            # deliberately conservative because later failures may occur
            # after the provider boundary.
        }
        with patch.dict(os.environ, environment, clear=True), redirect_stdout(output):
            exit_code = main(["--run"])
        self.assertEqual(exit_code, 2)
        result = json.loads(output.getvalue())
        self.assertEqual(result["status"], "FAIL")
        self.assertEqual(result["providerInvocation"], "UNKNOWN")

    def test_argument_error_does_not_echo_protected_value(self) -> None:
        output = io.StringIO()
        error = io.StringIO()
        protected = "Bearer-SECRET-TOKEN-123456789"
        with redirect_stdout(output), redirect_stderr(error):
            self.assertEqual(main(["--run", protected]), 2)
        self.assertNotIn(protected, output.getvalue())
        self.assertNotIn(protected, error.getvalue())
        self.assertEqual(error.getvalue(), "")

    def test_protected_principals_are_bound_to_authoritative_responses(self) -> None:
        config = dataclasses.replace(_config(), expected_customer_user_id=999)
        with self.assertRaisesRegex(RefundHarnessError, "INVARIANT_VIOLATION"):
            run_flow(config, api=FakeApi(), ledger=FakeLedger())

    def test_insecure_http_is_limited_to_the_host_loopback(self) -> None:
        validate_base_url(
            "http://127.0.0.1:18080/", allow_insecure_http=True
        )
        with self.assertRaisesRegex(RefundHarnessError, "CONFIGURATION"):
            validate_base_url(
                "http://10.0.2.2:18080/", allow_insecure_http=True
            )

    def test_mysql_container_is_limited_to_development(self) -> None:
        self.assertEqual(
            _validate_development_mysql_container(
                "voice-social-m3-development-mysql-1"
            ),
            "voice-social-m3-development-mysql-1",
        )
        with self.assertRaisesRegex(RefundHarnessError, "CONFIGURATION"):
            _validate_development_mysql_container(
                "voice-social-production-mysql-1"
            )

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
