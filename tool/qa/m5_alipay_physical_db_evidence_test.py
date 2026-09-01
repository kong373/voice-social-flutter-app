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
CREATE_REQUEST_ID = "qa-alipay-0123456789abcdef0123456789abcdef"
OTHER_CREATE_REQUEST_ID = "qa-alipay-fedcba9876543210fedcba9876543210"
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
        create_request_id=CREATE_REQUEST_ID,
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
        self.assertGreaterEqual(script.count("CONCAT_WS('|',"), 2)
        for table in evidence.TABLES:
            self.assertIn(f"MAX(id) FROM {table}", script)
        for forbidden in ("INSERT ", "UPDATE ", "DELETE ", "DROP ", "ALTER ", "TRUNCATE "):
            self.assertNotIn(forbidden, script.upper())
        self.assertIn("TRADE_NOT_EXIST", script)
        self.assertIn("TRADE_CLOSED", script)
        self.assertIn("IFS= read -r create_request_id", script)
        self.assertIn("column_exists recharge_order \"$column\"", script)
        self.assertIn("idempotency_key", script)
        self.assertIn("idempotency_key = '$create_request_id'", script)

    def test_real_mysql_wire_markers_parse_in_exact_start_and_collect_order(self) -> None:
        start_output = (
            "SCHEMA_OK\n"
            "S|2026-09-01 01:02:03.123456|100|200|300|400|500\n"
        )
        start = evidence._parse_db_output(start_output, "start")
        self.assertEqual(start.start_snapshot.max_ids, MAX_IDS)

        collect_output = "\n".join(
            (
                "SCHEMA_OK",
                "B|2026-09-01 01:02:03.123456|101|200|300|400|500",
                "M|1|1|1|1|0|0|0|0|0|0",
                "C|2026-09-01 01:02:03.223456|101|200|300|400|500",
                "F|1|1|1|1|0|0|0|0|0|0",
                "E|2026-09-01 01:02:04.123456|101|200|300|400|500",
                "",
            )
        )
        collect = evidence._parse_db_output(collect_output, "collect")
        self.assertEqual(collect.metrics, collect.metrics_repeat)
        self.assertEqual(collect.after_snapshot.max_ids["recharge_order"], 101)

        with self.assertRaisesRegex(evidence.CollectorError, "INVALID_MARKER"):
            evidence._parse_db_output(
                "SCHEMA_OK\n"
                "S|2026-09-01 01:02:03.123456\t100\t200\t300\t400\t500\n",
                "start",
            )

    def test_read_config_requires_valid_create_request_id(self) -> None:
        with tempfile.TemporaryDirectory() as root:
            os.chmod(root, 0o700)
            resolved_root = str(Path(root).resolve())
            environment = {
                "QA_ALIPAY_PHYSICAL_EVIDENCE_PHASE": "start",
                "QA_ALIPAY_PHYSICAL_SERIAL": SERIAL,
                "QA_ALIPAY_PHYSICAL_RUN_ID": RUN_ID,
                "QA_ALIPAY_PHYSICAL_RUN_STARTED_AT": str(int(time.time())),
                "QA_ALIPAY_PHYSICAL_FLUTTER_SHA": FLUTTER_SHA,
                "QA_ALIPAY_PHYSICAL_BACKEND_SHA": BACKEND_SHA,
                "QA_ALIPAY_PHYSICAL_DB_EVIDENCE_FILE": str(Path(resolved_root) / "evidence.json"),
                "QA_ALIPAY_PHYSICAL_EVIDENCE_STATE_DIR": resolved_root,
                "QA_ALIPAY_PHYSICAL_MYSQL_CONTAINER": "voice-social-m3-development-mysql-1",
                "PATH": "/usr/bin:/bin",
            }
            with patch.object(
                evidence, "_resolve_docker", return_value=("docker", {"PATH": "/usr/bin:/bin"})
            ):
                with self.assertRaisesRegex(evidence.CollectorError, "CONFIGURATION"):
                    evidence.read_config(environment)
                invalid = dict(environment)
                invalid["QA_ALIPAY_PHYSICAL_CREATE_REQUEST_ID"] = "qa-alipay-NOT-VALID"
                with self.assertRaisesRegex(evidence.CollectorError, "CONFIGURATION"):
                    evidence.read_config(invalid)
                valid = dict(environment)
                valid["QA_ALIPAY_PHYSICAL_CREATE_REQUEST_ID"] = CREATE_REQUEST_ID
                config = evidence.read_config(valid)
            self.assertEqual(config.create_request_id, CREATE_REQUEST_ID)

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
            baseline_data = baseline.read_text(encoding="utf-8")
            self.assertIn("createRequestIdSha256", baseline_data)
            self.assertNotIn(CREATE_REQUEST_ID, baseline_data)
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
            self.assertNotIn(CREATE_REQUEST_ID, encoded)
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

    def test_collect_rejects_baseline_bound_to_different_create_request_id(self) -> None:
        with tempfile.TemporaryDirectory() as root:
            os.chmod(root, 0o700)
            output = str(Path(root) / "evidence.json")
            config = _config(root, output)
            with patch.object(evidence, "_run_mysql", return_value=_db_start_result()):
                evidence.start(config)
            collect_config = evidence.Config(
                **{
                    **config.__dict__,
                    "phase": "collect",
                    "create_request_id": OTHER_CREATE_REQUEST_ID,
                }
            )
            with patch.object(evidence, "_run_mysql") as runner:
                with self.assertRaisesRegex(evidence.CollectorError, "INVALID_BASELINE"):
                    evidence.collect(collect_config)
            runner.assert_not_called()

    def test_run_mysql_collect_passes_exact_request_id_over_stdin(self) -> None:
        with tempfile.TemporaryDirectory() as root:
            os.chmod(root, 0o700)
            config = evidence.Config(
                **{
                    **_config(root, str(Path(root) / "evidence.json")).__dict__,
                    "phase": "collect",
                }
            )
            baseline = evidence._Baseline(
                BASELINE_TIMESTAMP,
                MAX_IDS,
                evidence._sha256(CREATE_REQUEST_ID),
                False,
            )
            completed = type(
                "Completed",
                (),
                {
                    "returncode": 0,
                    "stdout": "\n".join(
                        (
                            "SCHEMA_OK",
                            "B|2026-09-01 01:02:03.123456|101|200|300|400|500",
                            "M|1|1|1|1|0|0|0|0|0|0",
                            "C|2026-09-01 01:02:03.223456|101|200|300|400|500",
                            "F|1|1|1|1|0|0|0|0|0|0",
                            "E|2026-09-01 01:02:04.123456|101|200|300|400|500",
                            "",
                        )
                    ),
                },
            )()
            with patch.object(evidence.subprocess, "run", return_value=completed) as run:
                evidence._run_mysql(config, "collect", baseline)
            self.assertEqual(run.call_args.kwargs["input"], "\n".join(
                (
                    BASELINE_TIMESTAMP,
                    "100",
                    "200",
                    "300",
                    "400",
                    "500",
                    CREATE_REQUEST_ID,
                    "",
                )
            ))


if __name__ == "__main__":
    unittest.main()
