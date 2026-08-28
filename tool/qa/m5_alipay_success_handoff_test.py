#!/usr/bin/env python3
"""Provider-free tests for the protected Alipay success handoff."""

from __future__ import annotations

import json
import os
from pathlib import Path
import stat
import tempfile
import unittest
from unittest.mock import patch

from m5_alipay_success_handoff import (
    FLOW_SCHEMA_VERSION,
    HandoffConfig,
    HandoffError,
    MYSQL_HANDOFF_SCRIPT,
    _run_mysql_query,
    _write_json_atomically,
    read_state_file,
    run_handoff,
    validate_fixture_state,
    validate_state_path,
)


BACKEND_SHA = "a" * 40
ORDER_NO = "vs-alipay-success-001"


def _fixture(*, order_no: str | None = None) -> dict[str, object]:
    value: dict[str, object] = {
        "runId": "m5-success-test",
        "backendSha": BACKEND_SHA,
        "customerPhone": "fixture-customer-phone",
        "customerBearer": "customer-token-value",
        "customerUserId": 11,
        "reviewerBearer": "reviewer-token-value",
        "reviewerUserId": 22,
        "executorBearer": "executor-token-value",
        "executorUserId": 33,
        "orderBaselineId": 100,
    }
    if order_no is not None:
        value["orderNo"] = order_no
    return value


class M5AlipaySuccessHandoffTest(unittest.TestCase):
    def setUp(self) -> None:
        self._temporary_root = "/private/tmp" if os.path.isdir("/private/tmp") else None
        self._temporary = tempfile.TemporaryDirectory(
            prefix="m5-success-handoff-test-", dir=self._temporary_root
        )
        self.directory = Path(self._temporary.name)
        os.chmod(self.directory, 0o700)
        self.state_path = self.directory / "fixture.json"
        self.state_path.write_text(json.dumps(_fixture()), encoding="utf-8")
        os.chmod(self.state_path, 0o600)
        self.config = HandoffConfig(
            state_file=self.state_path,
            mysql_container="voice-social-m3-development-mysql-1",
            expected_backend_sha=BACKEND_SHA,
            docker_bin="/usr/bin/docker",
            docker_env={"PATH": "/usr/bin:/bin"},
        )

    def tearDown(self) -> None:
        self._temporary.cleanup()

    def _subprocess_result(self, output: str):
        class Result:
            returncode = 0
            stdout = output

        return Result()

    def test_zero_candidates_fail_closed(self) -> None:
        with patch(
            "m5_alipay_success_handoff.subprocess.run",
            return_value=self._subprocess_result("SCHEMA_OK\n"),
        ):
            with self.assertRaisesRegex(HandoffError, "ORDER_NOT_ELIGIBLE"):
                run_handoff(self.config)
        self.assertNotIn("orderNo", json.loads(self.state_path.read_text()))

    def test_one_candidate_is_atomically_bound_without_output_value(self) -> None:
        with patch(
            "m5_alipay_success_handoff.subprocess.run",
            return_value=self._subprocess_result(f"SCHEMA_OK\n{ORDER_NO}\n"),
        ) as command:
            result = run_handoff(self.config)
        self.assertEqual(result["schemaVersion"], FLOW_SCHEMA_VERSION)
        self.assertTrue(result["orderBound"])
        self.assertNotIn(ORDER_NO, json.dumps(result, sort_keys=True))
        state = json.loads(self.state_path.read_text())
        self.assertEqual(state["orderNo"], ORDER_NO)
        self.assertEqual(stat.S_IMODE(self.state_path.stat().st_mode), 0o600)
        self.assertNotIn(ORDER_NO, " ".join(command.call_args.args[0]))
        self.assertNotIn(ORDER_NO, command.call_args.kwargs["input"])

    def test_multiple_candidates_fail_closed(self) -> None:
        output = f"SCHEMA_OK\n{ORDER_NO}\nvs-alipay-success-002\n"
        with patch(
            "m5_alipay_success_handoff.subprocess.run",
            return_value=self._subprocess_result(output),
        ):
            with self.assertRaisesRegex(HandoffError, "ORDER_NOT_ELIGIBLE"):
                run_handoff(self.config)

    def test_wrong_provider_status_user_and_baseline_are_sql_rejected(self) -> None:
        # These are intentionally checked as source-level contract assertions:
        # raw order rows never cross the container boundary for Python-side
        # filtering, so the database predicates are the authority.
        required_predicates = (
            "o.user_id = $customer_user_id",
            "o.id > $order_baseline_id",
            "o.payment_provider = 'alipay-sandbox'",
            "o.status = 'SUCCEEDED'",
            "o.provider_status IN ('TRADE_SUCCESS', 'TRADE_FINISHED')",
            "pe.status = 'PROCESSED'",
            "pe.observed_status IN ('TRADE_SUCCESS', 'TRADE_FINISHED')",
            "wt.business_type = 'PAYMENT_RECHARGE'",
            "lj.business_type = 'PAYMENT_RECHARGE'",
        )
        for predicate in required_predicates:
            with self.subTest(predicate=predicate):
                self.assertIn(predicate, MYSQL_HANDOFF_SCRIPT)

    def test_schema_missing_and_malformed_marker_fail_closed(self) -> None:
        for output, category in (
            ("SCHEMA_MISSING\n", "SCHEMA_MISSING"),
            ("unexpected\n", "INVARIANT_VIOLATION"),
            ("SCHEMA_OK\nnot an order\n", "INVARIANT_VIOLATION"),
        ):
            with self.subTest(output=output):
                with patch(
                    "m5_alipay_success_handoff.subprocess.run",
                    return_value=self._subprocess_result(output),
                ):
                    with self.assertRaisesRegex(HandoffError, category):
                        _run_mysql_query(self.config, read_state_file(
                            self.state_path,
                            expected_backend_sha=BACKEND_SHA,
                            require_unbound=True,
                        )[0])

    def test_private_state_file_path_permissions_and_symlink_are_rejected(self) -> None:
        os.chmod(self.state_path, 0o640)
        with self.assertRaisesRegex(HandoffError, "STATE"):
            validate_state_path(str(self.state_path))
        os.chmod(self.state_path, 0o600)
        link = self.directory / "link.json"
        link.symlink_to(self.state_path)
        with self.assertRaisesRegex(HandoffError, "STATE"):
            validate_state_path(str(link))
        os.chmod(self.directory, 0o755)
        with self.assertRaisesRegex(HandoffError, "STATE"):
            validate_state_path(str(self.state_path))

    def test_state_backend_actor_schema_and_unbound_checks(self) -> None:
        valid = _fixture()
        state = validate_fixture_state(valid, expected_backend_sha=BACKEND_SHA)
        self.assertEqual(state.customer_user_id, 11)
        with self.assertRaisesRegex(HandoffError, "STATE"):
            validate_fixture_state(
                dict(valid, backendSha="b" * 40), expected_backend_sha=BACKEND_SHA
            )
        with self.assertRaisesRegex(HandoffError, "STATE"):
            validate_fixture_state(
                dict(valid, executorUserId=22), expected_backend_sha=BACKEND_SHA
            )
        with self.assertRaisesRegex(HandoffError, "STATE"):
            validate_fixture_state(
                dict(valid, orderNo=ORDER_NO),
                expected_backend_sha=BACKEND_SHA,
                require_unbound=True,
            )

    def test_state_update_rejects_non_serializable_values_without_corrupting_file(self) -> None:
        before = self.state_path.read_bytes()
        with self.assertRaisesRegex(HandoffError, "OUTPUT_WRITE"):
            _write_json_atomically(self.state_path, {"bad": object()})
        self.assertEqual(self.state_path.read_bytes(), before)


if __name__ == "__main__":
    unittest.main()
