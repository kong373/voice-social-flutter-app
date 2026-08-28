#!/usr/bin/env python3
"""Offline protocol tests for the aggregate-only refund ledger helper."""

from __future__ import annotations

import io
import json
import hashlib
import subprocess
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from unittest.mock import patch

from m5_alipay_refund_ledger_evidence import (
    LedgerConfig,
    LedgerEvidenceError,
    MYSQL_LEDGER_SCRIPT,
    _run_query,
    _development_mysql_container,
    _state_path,
    _write_state,
    collect,
    main,
)


ORDER_NO = "202608280001234"
REFUND_ID = "00000000-0000-4000-8000-000000000001"


def _config(state_dir: str) -> LedgerConfig:
    return LedgerConfig(
        container="mysql",
        docker_bin="/usr/bin/docker",
        docker_env={"PATH": "/usr/bin:/bin"},
        state_dir=state_dir,
        run_id="m5-refund-ledger-test",
    )


def _collect_values(*, reconcile: bool = True) -> list[int]:
    values = [1] * 28
    values[6] = 0  # reserve release credit
    values[8] = 2  # the reserve journal has two postings
    values[9] = 0  # balanced journal
    values[10] = 2 if reconcile else 1
    values[25] = 1 if reconcile else 0
    values[27] = 1 if reconcile else 0
    return values


class LedgerEvidenceProtocolTest(unittest.TestCase):
    def test_argument_error_does_not_echo_protected_value(self) -> None:
        output = io.StringIO()
        error = io.StringIO()
        protected = "Bearer accidental-token-value"
        with redirect_stdout(output), redirect_stderr(error):
            self.assertEqual(main(["--start", protected]), 2)
        self.assertNotIn(protected, output.getvalue())
        self.assertNotIn(protected, error.getvalue())
        self.assertEqual(error.getvalue(), "")

    def test_mysql_container_is_limited_to_development(self) -> None:
        self.assertEqual(
            _development_mysql_container("voice-social-m3-development-mysql-1"),
            "voice-social-m3-development-mysql-1",
        )
        with self.assertRaisesRegex(LedgerEvidenceError, "CONFIGURATION"):
            _development_mysql_container("voice-social-production-mysql-1")

    def test_query_parser_requires_schema_marker_and_all_collect_columns(self) -> None:
        output = "SCHEMA_OK\n" + "\t".join("1" for _ in range(28)) + "\n"
        completed = subprocess.CompletedProcess([], 0, stdout=output, stderr="")
        with tempfile.TemporaryDirectory() as state_dir:
            config = _config(state_dir)
            with patch(
                "m5_alipay_refund_ledger_evidence.subprocess.run",
                return_value=completed,
            ) as run:
                values = _run_query(config, "collect", ORDER_NO, REFUND_ID)
            self.assertEqual(len(values), 28)
            command = run.call_args.args[0]
            self.assertEqual(command[:4], ["/usr/bin/docker", "exec", "-i", "mysql"])
            self.assertNotIn(ORDER_NO, command[-1])
            self.assertNotIn(REFUND_ID, command[-1])
            self.assertIn("java.lang.Boolean:false", MYSQL_LEDGER_SCRIPT)
            self.assertIn("java.lang.Boolean:true", MYSQL_LEDGER_SCRIPT)

    def test_schema_missing_is_safe_category(self) -> None:
        completed = subprocess.CompletedProcess(
            [], 0, stdout="SCHEMA_MISSING\n1\t1\t1\n", stderr="",
        )
        with tempfile.TemporaryDirectory() as state_dir:
            with patch(
                "m5_alipay_refund_ledger_evidence.subprocess.run",
                return_value=completed,
            ):
                with self.assertRaisesRegex(LedgerEvidenceError, "SCHEMA_MISSING"):
                    _run_query(_config(state_dir), "start", ORDER_NO, None)

    def test_collect_maps_separate_idempotency_counts_without_identifiers(self) -> None:
        with tempfile.TemporaryDirectory() as state_dir:
            config = _config(state_dir)
            _write_state(
                _state_path(config),
                {
                    "schemaVersion": "m5-alipay-refund-ledger-v1",
                    "runIdHash": hashlib.sha256(config.run_id.encode()).hexdigest(),
                    "orderRefSha256": hashlib.sha256(ORDER_NO.encode()).hexdigest(),
                    "baseline": {
                        "orderRows": 1,
                        "eligibleOrderRows": 1,
                        "refundRows": 0,
                    },
                    "startedAtEpoch": 1,
                    "consumed": False,
                },
            )
            with patch(
                "m5_alipay_refund_ledger_evidence._run_query",
                return_value=_collect_values(),
            ):
                result = collect(config, ORDER_NO, REFUND_ID)
            self.assertEqual(result["executeIdempotencyRows"], 1)
            self.assertEqual(result["reconcileIdempotencyRows"], 1)
            self.assertEqual(result["executeFingerprintCount"], 1)
            self.assertEqual(result["reconcileFingerprintCount"], 1)
            self.assertEqual(result["operationIdempotencyRows"], 2)
            encoded = json.dumps(result, sort_keys=True)
            self.assertNotIn(ORDER_NO, encoded)
            self.assertNotIn(REFUND_ID, encoded)

    def test_collect_rejects_idempotency_count_not_bound_to_exact_fingerprint(self) -> None:
        with tempfile.TemporaryDirectory() as state_dir:
            config = _config(state_dir)
            _write_state(
                _state_path(config),
                {
                    "schemaVersion": "m5-alipay-refund-ledger-v1",
                    "runIdHash": hashlib.sha256(config.run_id.encode()).hexdigest(),
                    "orderRefSha256": hashlib.sha256(ORDER_NO.encode()).hexdigest(),
                    "baseline": {
                        "orderRows": 1,
                        "eligibleOrderRows": 1,
                        "refundRows": 0,
                    },
                    "startedAtEpoch": 1,
                    "consumed": False,
                },
            )
            values = _collect_values()
            values[26] = 0  # row exists but is not the exact execute fingerprint
            with patch(
                "m5_alipay_refund_ledger_evidence._run_query",
                return_value=values,
            ):
                with self.assertRaisesRegex(LedgerEvidenceError, "STATE"):
                    collect(config, ORDER_NO, REFUND_ID)


if __name__ == "__main__":
    unittest.main()
