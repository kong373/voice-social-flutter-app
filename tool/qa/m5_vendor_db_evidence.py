#!/usr/bin/env python3
"""Read-only, redacted M5 vendor/database evidence collector.

The supported live path is an authenticated ``start`` -> ``collect`` HTTP
session.  It snapshots only fixture-scoped aggregate markers at start,
persists a nonce-bound baseline, and emits a fixed JSON delta at collect.  It
never returns row payloads, user or room numeric identifiers, provider
credentials, provider order strings, message text, phone values, or database
diagnostics.  Tencent callback counts require a backend-ingested link to a
fixture-owned room-group outbox row; the helper fails closed when that link
is absent rather than treating a time-window match as ownership.  The
source/APK binding is supplied by the protected release harness and carried
through every successful report.

Use ``--self-test`` for an offline contract and leakage check.  A live run
requires the M5 environment variables documented in
``docs/qa/m5-vendor-db-evidence.md`` and starts the protected endpoint with
``--serve``.
"""

from __future__ import annotations

import argparse
import csv
import dataclasses
import hashlib
import hmac
import http.server
import json
import os
import re
from pathlib import Path
import secrets as secrets_module
import shlex
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from urllib.parse import urlsplit
from typing import IO, Mapping, Sequence


class EvidenceError(RuntimeError):
    """A failure that is safe to classify but unsafe to echo verbatim."""


class ConfigurationError(EvidenceError):
    """The protected harness configuration is absent or invalid."""


ALLOWED_ERROR_CATEGORIES = frozenset(
    {
        "CONFIGURATION",
        "ATTESTATION",
        "DB_UNAVAILABLE",
        "SCHEMA_MISSING",
        "READ_FAILED",
        "INVALID_MARKER",
        "INVARIANT_VIOLATION",
        "SECRET_POLICY",
        "OUTPUT_WRITE",
    }
)

# These terms are used by the offline tests and by the final report scan.  A
# hash field is intentionally represented by ``hash``/``bodySha256`` rather
# than by a raw provider/body value.
FORBIDDEN_MARKER_TERMS = (
    "bearer",
    "token",
    "usersig",
    "orderstr",
    "phone",
    "mobile",
    "secret",
    "password",
    "payload",
    "provider_order",
    "provider_refund",
)

M5_TOKEN_ENV_NAMES = (
    "M5_DB_EVIDENCE_TOKEN",
    "QA_DB_EVIDENCE_TOKEN",
    "M5_EVIDENCE_TOKEN",
)
M5_HOST_ENV_NAMES = ("M5_DB_EVIDENCE_HOST", "QA_DB_EVIDENCE_HOST")
M5_PORT_ENV_NAMES = ("M5_DB_EVIDENCE_PORT", "QA_DB_EVIDENCE_PORT")
M5_STATE_DIR_ENV_NAMES = ("M5_DB_EVIDENCE_STATE_DIR", "QA_M5_DB_EVIDENCE_STATE_DIR")
M5_BACKEND_DIGEST_ENV_NAMES = (
    "M5_BACKEND_DIGEST",
    "M5_BACKEND_SOURCE_DIGEST",
    "QA_BACKEND_DIGEST",
)
AVD_RE = re.compile(r"^AVD-[AB]$")
FIXTURE_ID_RE = re.compile(r"^m5-fresh-[A-Za-z0-9_.:-]{1,64}$")
START_NONCE_RE = re.compile(r"^[A-Za-z0-9_.~=-]{16,255}$")
UNIX_EPOCH_RE = re.compile(r"^[0-9]{1,12}$")
PAYMENT_SCENARIOS = frozenset({"none", "cancel", "success"})
PAYMENT_SETTLEMENT_POLL_MODE = "internal-bounded-90s"
# The HTTP client and the helper must leave enough time for a complete
# fixture-scoped aggregate scan.  Keep these values in one place so a future
# runner change cannot accidentally reintroduce the old 20/180 second
# ceilings.  The collect request also includes the bounded settlement poll.
START_REQUEST_TIMEOUT_SECONDS = 180
COLLECT_REQUEST_TIMEOUT_SECONDS = 900
DOCKER_EVIDENCE_TIMEOUT_SECONDS = 300
M5_RESPONSE_KEYS = frozenset(
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
    }
)
M5_WRITE_COUNTER_KEYS = (
    "auth_sessions",
    "im_credentials",
    "c2c_messages",
    "avchatroom_sessions",
    "alipay_orders",
    "payment_provider_events",
    "wallet_transactions",
    "ledger_journals",
    "ledger_entries",
)

RUN_ID_RE = re.compile(r"^[A-Za-z0-9_.:-]{1,96}$")
SHA1_RE = re.compile(r"^[0-9a-fA-F]{40}$")
SHA256_RE = re.compile(r"^[0-9a-fA-F]{64}$")
UUID_RE = re.compile(
    r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-"
    r"[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$"
)
CONTAINER_NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$")
COUNT_RE = re.compile(r"^[0-9]+$")
MARKER_NAME_RE = re.compile(r"^[A-Za-z][A-Za-z0-9_.-]{0,96}$")

STATUS_VALUES = (
    "VENDOR_BLOCKED",
    "PENDING",
    "PROCESSING",
    "RETRY",
    "UNKNOWN",
    "DELIVERED",
    "FAILED",
    "ACTIVE",
    "DESTROY_PENDING",
    "DESTROYED",
    "RECEIVED",
    "PROCESSED",
    "REJECTED",
    "CONFIRMING",
    "SUCCEEDED",
    "CANCELLED",
    "TRADE_SUCCESS",
    "TRADE_FINISHED",
    "TRADE_CLOSED",
    "WAIT_BUYER_PAY",
    "TRADE_PENDING",
    "CREATED",
    "APPROVED",
    "COMPLETED",
    "SUBMITTED",
    "REVIEWING",
    "SETTLED",
    "APPLIED",
    "IN_PROGRESS",
    "BALANCED",
    "MISMATCH",
    "QUEUED",
    "EXPIRED",
    "REFUNDED",
    "HELD",
    "RELEASED",
    "HELD_CONSUMED",
    "UNCONTROLLED",
    "PASS",
    "FAIL",
)
STATUS_SET = frozenset(STATUS_VALUES)


@dataclasses.dataclass(frozen=True)
class TableSpec:
    """The only table/column vocabulary the SQL collector may address."""

    name: str
    status_columns: Mapping[str, tuple[str, ...]] = dataclasses.field(
        default_factory=dict
    )
    # The tuple is a list of sample IDs used only by offline marker fixtures;
    # a live marker carries at most 32 valid UUID public IDs.
    public_ids: tuple[str, ...] = ()
    hash_kinds: tuple[str, ...] = ()
    # Columns that make the aggregate projection meaningful even when the
    # column is not a status/hash projection.  These are presence-only
    # markers; no row values cross the container boundary.
    required_columns: tuple[str, ...] = ()


_PUBLIC_ID = ("00000000-0000-4000-8000-000000000001",)
_PUBLIC_ID_2 = ("00000000-0000-4000-8000-000000000002",)
# V30 currently does not persist a callback's owning room/outbox/message.  The
# live M5 contract therefore requires the backend callback ingest to add this
# explicit link before the helper can count a Tencent group callback.
M5_CALLBACK_SCOPE_LINK_COLUMN = "room_group_outbox_public_id"


TABLE_SPECS: tuple[TableSpec, ...] = (
    # Authentication writes are included only to provide a truthful
    # ``auth_sessions`` delta in the runner contract.  SMS challenge rows are
    # intentionally excluded: their phone hash has no first-party user
    # foreign key, so they cannot be safely attributed to this fixture.
    TableSpec("app_user", required_columns=("nickname", "created_at")),
    TableSpec(
        "refresh_session",
        required_columns=("user_id", "created_at"),
    ),
    TableSpec(
        "provider_delivery_outbox",
        {"status": (
            "VENDOR_BLOCKED",
            "PENDING",
            "PROCESSING",
            "RETRY",
            "UNKNOWN",
            "DELIVERED",
            "FAILED",
        )},
        _PUBLIC_ID,
        required_columns=(
            "aggregate_type",
            "aggregate_public_id",
            "recipient_user_id",
            "channel",
            "attempt_count",
            "created_at",
        ),
    ),
    TableSpec(
        "private_message",
        {"delivery_status": (
            "VENDOR_BLOCKED",
            "PENDING",
            "PROCESSING",
            "RETRY",
            "UNKNOWN",
            "DELIVERED",
            "FAILED",
        )},
        _PUBLIC_ID_2,
        required_columns=("sender_user_id", "receiver_user_id", "created_at"),
    ),
    TableSpec(
        "tencent_im_account",
        {"status": ("PENDING", "PROCESSING", "IMPORTED", "UNKNOWN", "FAILED")},
        required_columns=("user_id", "created_at"),
    ),
    TableSpec(
        "tencent_im_callback_event",
        hash_kinds=("event_key", "body_sha256"),
        required_columns=("received_at", M5_CALLBACK_SCOPE_LINK_COLUMN, "callback_command"),
    ),
    TableSpec(
        "tencent_im_room_group",
        {"state": (
            "VENDOR_BLOCKED",
            "PENDING",
            "PROCESSING",
            "RETRY",
            "UNKNOWN",
            "ACTIVE",
            "DESTROY_PENDING",
            "DESTROYED",
            "FAILED",
        )},
        required_columns=("room_id", "group_id", "generation", "created_at"),
    ),
    TableSpec(
        "tencent_im_room_group_outbox",
        {
            "operation": ("CREATE_GROUP", "SEND_GROUP_MSG", "DESTROY_GROUP"),
            "status": (
                "VENDOR_BLOCKED",
                "PENDING",
                "PROCESSING",
                "RETRY",
                "UNKNOWN",
                "DELIVERED",
                "FAILED",
            ),
        },
        _PUBLIC_ID,
        required_columns=(
            "public_id",
            "room_id",
            "group_id",
            "generation",
            "event_version",
            "aggregate_public_id",
            "attempt_count",
            "created_at",
        ),
    ),
    TableSpec(
        "room_public_message",
        public_ids=_PUBLIC_ID_2,
        required_columns=(
            "public_id",
            "room_id",
            "sender_user_id",
            "event_version",
            "created_at",
        ),
    ),
    TableSpec(
        "payment_provider_event",
        {
            "status": ("RECEIVED", "PROCESSED", "REJECTED"),
            "observed_status": (
                "TRADE_SUCCESS",
                "TRADE_FINISHED",
                "TRADE_CLOSED",
                "WAIT_BUYER_PAY",
                "TRADE_PENDING",
                "CONFIRMING",
                "SUCCEEDED",
                "FAILED",
            ),
        },
        _PUBLIC_ID,
        ("event_fingerprint",),
        required_columns=("provider", "order_no", "received_at"),
    ),
    TableSpec(
        "recharge_order",
        {
            "status": ("CONFIRMING", "SUCCEEDED", "FAILED", "CANCELLED"),
            "provider_status": (
                "",
                "CREATED",
                "TRADE_SUCCESS",
                "TRADE_FINISHED",
                "TRADE_CLOSED",
                "WAIT_BUYER_PAY",
                "TRADE_PENDING",
            ),
        },
        required_columns=(
            "order_no",
            "user_id",
            "amount_minor",
            "gift_coin_amount",
            "payment_provider",
            "created_at",
        ),
    ),
    TableSpec("wallet", required_columns=("user_id", "balance_minor", "frozen_minor")),
    TableSpec(
        "wallet_transaction",
        {"transaction_type": ("CREDIT", "DEBIT", "HOLD", "RELEASE")},
        _PUBLIC_ID_2,
        required_columns=(
            "wallet_id",
            "amount_minor",
            "business_type",
            "business_id",
            "created_at",
        ),
    ),
    TableSpec(
        "ledger_account",
        {"status": ("ACTIVE", "CLOSED")},
        _PUBLIC_ID,
        required_columns=("user_id",),
    ),
    TableSpec(
        "ledger_journal",
        public_ids=_PUBLIC_ID_2,
        required_columns=(
            "actor_user_id",
            "business_type",
            "business_id",
            "created_at",
        ),
    ),
    TableSpec(
        "ledger_posting",
        required_columns=(
            "journal_id",
            "account_id",
            "currency_code",
            "amount_minor",
            "created_at",
        ),
    ),
    TableSpec(
        "wallet_reconciliation",
        {"status": ("BALANCED", "MISMATCH")},
        _PUBLIC_ID,
        required_columns=("wallet_id", "checked_at"),
    ),
    TableSpec(
        "refund_application",
        {
            "status": (
                "SUBMITTED",
                "REVIEWING",
                "APPROVED",
                "REJECTED",
                "COMPLETED",
                "CANCELLED",
            ),
            "provider_status": (
                "",
                "APPROVED",
                "REJECTED",
                "PROCESSING",
                "PENDING",
                "UNKNOWN",
                "REFUNDED",
                "CANCELLED",
            ),
        },
        _PUBLIC_ID_2,
        required_columns=(
            "user_id",
            "submitted_at",
            "provider",
            "reviewed_by_user_id",
            "executed_by_user_id",
        ),
    ),
    TableSpec(
        "wallet_adjustment_request",
        {"status": ("SUBMITTED", "APPROVED", "REJECTED", "APPLIED", "CANCELLED")},
        _PUBLIC_ID,
        required_columns=(
            "target_user_id",
            "requested_by_user_id",
            "approved_by_user_id",
            "created_at",
        ),
    ),
    TableSpec(
        "operations_moderation_case",
        {"status": ("PENDING", "APPROVED", "REJECTED", "APPLIED", "CANCELLED")},
        _PUBLIC_ID_2,
        required_columns=("requested_by_user_id", "approved_by_user_id", "created_at"),
    ),
    TableSpec(
        "operations_export_job",
        {"status": ("QUEUED", "COMPLETED", "FAILED", "EXPIRED")},
        _PUBLIC_ID,
        required_columns=("requested_by_user_id", "created_at"),
    ),
    TableSpec(
        "operation_idempotency",
        {"status": ("IN_PROGRESS", "COMPLETED")},
        required_columns=("actor_user_id", "created_at", "request_fingerprint"),
    ),
    TableSpec("operations_audit_log", required_columns=("actor_user_id", "created_at")),
)

TABLE_BY_NAME = {spec.name: spec for spec in TABLE_SPECS}
TABLE_NAMES = frozenset(TABLE_BY_NAME)
SAFE_STRINGS = frozenset(
    {
        *TABLE_NAMES,
        *STATUS_SET,
        "CREATE_GROUP",
        "SEND_GROUP_MSG",
        "DESTROY_GROUP",
        "IMPORTED",
        "CREDIT",
        "DEBIT",
        "HOLD",
        "RELEASE",
        "SCHEMA_MISSING",
        "INVARIANT_VIOLATION",
        "OK",
        "PRESENT",
        "MISSING",
        "SENT",
        "",
        "m5-vendor-db-evidence-v1",
        "V29",
        "V30",
        "V31",
    }
)
STRUCTURAL_KEYS = frozenset(
    {
        "schemaVersion",
        "status",
        "secrets",
        "evidenceBinding",
        "runId",
        "backendSha",
        "flutterSha",
        "apkSha",
        "fixtureId",
        "avd",
        "startNonce",
        "backendSourceDigest",
        "schema",
        "migrationScope",
        "requiredTables",
        "requiredColumns",
        "missingTables",
        "missingColumns",
        "providerDelivery",
        "privateMessage",
        "outbox",
        "atomicState",
        "tencentIm",
        "account",
        "callbackEvent",
        "roomGroup",
        "roomGroupOutbox",
        "publicMessage",
        "payment",
        "providerEvent",
        "rechargeOrder",
        "walletLedger",
        "wallet",
        "walletTransaction",
        "ledgerAccount",
        "ledgerJournal",
        "ledgerPosting",
        "walletReconciliation",
        "refundOps",
        "refundApplication",
        "walletAdjustment",
        "moderationCase",
        "operationsAudit",
        "idempotency",
        "checks",
        "rowCount",
        "present",
        "columns",
        "statusCounts",
        "unknownStatusCounts",
        "publicIds",
        "hashes",
        "errorCategories",
        "pairedStateMismatchCount",
        "missingPrivateMessageCount",
        "badAttemptCount",
        "callbackBadHashCount",
        "roomGroupMappingMismatchCount",
        "publicMessageBadEventVersionCount",
        "eventOrderMissingCount",
        "eventBadFingerprintCount",
        "succeededProviderMismatchCount",
        "negativeWalletCount",
        "negativeFrozenCount",
        "badTransactionAmountCount",
        "imbalancedJournalCount",
        "reconciliationMismatchCount",
        "refundFourEyesViolationCount",
        "opsFourEyesViolationCount",
        "refundOutcomeMismatchCount",
        "auditRowCount",
        "badIdempotencyFingerprintCount",
        "vendorOutbox",
        "callbackEvents",
        "outboxAttempts",
        "state",
        "attempts",
        "verified",
        "eventCount",
        "paymentSettlement",
        "providerEventVerified",
        "providerEventProcessedCount",
        "succeededOrderCount",
        "walletTransactionCount",
        "walletCreditCount",
        "ledgerJournalCount",
        "ledgerEntryCount",
        "balancedJournalCount",
        "ledgerImbalanceCount",
    }
)
CHECK_NAMES = (
    "provider_delivery_pair_mismatch",
    "provider_delivery_missing_private_message",
    "provider_delivery_bad_attempts",
    "callback_event_bad_hashes",
    "room_group_outbox_mapping_mismatch",
    "room_public_message_bad_event_version",
    "payment_event_order_missing",
    "payment_event_bad_fingerprint",
    "payment_accounting_linkage_mismatch",
    "recharge_order_bad_amount",
    "recharge_succeeded_provider_mismatch",
    "wallet_negative",
    "wallet_frozen_negative",
    "wallet_transaction_bad_amount",
    "ledger_journal_imbalance",
    "wallet_reconciliation_mismatch",
    "refund_four_eyes_violation",
    "refund_outcome_mismatch",
    "ops_four_eyes_violation",
    "ops_audit_rows",
    "idempotency_bad_fingerprint",
)
CHECK_SET = frozenset(CHECK_NAMES)
ERROR_CHECKS = frozenset(CHECK_SET - {"ops_audit_rows"})


@dataclasses.dataclass(frozen=True)
class EvidenceBinding:
    run_id: str
    backend_sha: str
    flutter_sha: str
    apk_sha: str
    fixture_id: str | None = None
    avd: str | None = None
    start_nonce: str | None = None
    backend_source_digest: str | None = None

    def as_dict(self) -> dict[str, str]:
        result = {
            "runId": self.run_id,
            "backendSha": self.backend_sha.lower(),
            "flutterSha": self.flutter_sha.lower(),
            "apkSha": self.apk_sha.lower(),
        }
        if self.fixture_id is not None:
            result["fixtureId"] = self.fixture_id
        if self.avd is not None:
            result["avd"] = self.avd
        if self.start_nonce is not None:
            result["startNonce"] = self.start_nonce
        if self.backend_source_digest is not None:
            result["backendSourceDigest"] = self.backend_source_digest.lower()
        return result


@dataclasses.dataclass(frozen=True)
class ParsedDatabaseEvidence:
    tables: dict[str, dict[str, object]]
    checks: dict[str, int]


def _first_value(environment: Mapping[str, str], names: Sequence[str]) -> str:
    values = [environment[name] for name in names if environment.get(name)]
    if not values:
        return ""
    if any(value != values[0] for value in values[1:]):
        raise ConfigurationError("conflicting configuration")
    return values[0]


def _constant_time_equal(left: str, right: str) -> bool:
    try:
        left_bytes = left.encode("ascii")
        right_bytes = right.encode("ascii")
    except UnicodeEncodeError:
        return False
    return hmac.compare_digest(left_bytes, right_bytes)


def _fixture_nickname(fixture_id: str) -> str:
    if not FIXTURE_ID_RE.fullmatch(fixture_id):
        raise EvidenceError("invalid fixture id")
    return "m5-" + hashlib.sha256(fixture_id.encode("utf-8")).hexdigest()[:13]


def _valid_bearer_header(values: Sequence[str], expected: str) -> bool:
    if len(values) != 1 or not values[0].startswith("Bearer "):
        return False
    return _constant_time_equal(values[0][len("Bearer "):], expected)


def validate_evidence_url(value: str, *, allow_loopback_http: bool = False) -> None:
    """Validate an evidence endpoint before a client opens it.

    External evidence services must use HTTPS.  Plain HTTP is accepted only
    for the helper endpoint that this runner creates on loopback; callers
    cannot opt into a non-loopback HTTP endpoint.  Query strings, fragments,
    user-info, and alternate paths are rejected so a credential cannot be
    smuggled into a URL or redirected to an unrelated handler.
    """

    if not isinstance(value, str) or not value or any(ord(char) < 0x20 for char in value):
        raise ConfigurationError("invalid evidence URL")
    try:
        parsed = urlsplit(value)
        hostname = parsed.hostname
        port = parsed.port
    except ValueError as error:
        raise ConfigurationError("invalid evidence URL") from error
    scheme = parsed.scheme.lower()
    if scheme == "https":
        pass
    elif (
        allow_loopback_http
        and scheme == "http"
        and hostname is not None
        and hostname.lower() in {"127.0.0.1", "localhost", "::1"}
    ):
        pass
    else:
        raise ConfigurationError("evidence endpoint must use HTTPS")
    if (
        not hostname
        or parsed.username is not None
        or parsed.password is not None
        or parsed.query
        or parsed.fragment
        or parsed.path not in {"/m5/db-evidence", "/m5/db-evidence/"}
        or (port is not None and not 1 <= port <= 65535)
    ):
        raise ConfigurationError("invalid evidence URL")


def _validate_evidence_token(value: str) -> None:
    if (
        len(value) < 32
        or len(value) > 512
        or not value.isascii()
        or any(character.isspace() or ord(character) < 0x20 for character in value)
        or len(set(value)) < 3
    ):
        raise EvidenceError("CONFIGURATION")


def _valid_attestation_headers(
    headers: Mapping[str, object],
    binding: EvidenceBinding,
    backend_source_digest: str,
    payment_scenario: str,
) -> bool:
    """Require request metadata to agree with the attested server config."""

    expected = {
        "X-M5-Backend-SHA": binding.backend_sha,
        "X-M5-Flutter-SHA": binding.flutter_sha,
        "X-M5-APK-SHA": binding.apk_sha,
        "X-M5-Backend-Digest": backend_source_digest,
        "X-M5-Payment-Scenario": payment_scenario,
    }
    for name, value in expected.items():
        values = headers.get_all(name) if hasattr(headers, "get_all") else None
        if not isinstance(values, list) or len(values) != 1:
            return False
        if not isinstance(values[0], str) or not _constant_time_equal(
            values[0].lower(), value.lower()
        ):
            return False
    return True


def _count_text(value: str) -> int:
    if not COUNT_RE.fullmatch(value):
        raise EvidenceError("invalid numeric marker")
    return int(value)


def validate_binding(binding: EvidenceBinding) -> None:
    if not RUN_ID_RE.fullmatch(binding.run_id):
        raise EvidenceError("invalid evidence run id")
    if not SHA1_RE.fullmatch(binding.backend_sha):
        raise EvidenceError("invalid backend SHA")
    if not SHA1_RE.fullmatch(binding.flutter_sha):
        raise EvidenceError("invalid Flutter SHA")
    if not SHA256_RE.fullmatch(binding.apk_sha):
        raise EvidenceError("invalid APK SHA")
    if binding.fixture_id is not None and not FIXTURE_ID_RE.fullmatch(binding.fixture_id):
        raise EvidenceError("invalid fixture id")
    if binding.avd is not None and not AVD_RE.fullmatch(binding.avd):
        raise EvidenceError("invalid AVD")
    if binding.start_nonce is not None and not START_NONCE_RE.fullmatch(
        binding.start_nonce
    ):
        raise EvidenceError("invalid start nonce")
    if binding.backend_source_digest is not None and not SHA256_RE.fullmatch(
        binding.backend_source_digest
    ):
        raise EvidenceError("invalid backend source digest")


def _run_checked(
    arguments: Sequence[str],
    *,
    cwd: str = "/",
    timeout: float = 12.0,
) -> str:
    try:
        completed = subprocess.run(
            list(arguments),
            cwd=cwd,
            env={"PATH": os.environ.get("PATH", "/usr/bin:/bin")},
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=timeout,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise ConfigurationError("attestation command unavailable") from error
    if completed.returncode != 0:
        raise ConfigurationError("attestation command failed")
    return completed.stdout


def _attest_checkout(repo: str, expected_sha: str) -> str:
    path = os.path.realpath(repo)
    if not os.path.isdir(path) or not os.path.exists(os.path.join(path, ".git")):
        raise ConfigurationError("attested checkout unavailable")
    git = shutil.which("git")
    if not git:
        raise ConfigurationError("git unavailable")
    head = _run_checked([git, "-C", path, "rev-parse", "--verify", "HEAD"]).strip()
    if not SHA1_RE.fullmatch(head) or head.lower() != expected_sha.lower():
        raise ConfigurationError("attested checkout SHA mismatch")
    status = _run_checked(
        [
            git,
            "-C",
            path,
            "status",
            "--porcelain=v1",
            "--untracked-files=all",
            "--ignore-submodules=none",
        ]
    )
    if status.strip():
        raise ConfigurationError("attested checkout is dirty")
    return path


def _attest_vendor_schema(repo: str) -> None:
    """Require the three migration files that define this report contract."""

    git = shutil.which("git")
    if not git:
        raise ConfigurationError("git unavailable")
    for migration in (
        "src/main/resources/db/migration/V29__alipay_sandbox_payment_authority.sql",
        "src/main/resources/db/migration/V30__tencent_im_delivery.sql",
        "src/main/resources/db/migration/V31__tencent_im_avchatroom_hint.sql",
    ):
        _run_checked([git, "-C", repo, "ls-files", "--error-unmatch", "--", migration])


def _attest_backend_source_digest(repo: str, expected_digest: str) -> str:
    script = os.path.join(repo, "scripts", "compute-backend-source-digest.sh")
    if not os.path.isfile(script) or not os.access(script, os.X_OK):
        raise ConfigurationError("backend source digest unavailable")
    output = _run_checked([script], cwd=repo, timeout=30.0).strip()
    if not SHA256_RE.fullmatch(output) or not _constant_time_equal(
        output.lower(), expected_digest.lower()
    ):
        raise ConfigurationError("backend source digest mismatch")
    return output.lower()


def _sha256_file(path: str) -> str:
    resolved = os.path.realpath(path)
    if not os.path.isfile(resolved) or os.path.islink(path):
        raise ConfigurationError("APK artifact unavailable")
    digest = hashlib.sha256()
    try:
        with open(resolved, "rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
    except OSError as error:
        raise ConfigurationError("APK artifact unreadable") from error
    return digest.hexdigest()


@dataclasses.dataclass(frozen=True)
class EvidenceConfig:
    mysql_container: str
    docker_bin: str
    docker_env: Mapping[str, str]
    binding: EvidenceBinding
    backend_repo: str
    flutter_repo: str | None = None
    apk_path: str | None = None
    evidence_token: str = ""
    host: str = "127.0.0.1"
    port: int = 0
    state_dir: str | None = None
    backend_source_digest: str = ""
    fixture_id: str | None = None
    payment_scenario: str = "none"


def read_config(environment: Mapping[str, str] | None = None) -> EvidenceConfig:
    """Read protected metadata and attest the selected source checkouts."""

    env = os.environ if environment is None else environment
    evidence_token = _first_value(env, M5_TOKEN_ENV_NAMES)
    if len(evidence_token) < 32 or len(evidence_token) > 512 or not evidence_token.isascii() or any(
        character.isspace() or ord(character) < 0x20 for character in evidence_token
    ):
        raise ConfigurationError("invalid evidence token")
    if len(set(evidence_token)) < 3:
        raise ConfigurationError("invalid evidence token")
    host = _first_value(env, M5_HOST_ENV_NAMES) or "127.0.0.1"
    if host not in {"127.0.0.1", "localhost"}:
        raise ConfigurationError("evidence endpoint must bind loopback")
    configured_port = _first_value(env, M5_PORT_ENV_NAMES)
    try:
        port = int(configured_port) if configured_port else 0
    except ValueError as error:
        raise ConfigurationError("invalid evidence port") from error
    if port < 0 or port > 65535:
        raise ConfigurationError("invalid evidence port")
    state_dir_value = _first_value(env, M5_STATE_DIR_ENV_NAMES)
    if not state_dir_value:
        raise ConfigurationError("nonce state directory is required")
    state_dir = os.path.realpath(state_dir_value)
    if not os.path.isdir(state_dir) or os.path.islink(state_dir):
        raise ConfigurationError("nonce state directory unavailable")
    try:
        state_mode = os.stat(state_dir).st_mode & 0o777
    except OSError as error:
        raise ConfigurationError("nonce state directory unavailable") from error
    if state_mode & 0o077:
        raise ConfigurationError("nonce state directory is too broad")
    backend_source_digest = _first_value(env, M5_BACKEND_DIGEST_ENV_NAMES)
    if not SHA256_RE.fullmatch(backend_source_digest or ""):
        raise ConfigurationError("invalid backend source digest")
    binding = EvidenceBinding(
        run_id=_first_value(env, ("M5_RUN_ID", "QA_M5_RUN_ID", "QA_RUN_ID")),
        backend_sha=_first_value(env, ("M5_BACKEND_SHA", "QA_BACKEND_SHA")),
        flutter_sha=_first_value(env, ("M5_FLUTTER_SHA", "QA_FLUTTER_SHA")),
        apk_sha=_first_value(
            env,
            ("M5_APK_SHA", "M5_APK_SHA256", "QA_APK_SHA", "QA_APK_SHA256"),
        ),
    )
    configured_fixture_id = (
        _first_value(env, ("M5_FIXTURE_ID", "QA_M5_FIXTURE_ID")) or None
    )
    if configured_fixture_id is not None and not FIXTURE_ID_RE.fullmatch(
        configured_fixture_id
    ):
        raise ConfigurationError("invalid fixture id")
    payment_scenario = _first_value(env, ("M5_ALIPAY_SCENARIO", "QA_M5_ALIPAY_SCENARIO")) or "none"
    if payment_scenario not in PAYMENT_SCENARIOS:
        raise ConfigurationError("invalid payment scenario")
    apk_path = _first_value(env, ("M5_APK_PATH", "QA_APK_PATH")) or None
    if not binding.apk_sha and apk_path:
        binding = dataclasses.replace(binding, apk_sha=_sha256_file(apk_path))
    validate_binding(binding)

    mysql_container = _first_value(
        env,
        ("M5_MYSQL_CONTAINER", "M5_DB_EVIDENCE_MYSQL_CONTAINER", "QA_MYSQL_CONTAINER"),
    )
    if not CONTAINER_NAME_RE.fullmatch(mysql_container or ""):
        raise ConfigurationError("invalid MySQL container")
    backend_repo = _first_value(env, ("M5_BACKEND_REPO", "QA_BACKEND_REPO"))
    if not backend_repo:
        raise ConfigurationError("backend checkout is required")
    backend_repo = _attest_checkout(backend_repo, binding.backend_sha)
    _attest_vendor_schema(backend_repo)
    backend_source_digest = _attest_backend_source_digest(
        backend_repo, backend_source_digest
    )

    flutter_repo = _first_value(env, ("M5_FLUTTER_REPO", "QA_FLUTTER_REPO"))
    if not flutter_repo:
        flutter_repo = str(Path(__file__).resolve().parents[2])
    flutter_repo = _attest_checkout(flutter_repo, binding.flutter_sha)

    if apk_path and _sha256_file(apk_path) != binding.apk_sha.lower():
        raise ConfigurationError("APK SHA mismatch")
    docker = shutil.which("docker")
    if not docker:
        raise ConfigurationError("docker unavailable")
    docker_socket = _first_value(env, ("M5_DOCKER_SOCKET", "QA_DOCKER_SOCKET"))
    if docker_socket and not (
        docker_socket.startswith("unix://") or docker_socket.startswith("/")
    ):
        raise ConfigurationError("docker socket must be local")
    docker_env = {"PATH": env.get("PATH", "/usr/bin:/bin")}
    if docker_socket:
        docker_env["DOCKER_HOST"] = docker_socket
    return EvidenceConfig(
        mysql_container=mysql_container,
        docker_bin=docker,
        docker_env=docker_env,
        binding=binding,
        backend_repo=backend_repo,
        flutter_repo=flutter_repo,
        apk_path=apk_path,
        evidence_token=evidence_token,
        host=host,
        port=port,
        state_dir=state_dir,
        backend_source_digest=backend_source_digest.lower(),
        fixture_id=configured_fixture_id,
        payment_scenario=payment_scenario,
    )


class DockerRunner:
    """Bounded Docker execution with diagnostics discarded."""

    def __init__(self, config: EvidenceConfig):
        self._config = config

    def _run(
        self,
        arguments: Sequence[str],
        timeout: float = DOCKER_EVIDENCE_TIMEOUT_SECONDS,
    ) -> str:
        try:
            completed = subprocess.run(
                [self._config.docker_bin, *arguments],
                cwd="/",
                env=dict(self._config.docker_env),
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
                timeout=timeout,
                check=False,
            )
        except (OSError, subprocess.TimeoutExpired) as error:
            raise EvidenceError("DB_UNAVAILABLE") from error
        if completed.returncode != 0:
            raise EvidenceError("DB_UNAVAILABLE")
        return completed.stdout

    def exec_shell(self, container: str, script: str) -> str:
        if not CONTAINER_NAME_RE.fullmatch(container or "") or "\x00" in script:
            raise EvidenceError("CONFIGURATION")
        return self._run(
            ("exec", container, "/bin/sh", "-c", script),
            timeout=DOCKER_EVIDENCE_TIMEOUT_SECONDS,
        )


# The database secret is expanded only in the container shell.  Every
# statement sent to the client is a bounded aggregate/read projection.  No
# user text, JSON payload, provider identifier, order identifier, or numeric
# user/room key is selected.
MYSQL_EVIDENCE_SCRIPT = r"""
set -eu
database="${MYSQL_DATABASE:-}"
database_user="${MYSQL_USER:-${MYSQL_APP_USER:-root}}"
database_secret="${MYSQL_PASSWORD:-${MYSQL_APP_PASSWORD:-${MYSQL_ROOT_PASSWORD:-}}}"
[ -n "$database" ] && [ -n "$database_secret" ] || exit 20
scope_nickname="${M5_SCOPE_NICKNAME:-}"
scope_since_epoch="${M5_SCOPE_SINCE_EPOCH:-}"
include_public_ids="${M5_INCLUDE_PUBLIC_IDS:-0}"
if [ -n "$scope_nickname" ]; then
  case "$scope_nickname" in
    m5-[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) ;;
    *) exit 28 ;;
  esac
  case "$scope_since_epoch" in
    ''|*[!0-9]*) exit 29 ;;
    *) ;;
  esac
fi

mysql_query() {
  MYSQL_PWD="$database_secret" mysql \
    --protocol=socket --connect-timeout=5 \
    --user="$database_user" --database="$database" \
    --batch --skip-column-names --raw --execute="$1"
}

valid_name() {
  case "$1" in
    ""|*[!A-Za-z0-9_]*) return 1 ;;
    *) return 0 ;;
  esac
}

numeric() {
  case "$1" in
    ""|*[!0-9]*) exit 21 ;;
    *) return 0 ;;
  esac
}

table_exists() {
  valid_name "$1" || exit 22
  value="$(mysql_query "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = '$1'")"
  numeric "$value"
  [ "$value" = 0 ] || [ "$value" = 1 ] || exit 23
  printf '%s' "$value"
}

column_exists() {
  valid_name "$1" || exit 24
  valid_name "$2" || exit 25
  value="$(mysql_query "SELECT COUNT(*) FROM information_schema.columns WHERE table_schema = DATABASE() AND table_name = '$1' AND column_name = '$2'")"
  numeric "$value"
  [ "$value" = 0 ] || [ "$value" = 1 ] || exit 26
  printf '%s' "$value"
}

# room_group_outbox_public_id is the explicit ingest link from an accepted
# Tencent Group callback to tencent_im_room_group_outbox.public_id.  V30 does
# not currently have it.  Never interpolate the callback table's scope using
# only received_at; emit an empty scope until every relation needed below is
# present so the required-column marker makes the live session fail closed.
callback_scope_available=0
if [ "$(table_exists tencent_im_callback_event)" = 1 ] \
  && [ "$(table_exists tencent_im_room_group_outbox)" = 1 ] \
  && [ "$(table_exists tencent_im_room_group)" = 1 ] \
  && [ "$(table_exists room_public_message)" = 1 ] \
  && [ "$(table_exists room)" = 1 ] \
  && [ "$(table_exists room_member)" = 1 ] \
  && [ "$(column_exists tencent_im_callback_event room_group_outbox_public_id)" = 1 ] \
  && [ "$(column_exists tencent_im_callback_event callback_command)" = 1 ] \
  && [ "$(column_exists tencent_im_room_group_outbox public_id)" = 1 ] \
  && [ "$(column_exists tencent_im_room_group_outbox operation)" = 1 ] \
  && [ "$(column_exists tencent_im_room_group_outbox room_id)" = 1 ] \
  && [ "$(column_exists tencent_im_room_group_outbox group_id)" = 1 ] \
  && [ "$(column_exists tencent_im_room_group_outbox generation)" = 1 ] \
  && [ "$(column_exists tencent_im_room_group_outbox aggregate_public_id)" = 1 ] \
  && [ "$(column_exists tencent_im_room_group_outbox event_version)" = 1 ] \
  && [ "$(column_exists tencent_im_room_group room_id)" = 1 ] \
  && [ "$(column_exists tencent_im_room_group group_id)" = 1 ] \
  && [ "$(column_exists tencent_im_room_group generation)" = 1 ] \
  && [ "$(column_exists room_public_message public_id)" = 1 ] \
  && [ "$(column_exists room_public_message room_id)" = 1 ] \
  && [ "$(column_exists room_public_message event_version)" = 1 ] \
  && [ "$(column_exists room_public_message created_at)" = 1 ] \
  && [ "$(column_exists room id)" = 1 ] \
  && [ "$(column_exists room owner_user_id)" = 1 ] \
  && [ "$(column_exists room_member room_id)" = 1 ] \
  && [ "$(column_exists room_member user_id)" = 1 ] \
  && [ "$(column_exists app_user id)" = 1 ] \
  && [ "$(column_exists app_user nickname)" = 1 ]; then
  callback_scope_available=1
fi

scope_where() {
  table="$1"
  [ -n "$scope_nickname" ] || return 0
  # The fixture nickname is derived from the protected M5 fixture id.  These
  # predicates stay inside MySQL; only aggregate markers cross the container
  # boundary.  Group callback rows are additionally joined through the
  # explicit callback->room-group-outbox link and then to the outbox's
  # first-party room_public_message row.  A missing link is never replaced by
  # the old received_at-only predicate.
  case "$table" in
    provider_delivery_outbox)
      printf "recipient_user_id IN (SELECT id FROM app_user WHERE nickname = '%s') AND created_at >= FROM_UNIXTIME(%s)" "$scope_nickname" "$scope_since_epoch" ;;
    private_message)
      printf "(sender_user_id IN (SELECT id FROM app_user WHERE nickname = '%s') OR receiver_user_id IN (SELECT id FROM app_user WHERE nickname = '%s')) AND created_at >= FROM_UNIXTIME(%s)" "$scope_nickname" "$scope_nickname" "$scope_since_epoch" ;;
    tencent_im_account)
      printf "user_id IN (SELECT id FROM app_user WHERE nickname = '%s') AND created_at >= FROM_UNIXTIME(%s)" "$scope_nickname" "$scope_since_epoch" ;;
    app_user)
      printf "nickname = '%s' AND created_at >= FROM_UNIXTIME(%s)" "$scope_nickname" "$scope_since_epoch" ;;
    refresh_session)
      printf "user_id IN (SELECT id FROM app_user WHERE nickname = '%s') AND created_at >= FROM_UNIXTIME(%s)" "$scope_nickname" "$scope_since_epoch" ;;
    tencent_im_callback_event)
      if [ "$callback_scope_available" = 1 ]; then
        printf "room_group_outbox_public_id IN (SELECT o.public_id FROM tencent_im_room_group_outbox o JOIN room_public_message p ON p.public_id = o.aggregate_public_id AND p.room_id = o.room_id AND p.event_version = o.event_version JOIN room r ON r.id = o.room_id LEFT JOIN room_member rm ON rm.room_id = r.id WHERE o.operation = 'SEND_GROUP_MSG' AND EXISTS (SELECT 1 FROM tencent_im_room_group g WHERE g.room_id = o.room_id AND g.group_id = o.group_id AND g.generation = o.generation) AND (r.owner_user_id IN (SELECT id FROM app_user WHERE nickname = '%s') OR rm.user_id IN (SELECT id FROM app_user WHERE nickname = '%s')) AND o.created_at >= FROM_UNIXTIME(%s) AND p.created_at >= FROM_UNIXTIME(%s)) AND callback_command = 'Group.CallbackAfterSendMsg' AND received_at >= FROM_UNIXTIME(%s)" "$scope_nickname" "$scope_nickname" "$scope_since_epoch" "$scope_since_epoch" "$scope_since_epoch"
      else
        printf "1 = 0"
      fi ;;
    tencent_im_room_group)
      printf "room_id IN (SELECT r.id FROM room r LEFT JOIN room_member rm ON rm.room_id = r.id WHERE r.owner_user_id IN (SELECT id FROM app_user WHERE nickname = '%s') OR rm.user_id IN (SELECT id FROM app_user WHERE nickname = '%s')) AND created_at >= FROM_UNIXTIME(%s)" "$scope_nickname" "$scope_nickname" "$scope_since_epoch" ;;
    tencent_im_room_group_outbox)
      printf "room_id IN (SELECT r.id FROM room r LEFT JOIN room_member rm ON rm.room_id = r.id WHERE r.owner_user_id IN (SELECT id FROM app_user WHERE nickname = '%s') OR rm.user_id IN (SELECT id FROM app_user WHERE nickname = '%s')) AND created_at >= FROM_UNIXTIME(%s)" "$scope_nickname" "$scope_nickname" "$scope_since_epoch" ;;
    room_public_message)
      printf "(sender_user_id IN (SELECT id FROM app_user WHERE nickname = '%s') OR room_id IN (SELECT r.id FROM room r LEFT JOIN room_member rm ON rm.room_id = r.id WHERE r.owner_user_id IN (SELECT id FROM app_user WHERE nickname = '%s') OR rm.user_id IN (SELECT id FROM app_user WHERE nickname = '%s'))) AND created_at >= FROM_UNIXTIME(%s)" "$scope_nickname" "$scope_nickname" "$scope_nickname" "$scope_since_epoch" ;;
    payment_provider_event)
      printf "order_no IN (SELECT order_no FROM recharge_order WHERE user_id IN (SELECT id FROM app_user WHERE nickname = '%s')) AND received_at >= FROM_UNIXTIME(%s)" "$scope_nickname" "$scope_since_epoch" ;;
    recharge_order)
      printf "user_id IN (SELECT id FROM app_user WHERE nickname = '%s') AND created_at >= FROM_UNIXTIME(%s)" "$scope_nickname" "$scope_since_epoch" ;;
    wallet)
      printf "user_id IN (SELECT id FROM app_user WHERE nickname = '%s')" "$scope_nickname" ;;
    wallet_transaction)
      printf "wallet_id IN (SELECT id FROM wallet WHERE user_id IN (SELECT id FROM app_user WHERE nickname = '%s')) AND created_at >= FROM_UNIXTIME(%s)" "$scope_nickname" "$scope_since_epoch" ;;
    ledger_account)
      printf "user_id IN (SELECT id FROM app_user WHERE nickname = '%s')" "$scope_nickname" ;;
    ledger_journal)
      printf "actor_user_id IN (SELECT id FROM app_user WHERE nickname = '%s') AND created_at >= FROM_UNIXTIME(%s)" "$scope_nickname" "$scope_since_epoch" ;;
    ledger_posting)
      printf "journal_id IN (SELECT j.id FROM ledger_journal j WHERE j.actor_user_id IN (SELECT id FROM app_user WHERE nickname = '%s') AND j.created_at >= FROM_UNIXTIME(%s)) AND created_at >= FROM_UNIXTIME(%s)" "$scope_nickname" "$scope_since_epoch" "$scope_since_epoch" ;;
    wallet_reconciliation)
      printf "wallet_id IN (SELECT id FROM wallet WHERE user_id IN (SELECT id FROM app_user WHERE nickname = '%s')) AND checked_at >= FROM_UNIXTIME(%s)" "$scope_nickname" "$scope_since_epoch" ;;
    refund_application)
      printf "user_id IN (SELECT id FROM app_user WHERE nickname = '%s') AND submitted_at >= FROM_UNIXTIME(%s)" "$scope_nickname" "$scope_since_epoch" ;;
    wallet_adjustment_request)
      printf "(target_user_id IN (SELECT id FROM app_user WHERE nickname = '%s') OR requested_by_user_id IN (SELECT id FROM app_user WHERE nickname = '%s')) AND created_at >= FROM_UNIXTIME(%s)" "$scope_nickname" "$scope_nickname" "$scope_since_epoch" ;;
    operations_moderation_case|operations_export_job)
      printf "requested_by_user_id IN (SELECT id FROM app_user WHERE nickname = '%s') AND created_at >= FROM_UNIXTIME(%s)" "$scope_nickname" "$scope_since_epoch" ;;
    operation_idempotency)
      printf "actor_user_id IN (SELECT id FROM app_user WHERE nickname = '%s') AND created_at >= FROM_UNIXTIME(%s)" "$scope_nickname" "$scope_since_epoch" ;;
    operations_audit_log)
      printf "actor_user_id IN (SELECT id FROM app_user WHERE nickname = '%s') AND created_at >= FROM_UNIXTIME(%s)" "$scope_nickname" "$scope_since_epoch" ;;
    *) exit 30 ;;
  esac
}

scoped_count_query() {
  table="$1"
  condition="$(scope_where "$table")"
  if [ -n "$condition" ]; then
    printf 'SELECT COUNT(*) FROM %s WHERE %s' "$table" "$condition"
  else
    printf 'SELECT COUNT(*) FROM %s' "$table"
  fi
}

row_count() {
  table="$1"
  [ "$(table_exists "$table")" = 1 ] || { printf '0'; return; }
  query="$(scoped_count_query "$table")"
  value="$(mysql_query "$query")"
  numeric "$value"
  printf '%s' "$value"
}

emit_table() {
  table="$1"
  present="$(table_exists "$table")"
  rows=0
  if [ "$present" = 1 ]; then rows="$(row_count "$table")"; fi
  printf 'T|%s|%s|%s\n' "$table" "$rows" "$present"
}

emit_column() {
  table="$1"
  column="$2"
  shift 2
  present="$(table_exists "$table")"
  column_present=0
  if [ "$present" = 1 ] && [ "$(column_exists "$table" "$column")" = 1 ]; then
    column_present=1
  fi
  printf 'X|%s|%s|%s\n' "$table" "$column" "$column_present"
  known=0
  for status in "$@"; do
    value=0
    if [ "$column_present" = 1 ]; then
      condition="$(scope_where "$table")"
      query="SELECT COUNT(*) FROM $table WHERE $column = '$status'"
      if [ -n "$condition" ]; then query="$query AND ($condition)"; fi
      value="$(mysql_query "$query")"
      numeric "$value"
    fi
    known=$((known + value))
    printf 'S|%s|%s|%s|%s\n' "$table" "$column" "$status" "$value"
  done
  unknown=0
  if [ "$column_present" = 1 ]; then
    rows="$(row_count "$table")"
    unknown=$((rows - known))
    [ "$unknown" -ge 0 ] || exit 27
  fi
  printf 'U|%s|%s|%s\n' "$table" "$column" "$unknown"
}

emit_required_column() {
  table="$1"
  column="$2"
  present=0
  if [ "$(table_exists "$table")" = 1 ] && [ "$(column_exists "$table" "$column")" = 1 ]; then
    present=1
  fi
  printf 'X|%s|%s|%s\n' "$table" "$column" "$present"
}

emit_public_ids() {
  table="$1"
  [ "$include_public_ids" = 1 ] || return 0
  present="$(table_exists "$table")"
  if [ "$present" = 1 ] && [ "$(column_exists "$table" public_id)" = 1 ]; then
    condition="$(scope_where "$table")"
    query="SELECT public_id FROM $table WHERE public_id REGEXP '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'"
    if [ -n "$condition" ]; then query="$query AND ($condition)"; fi
    query="$query ORDER BY id LIMIT 32"
    ids="$(mysql_query "$query")"
    while IFS= read -r value; do
      [ -n "$value" ] || continue
      printf 'D|%s|%s\n' "$table" "$value"
    done <<EOF
$ids
EOF
  fi
}

emit_hashes() {
  table="$1"
  shift
  present="$(table_exists "$table")"
  for column in "$@"; do
    column_present=0
    if [ "$present" = 1 ] && [ "$(column_exists "$table" "$column")" = 1 ]; then
      column_present=1
    fi
    printf 'X|%s|%s|%s\n' "$table" "$column" "$column_present"
    if [ "$column_present" = 1 ] && [ "$include_public_ids" = 1 ]; then
      condition="$(scope_where "$table")"
      query="SELECT $column FROM $table WHERE $column REGEXP '^[0-9a-fA-F]{64}$'"
      if [ -n "$condition" ]; then query="$query AND ($condition)"; fi
      query="$query ORDER BY id LIMIT 32"
      hashes="$(mysql_query "$query")"
      while IFS= read -r value; do
        [ -n "$value" ] || continue
        printf 'H|%s|%s|%s\n' "$table" "$column" "$value"
      done <<EOF
$hashes
EOF
    fi
  done
}

emit_check() {
  name="$1"
  query="$2"
  value="$(mysql_query "$query")"
  numeric "$value"
  printf 'K|%s|%s\n' "$name" "$value"
}

emit_scoped_check() {
  name="$1"
  table="$2"
  base_where="$3"
  condition="$(scope_where "$table")"
  query="SELECT COUNT(*) FROM $table WHERE $base_where"
  if [ -n "$condition" ]; then query="$query AND ($condition)"; fi
  emit_check "$name" "$query"
}

for table in \
  app_user refresh_session provider_delivery_outbox private_message tencent_im_account \
  tencent_im_callback_event tencent_im_room_group \
  tencent_im_room_group_outbox room_public_message payment_provider_event \
  recharge_order wallet wallet_transaction ledger_account ledger_journal \
  ledger_posting wallet_reconciliation refund_application \
  wallet_adjustment_request operations_moderation_case operations_export_job \
  operation_idempotency operations_audit_log; do
  emit_table "$table"
done

emit_required_column app_user nickname
emit_required_column app_user created_at
emit_required_column refresh_session user_id
emit_required_column refresh_session created_at
emit_required_column provider_delivery_outbox aggregate_type
emit_required_column provider_delivery_outbox aggregate_public_id
emit_required_column provider_delivery_outbox recipient_user_id
emit_required_column provider_delivery_outbox channel
emit_required_column provider_delivery_outbox attempt_count
emit_required_column provider_delivery_outbox created_at
emit_required_column private_message sender_user_id
emit_required_column private_message receiver_user_id
emit_required_column private_message created_at
emit_required_column tencent_im_account user_id
emit_required_column tencent_im_account created_at
emit_required_column tencent_im_callback_event received_at
emit_required_column tencent_im_callback_event room_group_outbox_public_id
emit_required_column tencent_im_callback_event callback_command
emit_required_column tencent_im_room_group room_id
emit_required_column tencent_im_room_group group_id
emit_required_column tencent_im_room_group generation
emit_required_column tencent_im_room_group created_at
emit_required_column tencent_im_room_group_outbox public_id
emit_required_column tencent_im_room_group_outbox room_id
emit_required_column tencent_im_room_group_outbox group_id
emit_required_column tencent_im_room_group_outbox generation
emit_required_column tencent_im_room_group_outbox event_version
emit_required_column tencent_im_room_group_outbox aggregate_public_id
emit_required_column tencent_im_room_group_outbox attempt_count
emit_required_column tencent_im_room_group_outbox created_at
emit_required_column room_public_message public_id
emit_required_column room_public_message room_id
emit_required_column room_public_message sender_user_id
emit_required_column room_public_message event_version
emit_required_column room_public_message created_at
emit_required_column payment_provider_event provider
emit_required_column payment_provider_event order_no
emit_required_column payment_provider_event received_at
emit_required_column recharge_order order_no
emit_required_column recharge_order user_id
emit_required_column recharge_order amount_minor
emit_required_column recharge_order gift_coin_amount
emit_required_column recharge_order payment_provider
emit_required_column recharge_order created_at
emit_required_column wallet user_id
emit_required_column wallet balance_minor
emit_required_column wallet frozen_minor
emit_required_column wallet_transaction wallet_id
emit_required_column wallet_transaction amount_minor
emit_required_column wallet_transaction business_type
emit_required_column wallet_transaction business_id
emit_required_column wallet_transaction created_at
emit_required_column ledger_account user_id
emit_required_column ledger_journal actor_user_id
emit_required_column ledger_journal business_type
emit_required_column ledger_journal business_id
emit_required_column ledger_journal created_at
emit_required_column ledger_posting journal_id
emit_required_column ledger_posting account_id
emit_required_column ledger_posting currency_code
emit_required_column ledger_posting amount_minor
emit_required_column ledger_posting created_at
emit_required_column wallet_reconciliation wallet_id
emit_required_column wallet_reconciliation checked_at
emit_required_column refund_application user_id
emit_required_column refund_application submitted_at
emit_required_column refund_application provider
emit_required_column refund_application reviewed_by_user_id
emit_required_column refund_application executed_by_user_id
emit_required_column wallet_adjustment_request target_user_id
emit_required_column wallet_adjustment_request requested_by_user_id
emit_required_column wallet_adjustment_request approved_by_user_id
emit_required_column wallet_adjustment_request created_at
emit_required_column operations_moderation_case requested_by_user_id
emit_required_column operations_moderation_case approved_by_user_id
emit_required_column operations_moderation_case created_at
emit_required_column operations_export_job requested_by_user_id
emit_required_column operations_export_job created_at
emit_required_column operation_idempotency actor_user_id
emit_required_column operation_idempotency created_at
emit_required_column operation_idempotency request_fingerprint
emit_required_column operations_audit_log actor_user_id
emit_required_column operations_audit_log created_at

emit_column provider_delivery_outbox status VENDOR_BLOCKED PENDING PROCESSING RETRY UNKNOWN DELIVERED FAILED
emit_column private_message delivery_status VENDOR_BLOCKED PENDING PROCESSING RETRY UNKNOWN DELIVERED FAILED
emit_column tencent_im_account status PENDING PROCESSING IMPORTED UNKNOWN FAILED
emit_column tencent_im_room_group state VENDOR_BLOCKED PENDING PROCESSING RETRY UNKNOWN ACTIVE DESTROY_PENDING DESTROYED FAILED
emit_column tencent_im_room_group_outbox operation CREATE_GROUP SEND_GROUP_MSG DESTROY_GROUP
emit_column tencent_im_room_group_outbox status VENDOR_BLOCKED PENDING PROCESSING RETRY UNKNOWN DELIVERED FAILED
emit_column payment_provider_event status RECEIVED PROCESSED REJECTED
emit_column payment_provider_event observed_status TRADE_SUCCESS TRADE_FINISHED TRADE_CLOSED WAIT_BUYER_PAY TRADE_PENDING CONFIRMING SUCCEEDED FAILED
emit_column recharge_order status CONFIRMING SUCCEEDED FAILED CANCELLED
emit_column recharge_order provider_status "" CREATED TRADE_SUCCESS TRADE_FINISHED TRADE_CLOSED WAIT_BUYER_PAY TRADE_PENDING
emit_column wallet_transaction transaction_type CREDIT DEBIT HOLD RELEASE
emit_column ledger_account status ACTIVE CLOSED
emit_column wallet_reconciliation status BALANCED MISMATCH
emit_column refund_application status SUBMITTED REVIEWING APPROVED REJECTED COMPLETED CANCELLED
emit_column refund_application provider_status "" APPROVED REJECTED PROCESSING PENDING UNKNOWN REFUNDED CANCELLED
emit_column wallet_adjustment_request status SUBMITTED APPROVED REJECTED APPLIED CANCELLED
emit_column operations_moderation_case status PENDING APPROVED REJECTED APPLIED CANCELLED
emit_column operations_export_job status QUEUED COMPLETED FAILED EXPIRED
emit_column operation_idempotency status IN_PROGRESS COMPLETED

for table in \
  provider_delivery_outbox private_message tencent_im_room_group_outbox \
  room_public_message payment_provider_event wallet_transaction ledger_account \
  ledger_journal wallet_reconciliation refund_application \
  wallet_adjustment_request operations_moderation_case operations_export_job; do
  emit_public_ids "$table"
done
emit_hashes tencent_im_callback_event event_key body_sha256
emit_hashes payment_provider_event event_fingerprint

zero=0

if [ "$(table_exists provider_delivery_outbox)" = 1 ] \
  && [ "$(table_exists private_message)" = 1 ] \
  && [ "$(column_exists provider_delivery_outbox aggregate_type)" = 1 ] \
  && [ "$(column_exists provider_delivery_outbox aggregate_public_id)" = 1 ] \
  && [ "$(column_exists provider_delivery_outbox channel)" = 1 ] \
  && [ "$(column_exists provider_delivery_outbox status)" = 1 ] \
  && [ "$(column_exists private_message public_id)" = 1 ] \
  && [ "$(column_exists private_message delivery_status)" = 1 ]; then
  outbox_scope="1 = 1"
  private_scope="1 = 1"
  if [ -n "$scope_nickname" ]; then
    outbox_scope="o.recipient_user_id IN (SELECT id FROM app_user WHERE nickname = '$scope_nickname') AND o.created_at >= FROM_UNIXTIME($scope_since_epoch)"
    private_scope="(m.sender_user_id IN (SELECT id FROM app_user WHERE nickname = '$scope_nickname') OR m.receiver_user_id IN (SELECT id FROM app_user WHERE nickname = '$scope_nickname')) AND m.created_at >= FROM_UNIXTIME($scope_since_epoch)"
  fi
  emit_check provider_delivery_pair_mismatch \
    "SELECT COUNT(*) FROM provider_delivery_outbox o LEFT JOIN private_message m ON m.public_id = o.aggregate_public_id WHERE $outbox_scope AND o.aggregate_type = 'PRIVATE_MESSAGE' AND o.channel = 'TENCENT_IM' AND (m.id IS NULL OR m.delivery_status <> o.status)"
  emit_check provider_delivery_missing_private_message \
    "SELECT COUNT(*) FROM private_message m LEFT JOIN provider_delivery_outbox o ON o.aggregate_type = 'PRIVATE_MESSAGE' AND o.aggregate_public_id = m.public_id AND o.channel = 'TENCENT_IM' WHERE $private_scope AND o.id IS NULL AND m.delivery_status <> 'VENDOR_BLOCKED'"
  if [ "$(column_exists provider_delivery_outbox attempt_count)" = 1 ]; then
    emit_scoped_check provider_delivery_bad_attempts provider_delivery_outbox "attempt_count > 8"
  else
    # The required-column marker below will fail closed for this schema.  Do
    # not fall back to an unscoped legacy count that could mix old runs into
    # this session's evidence.
    emit_check provider_delivery_bad_attempts "SELECT COUNT(*) FROM information_schema.tables WHERE 1 = 0"
  fi
else
  emit_check provider_delivery_pair_mismatch "SELECT COUNT(*) FROM information_schema.tables WHERE 1 = 0"
  emit_check provider_delivery_missing_private_message "SELECT COUNT(*) FROM information_schema.tables WHERE 1 = 0"
  emit_check provider_delivery_bad_attempts "SELECT COUNT(*) FROM information_schema.tables WHERE 1 = 0"
fi

if [ "$(table_exists tencent_im_callback_event)" = 1 ] \
  && [ "$(column_exists tencent_im_callback_event event_key)" = 1 ] \
  && [ "$(column_exists tencent_im_callback_event body_sha256)" = 1 ]; then
  emit_scoped_check callback_event_bad_hashes tencent_im_callback_event "event_key NOT REGEXP '^[0-9a-f]{64}$' OR body_sha256 NOT REGEXP '^[0-9a-f]{64}$'"
else
  emit_check callback_event_bad_hashes "SELECT COUNT(*) FROM information_schema.tables WHERE 1 = 0"
fi

if [ "$(table_exists tencent_im_room_group_outbox)" = 1 ] \
  && [ "$(table_exists tencent_im_room_group)" = 1 ]; then
  room_outbox_scope="1 = 1"
  if [ -n "$scope_nickname" ]; then
    room_outbox_scope="o.room_id IN (SELECT r.id FROM room r LEFT JOIN room_member rm ON rm.room_id = r.id WHERE r.owner_user_id IN (SELECT id FROM app_user WHERE nickname = '$scope_nickname') OR rm.user_id IN (SELECT id FROM app_user WHERE nickname = '$scope_nickname')) AND o.created_at >= FROM_UNIXTIME($scope_since_epoch)"
  fi
  if [ "$(table_exists room_public_message)" = 1 ] \
    && [ "$(column_exists tencent_im_room_group_outbox aggregate_public_id)" = 1 ] \
    && [ "$(column_exists room_public_message event_version)" = 1 ]; then
    emit_check room_group_outbox_mapping_mismatch \
      "SELECT COUNT(*) FROM tencent_im_room_group_outbox o LEFT JOIN tencent_im_room_group g ON g.room_id = o.room_id AND g.group_id = o.group_id AND g.generation = o.generation LEFT JOIN room_public_message p ON p.public_id = o.aggregate_public_id WHERE $room_outbox_scope AND (g.room_id IS NULL OR (o.operation = 'SEND_GROUP_MSG' AND (p.id IS NULL OR p.room_id <> o.room_id OR p.event_version <> o.event_version)))"
  else
    emit_check room_group_outbox_mapping_mismatch \
      "SELECT COUNT(*) FROM tencent_im_room_group_outbox o LEFT JOIN tencent_im_room_group g ON g.room_id = o.room_id AND g.group_id = o.group_id AND g.generation = o.generation WHERE $room_outbox_scope AND g.room_id IS NULL"
  fi
else
  emit_check room_group_outbox_mapping_mismatch "SELECT COUNT(*) FROM information_schema.tables WHERE 1 = 0"
fi

if [ "$(table_exists room_public_message)" = 1 ] \
  && [ "$(column_exists room_public_message event_version)" = 1 ]; then
  emit_scoped_check room_public_message_bad_event_version room_public_message "event_version <= 0"
else
  emit_check room_public_message_bad_event_version "SELECT COUNT(*) FROM information_schema.tables WHERE 1 = 0"
fi

if [ "$(table_exists payment_provider_event)" = 1 ] \
  && [ "$(table_exists recharge_order)" = 1 ]; then
  payment_event_scope="1 = 1"
  payment_order_scope="1 = 1"
  payment_event_since="1 = 1"
  payment_row_since="1 = 1"
  payment_journal_since="1 = 1"
  if [ -n "$scope_nickname" ]; then
    # A provider event has no first-party user foreign key.  Include every
    # event received after the run boundary so an event with a missing or
    # mismatched order fails closed instead of being silently discarded.
    payment_event_scope="e.received_at >= FROM_UNIXTIME($scope_since_epoch)"
    payment_order_scope="o.user_id IN (SELECT id FROM app_user WHERE nickname = '$scope_nickname') AND o.created_at >= FROM_UNIXTIME($scope_since_epoch)"
    payment_event_since="e.received_at >= FROM_UNIXTIME($scope_since_epoch)"
    payment_row_since="wt.created_at >= FROM_UNIXTIME($scope_since_epoch)"
    payment_journal_since="j.created_at >= FROM_UNIXTIME($scope_since_epoch)"
  fi
  emit_check payment_event_order_missing \
    "SELECT COUNT(*) FROM payment_provider_event e LEFT JOIN recharge_order o ON o.order_no = e.order_no AND o.payment_provider = e.provider WHERE $payment_event_scope AND o.id IS NULL"
  emit_check payment_event_bad_fingerprint \
    "SELECT COUNT(*) FROM payment_provider_event e LEFT JOIN recharge_order o ON o.order_no = e.order_no AND o.payment_provider = e.provider WHERE $payment_event_scope AND (e.event_fingerprint IS NULL OR e.event_fingerprint NOT REGEXP '^[0-9a-fA-F]{64}$')"
  # A successful settlement is one redacted relational fact, not four
  # unrelated row counters: the provider event and recharge order share the
  # same order_no/provider, the wallet credit uses that order_no as its
  # business_id and exactly the order's gift_coin_amount, and the one ledger
  # journal uses the same business_id with exactly two balanced postings of
  # that amount.  The provider event table intentionally stores no amount;
  # its amount was verified against recharge_order before the event was
  # persisted by the authoritative webhook service.
  if [ "$(column_exists payment_provider_event provider)" = 1 ] \
    && [ "$(column_exists payment_provider_event order_no)" = 1 ] \
    && [ "$(column_exists recharge_order order_no)" = 1 ] \
    && [ "$(column_exists recharge_order user_id)" = 1 ] \
    && [ "$(column_exists recharge_order amount_minor)" = 1 ] \
    && [ "$(column_exists recharge_order gift_coin_amount)" = 1 ] \
    && [ "$(column_exists recharge_order payment_provider)" = 1 ] \
    && [ "$(column_exists wallet_transaction wallet_id)" = 1 ] \
    && [ "$(column_exists wallet_transaction amount_minor)" = 1 ] \
    && [ "$(column_exists wallet_transaction business_type)" = 1 ] \
    && [ "$(column_exists wallet_transaction business_id)" = 1 ] \
    && [ "$(column_exists wallet_transaction transaction_type)" = 1 ] \
    && [ "$(column_exists ledger_journal actor_user_id)" = 1 ] \
    && [ "$(column_exists ledger_journal business_type)" = 1 ] \
    && [ "$(column_exists ledger_journal business_id)" = 1 ] \
    && [ "$(column_exists ledger_posting journal_id)" = 1 ] \
    && [ "$(column_exists ledger_posting account_id)" = 1 ] \
    && [ "$(column_exists ledger_posting currency_code)" = 1 ] \
    && [ "$(column_exists ledger_posting amount_minor)" = 1 ] \
    && [ "$(table_exists wallet)" = 1 ] \
    && [ "$(table_exists ledger_journal)" = 1 ] \
    && [ "$(table_exists ledger_posting)" = 1 ] \
    && [ "$(table_exists ledger_account)" = 1 ]; then
    emit_check payment_accounting_linkage_mismatch \
      "SELECT COUNT(*) FROM recharge_order o WHERE $payment_order_scope AND o.payment_provider = 'alipay-sandbox' AND o.status = 'SUCCEEDED' AND o.amount_minor > 0 AND o.gift_coin_amount > 0 AND (NOT EXISTS (SELECT 1 FROM payment_provider_event e WHERE e.provider = o.payment_provider AND e.order_no = o.order_no AND e.status = 'PROCESSED' AND e.observed_status IN ('TRADE_SUCCESS', 'TRADE_FINISHED', 'SUCCEEDED') AND $payment_event_since) OR (SELECT COUNT(*) FROM wallet_transaction wt JOIN wallet w ON w.id = wt.wallet_id WHERE w.user_id = o.user_id AND wt.business_type = 'PAYMENT_RECHARGE' AND wt.business_id = o.order_no AND wt.transaction_type = 'CREDIT' AND wt.amount_minor = o.gift_coin_amount AND $payment_row_since) <> 1 OR (SELECT COUNT(*) FROM ledger_journal j WHERE j.actor_user_id = o.user_id AND j.business_type = 'PAYMENT_RECHARGE' AND j.business_id = o.order_no AND $payment_journal_since) <> 1 OR NOT EXISTS (SELECT 1 FROM ledger_journal j WHERE j.actor_user_id = o.user_id AND j.business_type = 'PAYMENT_RECHARGE' AND j.business_id = o.order_no AND $payment_journal_since AND (SELECT COUNT(*) FROM ledger_posting p WHERE p.journal_id = j.id) = 2 AND NOT EXISTS (SELECT 1 FROM ledger_posting p WHERE p.journal_id = j.id AND p.currency_code <> 'GIFT_COIN') AND (SELECT COALESCE(SUM(p.amount_minor), 0) FROM ledger_posting p WHERE p.journal_id = j.id AND p.currency_code = 'GIFT_COIN') = 0 AND (SELECT COALESCE(SUM(CASE WHEN p.amount_minor > 0 THEN p.amount_minor ELSE 0 END), 0) FROM ledger_posting p WHERE p.journal_id = j.id AND p.currency_code = 'GIFT_COIN') = o.gift_coin_amount AND (SELECT COALESCE(SUM(CASE WHEN p.amount_minor < 0 THEN -p.amount_minor ELSE 0 END), 0) FROM ledger_posting p WHERE p.journal_id = j.id AND p.currency_code = 'GIFT_COIN') = o.gift_coin_amount AND EXISTS (SELECT 1 FROM ledger_posting p JOIN ledger_account a ON a.id = p.account_id WHERE p.journal_id = j.id AND p.currency_code = 'GIFT_COIN' AND p.amount_minor > 0 AND a.user_id = o.user_id AND a.currency_code = 'GIFT_COIN' AND a.account_type = 'USER_AVAILABLE')))"
  else
    emit_check payment_accounting_linkage_mismatch "SELECT COUNT(*) FROM information_schema.tables WHERE 1 = 0"
  fi
else
  emit_check payment_event_order_missing "SELECT COUNT(*) FROM information_schema.tables WHERE 1 = 0"
  emit_check payment_event_bad_fingerprint "SELECT COUNT(*) FROM information_schema.tables WHERE 1 = 0"
  emit_check payment_accounting_linkage_mismatch "SELECT COUNT(*) FROM information_schema.tables WHERE 1 = 0"
fi

if [ "$(table_exists recharge_order)" = 1 ]; then
  emit_scoped_check recharge_order_bad_amount recharge_order "amount_minor <= 0 OR gift_coin_amount <= 0"
  emit_scoped_check recharge_succeeded_provider_mismatch recharge_order "status = 'SUCCEEDED' AND payment_provider = 'alipay-sandbox' AND provider_status <> 'TRADE_SUCCESS'"
else
  emit_check recharge_order_bad_amount "SELECT COUNT(*) FROM information_schema.tables WHERE 1 = 0"
  emit_check recharge_succeeded_provider_mismatch "SELECT COUNT(*) FROM information_schema.tables WHERE 1 = 0"
fi

if [ "$(table_exists wallet)" = 1 ]; then
  emit_scoped_check wallet_negative wallet "balance_minor < 0"
  emit_scoped_check wallet_frozen_negative wallet "frozen_minor < 0"
else
  emit_check wallet_negative "SELECT COUNT(*) FROM information_schema.tables WHERE 1 = 0"
  emit_check wallet_frozen_negative "SELECT COUNT(*) FROM information_schema.tables WHERE 1 = 0"
fi
if [ "$(table_exists wallet_transaction)" = 1 ]; then
  emit_scoped_check wallet_transaction_bad_amount wallet_transaction "amount_minor <= 0"
else
  emit_check wallet_transaction_bad_amount "SELECT COUNT(*) FROM information_schema.tables WHERE 1 = 0"
fi
if [ "$(table_exists ledger_journal)" = 1 ] && [ "$(table_exists ledger_posting)" = 1 ]; then
  ledger_scope="1 = 1"
  if [ -n "$scope_nickname" ]; then
    ledger_scope="j.actor_user_id IN (SELECT id FROM app_user WHERE nickname = '$scope_nickname') AND j.created_at >= FROM_UNIXTIME($scope_since_epoch)"
  fi
  emit_check ledger_journal_imbalance \
    "SELECT COUNT(*) FROM (SELECT p.journal_id FROM ledger_posting p JOIN ledger_journal j ON j.id = p.journal_id WHERE $ledger_scope GROUP BY p.journal_id HAVING COALESCE(SUM(p.amount_minor), 0) <> 0) x"
else
  emit_check ledger_journal_imbalance "SELECT COUNT(*) FROM information_schema.tables WHERE 1 = 0"
fi
if [ "$(table_exists wallet_reconciliation)" = 1 ]; then
  emit_scoped_check wallet_reconciliation_mismatch wallet_reconciliation "status = 'MISMATCH'"
else
  emit_check wallet_reconciliation_mismatch "SELECT COUNT(*) FROM information_schema.tables WHERE 1 = 0"
fi

if [ "$(table_exists refund_application)" = 1 ]; then
  refund_scope="1 = 1"
  if [ -n "$scope_nickname" ]; then
    refund_scope="user_id IN (SELECT id FROM app_user WHERE nickname = '$scope_nickname') AND submitted_at >= FROM_UNIXTIME($scope_since_epoch)"
  fi
  emit_check refund_four_eyes_violation \
    "SELECT COUNT(*) FROM refund_application WHERE $refund_scope AND (reviewed_by_user_id IS NOT NULL AND executed_by_user_id IS NOT NULL AND reviewed_by_user_id = executed_by_user_id)"
  emit_check refund_outcome_mismatch \
    "SELECT COUNT(*) FROM refund_application WHERE $refund_scope AND (provider <> '' OR provider_status <> '') AND ((status = 'COMPLETED' AND (provider_status <> 'REFUNDED' OR reviewed_by_user_id IS NULL OR executed_by_user_id IS NULL)) OR (status = 'CANCELLED' AND provider_status <> 'CANCELLED') OR (status = 'APPROVED' AND provider_status <> 'APPROVED') OR (status = 'REJECTED' AND provider_status <> 'REJECTED') OR (status = 'SUBMITTED' AND provider_status <> ''))"
else
  emit_check refund_four_eyes_violation "SELECT COUNT(*) FROM information_schema.tables WHERE 1 = 0"
  emit_check refund_outcome_mismatch "SELECT COUNT(*) FROM information_schema.tables WHERE 1 = 0"
fi

if [ "$(table_exists wallet_adjustment_request)" = 1 ] \
  && [ "$(column_exists wallet_adjustment_request requested_by_user_id)" = 1 ] \
  && [ "$(column_exists wallet_adjustment_request approved_by_user_id)" = 1 ]; then
  adjustment_scope="1 = 1"
  if [ -n "$scope_nickname" ]; then
    adjustment_scope="(target_user_id IN (SELECT id FROM app_user WHERE nickname = '$scope_nickname') OR requested_by_user_id IN (SELECT id FROM app_user WHERE nickname = '$scope_nickname')) AND created_at >= FROM_UNIXTIME($scope_since_epoch)"
  fi
  value="$(mysql_query "SELECT COUNT(*) FROM wallet_adjustment_request WHERE $adjustment_scope AND approved_by_user_id IS NOT NULL AND approved_by_user_id = requested_by_user_id")"
  numeric "$value"
  adjustment_four_eyes="$value"
else
  adjustment_four_eyes=0
fi
if [ "$(table_exists operations_moderation_case)" = 1 ] \
  && [ "$(column_exists operations_moderation_case requested_by_user_id)" = 1 ] \
  && [ "$(column_exists operations_moderation_case approved_by_user_id)" = 1 ]; then
  moderation_scope="1 = 1"
  if [ -n "$scope_nickname" ]; then
    moderation_scope="requested_by_user_id IN (SELECT id FROM app_user WHERE nickname = '$scope_nickname') AND created_at >= FROM_UNIXTIME($scope_since_epoch)"
  fi
  value="$(mysql_query "SELECT COUNT(*) FROM operations_moderation_case WHERE $moderation_scope AND approved_by_user_id IS NOT NULL AND approved_by_user_id = requested_by_user_id")"
  numeric "$value"
  moderation_four_eyes="$value"
else
  moderation_four_eyes=0
fi
value=$((adjustment_four_eyes + moderation_four_eyes))
numeric "$value"
printf 'K|ops_four_eyes_violation|%s\n' "$value"

if [ "$(table_exists operations_audit_log)" = 1 ]; then
  emit_scoped_check ops_audit_rows operations_audit_log "1 = 1"
else
  emit_check ops_audit_rows "SELECT COUNT(*) FROM information_schema.tables WHERE 1 = 0"
fi
if [ "$(table_exists operation_idempotency)" = 1 ] \
  && [ "$(column_exists operation_idempotency request_fingerprint)" = 1 ]; then
  emit_scoped_check idempotency_bad_fingerprint operation_idempotency "request_fingerprint IS NULL OR request_fingerprint NOT REGEXP '^[0-9a-fA-F]{64}$'"
else
  emit_check idempotency_bad_fingerprint "SELECT COUNT(*) FROM information_schema.tables WHERE 1 = 0"
fi

unset database_secret MYSQL_PWD
""".strip()


def _new_table_state(spec: TableSpec) -> dict[str, object]:
    columns = {column: False for column in spec.status_columns}
    columns.update({kind: False for kind in spec.hash_kinds})
    columns.update({column: False for column in spec.required_columns})
    return {
        "rowCount": 0,
        "present": False,
        "columns": columns,
        "statusCounts": {
            column: {status: 0 for status in statuses}
            for column, statuses in spec.status_columns.items()
        },
        "unknownStatusCounts": {column: 0 for column in spec.status_columns},
        "publicIds": [],
        "hashes": {kind: [] for kind in spec.hash_kinds},
    }


def _parse_marker_line(line: str) -> list[str]:
    if not line or len(line) > 512 or any(ord(char) < 0x20 for char in line):
        raise EvidenceError("INVALID_MARKER")
    fields = line.split("|")
    if not fields or not MARKER_NAME_RE.fullmatch(fields[0]):
        raise EvidenceError("INVALID_MARKER")
    return fields


def parse_mysql_markers(output: str) -> ParsedDatabaseEvidence:
    """Parse only the typed marker protocol emitted by the SQL script."""

    if not isinstance(output, str) or not output or len(output) > 2_000_000:
        raise EvidenceError("INVALID_MARKER")
    tables = {spec.name: _new_table_state(spec) for spec in TABLE_SPECS}
    checks: dict[str, int] = {}
    seen_tables: set[str] = set()
    seen_columns: set[tuple[str, str]] = set()
    seen_statuses: set[tuple[str, str, str]] = set()
    seen_checks: set[str] = set()
    for raw_line in output.splitlines():
        fields = _parse_marker_line(raw_line)
        marker = fields[0]
        if marker == "T" and len(fields) == 4:
            table, count, present = fields[1:]
            if table not in TABLE_NAMES or table in seen_tables:
                raise EvidenceError("INVALID_MARKER")
            if present not in {"0", "1"}:
                raise EvidenceError("INVALID_MARKER")
            state = tables[table]
            state["rowCount"] = _count_text(count)
            state["present"] = present == "1"
            seen_tables.add(table)
        elif marker == "X" and len(fields) == 4:
            table, column, present = fields[1:]
            spec = TABLE_BY_NAME.get(table)
            if spec is None or (
                column not in spec.status_columns
                and column not in spec.hash_kinds
                and column not in spec.required_columns
            ):
                raise EvidenceError("INVALID_MARKER")
            key = (table, column)
            if key in seen_columns or present not in {"0", "1"}:
                raise EvidenceError("INVALID_MARKER")
            tables[table]["columns"][column] = present == "1"
            seen_columns.add(key)
        elif marker == "S" and len(fields) == 5:
            table, column, status, count = fields[1:]
            spec = TABLE_BY_NAME.get(table)
            if spec is None or status not in spec.status_columns.get(column, ()):
                raise EvidenceError("INVALID_MARKER")
            key = (table, column, status)
            if key in seen_statuses:
                raise EvidenceError("INVALID_MARKER")
            tables[table]["statusCounts"][column][status] = _count_text(count)
            seen_statuses.add(key)
        elif marker == "U" and len(fields) == 4:
            table, column, count = fields[1:]
            spec = TABLE_BY_NAME.get(table)
            if spec is None or column not in spec.status_columns:
                raise EvidenceError("INVALID_MARKER")
            key = (table, column, "unknown")
            if key in seen_statuses:
                raise EvidenceError("INVALID_MARKER")
            tables[table]["unknownStatusCounts"][column] = _count_text(count)
            seen_statuses.add(key)
        elif marker == "D" and len(fields) == 3:
            table, public_id = fields[1:]
            spec = TABLE_BY_NAME.get(table)
            if spec is None or not spec.public_ids or not UUID_RE.fullmatch(public_id):
                raise EvidenceError("INVALID_MARKER")
            ids = tables[table]["publicIds"]
            if len(ids) >= 32 or public_id.lower() in ids:
                raise EvidenceError("INVALID_MARKER")
            ids.append(public_id.lower())
        elif marker == "H" and len(fields) == 4:
            table, kind, value = fields[1:]
            spec = TABLE_BY_NAME.get(table)
            if spec is None or kind not in spec.hash_kinds or not SHA256_RE.fullmatch(value):
                raise EvidenceError("INVALID_MARKER")
            values = tables[table]["hashes"][kind]
            if len(values) >= 32:
                raise EvidenceError("INVALID_MARKER")
            values.append(value.lower())
        elif marker == "K" and len(fields) == 3:
            key, count = fields[1:]
            if key not in CHECK_SET or key in seen_checks:
                raise EvidenceError("INVALID_MARKER")
            checks[key] = _count_text(count)
            seen_checks.add(key)
        else:
            raise EvidenceError("INVALID_MARKER")

    if seen_tables != TABLE_NAMES or seen_checks != CHECK_SET:
        raise EvidenceError("INVALID_MARKER")
    for spec in TABLE_SPECS:
        for column, statuses in spec.status_columns.items():
            if (spec.name, column) not in seen_columns:
                raise EvidenceError("INVALID_MARKER")
            if any((spec.name, column, status) not in seen_statuses for status in statuses):
                raise EvidenceError("INVALID_MARKER")
            # The unknown marker uses a separate sentinel in seen_statuses.
            if (spec.name, column, "unknown") not in seen_statuses:
                raise EvidenceError("INVALID_MARKER")
        for column in spec.hash_kinds:
            if (spec.name, column) not in seen_columns:
                raise EvidenceError("INVALID_MARKER")
        for column in spec.required_columns:
            if (spec.name, column) not in seen_columns:
                raise EvidenceError("INVALID_MARKER")
    return ParsedDatabaseEvidence(tables=tables, checks=checks)


def _table_projection(
    table: Mapping[str, object],
    *,
    projected_columns: Sequence[str] | None = None,
) -> dict[str, object]:
    columns = table["columns"]
    if not isinstance(columns, Mapping):
        raise EvidenceError("INVALID_MARKER")
    if projected_columns is None:
        projected_columns = tuple(columns)
    return {
        "rowCount": table["rowCount"],
        "present": table["present"],
        # Presence-only required columns live in schema.requiredColumns.  The
        # per-table projection keeps only status/hash columns so no
        # ``user_id``-shaped schema key is mistaken for a row field by the
        # generic secret-policy validator.
        "columns": {
            column: columns[column]
            for column in projected_columns
            if column in columns
        },
        "statusCounts": {
            column: dict(values)
            for column, values in table["statusCounts"].items()
        },
        "unknownStatusCounts": dict(table["unknownStatusCounts"]),
        "publicIds": list(table["publicIds"]),
        "hashes": {kind: list(values) for kind, values in table["hashes"].items()},
    }


def _required_schema(parsed: ParsedDatabaseEvidence) -> tuple[dict[str, bool], dict[str, dict[str, bool]]]:
    table_presence = {
        name: bool(table["present"]) for name, table in parsed.tables.items()
    }
    column_presence = {
        name: {column: bool(value) for column, value in table["columns"].items()}
        for name, table in parsed.tables.items()
    }
    return table_presence, column_presence


def build_payload(
    parsed: ParsedDatabaseEvidence,
    binding: EvidenceBinding,
) -> dict[str, object]:
    """Build the fixed redacted JSON shape from validated markers."""

    validate_binding(binding)
    table_presence, column_presence = _required_schema(parsed)
    missing_tables = sorted(name for name, present in table_presence.items() if not present)
    missing_columns = sorted(
        f"{table}.{column}"
        for table, columns in column_presence.items()
        for column, present in columns.items()
        if table_presence[table] and not present
    )
    errors: list[str] = []
    if missing_tables or missing_columns:
        errors.append("SCHEMA_MISSING")
    if any(parsed.checks[name] > 0 for name in ERROR_CHECKS):
        errors.append("INVARIANT_VIOLATION")

    def table(name: str) -> dict[str, object]:
        spec = TABLE_BY_NAME[name]
        return _table_projection(
            parsed.tables[name],
            projected_columns=(*spec.status_columns, *spec.hash_kinds),
        )

    checks = dict(parsed.checks)
    payload: dict[str, object] = {
        "schemaVersion": "m5-vendor-db-evidence-v1",
        "status": "FAIL" if errors else "OK",
        "secrets": False,
        "evidenceBinding": binding.as_dict(),
        "schema": {
            "migrationScope": ["V29", "V30", "V31"],
            "requiredTables": table_presence,
            "requiredColumns": column_presence,
            "missingTables": missing_tables,
            "missingColumns": missing_columns,
        },
        "providerDelivery": {
            "privateMessage": table("private_message"),
            "outbox": table("provider_delivery_outbox"),
            "atomicState": {
                "pairedStateMismatchCount": checks["provider_delivery_pair_mismatch"],
                "missingPrivateMessageCount": checks["provider_delivery_missing_private_message"],
                "badAttemptCount": checks["provider_delivery_bad_attempts"],
            },
        },
        "tencentIm": {
            "account": table("tencent_im_account"),
            "callbackEvent": table("tencent_im_callback_event"),
            "roomGroup": table("tencent_im_room_group"),
            "roomGroupOutbox": table("tencent_im_room_group_outbox"),
            "publicMessage": table("room_public_message"),
            "checks": {
                "callbackBadHashCount": checks["callback_event_bad_hashes"],
                "roomGroupMappingMismatchCount": checks["room_group_outbox_mapping_mismatch"],
                "publicMessageBadEventVersionCount": checks["room_public_message_bad_event_version"],
            },
        },
        "payment": {
            "providerEvent": table("payment_provider_event"),
            "rechargeOrder": table("recharge_order"),
            "checks": {
                "eventOrderMissingCount": checks["payment_event_order_missing"],
                "eventBadFingerprintCount": checks["payment_event_bad_fingerprint"],
                "succeededProviderMismatchCount": checks["recharge_succeeded_provider_mismatch"],
            },
        },
        "walletLedger": {
            "wallet": table("wallet"),
            "walletTransaction": table("wallet_transaction"),
            "ledgerAccount": table("ledger_account"),
            "ledgerJournal": table("ledger_journal"),
            "ledgerPosting": table("ledger_posting"),
            "walletReconciliation": table("wallet_reconciliation"),
            "checks": {
                "negativeWalletCount": checks["wallet_negative"],
                "negativeFrozenCount": checks["wallet_frozen_negative"],
                "badTransactionAmountCount": checks["wallet_transaction_bad_amount"],
                "imbalancedJournalCount": checks["ledger_journal_imbalance"],
                "reconciliationMismatchCount": checks["wallet_reconciliation_mismatch"],
            },
        },
        "refundOps": {
            "refundApplication": table("refund_application"),
            "walletAdjustment": table("wallet_adjustment_request"),
            "moderationCase": table("operations_moderation_case"),
            "operationsAudit": table("operations_audit_log"),
            "idempotency": table("operation_idempotency"),
            "checks": {
                "refundFourEyesViolationCount": checks["refund_four_eyes_violation"],
                "opsFourEyesViolationCount": checks["ops_four_eyes_violation"],
                "refundOutcomeMismatchCount": checks["refund_outcome_mismatch"],
                "auditRowCount": checks["ops_audit_rows"],
                "badIdempotencyFingerprintCount": checks["idempotency_bad_fingerprint"],
            },
        },
        "errorCategories": sorted(set(errors)),
    }
    validate_payload(payload)
    return payload


def _normal_key(value: str) -> str:
    return re.sub(r"[^a-z0-9]", "", value.lower())


def _safe_key(key: str) -> bool:
    if key in STRUCTURAL_KEYS:
        return True
    normalized = _normal_key(key)
    if normalized in {
        "bodysha256",
        "eventfingerprint",
        "eventkey",
        "runid",
        "backendsha",
        "fluttersha",
        "apksha",
        "fixtureid",
        "avd",
        "startnonce",
        "backendsourcedigest",
    }:
        return True
    forbidden = (
        "token",
        "usersig",
        "orderstr",
        "password",
        "secret",
        "phone",
        "mobile",
        "userid",
        "roomid",
        "orderid",
        "providerid",
        "payload",
        "content",
        "reason",
        "detail",
    )
    return not any(term in normalized for term in forbidden)


def _safe_scalar(key: str, value: object) -> None:
    if isinstance(value, bool):
        return
    if type(value) is int:
        if value < 0:
            raise EvidenceError("SECRET_POLICY")
        return
    if not isinstance(value, str):
        raise EvidenceError("SECRET_POLICY")
    normalized_key = _normal_key(key)
    if normalized_key in {"backendsha", "fluttersha"}:
        if not SHA1_RE.fullmatch(value):
            raise EvidenceError("SECRET_POLICY")
        return
    if normalized_key == "apksha":
        if not SHA256_RE.fullmatch(value):
            raise EvidenceError("SECRET_POLICY")
        return
    if normalized_key == "backendsourcedigest":
        if not SHA256_RE.fullmatch(value):
            raise EvidenceError("SECRET_POLICY")
        return
    if normalized_key in {
        "bodysha256",
        "eventfingerprint",
        "eventkey",
        "hash",
        "eventkey",
        "eventfingerprint",
    } or key in {"event_key", "body_sha256", "event_fingerprint"}:
        if not SHA256_RE.fullmatch(value):
            raise EvidenceError("SECRET_POLICY")
        return
    if normalized_key == "runid":
        if not RUN_ID_RE.fullmatch(value):
            raise EvidenceError("SECRET_POLICY")
        return
    if normalized_key == "fixtureid":
        if not FIXTURE_ID_RE.fullmatch(value):
            raise EvidenceError("SECRET_POLICY")
        return
    if normalized_key == "avd":
        if not AVD_RE.fullmatch(value):
            raise EvidenceError("SECRET_POLICY")
        return
    if normalized_key == "startnonce":
        if not START_NONCE_RE.fullmatch(value):
            raise EvidenceError("SECRET_POLICY")
        return
    if normalized_key in {"publicid", "publicids"} or key == "public_id":
        if not UUID_RE.fullmatch(value):
            raise EvidenceError("SECRET_POLICY")
        return
    if value not in SAFE_STRINGS and not re.fullmatch(
        r"[A-Za-z0-9_.-]+\.[A-Za-z0-9_.-]+", value
    ):
        raise EvidenceError("SECRET_POLICY")


def _validate_tree(value: object, key: str = "") -> None:
    if isinstance(value, Mapping):
        if key == "requiredColumns":
            # Schema metadata necessarily names columns such as ``user_id``;
            # that is not a row value.  Validate this one projection against
            # the fixed TableSpec vocabulary instead of allowing arbitrary
            # ``user_id``-shaped keys elsewhere in a report.
            if set(value) != TABLE_NAMES:
                raise EvidenceError("SECRET_POLICY")
            for table_name, columns in value.items():
                spec = TABLE_BY_NAME[table_name]
                if not isinstance(columns, Mapping):
                    raise EvidenceError("SECRET_POLICY")
                allowed = {
                    *spec.status_columns,
                    *spec.hash_kinds,
                    *spec.required_columns,
                }
                if set(columns) != allowed or any(
                    type(present) is not bool for present in columns.values()
                ):
                    raise EvidenceError("SECRET_POLICY")
            return
        for child_key, child_value in value.items():
            if not isinstance(child_key, str) or not _safe_key(child_key):
                raise EvidenceError("SECRET_POLICY")
            _validate_tree(child_value, child_key)
        return
    if isinstance(value, (list, tuple)):
        for child in value:
            _validate_tree(child, key)
        return
    _safe_scalar(key, value)


def validate_payload(payload: Mapping[str, object]) -> None:
    """Reject any shape/value that could carry a secret or raw row field."""

    expected = {
        "schemaVersion",
        "status",
        "secrets",
        "evidenceBinding",
        "schema",
        "providerDelivery",
        "tencentIm",
        "payment",
        "walletLedger",
        "refundOps",
        "errorCategories",
    }
    if not isinstance(payload, Mapping) or set(payload) != expected:
        raise EvidenceError("SECRET_POLICY")
    if payload.get("schemaVersion") != "m5-vendor-db-evidence-v1":
        raise EvidenceError("SECRET_POLICY")
    if payload.get("status") not in {"OK", "FAIL"}:
        raise EvidenceError("SECRET_POLICY")
    if payload.get("secrets") is not False:
        raise EvidenceError("SECRET_POLICY")
    binding = payload.get("evidenceBinding")
    if not isinstance(binding, Mapping) or set(binding) != {
        "runId",
        "backendSha",
        "flutterSha",
        "apkSha",
    }:
        raise EvidenceError("SECRET_POLICY")
    try:
        validate_binding(
            EvidenceBinding(
                run_id=str(binding["runId"]),
                backend_sha=str(binding["backendSha"]),
                flutter_sha=str(binding["flutterSha"]),
                apk_sha=str(binding["apkSha"]),
            )
        )
    except (KeyError, TypeError, ValueError) as error:
        raise EvidenceError("SECRET_POLICY") from error
    errors = payload.get("errorCategories")
    if not isinstance(errors, list) or any(
        not isinstance(category, str) or category not in ALLOWED_ERROR_CATEGORIES
        for category in errors
    ):
        raise EvidenceError("SECRET_POLICY")
    _validate_tree(payload)


CSV_FIELDS = (
    "evidence_type",
    "section",
    "metric",
    "status",
    "count",
    "public_id",
    "hash",
    "error_category",
    "value",
)


def payload_to_csv(payload: Mapping[str, object], stream: IO[str]) -> None:
    """Write a fixed-column CSV projection without introducing new values."""

    validate_payload(payload)
    writer = csv.DictWriter(stream, fieldnames=CSV_FIELDS, lineterminator="\n")
    writer.writeheader()
    binding = payload["evidenceBinding"]
    assert isinstance(binding, Mapping)
    writer.writerow(
        {
            "evidence_type": "binding",
            "section": "evidenceBinding",
            "metric": "runId",
            "value": binding["runId"],
        }
    )
    for key in ("backendSha", "flutterSha", "apkSha"):
        writer.writerow(
            {
                "evidence_type": "binding",
                "section": "evidenceBinding",
                "metric": key,
                "hash": binding[key],
            }
        )

    def row(
        evidence_type: str,
        section: str,
        metric: str,
        *,
        status: str = "",
        count: int | str = "",
        public_id: str = "",
        hash_value: str = "",
        error_category: str = "",
        value: str = "",
    ) -> None:
        writer.writerow(
            {
                "evidence_type": evidence_type,
                "section": section,
                "metric": metric,
                "status": status,
                "count": count,
                "public_id": public_id,
                "hash": hash_value,
                "error_category": error_category,
                "value": value,
            }
        )

    def table_rows(section: str, table_name: str, table: Mapping[str, object]) -> None:
        row("table", section, table_name, count=table["rowCount"])
        for column, statuses in table["statusCounts"].items():
            for status, count in statuses.items():
                row("status", section, f"{table_name}.{column}", status=status, count=count)
            unknown = table["unknownStatusCounts"][column]
            row(
                "status",
                section,
                f"{table_name}.{column}",
                status="UNCONTROLLED",
                count=unknown,
            )
        for public_id in table["publicIds"]:
            row("public_id", section, table_name, public_id=public_id)
        for kind, values in table["hashes"].items():
            for value in values:
                row("hash", section, f"{table_name}.{kind}", hash_value=value)

    sections = (
        ("schema", "schema"),
        ("providerDelivery", "providerDelivery"),
        ("tencentIm", "tencentIm"),
        ("payment", "payment"),
        ("walletLedger", "walletLedger"),
        ("refundOps", "refundOps"),
    )
    for section_key, section_name in sections:
        section = payload[section_key]
        if not isinstance(section, Mapping):
            raise EvidenceError("SECRET_POLICY")
        # Tables are one level below the section, except for schema metadata.
        if section_key == "schema":
            for metric, values in section["requiredTables"].items():
                row("schema", section_name, metric, status="PRESENT" if values else "MISSING", count=1 if values else 0)
            for metric in section["missingTables"]:
                row("schema", section_name, "missingTable", value=metric)
            for metric in section["missingColumns"]:
                row("schema", section_name, "missingColumn", value=metric)
            continue
        for metric, value in section.items():
            if isinstance(value, Mapping) and "rowCount" in value:
                table_rows(section_name, metric, value)
            elif isinstance(value, Mapping):
                for check, count in value.items():
                    row(
                        "check",
                        section_name,
                        f"{metric}.{check}",
                        status="PASS" if count == 0 else "FAIL",
                        count=count,
                    )
    for category in payload["errorCategories"]:
        row("error", "report", "category", error_category=category)
    row("report", "report", "status", status=payload["status"])


class VendorDatabaseEvidenceCollector:
    """Collect one immutable snapshot from the configured MySQL container."""

    def __init__(self, config: EvidenceConfig):
        self._config = config
        self._docker = DockerRunner(config)

    def collect(self) -> dict[str, object]:
        try:
            # Keep this compatibility API redacted even when called by an
            # external importer.  It is not the live current-run contract;
            # callers that need ownership must use M5EvidenceSessionCollector.
            scoped_script = "export M5_INCLUDE_PUBLIC_IDS=0\n" + MYSQL_EVIDENCE_SCRIPT
            output = self._docker.exec_shell(
                self._config.mysql_container,
                scoped_script,
            )
            parsed = parse_mysql_markers(output)
            return build_payload(parsed, self._config.binding)
        except EvidenceError:
            raise
        except (OSError, ValueError, TypeError) as error:
            raise EvidenceError("READ_FAILED") from error


# A shorter name is convenient for harness imports while retaining the
# descriptive class for reviewers and external tooling.
M5EvidenceCollector = VendorDatabaseEvidenceCollector


def collect_evidence(config: EvidenceConfig) -> dict[str, object]:
    return VendorDatabaseEvidenceCollector(config).collect()


@dataclasses.dataclass(frozen=True)
class _ScopedSnapshot:
    """A marker snapshot with no public identifiers retained in state."""

    tables: dict[str, dict[str, object]]
    checks: dict[str, int]


@dataclasses.dataclass(frozen=True)
class _EvidenceStart:
    run_id: str
    avd: str
    fixture_id: str
    backend_sha: str
    flutter_sha: str
    apk_sha: str
    backend_source_digest: str
    start_nonce_hash: str
    since_epoch: int
    snapshot: _ScopedSnapshot
    consumed: bool = False


def _state_snapshot(parsed: ParsedDatabaseEvidence) -> _ScopedSnapshot:
    """Strip IDs/hashes before a baseline is persisted on disk."""

    tables: dict[str, dict[str, object]] = {}
    for spec in TABLE_SPECS:
        table = parsed.tables[spec.name]
        tables[spec.name] = {
            "rowCount": int(table["rowCount"]),
            "present": bool(table["present"]),
            "columns": {
                str(column): bool(present)
                for column, present in table["columns"].items()
            },
            "statusCounts": {
                str(column): {
                    str(status): int(count)
                    for status, count in statuses.items()
                }
                for column, statuses in table["statusCounts"].items()
            },
            "unknownStatusCounts": {
                str(column): int(count)
                for column, count in table["unknownStatusCounts"].items()
            },
        }
    return _ScopedSnapshot(tables=tables, checks=dict(parsed.checks))


def _validate_snapshot(snapshot: _ScopedSnapshot) -> None:
    if set(snapshot.tables) != TABLE_NAMES or set(snapshot.checks) != CHECK_SET:
        raise EvidenceError("INVALID_MARKER")
    for spec in TABLE_SPECS:
        table = snapshot.tables[spec.name]
        if set(table) != {
            "rowCount",
            "present",
            "columns",
            "statusCounts",
            "unknownStatusCounts",
        }:
            raise EvidenceError("INVALID_MARKER")
        if type(table["rowCount"]) is not int or table["rowCount"] < 0:
            raise EvidenceError("INVALID_MARKER")
        columns = table["columns"]
        if not isinstance(columns, dict) or set(columns) != {
            *spec.status_columns,
            *spec.hash_kinds,
            *spec.required_columns,
        } or any(type(value) is not bool for value in columns.values()):
            raise EvidenceError("INVALID_MARKER")
        statuses = table["statusCounts"]
        if not isinstance(statuses, dict) or set(statuses) != set(spec.status_columns):
            raise EvidenceError("INVALID_MARKER")
        for column, allowed in spec.status_columns.items():
            values = statuses[column]
            if not isinstance(values, dict) or set(values) != set(allowed):
                raise EvidenceError("INVALID_MARKER")
            if any(type(value) is not int or value < 0 for value in values.values()):
                raise EvidenceError("INVALID_MARKER")
        unknown = table["unknownStatusCounts"]
        if not isinstance(unknown, dict) or set(unknown) != set(spec.status_columns):
            raise EvidenceError("INVALID_MARKER")
        if any(type(value) is not int or value < 0 for value in unknown.values()):
            raise EvidenceError("INVALID_MARKER")
    if any(type(value) is not int or value < 0 for value in snapshot.checks.values()):
        raise EvidenceError("INVALID_MARKER")


def _snapshot_state_dict(snapshot: _ScopedSnapshot) -> dict[str, object]:
    _validate_snapshot(snapshot)
    return {"tables": snapshot.tables, "checks": snapshot.checks}


def _snapshot_from_state(value: object) -> _ScopedSnapshot:
    if not isinstance(value, Mapping):
        raise EvidenceError("INVALID_MARKER")
    snapshot = _ScopedSnapshot(
        tables=dict(value.get("tables", {})),
        checks=dict(value.get("checks", {})),
    )
    _validate_snapshot(snapshot)
    return snapshot


def _nonce_hash(nonce: str) -> str:
    return hashlib.sha256(nonce.encode("ascii")).hexdigest()


def _signed_start_nonce(secret: str) -> str:
    random_part = secrets_module.token_urlsafe(24)
    signature = hmac.new(
        secret.encode("utf-8"),
        random_part.encode("ascii"),
        hashlib.sha256,
    ).hexdigest()
    nonce = f"{random_part}.{signature}"
    if not START_NONCE_RE.fullmatch(nonce):
        raise EvidenceError("ATTESTATION")
    return nonce


def _verify_signed_start_nonce(nonce: str, secret: str) -> bool:
    if not START_NONCE_RE.fullmatch(nonce):
        return False
    random_part, separator, signature = nonce.partition(".")
    if not separator or not random_part or not re.fullmatch(r"[A-Za-z0-9_-]{16,128}", random_part):
        return False
    expected = hmac.new(
        secret.encode("utf-8"),
        random_part.encode("ascii"),
        hashlib.sha256,
    ).hexdigest()
    return _constant_time_equal(signature, expected)


def _state_filename(state_dir: str, run_id: str, avd: str, fixture_id: str) -> str:
    key = "\0".join((run_id, avd, fixture_id)).encode("utf-8")
    digest = hashlib.sha256(key).hexdigest()
    return os.path.join(state_dir, f"{digest}.json")


def _state_to_dict(start: _EvidenceStart) -> dict[str, object]:
    _validate_snapshot(start.snapshot)
    return {
        "schemaVersion": "m5-vendor-db-state-v1",
        "runId": start.run_id,
        "avd": start.avd,
        "fixtureId": start.fixture_id,
        "backendSha": start.backend_sha,
        "flutterSha": start.flutter_sha,
        "apkSha": start.apk_sha,
        "backendSourceDigest": start.backend_source_digest,
        "startNonceHash": start.start_nonce_hash,
        "sinceEpoch": start.since_epoch,
        "consumed": start.consumed,
        "snapshot": _snapshot_state_dict(start.snapshot),
    }


def _state_from_dict(value: object) -> _EvidenceStart:
    if not isinstance(value, Mapping) or set(value) != {
        "schemaVersion",
        "runId",
        "avd",
        "fixtureId",
        "backendSha",
        "flutterSha",
        "apkSha",
        "backendSourceDigest",
        "startNonceHash",
        "sinceEpoch",
        "consumed",
        "snapshot",
    }:
        raise EvidenceError("INVALID_MARKER")
    run_id = value["runId"]
    avd = value["avd"]
    fixture_id = value["fixtureId"]
    backend_sha = value["backendSha"]
    flutter_sha = value["flutterSha"]
    apk_sha = value["apkSha"]
    backend_source_digest = value["backendSourceDigest"]
    nonce_hash = value["startNonceHash"]
    since_epoch = value["sinceEpoch"]
    if (
        value["schemaVersion"] != "m5-vendor-db-state-v1"
        or not isinstance(run_id, str)
        or not RUN_ID_RE.fullmatch(run_id)
        or not isinstance(avd, str)
        or not AVD_RE.fullmatch(avd)
        or not isinstance(fixture_id, str)
        or not FIXTURE_ID_RE.fullmatch(fixture_id)
        or not isinstance(backend_sha, str)
        or not SHA1_RE.fullmatch(backend_sha)
        or not isinstance(flutter_sha, str)
        or not SHA1_RE.fullmatch(flutter_sha)
        or not isinstance(apk_sha, str)
        or not SHA256_RE.fullmatch(apk_sha)
        or not isinstance(backend_source_digest, str)
        or not SHA256_RE.fullmatch(backend_source_digest)
        or not isinstance(nonce_hash, str)
        or not SHA256_RE.fullmatch(nonce_hash)
        or type(since_epoch) is not int
        or since_epoch <= 0
        or type(value["consumed"]) is not bool
    ):
        raise EvidenceError("INVALID_MARKER")
    return _EvidenceStart(
        run_id=run_id,
        avd=avd,
        fixture_id=fixture_id,
        backend_sha=backend_sha.lower(),
        flutter_sha=flutter_sha.lower(),
        apk_sha=apk_sha.lower(),
        backend_source_digest=backend_source_digest.lower(),
        start_nonce_hash=nonce_hash.lower(),
        since_epoch=since_epoch,
        snapshot=_snapshot_from_state(value["snapshot"]),
        consumed=value["consumed"],
    )


def _read_state(path: str) -> _EvidenceStart:
    target = Path(path)
    if target.is_symlink() or not target.is_file():
        raise EvidenceError("ATTESTATION")
    try:
        if target.stat().st_size > 2_000_000:
            raise EvidenceError("INVALID_MARKER")
        with target.open("r", encoding="utf-8") as stream:
            value = json.load(stream)
    except EvidenceError:
        raise
    except (OSError, ValueError, TypeError) as error:
        raise EvidenceError("INVALID_MARKER") from error
    return _state_from_dict(value)


def _replace_state(path: str, content: str) -> None:
    target = Path(path)
    if target.is_symlink() or not target.is_file():
        raise EvidenceError("OUTPUT_WRITE")
    temporary: str | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            dir=target.parent,
            prefix=f".{target.name}.",
            suffix=".tmp",
            delete=False,
        ) as stream:
            temporary = stream.name
            os.chmod(temporary, 0o600)
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, target)
        temporary = None
    except OSError as error:
        raise EvidenceError("OUTPUT_WRITE") from error
    finally:
        if temporary:
            try:
                os.unlink(temporary)
            except OSError:
                pass


def _snapshot_count_delta(
    current: _ScopedSnapshot,
    baseline: _ScopedSnapshot,
    table_name: str,
) -> int:
    current_count = int(current.tables[table_name]["rowCount"])
    baseline_count = int(baseline.tables[table_name]["rowCount"])
    if current_count < baseline_count:
        raise EvidenceError("READ_FAILED")
    return current_count - baseline_count


def _status_delta(
    current: _ScopedSnapshot,
    baseline: _ScopedSnapshot,
    table_name: str,
    column: str,
    status: str,
) -> int:
    current_values = current.tables[table_name]["statusCounts"][column]
    baseline_values = baseline.tables[table_name]["statusCounts"][column]
    return max(0, int(current_values[status]) - int(baseline_values[status]))


def _check_delta(
    current: _ScopedSnapshot,
    baseline: _ScopedSnapshot,
    name: str,
) -> int:
    return max(0, int(current.checks[name]) - int(baseline.checks[name]))


def _payment_settlement_ready(
    current: _ScopedSnapshot,
    baseline: _ScopedSnapshot,
) -> bool:
    """Return true once the minimum success settlement rows are visible."""

    return (
        _status_delta(
            current, baseline, "payment_provider_event", "status", "PROCESSED"
        )
        >= 1
        and _status_delta(
            current,
            baseline,
            "payment_provider_event",
            "observed_status",
            "TRADE_SUCCESS",
        )
        >= 1
        and _status_delta(
            current, baseline, "recharge_order", "status", "SUCCEEDED"
        )
        >= 1
        and _status_delta(
            current,
            baseline,
            "wallet_transaction",
            "transaction_type",
            "CREDIT",
        )
        >= 1
        and _snapshot_count_delta(current, baseline, "ledger_journal") >= 1
        and _snapshot_count_delta(current, baseline, "ledger_posting") >= 2
    )


def _vendor_state(
    values: Mapping[str, int],
) -> str:
    if values.get("DELIVERED", 0) > 0:
        return "SENT"
    for status in ("FAILED", "UNKNOWN", "PROCESSING", "RETRY", "PENDING", "VENDOR_BLOCKED"):
        if values.get(status, 0) > 0:
            return status
    return "MISSING"


def _m5_payload_valid(payload: Mapping[str, object]) -> None:
    if set(payload) != M5_RESPONSE_KEYS or payload.get("status") != "OK":
        raise EvidenceError("SECRET_POLICY")
    if payload.get("secrets") is not False:
        raise EvidenceError("SECRET_POLICY")
    binding = payload.get("evidenceBinding")
    if not isinstance(binding, Mapping) or set(binding) != {
        "runId",
        "avd",
        "fixtureId",
        "startNonce",
        "backendSha",
        "flutterSha",
        "apkSha",
        "backendSourceDigest",
    }:
        raise EvidenceError("SECRET_POLICY")
    evidence_binding = EvidenceBinding(
        run_id=str(binding["runId"]),
        backend_sha=str(binding["backendSha"]),
        flutter_sha=str(binding["flutterSha"]),
        apk_sha=str(binding["apkSha"]),
        fixture_id=str(binding["fixtureId"]),
        avd=str(binding["avd"]),
        start_nonce=str(binding["startNonce"]),
        backend_source_digest=str(binding["backendSourceDigest"]),
    )
    validate_binding(evidence_binding)
    counters = payload.get("writeCounters")
    if not isinstance(counters, Mapping) or set(counters) != set(M5_WRITE_COUNTER_KEYS):
        raise EvidenceError("SECRET_POLICY")
    if any(type(value) is not int or value < 0 for value in counters.values()):
        raise EvidenceError("SECRET_POLICY")
    outbox = payload.get("vendorOutbox")
    callbacks = payload.get("callbackEvents")
    for section in (outbox, callbacks):
        if not isinstance(section, Mapping) or set(section) != {"tencentIm", "alipay"}:
            raise EvidenceError("SECRET_POLICY")
    for provider in ("tencentIm", "alipay"):
        value = outbox[provider]
        if not isinstance(value, Mapping) or set(value) != {"state", "attempts"}:
            raise EvidenceError("SECRET_POLICY")
        if value["state"] not in {
            "MISSING",
            "SENT",
            "VENDOR_BLOCKED",
            "PENDING",
            "PROCESSING",
            "RETRY",
            "UNKNOWN",
            "FAILED",
        } or type(value["attempts"]) is not int or value["attempts"] < 0:
            raise EvidenceError("SECRET_POLICY")
        callback = callbacks[provider]
        if not isinstance(callback, Mapping) or set(callback) != {"verified", "eventCount"}:
            raise EvidenceError("SECRET_POLICY")
        if type(callback["verified"]) is not bool or type(callback["eventCount"]) is not int or callback["eventCount"] < 0:
            raise EvidenceError("SECRET_POLICY")
    attempts = payload.get("outboxAttempts")
    if not isinstance(attempts, Mapping) or set(attempts) != {"tencentIm", "alipay"}:
        raise EvidenceError("SECRET_POLICY")
    if any(type(value) is not int or value < 0 for value in attempts.values()):
        raise EvidenceError("SECRET_POLICY")
    settlement = payload.get("paymentSettlement")
    settlement_keys = {
        "providerEventVerified",
        "providerEventProcessedCount",
        "succeededOrderCount",
        "walletTransactionCount",
        "walletCreditCount",
        "ledgerJournalCount",
        "ledgerEntryCount",
        "balancedJournalCount",
        "ledgerImbalanceCount",
    }
    if (
        not isinstance(settlement, Mapping)
        or set(settlement) != settlement_keys
        or type(settlement["providerEventVerified"]) is not bool
        or any(
            type(settlement[key]) is not int or settlement[key] < 0
            for key in settlement_keys - {"providerEventVerified"}
        )
    ):
        raise EvidenceError("SECRET_POLICY")
    digest = payload.get("backendSourceDigest")
    if not isinstance(digest, str) or not SHA256_RE.fullmatch(digest):
        raise EvidenceError("SECRET_POLICY")
    if digest.lower() != str(binding["backendSourceDigest"]).lower():
        raise EvidenceError("SECRET_POLICY")
    _validate_tree(payload)


class M5EvidenceSessionCollector:
    """Protected start/collect collector used by the M5 AVD runner."""

    def __init__(self, config: EvidenceConfig):
        self._config = config
        self._docker = DockerRunner(config)
        self._lock = threading.Lock()

    def _snapshot(self, fixture_id: str, since_epoch: int) -> _ScopedSnapshot:
        nickname = _fixture_nickname(fixture_id)
        if since_epoch <= 0 or not UNIX_EPOCH_RE.fullmatch(str(since_epoch)):
            raise EvidenceError("CONFIGURATION")
        script = (
            "export M5_SCOPE_NICKNAME="
            + shlex.quote(nickname)
            + "\nexport M5_SCOPE_SINCE_EPOCH="
            + str(since_epoch)
            + "\nexport M5_INCLUDE_PUBLIC_IDS=0\n"
            + MYSQL_EVIDENCE_SCRIPT
        )
        output = self._docker.exec_shell(self._config.mysql_container, script)
        return _state_snapshot(parse_mysql_markers(output))

    def _path(self, run_id: str, avd: str, fixture_id: str) -> str:
        if not RUN_ID_RE.fullmatch(run_id) or not AVD_RE.fullmatch(avd):
            raise EvidenceError("CONFIGURATION")
        _fixture_nickname(fixture_id)
        configured_run_id = self._config.binding.run_id
        configured_fixture_id = self._config.fixture_id
        if run_id != configured_run_id or (
            configured_fixture_id is not None
            and fixture_id != configured_fixture_id
        ):
            raise EvidenceError("ATTESTATION")
        if not self._config.state_dir:
            raise EvidenceError("CONFIGURATION")
        return _state_filename(self._config.state_dir, run_id, avd, fixture_id)

    def start(self, run_id: str, avd: str, fixture_id: str) -> dict[str, object]:
        with self._lock:
            path = self._path(run_id, avd, fixture_id)
            target = Path(path)
            if target.exists() or target.is_symlink():
                raise EvidenceError("ATTESTATION")
            since_epoch = int(time.time())
            snapshot = self._snapshot(fixture_id, since_epoch)
            nonce = _signed_start_nonce(self._config.evidence_token)
            start = _EvidenceStart(
                run_id=run_id,
                avd=avd,
                fixture_id=fixture_id,
                backend_sha=self._config.binding.backend_sha.lower(),
                flutter_sha=self._config.binding.flutter_sha.lower(),
                apk_sha=self._config.binding.apk_sha.lower(),
                backend_source_digest=self._config.backend_source_digest.lower(),
                start_nonce_hash=_nonce_hash(nonce),
                since_epoch=since_epoch,
                snapshot=snapshot,
            )
            _write_new_file(path, json.dumps(_state_to_dict(start), separators=(",", ":")))
            return {
                "status": "STARTED",
                "runId": run_id,
                "avd": avd,
                "fixtureId": fixture_id,
                "startNonce": nonce,
                "paymentScenario": self._config.payment_scenario,
                "paymentSettlementPoll": PAYMENT_SETTLEMENT_POLL_MODE,
                "backendSha": self._config.binding.backend_sha.lower(),
                "flutterSha": self._config.binding.flutter_sha.lower(),
                "apkSha": self._config.binding.apk_sha.lower(),
                "backendSourceDigest": self._config.backend_source_digest,
            }

    def collect(
        self,
        run_id: str,
        avd: str,
        fixture_id: str,
        start_nonce: str,
    ) -> dict[str, object]:
        with self._lock:
            path = self._path(run_id, avd, fixture_id)
            start = _read_state(path)
            if (
                start.consumed
                or start.run_id != run_id
                or start.avd != avd
                or start.fixture_id != fixture_id
                or start.backend_sha != self._config.binding.backend_sha.lower()
                or start.flutter_sha != self._config.binding.flutter_sha.lower()
                or start.apk_sha != self._config.binding.apk_sha.lower()
                or start.backend_source_digest
                != self._config.backend_source_digest.lower()
            ):
                raise EvidenceError("ATTESTATION")
            if not _verify_signed_start_nonce(start_nonce, self._config.evidence_token):
                raise EvidenceError("ATTESTATION")
            if not _constant_time_equal(_nonce_hash(start_nonce), start.start_nonce_hash):
                raise EvidenceError("ATTESTATION")
            now = int(time.time())
            if start.since_epoch > now + 60 or now - start.since_epoch > 2 * 60 * 60:
                raise EvidenceError("ATTESTATION")
            current = self._snapshot(fixture_id, start.since_epoch)
            _validate_snapshot(current)
            table_presence = all(
                bool(table["present"])
                and all(bool(present) for present in table["columns"].values())
                for table in current.tables.values()
            )
            if not table_presence:
                raise EvidenceError("SCHEMA_MISSING")
            if self._config.payment_scenario == "success" and avd == "AVD-A":
                # Alipay notify/worker settlement may be slightly later than
                # the native 9000 result. Keep the one-shot nonce open while
                # polling the same fixture-scoped aggregate snapshot for a
                # bounded 90 seconds; the final response still enforces exact
                # counts and all invariant checks below.
                deadline = time.monotonic() + 90.0
                while not _payment_settlement_ready(current, start.snapshot):
                    if time.monotonic() >= deadline:
                        break
                    time.sleep(1.0)
                    current = self._snapshot(fixture_id, start.since_epoch)
                    _validate_snapshot(current)

            private_delta = _snapshot_count_delta(current, start.snapshot, "private_message")
            app_user_delta = _snapshot_count_delta(current, start.snapshot, "app_user")
            refresh_session_delta = _snapshot_count_delta(
                current, start.snapshot, "refresh_session"
            )
            delivery_delta = _snapshot_count_delta(
                current, start.snapshot, "provider_delivery_outbox"
            )
            room_outbox_delta = _snapshot_count_delta(
                current, start.snapshot, "tencent_im_room_group_outbox"
            )
            account_delta = _snapshot_count_delta(
                current, start.snapshot, "tencent_im_account"
            )
            callback_delta = _snapshot_count_delta(
                current, start.snapshot, "tencent_im_callback_event"
            )
            payment_event_delta = _snapshot_count_delta(
                current, start.snapshot, "payment_provider_event"
            )
            recharge_delta = _snapshot_count_delta(current, start.snapshot, "recharge_order")
            wallet_transaction_delta = _snapshot_count_delta(
                current, start.snapshot, "wallet_transaction"
            )
            ledger_journal_delta = _snapshot_count_delta(
                current, start.snapshot, "ledger_journal"
            )
            # The V4/V11 schema names the journal's debit/credit rows
            # ``ledger_posting``.  The public M5 contract calls these
            # ``ledger_entries`` so the acceptance gate remains independent
            # of the storage naming; this is still a row-count-only delta.
            ledger_entry_delta = _snapshot_count_delta(
                current, start.snapshot, "ledger_posting"
            )
            payment_event_processed_delta = _status_delta(
                current,
                start.snapshot,
                "payment_provider_event",
                "status",
                "PROCESSED",
            )
            payment_event_trade_success_delta = _status_delta(
                current,
                start.snapshot,
                "payment_provider_event",
                "observed_status",
                "TRADE_SUCCESS",
            )
            recharge_succeeded_delta = _status_delta(
                current,
                start.snapshot,
                "recharge_order",
                "status",
                "SUCCEEDED",
            )
            wallet_credit_delta = _status_delta(
                current,
                start.snapshot,
                "wallet_transaction",
                "transaction_type",
                "CREDIT",
            )
            ledger_imbalance_delta = _check_delta(
                current, start.snapshot, "ledger_journal_imbalance"
            )

            tencent_status: dict[str, int] = {}
            for status in TABLE_BY_NAME["provider_delivery_outbox"].status_columns["status"]:
                tencent_status[status] = _status_delta(
                    current, start.snapshot, "provider_delivery_outbox", "status", status
                )
            for status in TABLE_BY_NAME["tencent_im_room_group_outbox"].status_columns["status"]:
                tencent_status[status] = tencent_status.get(status, 0) + _status_delta(
                    current,
                    start.snapshot,
                    "tencent_im_room_group_outbox",
                    "status",
                    status,
                )
            errors = [
                name
                for name in ERROR_CHECKS
                if _check_delta(current, start.snapshot, name) > 0
            ]
            if errors:
                raise EvidenceError("INVARIANT_VIOLATION")
            binding = EvidenceBinding(
                run_id=run_id,
                backend_sha=self._config.binding.backend_sha,
                flutter_sha=self._config.binding.flutter_sha,
                apk_sha=self._config.binding.apk_sha,
                fixture_id=fixture_id,
                avd=avd,
                start_nonce=start_nonce,
                backend_source_digest=self._config.backend_source_digest,
            )
            tencent_attempts = delivery_delta + room_outbox_delta
            alipay_attempts = payment_event_delta + recharge_delta
            payload: dict[str, object] = {
                "status": "OK",
                "evidenceBinding": binding.as_dict(),
                "writeCounters": {
                    # ``auth_sessions`` is intentionally the observed delta
                    # of the user and refresh-session authority rows.  It is
                    # not a synthetic success bit, and SMS challenge rows
                    # are omitted because they cannot be fixture-attributed.
                    "auth_sessions": app_user_delta + refresh_session_delta,
                    "im_credentials": account_delta,
                    "c2c_messages": private_delta,
                    "avchatroom_sessions": room_outbox_delta,
                    "alipay_orders": recharge_delta,
                    "payment_provider_events": payment_event_delta,
                    "wallet_transactions": wallet_transaction_delta,
                    "ledger_journals": ledger_journal_delta,
                    "ledger_entries": ledger_entry_delta,
                },
                "vendorOutbox": {
                    "tencentIm": {
                        "state": _vendor_state(tencent_status),
                        "attempts": tencent_attempts,
                    },
                    "alipay": {
                        "state": "SENT" if alipay_attempts > 0 else "MISSING",
                        "attempts": alipay_attempts,
                    },
                },
                "callbackEvents": {
                    "tencentIm": {
                        "verified": callback_delta > 0
                        and _check_delta(current, start.snapshot, "callback_event_bad_hashes") == 0,
                        "eventCount": callback_delta,
                    },
                    "alipay": {
                        "verified": payment_event_processed_delta > 0
                        and payment_event_trade_success_delta > 0
                        and _check_delta(current, start.snapshot, "payment_event_bad_fingerprint") == 0,
                        "eventCount": payment_event_delta,
                    },
                },
                # This is deliberately row-count-only accounting evidence.
                # The success gate combines it with the integration lane's
                # repeated reconcile marker; no order numbers, amounts,
                # provider payloads or user identifiers leave the collector.
                "paymentSettlement": {
                    "providerEventVerified": payment_event_processed_delta > 0
                    and payment_event_trade_success_delta > 0
                    and _check_delta(current, start.snapshot, "payment_event_bad_fingerprint") == 0,
                    "providerEventProcessedCount": payment_event_processed_delta,
                    "succeededOrderCount": recharge_succeeded_delta,
                    "walletTransactionCount": wallet_transaction_delta,
                    "walletCreditCount": wallet_credit_delta,
                    "ledgerJournalCount": ledger_journal_delta,
                    "ledgerEntryCount": ledger_entry_delta,
                    "balancedJournalCount": max(
                        0, ledger_journal_delta - ledger_imbalance_delta
                    ),
                    "ledgerImbalanceCount": ledger_imbalance_delta,
                },
                # These are outbox/order attempts, not SDK calls. Actual SDK
                # callback counts are attested separately by the Flutter
                # integration markers and are never inferred from DB rows.
                "outboxAttempts": {
                    "tencentIm": tencent_attempts,
                    "alipay": alipay_attempts,
                },
                "secrets": False,
                "backendSourceDigest": self._config.backend_source_digest,
            }
            _m5_payload_valid(payload)
            consumed = dataclasses.replace(start, consumed=True)
            _replace_state(path, json.dumps(_state_to_dict(consumed), separators=(",", ":")))
            return payload


class M5EvidenceHandler(http.server.BaseHTTPRequestHandler):
    """Loopback-only GET handler for the runner's start/collect protocol."""

    server_version = "M5Evidence"
    sys_version = ""

    def setup(self) -> None:
        super().setup()
        # A collect request may own the bounded settlement poll and a full
        # aggregate scan.  Do not let an idle socket timeout before that
        # response is available.
        self.connection.settimeout(float(COLLECT_REQUEST_TIMEOUT_SECONDS))

    def log_message(self, _format: str, *_arguments: object) -> None:
        return

    def log_error(self, _format: str, *_arguments: object) -> None:
        return

    def log_request(self, *_arguments: object) -> None:
        return

    def _json(self, status: int, payload: Mapping[str, object]) -> None:
        body = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode(
            "utf-8"
        )
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Connection", "close")
        self.end_headers()
        try:
            self.wfile.write(body)
        except OSError:
            pass
        self.close_connection = True

    def _single_header(self, name: str) -> str:
        values = self.headers.get_all(name) or []
        return values[0] if len(values) == 1 else ""

    def _not_allowed(self) -> None:
        self._json(405, {"status": "METHOD_NOT_ALLOWED"})

    def do_GET(self) -> None:
        parsed = urlsplit(self.path)
        if parsed.path not in {"/m5/db-evidence", "/m5/db-evidence/"} or parsed.query or parsed.fragment:
            self._json(404, {"status": "NOT_FOUND"})
            return
        lengths = self.headers.get_all("Content-Length")
        if lengths not in (None, ["0"]):
            self._json(400, {"status": "BAD_REQUEST"})
            return
        server = self.server
        if not _valid_bearer_header(
            self.headers.get_all("Authorization") or [], server.evidence_token
        ):
            self._json(401, {"status": "UNAUTHORIZED"})
            return
        if not _valid_attestation_headers(
            self.headers,
            server.binding,
            server.backend_source_digest,
            server.payment_scenario,
        ):
            self._json(400, {"status": "BAD_REQUEST"})
            return
        phase = self._single_header("X-M5-Evidence-Phase")
        run_id = self._single_header("X-M5-Run-ID")
        avd = self._single_header("X-M5-AVD")
        fixture_id = self._single_header("X-M5-Fixture-ID")
        start_nonce = self._single_header("X-M5-Start-Nonce")
        if not RUN_ID_RE.fullmatch(run_id) or not AVD_RE.fullmatch(avd) or not FIXTURE_ID_RE.fullmatch(fixture_id):
            self._json(400, {"status": "BAD_REQUEST"})
            return
        try:
            if phase == "start" and not start_nonce:
                self._json(201, server.collector.start(run_id, avd, fixture_id))
                return
            if phase == "collect" and START_NONCE_RE.fullmatch(start_nonce):
                self._json(
                    200,
                    server.collector.collect(run_id, avd, fixture_id, start_nonce),
                )
                return
            self._json(400, {"status": "BAD_REQUEST"})
        except EvidenceError as error:
            # Keep failures controlled; never echo Docker/MySQL diagnostics or
            # the supplied nonce. The runner treats any unavailable response
            # as a fail-closed evidence result.
            self._json(
                503,
                {
                    "status": "UNAVAILABLE",
                    "errorCategories": [_classify_exception(error)],
                },
            )
        except Exception:
            # Unexpected Docker/HTTP/parser exceptions are deliberately
            # collapsed into the same controlled category.  Never let a
            # traceback or exception text become an evidence response.
            self._json(
                503,
                {"status": "UNAVAILABLE", "errorCategories": ["READ_FAILED"]},
            )

    def do_POST(self) -> None:
        self._not_allowed()

    def do_PUT(self) -> None:
        self._not_allowed()

    def do_PATCH(self) -> None:
        self._not_allowed()

    def do_DELETE(self) -> None:
        self._not_allowed()

    def do_HEAD(self) -> None:
        self._not_allowed()

    def do_OPTIONS(self) -> None:
        self._not_allowed()

    def do_CONNECT(self) -> None:
        self._not_allowed()

    def do_TRACE(self) -> None:
        self._not_allowed()


class M5EvidenceServer(http.server.ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = False

    def __init__(
        self,
        address: tuple[str, int],
        collector: M5EvidenceSessionCollector,
        evidence_token: str,
        *,
        binding: EvidenceBinding | None = None,
        backend_source_digest: str = "",
    ):
        if address[0] not in {"127.0.0.1", "localhost"}:
            raise EvidenceError("CONFIGURATION")
        _validate_evidence_token(evidence_token)
        super().__init__(address, M5EvidenceHandler)
        self.collector = collector
        self.evidence_token = evidence_token
        configured_binding = binding
        if configured_binding is None:
            configured = getattr(collector, "_config", None)
            configured_binding = getattr(configured, "binding", None)
        if not isinstance(configured_binding, EvidenceBinding):
            raise EvidenceError("CONFIGURATION")
        digest = backend_source_digest
        if not digest:
            configured = getattr(collector, "_config", None)
            digest = str(getattr(configured, "backend_source_digest", ""))
        validate_binding(configured_binding)
        if not SHA256_RE.fullmatch(digest):
            raise EvidenceError("CONFIGURATION")
        configured = getattr(collector, "_config", None)
        payment_scenario = str(getattr(configured, "payment_scenario", ""))
        if payment_scenario not in PAYMENT_SCENARIOS:
            raise EvidenceError("CONFIGURATION")
        self.binding = configured_binding
        self.backend_source_digest = digest.lower()
        self.payment_scenario = payment_scenario


def serve_evidence(config: EvidenceConfig) -> int:
    """Serve the protected M5 endpoint until interrupted."""

    server = M5EvidenceServer(
        (config.host, config.port),
        M5EvidenceSessionCollector(config),
        config.evidence_token,
        binding=config.binding,
        backend_source_digest=config.backend_source_digest,
    )
    try:
        print(
            f"M5_DB_EVIDENCE_LISTENING={config.host}:{server.server_address[1]}/m5/db-evidence",
            flush=True,
        )
        server.serve_forever(poll_interval=0.25)
    except KeyboardInterrupt:
        return 0
    finally:
        server.server_close()
    return 0


def _failure_payload(
    category: str,
    binding: EvidenceBinding | None = None,
) -> dict[str, object]:
    if category not in ALLOWED_ERROR_CATEGORIES:
        category = "READ_FAILED"
    result: dict[str, object] = {
        "status": "UNAVAILABLE",
        "secrets": False,
        "errorCategories": [category],
    }
    if binding is not None:
        # A valid binding is safe to carry in a failure report as well; it
        # prevents an operator from accidentally attaching a stale failure.
        result["evidenceBinding"] = binding.as_dict()
    return result


def _classify_exception(error: BaseException) -> str:
    if isinstance(error, ConfigurationError):
        return "CONFIGURATION"
    if isinstance(error, EvidenceError):
        value = str(error)
        if value in ALLOWED_ERROR_CATEGORIES:
            return value
        if "marker" in value.lower():
            return "INVALID_MARKER"
        if "schema" in value.lower():
            return "SCHEMA_MISSING"
        return "READ_FAILED"
    return "READ_FAILED"


def _write_new_file(path: str, content: str) -> None:
    """Publish an output atomically without following an existing symlink."""

    target = Path(path)
    if target.exists() or target.is_symlink():
        raise EvidenceError("OUTPUT_WRITE")
    parent = target.parent
    if not parent.is_dir() or parent.is_symlink():
        raise EvidenceError("OUTPUT_WRITE")
    temporary: str | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            dir=parent,
            prefix=f".{target.name}.",
            suffix=".tmp",
            delete=False,
        ) as stream:
            temporary = stream.name
            os.chmod(temporary, 0o600)
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, target)
        temporary = None
    except (OSError, ValueError) as error:
        raise EvidenceError("OUTPUT_WRITE") from error
    finally:
        if temporary:
            try:
                os.unlink(temporary)
            except OSError:
                pass


def _safe_json(payload: Mapping[str, object]) -> str:
    validate_payload(payload)
    return json.dumps(payload, ensure_ascii=False, separators=(",", ":"))


def _self_test() -> int:
    """Run a local no-Docker contract and leakage test."""

    binding = EvidenceBinding(
        run_id="m5-self-test",
        backend_sha="1" * 40,
        flutter_sha="2" * 40,
        apk_sha="3" * 64,
    )
    validate_binding(binding)
    if any(
        re.search(rf"\b{keyword}\b", MYSQL_EVIDENCE_SCRIPT, re.IGNORECASE)
        for keyword in ("INSERT", "UPDATE", "DELETE", "ALTER", "DROP", "TRUNCATE")
    ):
        raise AssertionError("non-read SQL keyword found")
    for term in (
        "payload_json",
        "order_str",
        "user_sig",
        "usersig",
        "provider_order_id",
        "provider_refund_id",
    ):
        if term in MYSQL_EVIDENCE_SCRIPT.lower():
            raise AssertionError("sensitive row column found in SQL")
    if "SELECT COUNT(*)" not in MYSQL_EVIDENCE_SCRIPT:
        raise AssertionError("aggregate SQL missing")
    parsed = parse_mysql_markers(
        ""  # The full marker fixture is assembled below to keep this self-test readable.
    ) if False else None
    # A minimal marker fixture is deliberately generated from the fixed
    # vocabulary, which also catches accidental table/column drift.
    lines: list[str] = []
    for spec in TABLE_SPECS:
        lines.append(f"T|{spec.name}|0|1")
        for column, statuses in spec.status_columns.items():
            lines.append(f"X|{spec.name}|{column}|1")
            lines.extend(f"S|{spec.name}|{column}|{status}|0" for status in statuses)
            lines.append(f"U|{spec.name}|{column}|0")
        lines.extend(f"X|{spec.name}|{kind}|1" for kind in spec.hash_kinds)
        lines.extend(f"X|{spec.name}|{column}|1" for column in spec.required_columns)
        for public_id in spec.public_ids:
            lines.append(f"D|{spec.name}|{public_id}")
        for kind in spec.hash_kinds:
            lines.append(f"H|{spec.name}|{kind}|{'a' * 64}")
    lines.extend(f"K|{name}|0" for name in CHECK_NAMES)
    parsed = parse_mysql_markers("\n".join(lines) + "\n")
    payload = build_payload(parsed, binding)
    validate_payload(payload)
    encoded = _safe_json(payload).lower()
    for term in FORBIDDEN_MARKER_TERMS:
        if term == "secret":
            # The fixed boolean field ``secrets=false`` is part of the
            # contract; it does not carry a secret value.
            continue
        if term in encoded:
            # ``errorCategories``/structure never include a forbidden term;
            # this guard is intentionally strict for future schema changes.
            raise AssertionError("forbidden report term found")
    csv_output = __import__("io").StringIO()
    payload_to_csv(payload, csv_output)
    if "payload_json" in csv_output.getvalue().lower():
        raise AssertionError("sensitive CSV term found")
    print("self-test=PASS")
    return 0


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Collect redacted M5 V29-V31 vendor database evidence"
    )
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument(
        "--serve",
        action="store_true",
        help="serve the protected M5 start/collect endpoint",
    )
    parser.add_argument("--json", "--output-json", dest="json_path")
    parser.add_argument("--csv", "--output-csv", dest="csv_path")
    parser.add_argument("--run-id")
    parser.add_argument("--backend-sha")
    parser.add_argument("--flutter-sha")
    parser.add_argument("--apk-sha")
    parser.add_argument("--mysql-container")
    parser.add_argument("--backend-repo")
    parser.add_argument("--flutter-repo")
    parser.add_argument("--apk-path")
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = _parser().parse_args(list(argv) if argv is not None else None)
    if args.self_test:
        if args.serve or any(
            value is not None
            for value in (
                args.json_path,
                args.csv_path,
                args.run_id,
                args.backend_sha,
                args.flutter_sha,
                args.apk_sha,
                args.mysql_container,
                args.backend_repo,
                args.flutter_repo,
                args.apk_path,
            )
        ):
            return 64
        try:
            return _self_test()
        except AssertionError:
            return 1

    if not args.serve:
        # The old one-shot global snapshot cannot establish current-run
        # ownership. Keep the CLI fail-closed; the supported live path is the
        # authenticated start -> collect endpoint.
        print(
            json.dumps(
                {"status": "UNAVAILABLE", "errorCategories": ["CONFIGURATION"]},
                separators=(",", ":"),
            )
        )
        return 64
    if args.json_path or args.csv_path:
        print(
            json.dumps(
                {"status": "UNAVAILABLE", "errorCategories": ["CONFIGURATION"]},
                separators=(",", ":"),
            )
        )
        return 64

    environment = dict(os.environ)
    overrides = {
        "M5_RUN_ID": args.run_id,
        "M5_BACKEND_SHA": args.backend_sha,
        "M5_FLUTTER_SHA": args.flutter_sha,
        "M5_APK_SHA": args.apk_sha,
        "M5_MYSQL_CONTAINER": args.mysql_container,
        "M5_BACKEND_REPO": args.backend_repo,
        "M5_FLUTTER_REPO": args.flutter_repo,
        "M5_APK_PATH": args.apk_path,
    }
    for name, value in overrides.items():
        if value is not None:
            environment[name] = value
    config: EvidenceConfig | None = None
    try:
        config = read_config(environment)
        return serve_evidence(config)
    except BaseException as error:  # Do not leak diagnostics to stdout/stderr.
        category = _classify_exception(error)
        failure = _failure_payload(category, config.binding if config else None)
        print(json.dumps(failure, separators=(",", ":")))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
