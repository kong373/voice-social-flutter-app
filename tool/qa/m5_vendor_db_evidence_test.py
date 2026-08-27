#!/usr/bin/env python3
"""Contract and hostile-input tests for the M5 vendor DB evidence helper."""

from __future__ import annotations

import csv
import io
import json
import os
from pathlib import Path
import re
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from unittest.mock import patch

from m5_vendor_db_evidence import (
    ALLOWED_ERROR_CATEGORIES,
    FORBIDDEN_MARKER_TERMS,
    MYSQL_EVIDENCE_SCRIPT,
    EvidenceBinding,
    EvidenceConfig,
    EvidenceError,
    CHECK_NAMES,
    COLLECT_REQUEST_TIMEOUT_SECONDS,
    DOCKER_EVIDENCE_TIMEOUT_SECONDS,
    M5_CALLBACK_SCOPE_LINK_COLUMN,
    M5EvidenceSessionCollector,
    M5EvidenceServer,
    START_REQUEST_TIMEOUT_SECONDS,
    TABLE_SPECS,
    build_payload,
    parse_mysql_markers,
    payload_to_csv,
    _fixture_nickname,
    _state_snapshot,
    validate_evidence_url,
    validate_binding,
    validate_payload,
)


BACKEND_SHA = "a" * 40
FLUTTER_SHA = "b" * 40
APK_SHA = "c" * 64


def _binding() -> EvidenceBinding:
    return EvidenceBinding(
        run_id="m5-contract-run",
        backend_sha=BACKEND_SHA,
        flutter_sha=FLUTTER_SHA,
        apk_sha=APK_SHA,
    )


def _markers(*, present: bool = True) -> str:
    lines: list[str] = []
    for spec in TABLE_SPECS:
        lines.append(f"T|{spec.name}|1|{1 if present else 0}")
        for column, statuses in spec.status_columns.items():
            lines.append(f"X|{spec.name}|{column}|{1 if present else 0}")
            for status in statuses:
                lines.append(f"S|{spec.name}|{column}|{status}|0")
            lines.append(f"U|{spec.name}|{column}|0")
        for hash_kind in spec.hash_kinds:
            lines.append(f"X|{spec.name}|{hash_kind}|{1 if present else 0}")
        for required_column in spec.required_columns:
            lines.append(f"X|{spec.name}|{required_column}|{1 if present else 0}")
        for public_id in spec.public_ids:
            lines.append(f"D|{spec.name}|{public_id}")
        for hash_kind in spec.hash_kinds:
            lines.append(f"H|{spec.name}|{hash_kind}|{'d' * 64}")
    for key in CHECK_NAMES:
        lines.append(f"K|{key}|0")
    return "\n".join(lines) + "\n"


def _current_run_markers() -> str:
    markers = _markers()
    for table in ("app_user", "refresh_session"):
        markers = markers.replace(f"T|{table}|1|1", f"T|{table}|2|1")
    for table in (
        "provider_delivery_outbox",
        "private_message",
        "tencent_im_account",
        "tencent_im_callback_event",
        "tencent_im_room_group_outbox",
        "payment_provider_event",
        "recharge_order",
    ):
        markers = markers.replace(f"T|{table}|1|1", f"T|{table}|2|1")
    for table in ("provider_delivery_outbox", "tencent_im_room_group_outbox"):
        markers = markers.replace(
            f"S|{table}|status|DELIVERED|0",
            f"S|{table}|status|DELIVERED|1",
        )
    return markers


class _FakeSessionCollector(M5EvidenceSessionCollector):
    def __init__(self, config: EvidenceConfig, snapshots: list[str]) -> None:
        super().__init__(config)
        self._snapshots = [parse_mysql_markers(value) for value in snapshots]

    def _snapshot(self, fixture_id: str, since_epoch: int):  # type: ignore[no-untyped-def]
        del fixture_id, since_epoch
        if not self._snapshots:
            raise EvidenceError("READ_FAILED")
        return _state_snapshot(self._snapshots.pop(0))


def _session_config(
    state_dir: str,
    *,
    run_id: str = "m5-run",
    payment_scenario: str = "none",
) -> EvidenceConfig:
    return EvidenceConfig(
        mysql_container="mysql",
        docker_bin="docker",
        docker_env={"PATH": "/usr/bin:/bin"},
        binding=EvidenceBinding(
            run_id=run_id,
            backend_sha=BACKEND_SHA,
            flutter_sha=FLUTTER_SHA,
            apk_sha=APK_SHA,
        ),
        backend_repo="/secure/backend",
        evidence_token="T" * 16 + "u" * 8 + "v" * 8,
        state_dir=state_dir,
        backend_source_digest="d" * 64,
        payment_scenario=payment_scenario,
    )


class M5VendorDbEvidenceContractTest(unittest.TestCase):
    def test_v29_v31_schema_markers_cover_every_required_table(self) -> None:
        parsed = parse_mysql_markers(_markers())
        self.assertEqual(set(parsed.tables), {spec.name for spec in TABLE_SPECS})
        self.assertTrue(all(table["present"] for table in parsed.tables.values()))
        payload = build_payload(parsed, _binding())
        validate_payload(payload)
        self.assertEqual(payload["status"], "OK")
        self.assertFalse(payload["secrets"])

    def test_binding_requires_run_and_backend_flutter_apk_hashes(self) -> None:
        binding = _binding()
        validate_binding(binding)
        for field, value in (
            ("run_id", "m5 bad run"),
            ("backend_sha", "not-a-sha"),
            ("flutter_sha", "e" * 39),
            ("apk_sha", "f" * 63),
        ):
            values = {
                "run_id": binding.run_id,
                "backend_sha": binding.backend_sha,
                "flutter_sha": binding.flutter_sha,
                "apk_sha": binding.apk_sha,
            }
            values[field] = value
            with self.assertRaises(EvidenceError):
                validate_binding(EvidenceBinding(**values))

    def test_missing_v29_v31_schema_fails_closed(self) -> None:
        payload = build_payload(
            parse_mysql_markers(_markers(present=False)),
            _binding(),
        )
        self.assertEqual(payload["status"], "FAIL")
        self.assertEqual(payload["errorCategories"], ["SCHEMA_MISSING"])

    def test_missing_v31_required_column_fails_closed(self) -> None:
        markers = _markers().replace(
            "X|room_public_message|event_version|1\n", ""
        )
        with self.assertRaises(EvidenceError):
            parse_mysql_markers(markers)

    def test_callback_evidence_requires_explicit_outbox_link_marker(self) -> None:
        # V30's received_at-only callback table cannot prove that a row came
        # from this fixture's room/message.  A legacy marker stream must not
        # remain acceptable after the callback ownership gate is enabled.
        markers = _markers().replace(
            "X|tencent_im_callback_event|room_group_outbox_public_id|1\n", ""
        )
        with self.assertRaises(EvidenceError):
            parse_mysql_markers(markers)

    def test_callback_evidence_missing_link_fails_closed_at_collect(self) -> None:
        # Model the current V30 schema explicitly: the marker exists as a
        # schema probe, but the callback-to-outbox column is absent. Even if a
        # callback count changes between start and collect, the session must
        # reject the report instead of returning a timestamp-scoped success.
        missing_link = "X|tencent_im_callback_event|room_group_outbox_public_id|1\n"
        missing_link_marker = missing_link.replace("|1\n", "|0\n")
        legacy_baseline = _markers().replace(missing_link, missing_link_marker)
        legacy_current = _current_run_markers().replace(
            missing_link, missing_link_marker
        )
        with tempfile.TemporaryDirectory() as state_dir:
            collector = _FakeSessionCollector(
                _session_config(state_dir, run_id="m5-callback-schema"),
                [legacy_baseline, legacy_current],
            )
            started = collector.start(
                "m5-callback-schema", "AVD-A", "m5-fresh-callback"
            )
            with self.assertRaisesRegex(EvidenceError, "SCHEMA_MISSING"):
                collector.collect(
                    "m5-callback-schema",
                    "AVD-A",
                    "m5-fresh-callback",
                    started["startNonce"],
                )

    def test_nonzero_integrity_check_fails_closed(self) -> None:
        markers = _markers().replace("K|wallet_negative|0", "K|wallet_negative|2")
        payload = build_payload(parse_mysql_markers(markers), _binding())
        self.assertEqual(payload["status"], "FAIL")
        self.assertEqual(payload["errorCategories"], ["INVARIANT_VIOLATION"])

    def test_private_and_provider_payload_values_are_not_marker_data(self) -> None:
        parsed = parse_mysql_markers(_markers())
        payload = build_payload(parsed, _binding())
        encoded = repr(payload).lower()
        for term in ("usersig", "orderstr", "phone", "mobile", "password"):
            self.assertNotIn(term, encoded)
        self.assertNotIn("payload_json", encoded)

    def test_parser_rejects_malformed_or_secret_like_public_id(self) -> None:
        malformed = _markers().replace(
            "D|provider_delivery_outbox|", "D|provider_delivery_outbox|secret-order-str-"
        )
        with self.assertRaises(EvidenceError):
            parse_mysql_markers(malformed)

        hostile = _markers().replace("T|wallet|1|1", "T|wallet|1|1|Bearer secret")
        with self.assertRaises(EvidenceError):
            parse_mysql_markers(hostile)

    def test_parser_rejects_duplicate_or_uncontrolled_status_markers(self) -> None:
        duplicate = _markers() + "K|wallet_negative|0\n"
        with self.assertRaises(EvidenceError):
            parse_mysql_markers(duplicate)
        uncontrolled = _markers().replace(
            "S|recharge_order|status|CONFIRMING|0",
            "S|recharge_order|status|secret-value|0",
        )
        with self.assertRaises(EvidenceError):
            parse_mysql_markers(uncontrolled)

    def test_payload_validator_rejects_forbidden_fields_even_when_nested(self) -> None:
        payload = build_payload(parse_mysql_markers(_markers()), _binding())
        for key, value in (
            ("token", "A" * 64),
            ("userSig", "signed-value"),
            ("orderStr", "signed-order"),
            ("body", "private message"),
            ("phone", "13800138000"),
            ("secretKey", "private-key"),
            ("databasePassword", "db-password"),
        ):
            hostile = dict(payload)
            hostile["hostile"] = {key: value}
            with self.assertRaises(EvidenceError, msg=key):
                validate_payload(hostile)

    def test_csv_is_fixed_shape_and_does_not_contain_secret_terms(self) -> None:
        payload = build_payload(parse_mysql_markers(_markers()), _binding())
        output = io.StringIO()
        payload_to_csv(payload, output)
        rows = list(csv.DictReader(io.StringIO(output.getvalue())))
        self.assertTrue(rows)
        self.assertEqual(
            set(rows[0]),
            {
                "evidence_type",
                "section",
                "metric",
                "status",
                "count",
                "public_id",
                "hash",
                "error_category",
                "value",
            },
        )
        encoded = output.getvalue().lower()
        for term in FORBIDDEN_MARKER_TERMS:
            self.assertNotIn(term.lower(), encoded)
        self.assertNotIn("payload_json", encoded)

    def test_sql_script_is_select_only_and_has_no_sensitive_row_columns(self) -> None:
        for keyword in (
            "INSERT",
            "UPDATE",
            "DELETE",
            "ALTER",
            "DROP",
            "TRUNCATE",
            "CREATE",
        ):
            self.assertIsNone(
                re.search(rf"\b{keyword}\b", MYSQL_EVIDENCE_SCRIPT, re.IGNORECASE),
                keyword,
            )
        for forbidden in (
            "payload_json",
            "order_str",
            "orderStr",
            "user_sig",
            "usersig",
            "phone",
            "mobile",
            "secret_key",
            "provider_order_id",
            "provider_refund_id",
        ):
            self.assertNotIn(forbidden.lower(), MYSQL_EVIDENCE_SCRIPT.lower())
        self.assertIn("SELECT COUNT(*)", MYSQL_EVIDENCE_SCRIPT)
        self.assertIn("M5_SCOPE_NICKNAME", MYSQL_EVIDENCE_SCRIPT)
        self.assertIn("M5_SCOPE_SINCE_EPOCH", MYSQL_EVIDENCE_SCRIPT)
        self.assertIn('include_public_ids="${M5_INCLUDE_PUBLIC_IDS:-0}"', MYSQL_EVIDENCE_SCRIPT)
        self.assertIn("FROM_UNIXTIME", MYSQL_EVIDENCE_SCRIPT)
        self.assertIn("payment_provider = 'alipay-sandbox'", MYSQL_EVIDENCE_SCRIPT)
        self.assertNotIn("payment_provider = 'alipay'", MYSQL_EVIDENCE_SCRIPT)

    def test_sql_script_does_not_emit_same_column_as_required_and_status(self) -> None:
        required_pairs = set(
            re.findall(
                r"^emit_required_column\s+([A-Za-z0-9_]+)\s+([A-Za-z0-9_]+)$",
                MYSQL_EVIDENCE_SCRIPT,
                re.MULTILINE,
            )
        )
        status_pairs = set(
            re.findall(
                r"^emit_column\s+([A-Za-z0-9_]+)\s+([A-Za-z0-9_]+)\s+",
                MYSQL_EVIDENCE_SCRIPT,
                re.MULTILINE,
            )
        )
        overlap = sorted(required_pairs & status_pairs)
        self.assertEqual(overlap, [], overlap)

    def test_scoped_checks_parenthesize_disjunctions_and_reject_missing_fingerprints(self) -> None:
        self.assertIn(
            'query="SELECT COUNT(*) FROM $table WHERE ($base_where)"',
            MYSQL_EVIDENCE_SCRIPT,
        )
        self.assertIn(
            "request_fingerprint IS NULL OR request_fingerprint NOT REGEXP",
            MYSQL_EVIDENCE_SCRIPT,
        )

    def test_sql_scope_accepts_the_exact_derived_fixture_nickname_length(self) -> None:
        nickname = _fixture_nickname("m5-fresh-contract")
        self.assertRegex(nickname, r"^m5-[0-9a-f]{13}$")
        shell_pattern = "m5-" + "[0-9a-f]" * 13 + ") ;;"
        self.assertIn(shell_pattern, MYSQL_EVIDENCE_SCRIPT)

    def test_callback_scope_joins_fixture_room_outbox_and_message_identity(self) -> None:
        # The callback count must come from an explicit ingest link to the
        # room-group outbox and then traverse the outbox's room/message keys.
        # A received_at window by itself is intentionally insufficient.
        callback_scope_start = MYSQL_EVIDENCE_SCRIPT.index(
            "    tencent_im_callback_event)"
        )
        callback_scope_end = MYSQL_EVIDENCE_SCRIPT.index(
            "    tencent_im_room_group)", callback_scope_start
        )
        callback_scope = MYSQL_EVIDENCE_SCRIPT[
            callback_scope_start:callback_scope_end
        ]
        for term in (
            "room_group_outbox_public_id",
            "callback_command = 'Group.CallbackAfterSendMsg'",
            "o.public_id",
            "o.operation = 'SEND_GROUP_MSG'",
            "p.public_id = o.aggregate_public_id",
            "p.room_id = o.room_id",
            "p.event_version = o.event_version",
            "JOIN room r ON r.id = o.room_id",
            "r.owner_user_id IN (SELECT id FROM app_user WHERE nickname =",
            "rm.user_id IN (SELECT id FROM app_user WHERE nickname =",
            "received_at >= FROM_UNIXTIME",
        ):
            self.assertIn(term, callback_scope)
        self.assertIn(M5_CALLBACK_SCOPE_LINK_COLUMN, callback_scope)

    def test_payment_evidence_joins_one_order_business_and_amount_chain(self) -> None:
        # These are aggregate-only predicates.  The SQL may compare the
        # protected values inside MySQL, but no order/business/amount value is
        # emitted in a marker or response.
        for term in (
            "e.order_no = o.order_no",
            "e.provider = o.payment_provider",
            "wt.business_id = o.order_no",
            "wt.amount_minor = o.gift_coin_amount",
            "j.business_id = o.order_no",
            "p.journal_id = j.id",
            "p.amount_minor",
            "payment_accounting_linkage_mismatch",
        ):
            self.assertIn(term, MYSQL_EVIDENCE_SCRIPT)
        self.assertIn("o.status = 'SUCCEEDED'", MYSQL_EVIDENCE_SCRIPT)
        self.assertIn("COUNT(*) FROM ledger_posting", MYSQL_EVIDENCE_SCRIPT)
        self.assertIn("= 2", MYSQL_EVIDENCE_SCRIPT)

    def test_evidence_request_timeouts_have_settlement_headroom(self) -> None:
        self.assertGreaterEqual(START_REQUEST_TIMEOUT_SECONDS, 60)
        self.assertGreaterEqual(COLLECT_REQUEST_TIMEOUT_SECONDS, 300)
        self.assertGreaterEqual(DOCKER_EVIDENCE_TIMEOUT_SECONDS, 300)

    def test_external_evidence_url_is_https_and_loopback_http_is_explicit(self) -> None:
        validate_evidence_url("https://evidence.example.test/m5/db-evidence")
        validate_evidence_url("https://127.0.0.1/m5/db-evidence/")
        validate_evidence_url(
            "http://127.0.0.1:49152/m5/db-evidence", allow_loopback_http=True
        )
        for url in (
            "http://evidence.example.test/m5/db-evidence",
            "http://10.0.2.2:18080/m5/db-evidence",
            "https://evidence.example.test/m5/db-evidence?token=secret",
            "https://user:password@evidence.example.test/m5/db-evidence",
            "https://evidence.example.test/redirect",
        ):
            with self.assertRaises(EvidenceError):
                validate_evidence_url(url)

    def test_error_categories_are_controlled(self) -> None:
        self.assertIn("DB_UNAVAILABLE", ALLOWED_ERROR_CATEGORIES)
        self.assertIn("INVARIANT_VIOLATION", ALLOWED_ERROR_CATEGORIES)
        self.assertNotIn("raw_database_error", ALLOWED_ERROR_CATEGORIES)

    def test_start_collect_is_fixture_avd_bound_and_nonce_is_one_shot(self) -> None:
        fixture = "m5-fresh-contract"
        with tempfile.TemporaryDirectory() as state_dir:
            collector = _FakeSessionCollector(
                _session_config(state_dir),
                [_markers(), _current_run_markers()],
            )
            started = collector.start("m5-run", "AVD-A", fixture)
            self.assertEqual(started["status"], "STARTED")
            self.assertEqual(started["paymentScenario"], "none")
            self.assertEqual(
                started["paymentSettlementPoll"], "internal-bounded-90s"
            )
            nonce = started["startNonce"]
            self.assertIsInstance(nonce, str)
            result = collector.collect("m5-run", "AVD-A", fixture, nonce)
            self.assertEqual(result["status"], "OK")
            self.assertEqual(
                set(result),
                {
                    "status",
                    "evidenceBinding",
                    "writeCounters",
                    "vendorOutbox",
                    "callbackEvents",
                    "outboxAttempts",
                    "paymentSettlement",
                    "secrets",
                    "backendSourceDigest",
                },
            )
            self.assertEqual(
                set(result["evidenceBinding"]),
                {
                    "runId",
                    "avd",
                    "fixtureId",
                    "startNonce",
                    "backendSha",
                    "flutterSha",
                    "apkSha",
                    "backendSourceDigest",
                },
            )
            self.assertEqual(result["writeCounters"]["auth_sessions"], 2)
            self.assertEqual(
                result["paymentSettlement"],
                {
                    "providerEventVerified": False,
                    "providerEventProcessedCount": 0,
                    "succeededOrderCount": 0,
                    "walletTransactionCount": 0,
                    "walletCreditCount": 0,
                    "ledgerJournalCount": 0,
                    "ledgerEntryCount": 0,
                    "balancedJournalCount": 0,
                    "ledgerImbalanceCount": 0,
                },
            )
            self.assertEqual(
                result["writeCounters"],
                {
                    "auth_sessions": 2,
                    "im_credentials": 1,
                    "c2c_messages": 1,
                    "avchatroom_sessions": 1,
                    "alipay_orders": 1,
                    "payment_provider_events": 1,
                    "wallet_transactions": 0,
                    "ledger_journals": 0,
                    "ledger_entries": 0,
                },
            )
            self.assertEqual(result["evidenceBinding"]["fixtureId"], fixture)
            self.assertEqual(result["evidenceBinding"]["avd"], "AVD-A")
            self.assertNotIn("publicIds", repr(result))
            self.assertNotIn("bodySha256", repr(result))
            with self.assertRaises(EvidenceError):
                collector.collect("m5-run", "AVD-A", fixture, nonce)
            with self.assertRaises(EvidenceError):
                collector.collect("m5-other", "AVD-A", fixture, nonce)
            with self.assertRaises(EvidenceError):
                collector.collect("m5-run", "AVD-B", fixture, nonce)

    def test_counters_track_future_payment_accounting_delta_without_values(self) -> None:
        fixture = "m5-fresh-accounting"
        current = _current_run_markers()
        for table in ("wallet_transaction", "ledger_journal", "ledger_posting"):
            current = current.replace(
                f"T|{table}|1|1", f"T|{table}|2|1"
            )
        with tempfile.TemporaryDirectory() as state_dir:
            collector = _FakeSessionCollector(
                _session_config(state_dir, run_id="m5-accounting"),
                [_markers(), current],
            )
            started = collector.start("m5-accounting", "AVD-A", fixture)
            result = collector.collect(
                "m5-accounting", "AVD-A", fixture, started["startNonce"]
            )
            self.assertEqual(result["writeCounters"]["payment_provider_events"], 1)
            self.assertEqual(result["writeCounters"]["wallet_transactions"], 1)
            self.assertEqual(result["writeCounters"]["ledger_journals"], 1)
            self.assertEqual(result["writeCounters"]["ledger_entries"], 1)
            self.assertEqual(result["paymentSettlement"]["walletCreditCount"], 0)
            self.assertEqual(result["paymentSettlement"]["ledgerEntryCount"], 1)
            self.assertNotIn("amount_minor", repr(result))
            self.assertNotIn("publicIds", repr(result))

    def test_success_settlement_evidence_requires_verified_event_and_balanced_double_entry(self) -> None:
        fixture = "m5-fresh-success"
        current = _current_run_markers()
        for table, delta in (
            ("wallet_transaction", 1),
            ("ledger_journal", 1),
            ("ledger_posting", 2),
        ):
            current = current.replace(
                f"T|{table}|1|1", f"T|{table}|{1 + delta}|1"
            )
        for table, column, status in (
            ("payment_provider_event", "status", "PROCESSED"),
            ("payment_provider_event", "observed_status", "TRADE_SUCCESS"),
            ("recharge_order", "status", "SUCCEEDED"),
            ("recharge_order", "provider_status", "TRADE_SUCCESS"),
            ("wallet_transaction", "transaction_type", "CREDIT"),
        ):
            current = current.replace(
                f"S|{table}|{column}|{status}|0",
                f"S|{table}|{column}|{status}|1",
            )
        with tempfile.TemporaryDirectory() as state_dir:
            collector = _FakeSessionCollector(
                _session_config(
                    state_dir, run_id="m5-success", payment_scenario="success"
                ),
                [_markers(), current],
            )
            started = collector.start("m5-success", "AVD-A", fixture)
            result = collector.collect(
                "m5-success", "AVD-A", fixture, started["startNonce"]
            )
            self.assertEqual(
                result["paymentSettlement"],
                {
                    "providerEventVerified": True,
                    "providerEventProcessedCount": 1,
                    "succeededOrderCount": 1,
                    "walletTransactionCount": 1,
                    "walletCreditCount": 1,
                    "ledgerJournalCount": 1,
                    "ledgerEntryCount": 2,
                    "balancedJournalCount": 1,
                    "ledgerImbalanceCount": 0,
                },
            )
            self.assertEqual(
                result["callbackEvents"]["alipay"],
                {"verified": True, "eventCount": 1},
            )

    def test_start_rejects_replay_and_collect_rejects_stale_or_bad_nonce(self) -> None:
        fixture = "m5-fresh-replay"
        with tempfile.TemporaryDirectory() as state_dir:
            collector = _FakeSessionCollector(
                _session_config(state_dir, run_id="m5-replay"),
                [_markers(), _current_run_markers()],
            )
            started = collector.start("m5-replay", "AVD-B", fixture)
            with self.assertRaises(EvidenceError):
                collector.start("m5-replay", "AVD-B", fixture)
            with self.assertRaises(EvidenceError):
                collector.collect(
                    "m5-replay", "AVD-B", fixture, "A" * 16 + "." + "b" * 64
                )
            with patch("m5_vendor_db_evidence.time.time", return_value=10**10):
                with self.assertRaises(EvidenceError):
                    collector.collect(
                        "m5-replay", "AVD-B", fixture, started["startNonce"]
                    )

    def test_collect_rejects_a_counter_rollback_instead_of_reusing_stale_delta(self) -> None:
        fixture = "m5-fresh-rollback"
        with tempfile.TemporaryDirectory() as state_dir:
            collector = _FakeSessionCollector(
                _session_config(state_dir, run_id="m5-rollback"),
                [_current_run_markers(), _markers()],
            )
            started = collector.start("m5-rollback", "AVD-A", fixture)
            with self.assertRaises(EvidenceError):
                collector.collect(
                    "m5-rollback", "AVD-A", fixture, started["startNonce"]
                )

    def test_persisted_state_contains_no_public_ids_or_hash_payloads(self) -> None:
        fixture = "m5-fresh-state"
        with tempfile.TemporaryDirectory() as state_dir:
            collector = _FakeSessionCollector(
                _session_config(state_dir, run_id="m5-state"),
                [_markers(), _current_run_markers()],
            )
            collector.start("m5-state", "AVD-A", fixture)
            files = [
                os.path.join(state_dir, name)
                for name in os.listdir(state_dir)
                if name.endswith(".json")
            ]
            self.assertEqual(len(files), 1)
            state = Path(files[0]).read_text(encoding="utf-8")
            self.assertNotIn("publicIds", state)
            self.assertNotIn("bodySha256", state)
            self.assertNotIn("payload_json", state)
            json.loads(state)

    def test_http_start_collect_contract_rejects_replay_and_wrong_auth(self) -> None:
        fixture = "m5-fresh-http"
        with tempfile.TemporaryDirectory() as state_dir:
            config = _session_config(state_dir, run_id="m5-http")
            collector = _FakeSessionCollector(config, [_markers(), _current_run_markers()])
            server = M5EvidenceServer(("127.0.0.1", 0), collector, config.evidence_token)
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            url = f"http://127.0.0.1:{server.server_address[1]}/m5/db-evidence"

            def call(
                phase: str,
                *,
                nonce: str = "",
                token: str = config.evidence_token,
                avd: str = "AVD-A",
                backend_sha: str = BACKEND_SHA,
                payment_scenario: str = config.payment_scenario,
            ):
                headers = {
                    "Authorization": f"Bearer {token}",
                    "X-M5-Evidence-Phase": phase,
                    "X-M5-Run-ID": "m5-http",
                    "X-M5-AVD": avd,
                    "X-M5-Fixture-ID": fixture,
                    "X-M5-Backend-SHA": backend_sha,
                    "X-M5-Flutter-SHA": FLUTTER_SHA,
                    "X-M5-APK-SHA": APK_SHA,
                    "X-M5-Backend-Digest": config.backend_source_digest,
                    "X-M5-Payment-Scenario": payment_scenario,
                }
                if nonce:
                    headers["X-M5-Start-Nonce"] = nonce
                request = urllib.request.Request(url, headers=headers)
                opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
                return opener.open(request, timeout=3)

            try:
                with self.assertRaises(urllib.error.HTTPError) as scenario_mismatch:
                    try:
                        call("start", payment_scenario="success")
                    except urllib.error.HTTPError as error:
                        error.close()
                        raise
                self.assertEqual(scenario_mismatch.exception.code, 400)
                with call("start") as response:
                    started = json.loads(response.read())
                self.assertEqual(started["paymentScenario"], "none")
                self.assertEqual(
                    started["paymentSettlementPoll"], "internal-bounded-90s"
                )
                with call("collect", nonce=started["startNonce"]) as response:
                    collected = json.loads(response.read())
                self.assertEqual(collected["status"], "OK")
                with self.assertRaises(urllib.error.HTTPError) as replay:
                    try:
                        call("collect", nonce=started["startNonce"])
                    except urllib.error.HTTPError as error:
                        error.close()
                        raise
                self.assertEqual(replay.exception.code, 503)
                with self.assertRaises(urllib.error.HTTPError) as mismatched:
                    try:
                        call("start", backend_sha="e" * 40)
                    except urllib.error.HTTPError as error:
                        error.close()
                        raise
                self.assertEqual(mismatched.exception.code, 400)
                with self.assertRaises(urllib.error.HTTPError) as unauthorized:
                    try:
                        call("start", token="wrong-token")
                    except urllib.error.HTTPError as error:
                        error.close()
                        raise
                self.assertEqual(unauthorized.exception.code, 401)
            finally:
                server.shutdown()
                server.server_close()
                thread.join(timeout=3)


if __name__ == "__main__":
    unittest.main()
