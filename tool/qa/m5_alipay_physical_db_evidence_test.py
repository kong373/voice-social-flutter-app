#!/usr/bin/env python3
"""Focused contract tests for the physical Alipay DB evidence hook."""

from __future__ import annotations

import os
from pathlib import Path
import tempfile
import time
import unittest
from unittest.mock import patch

import m5_alipay_physical_db_evidence as evidence


SERIAL = "R58PHYSICAL001"
RUN_ID = "physical-contract"
FLUTTER_SHA = "a" * 40
BACKEND_SHA = "b" * 40
BASELINE_TIMESTAMP = "2026-09-01 01:02:03.123456"
MAX_IDS = {
    "recharge_order": 100,
    "payment_provider_event": 200,
    "wallet_transaction": 300,
    "ledger_journal": 400,
    "ledger_posting": 500,
}


def _config(state_dir: str, evidence_file: str) -> evidence.Config:
    return evidence.Config(
        phase="start",
        serial=SERIAL,
        run_id=RUN_ID,
        run_started_at=int(time.time()),
        flutter_sha=FLUTTER_SHA,
        backend_sha=BACKEND_SHA,
        evidence_file=evidence_file,
        state_dir=state_dir,
        baseline_file=str(Path(state_dir) / "baseline.json"),
        mysql_container="voice-social-m3-development-mysql-1",
        docker_bin="docker",
        docker_env={"PATH": "/usr/bin:/bin"},
    )


def _db_start_result() -> evidence.DbResult:
    return evidence.DbResult(
        start_snapshot=evidence.DbSnapshot(BASELINE_TIMESTAMP, MAX_IDS),
    )


def _db_collect_result() -> evidence.DbResult:
    current_ids = dict(MAX_IDS)
    current_ids["recharge_order"] += 1
    before = evidence.DbSnapshot(BASELINE_TIMESTAMP, current_ids)
    after = evidence.DbSnapshot("2026-09-01 01:02:04.123456", current_ids)
    metrics = evidence.DbMetrics(
        new_order_count=1,
        alipay_order_count=1,
        cancelled_order_count=1,
        safe_provider_order_count=1,
        unsafe_provider_order_count=0,
        missing_provider_status_count=0,
        payment_provider_events=0,
        wallet_transactions=0,
        ledger_journals=0,
        ledger_postings=0,
    )
    return evidence.DbResult(
        before_snapshot=before,
        metrics=metrics,
        middle_snapshot=evidence.DbSnapshot("2026-09-01 01:02:03.223456", current_ids),
        metrics_repeat=metrics,
        after_snapshot=after,
    )


class PhysicalAlipayDbEvidenceContractTest(unittest.TestCase):
    def test_mysql_script_is_aggregate_only_and_has_required_baselines(self) -> None:
        script = evidence.MYSQL_PHYSICAL_EVIDENCE_SCRIPT
        self.assertIn("UTC_TIMESTAMP(6)", script)
        self.assertIn("MYSQL_PWD=", script)
        for table in evidence.TABLES:
            self.assertIn(f"MAX(id) FROM {table}", script)
        for forbidden in ("INSERT ", "UPDATE ", "DELETE ", "DROP ", "ALTER ", "TRUNCATE "):
            self.assertNotIn(forbidden, script.upper())
        self.assertIn("TRADE_NOT_EXIST", script)
        self.assertIn("TRADE_CLOSED", script)

    def test_two_phase_state_and_output_bindings_are_private_and_exact(self) -> None:
        with tempfile.TemporaryDirectory() as root:
            os.chmod(root, 0o700)
            output = str(Path(root) / "evidence.json")
            config = _config(root, output)
            with patch.object(evidence, "_run_mysql", return_value=_db_start_result()):
                evidence.start(config)
            baseline = Path(config.baseline_file)
            self.assertTrue(baseline.is_file())
            self.assertEqual(baseline.stat().st_mode & 0o777, 0o600)
            self.assertFalse(Path(output).exists())

            collect_config = evidence.Config(**{**config.__dict__, "phase": "collect"})
            with patch.object(evidence, "_run_mysql", return_value=_db_collect_result()):
                payload = evidence.collect(collect_config)
            self.assertEqual(
                set(payload),
                {
                    "schema",
                    "status",
                    "serial",
                    "flutterSha",
                    "backendSha",
                    "runId",
                    "runStartedAt",
                    "observedAt",
                    "evidenceSource",
                    "payment",
                    "writeCounters",
                    "secrets",
                },
            )
            self.assertEqual(payload["serial"], SERIAL)
            self.assertEqual(payload["runId"], RUN_ID)
            self.assertEqual(payload["payment"]["provider"], "alipay-sandbox")
            self.assertEqual(payload["payment"]["status"], "CANCELED")
            self.assertEqual(payload["payment"]["databaseStatus"], "CANCELLED")
            self.assertEqual(payload["payment"]["canceledOrderCount"], 1)
            self.assertEqual(
                payload["writeCounters"],
                {
                    "payment_provider_events": 0,
                    "wallet_transactions": 0,
                    "ledger_journals": 0,
                    "ledger_entries": 0,
                },
            )
            self.assertFalse(payload["secrets"])
            output_path = Path(output)
            self.assertEqual(output_path.stat().st_mode & 0o777, 0o600)
            encoded = output_path.read_text(encoding="utf-8")
            self.assertNotIn("order_no", encoded)
            self.assertNotIn("provider_order_id", encoded)
            with self.assertRaises(evidence.CollectorError):
                evidence.collect(collect_config)

    def test_nonzero_financial_delta_and_concurrent_snapshot_fail_closed(self) -> None:
        with tempfile.TemporaryDirectory() as root:
            os.chmod(root, 0o700)
            output = str(Path(root) / "evidence.json")
            config = _config(root, output)
            with patch.object(evidence, "_run_mysql", return_value=_db_start_result()):
                evidence.start(config)
            current = _db_collect_result()
            bad_metrics = evidence.DbMetrics(**{**current.metrics.__dict__, "ledger_postings": 1})
            bad = evidence.DbResult(
                before_snapshot=current.before_snapshot,
                metrics=bad_metrics,
                middle_snapshot=current.middle_snapshot,
                metrics_repeat=bad_metrics,
                after_snapshot=current.after_snapshot,
            )
            collect_config = evidence.Config(**{**config.__dict__, "phase": "collect"})
            with patch.object(evidence, "_run_mysql", return_value=bad):
                with self.assertRaisesRegex(evidence.CollectorError, "INVARIANT_VIOLATION"):
                    evidence.collect(collect_config)
            self.assertFalse(Path(output).exists())

            concurrent_ids = dict(current.after_snapshot.max_ids)
            concurrent_ids["wallet_transaction"] += 1
            concurrent = evidence.DbResult(
                before_snapshot=current.before_snapshot,
                metrics=current.metrics,
                middle_snapshot=current.middle_snapshot,
                metrics_repeat=current.metrics_repeat,
                after_snapshot=evidence.DbSnapshot(
                    "2026-09-01 01:02:04.123456", concurrent_ids
                ),
            )
            with patch.object(evidence, "_run_mysql", return_value=concurrent):
                with self.assertRaisesRegex(evidence.CollectorError, "CONCURRENT_WRITE"):
                    evidence.collect(collect_config)

    def test_invalid_provider_status_or_order_count_is_not_normalized_to_success(self) -> None:
        with tempfile.TemporaryDirectory() as root:
            os.chmod(root, 0o700)
            output = str(Path(root) / "evidence.json")
            config = _config(root, output)
            with patch.object(evidence, "_run_mysql", return_value=_db_start_result()):
                evidence.start(config)
            current = _db_collect_result()
            unsafe = evidence.DbMetrics(
                **{
                    **current.metrics.__dict__,
                    "safe_provider_order_count": 0,
                    "unsafe_provider_order_count": 1,
                }
            )
            collect_config = evidence.Config(**{**config.__dict__, "phase": "collect"})
            with patch.object(
                evidence,
                "_run_mysql",
                return_value=evidence.DbResult(
                    before_snapshot=current.before_snapshot,
                    metrics=unsafe,
                    middle_snapshot=current.middle_snapshot,
                    metrics_repeat=unsafe,
                    after_snapshot=current.after_snapshot,
                ),
            ):
                with self.assertRaisesRegex(evidence.CollectorError, "INVARIANT_VIOLATION"):
                    evidence.collect(collect_config)
            self.assertFalse(Path(output).exists())


if __name__ == "__main__":
    unittest.main()
