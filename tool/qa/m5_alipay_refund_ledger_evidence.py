#!/usr/bin/env python3
"""Read-only ledger evidence for the M5 Alipay Finance refund lane.

The helper is deliberately separate from the provider-facing acceptance
runner.  It reads only aggregate counts from the serving MySQL container and
never selects an order number, refund id, actor id, amount, provider id, or
ledger value.  Identifiers are supplied to the container over stdin and are
never put in the Docker command line.  State contains only a SHA-256 order
reference and the baseline count, so the resulting evidence can be persisted
as an artifact without exposing protected inputs.

The supported protocol is a local ``start`` -> ``collect`` pair.  ``start``
must happen before the customer applies for a refund.  ``collect`` is called
after the Finance executor has reached ``COMPLETED``/``REFUNDED`` and proves
the single reserve debit, absence of a reserve-release credit, one balanced
two-posting reserve journal, and one refund application tied to the selected
order.  A missing container, schema, malformed marker, or stale state fails
closed.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import tempfile
import time
from dataclasses import dataclass
from typing import Mapping, Sequence


SCHEMA_VERSION = "m5-alipay-refund-ledger-v1"
EXPECTED_DEVELOPMENT_MYSQL_CONTAINER = "voice-social-m3-development-mysql-1"
ORDER_REF_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:-]{0,79}$")
REFUND_ID_RE = re.compile(
    r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-"
    r"[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$"
)
RUN_ID_RE = re.compile(r"^m5-refund-[A-Za-z0-9_.:-]{1,80}$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")


class LedgerEvidenceError(RuntimeError):
    """A safe category; the original database/command error is discarded."""

    def __init__(self, category: str):
        super().__init__(category)
        self.category = category


ALLOWED_CATEGORIES = frozenset(
    {"CONFIGURATION", "DB_UNAVAILABLE", "SCHEMA_MISSING", "INVALID_MARKER", "STATE"}
)


@dataclass(frozen=True)
class LedgerConfig:
    container: str
    docker_bin: str
    docker_env: Mapping[str, str]
    state_dir: str
    run_id: str


@dataclass(frozen=True)
class LedgerSnapshot:
    # The first thirteen fields are kept stable for callers that used the
    # original helper draft.  The collect marker now carries the additional
    # aggregate-only checks below them.
    order_rows: int
    eligible_order_rows: int
    refund_rows: int
    completed_rows: int
    refunded_rows: int
    order_match_rows: int
    alipay_refund_rows: int
    reserve_debit_count: int
    reserve_release_credit_count: int
    reserve_journal_count: int
    reserve_posting_count: int
    reserve_unbalanced_count: int
    operation_idempotency_rows: int
    order_succeeded_rows: int = 0
    order_alipay_rows: int = 0
    order_provider_order_rows: int = 0
    order_currency_rows: int = 0
    refund_provider_order_match_count: int = 0
    refund_amount_match_count: int = 0
    refund_out_request_match_count: int = 0
    reviewed_actor_count: int = 0
    executed_actor_count: int = 0
    distinct_finance_actor_count: int = 0
    reviewer_not_owner_count: int = 0
    executor_not_owner_count: int = 0
    reserve_amount_match_count: int = 0
    execute_idempotency_rows: int = 0
    reconcile_idempotency_rows: int = 0
    execute_fingerprint_count: int = 0
    reconcile_fingerprint_count: int = 0


def _sha256(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def _private_state_dir(path_value: str) -> str:
    if not path_value or "\x00" in path_value:
        raise LedgerEvidenceError("CONFIGURATION")
    path = Path(path_value)
    if not path.is_absolute() or path != Path(os.path.normpath(path_value)):
        raise LedgerEvidenceError("CONFIGURATION")
    try:
        if path.resolve(strict=False) != path:
            raise LedgerEvidenceError("CONFIGURATION")
        metadata = path.lstat()
    except OSError as exc:
        raise LedgerEvidenceError("CONFIGURATION") from exc
    if not metadata or not path.is_dir() or path.is_symlink():
        raise LedgerEvidenceError("CONFIGURATION")
    mode = metadata.st_mode & 0o777
    if mode & 0o077:
        raise LedgerEvidenceError("CONFIGURATION")
    return str(path)


def _development_mysql_container(value: str) -> str:
    if value != EXPECTED_DEVELOPMENT_MYSQL_CONTAINER:
        raise LedgerEvidenceError("CONFIGURATION")
    return value


def read_config(environment: Mapping[str, str] | None = None) -> LedgerConfig:
    env = os.environ if environment is None else environment
    container = _development_mysql_container(
        env.get("QA_M5_REFUND_MYSQL_CONTAINER", "")
    )
    state_dir = _private_state_dir(env.get("QA_M5_REFUND_LEDGER_STATE_DIR", ""))
    run_id = env.get("QA_M5_REFUND_RUN_ID", "")
    if not RUN_ID_RE.fullmatch(run_id):
        raise LedgerEvidenceError("CONFIGURATION")
    docker_bin = shutil.which("docker")
    if not docker_bin:
        raise LedgerEvidenceError("CONFIGURATION")
    docker_socket = env.get("QA_M5_REFUND_DOCKER_SOCKET", "")
    if not docker_socket.startswith("unix://"):
        raise LedgerEvidenceError("CONFIGURATION")
    socket_path = docker_socket.removeprefix("unix://")
    if not socket_path or not os.path.isabs(socket_path) or os.path.normpath(socket_path) != socket_path:
        raise LedgerEvidenceError("CONFIGURATION")
    try:
        socket_metadata = os.lstat(socket_path)
    except OSError:
        raise LedgerEvidenceError("CONFIGURATION") from None
    if not stat.S_ISSOCK(socket_metadata.st_mode):
        raise LedgerEvidenceError("CONFIGURATION")
    docker_env = {"PATH": env.get("PATH", "/usr/bin:/bin")}
    docker_env["DOCKER_HOST"] = docker_socket
    return LedgerConfig(container, docker_bin, docker_env, state_dir, run_id)


# This script is static and contains no operator input.  Both protected
# identifiers are read from stdin before interpolation into a validated SQL
# string.  The SQL itself is then piped to mysql's stdin, so neither the
# identifiers nor the query containing them appear in argv.  Every selected
# value is an aggregate count/boolean predicate; no row value crosses the
# container boundary.
MYSQL_LEDGER_SCRIPT = r"""
set -eu
database="${MYSQL_DATABASE:-}"
database_user="${MYSQL_USER:-${MYSQL_APP_USER:-root}}"
database_secret="${MYSQL_PASSWORD:-${MYSQL_APP_PASSWORD:-${MYSQL_ROOT_PASSWORD:-}}}"
[ -n "$database" ] && [ -n "$database_secret" ] || exit 20
phase="${M5_REFUND_PHASE:-}"
case "$phase" in
  start)
    IFS= read -r order_ref || exit 21
    ;;
  collect)
    IFS= read -r order_ref || exit 21
    IFS= read -r refund_ref || exit 22
    ;;
  *) exit 23 ;;
esac
case "$order_ref" in
  ""|*[!A-Za-z0-9._:-]*) exit 24 ;;
  *) ;;
esac
if [ "$phase" = "collect" ]; then
  case "$refund_ref" in
    ????????-????-[1-5]???-[89abAB]???-????????????)
      case "$refund_ref" in *[!A-Za-z0-9-]*) exit 25 ;; esac
      ;;
    *) exit 26 ;;
  esac
fi

mysql_query() {
  MYSQL_PWD="$database_secret" mysql \
    --protocol=socket --connect-timeout=5 \
    --user="$database_user" --database="$database" \
    --batch --skip-column-names --raw
}

# Schema checks are emitted as a fixed enum before the numeric marker.  This
# distinguishes a missing migration from an unavailable database without
# echoing the vendor/database diagnostic.
schema_sql="SELECT CASE WHEN
  (SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE()
    AND table_name IN ('recharge_order', 'refund_application', 'wallet',
      'wallet_transaction', 'ledger_journal', 'ledger_posting',
      'operation_idempotency')) = 7
  AND (SELECT COUNT(*) FROM information_schema.columns WHERE table_schema = DATABASE()
    AND table_name = 'recharge_order' AND column_name IN
      ('order_no', 'status', 'payment_provider', 'provider_order_id',
       'currency_code', 'amount_minor')) = 6
  AND (SELECT COUNT(*) FROM information_schema.columns WHERE table_schema = DATABASE()
    AND table_name = 'refund_application' AND column_name IN
      ('public_id', 'recharge_order_id', 'user_id', 'amount_minor', 'status',
       'provider', 'provider_order_id', 'provider_refund_id', 'provider_status',
       'reviewed_by_user_id', 'executed_by_user_id')) = 11
  AND (SELECT COUNT(*) FROM information_schema.columns WHERE table_schema = DATABASE()
    AND table_name = 'wallet_transaction' AND column_name IN
      ('wallet_id', 'public_id', 'transaction_type', 'amount_minor',
       'business_type', 'business_id')) = 6
  AND (SELECT COUNT(*) FROM information_schema.columns WHERE table_schema = DATABASE()
    AND table_name = 'wallet' AND column_name IN
      ('id', 'user_id', 'currency_code')) = 3
  AND (SELECT COUNT(*) FROM information_schema.columns WHERE table_schema = DATABASE()
    AND table_name = 'ledger_journal' AND column_name IN
      ('id', 'actor_user_id', 'business_type', 'business_id')) = 4
  AND (SELECT COUNT(*) FROM information_schema.columns WHERE table_schema = DATABASE()
    AND table_name = 'ledger_posting' AND column_name IN
      ('journal_id', 'currency_code', 'amount_minor')) = 3
  AND (SELECT COUNT(*) FROM information_schema.columns WHERE table_schema = DATABASE()
    AND table_name = 'operation_idempotency' AND column_name IN
      ('operation_scope', 'request_fingerprint', 'status', 'response_json')) = 4
  THEN 'SCHEMA_OK' ELSE 'SCHEMA_MISSING' END"

if [ "$phase" = "start" ]; then
  sql="SELECT
    COUNT(*) AS order_rows,
    COALESCE(SUM(status = 'SUCCEEDED' AND payment_provider = 'alipay-sandbox'
      AND provider_order_id IS NOT NULL AND provider_order_id <> ''
      AND currency_code = 'CNY'), 0) AS eligible_order_rows,
    COALESCE(SUM((SELECT COUNT(*) FROM refund_application r
      WHERE r.recharge_order_id = o.id)), 0) AS refund_rows
    FROM recharge_order o WHERE o.order_no = '$order_ref'"
else
  sql="SELECT
    COUNT(*) AS refund_rows,
    COALESCE(SUM(r.status = 'COMPLETED'), 0) AS completed_rows,
    COALESCE(SUM(r.provider_status = 'REFUNDED'), 0) AS refunded_rows,
    COALESCE(SUM(o.order_no = '$order_ref'), 0) AS order_match_rows,
    COALESCE(SUM(r.provider = 'alipay-sandbox'), 0) AS alipay_refund_rows,
    COALESCE((SELECT COUNT(*) FROM wallet_transaction wt
      JOIN wallet w ON w.id = wt.wallet_id
      JOIN refund_application rr ON rr.user_id = w.user_id
      WHERE rr.public_id = '$refund_ref'
        AND rr.recharge_order_id = o.id
        AND w.currency_code = 'GIFT_COIN'
        AND wt.transaction_type = 'DEBIT'
        AND wt.business_type = 'REFUND_RESERVE'
        AND wt.business_id = '$refund_ref'), 0) AS reserve_debit_count,
    COALESCE((SELECT COUNT(*) FROM wallet_transaction wt
      JOIN wallet w ON w.id = wt.wallet_id
      JOIN refund_application rr ON rr.user_id = w.user_id
      WHERE rr.public_id = '$refund_ref'
        AND rr.recharge_order_id = o.id
        AND w.currency_code = 'GIFT_COIN'
        AND wt.transaction_type = 'CREDIT'
        AND wt.business_type = 'REFUND_RESERVE_RELEASE'
        AND wt.business_id = '$refund_ref'), 0) AS reserve_release_credit_count,
    COALESCE((SELECT COUNT(*) FROM ledger_journal j
      WHERE j.business_type = 'REFUND_RESERVE' AND j.business_id = '$refund_ref'), 0) AS reserve_journal_count,
    COALESCE((SELECT COUNT(*) FROM ledger_posting p
      JOIN ledger_journal j ON j.id = p.journal_id
      WHERE j.business_type = 'REFUND_RESERVE' AND j.business_id = '$refund_ref'), 0) AS reserve_posting_count,
    COALESCE((SELECT COUNT(*) FROM (
      SELECT p.journal_id, p.currency_code
      FROM ledger_posting p JOIN ledger_journal j ON j.id = p.journal_id
      WHERE j.business_type = 'REFUND_RESERVE' AND j.business_id = '$refund_ref'
      GROUP BY p.journal_id, p.currency_code
      HAVING SUM(p.amount_minor) <> 0
    ) unbalanced), 0) AS reserve_unbalanced_count,
    COALESCE((SELECT COUNT(*) FROM operation_idempotency oi
      WHERE oi.operation_scope = 'OPS_PAYMENT_REFUND_EXECUTE'
        AND oi.status = 'COMPLETED'
        AND oi.actor_user_id = r.executed_by_user_id
        AND oi.request_fingerprint = LOWER(SHA2(CONCAT(
          'java.lang.String:', r.public_id, '|java.lang.Boolean:false|'), 256))
        AND JSON_UNQUOTE(JSON_EXTRACT(oi.response_json, '$.refundId')) = r.public_id), 0)
      + COALESCE((SELECT COUNT(*) FROM operation_idempotency oi
      WHERE oi.operation_scope = 'OPS_PAYMENT_REFUND_RECONCILE'
        AND oi.status = 'COMPLETED'
        AND oi.actor_user_id = r.executed_by_user_id
        AND oi.request_fingerprint = LOWER(SHA2(CONCAT(
          'java.lang.String:', r.public_id, '|java.lang.Boolean:true|'), 256))
        AND JSON_UNQUOTE(JSON_EXTRACT(oi.response_json, '$.refundId')) = r.public_id), 0)
      AS operation_idempotency_rows,
    COALESCE(SUM(o.status = 'SUCCEEDED'), 0) AS order_succeeded_rows,
    COALESCE(SUM(o.status = 'SUCCEEDED' AND o.payment_provider = 'alipay-sandbox'), 0)
      AS order_alipay_rows,
    COALESCE(SUM(o.status = 'SUCCEEDED' AND o.payment_provider = 'alipay-sandbox'
      AND o.provider_order_id IS NOT NULL AND o.provider_order_id <> ''), 0)
      AS order_provider_order_rows,
    COALESCE(SUM(o.status = 'SUCCEEDED' AND o.payment_provider = 'alipay-sandbox'
      AND o.currency_code = 'CNY'), 0) AS order_currency_rows,
    COALESCE(SUM(r.provider = 'alipay-sandbox'
      AND r.provider_order_id = o.provider_order_id
      AND r.provider_order_id IS NOT NULL AND r.provider_order_id <> ''), 0)
      AS refund_provider_order_match_count,
    COALESCE(SUM(r.amount_minor = o.amount_minor), 0) AS refund_amount_match_count,
    COALESCE(SUM(r.provider_refund_id = r.public_id
      AND r.provider_refund_id IS NOT NULL AND r.provider_refund_id <> ''), 0)
      AS refund_out_request_match_count,
    COALESCE(SUM(r.reviewed_by_user_id IS NOT NULL), 0) AS reviewed_actor_count,
    COALESCE(SUM(r.executed_by_user_id IS NOT NULL), 0) AS executed_actor_count,
    COALESCE(SUM(r.reviewed_by_user_id IS NOT NULL
      AND r.executed_by_user_id IS NOT NULL
      AND r.reviewed_by_user_id <> r.executed_by_user_id), 0)
      AS distinct_finance_actor_count,
    COALESCE(SUM(r.reviewed_by_user_id IS NOT NULL
      AND r.reviewed_by_user_id <> r.user_id), 0) AS reviewer_not_owner_count,
    COALESCE(SUM(r.executed_by_user_id IS NOT NULL
      AND r.executed_by_user_id <> r.user_id), 0) AS executor_not_owner_count,
    COALESCE((SELECT COUNT(*) FROM wallet_transaction wt
      JOIN wallet w ON w.id = wt.wallet_id
      JOIN refund_application rr ON rr.user_id = w.user_id
      WHERE rr.public_id = '$refund_ref'
        AND rr.recharge_order_id = o.id
        AND w.currency_code = 'GIFT_COIN'
        AND wt.transaction_type = 'DEBIT'
        AND wt.business_type = 'REFUND_RESERVE'
        AND wt.business_id = '$refund_ref'
        AND wt.amount_minor = o.gift_coin_amount), 0) AS reserve_amount_match_count,
    COALESCE((SELECT COUNT(*) FROM operation_idempotency oi
      WHERE oi.operation_scope = 'OPS_PAYMENT_REFUND_EXECUTE'
        AND oi.status = 'COMPLETED'
        AND oi.actor_user_id = r.executed_by_user_id
        AND oi.request_fingerprint = LOWER(SHA2(CONCAT(
          'java.lang.String:', r.public_id, '|java.lang.Boolean:false|'), 256))
        AND JSON_UNQUOTE(JSON_EXTRACT(oi.response_json, '$.refundId')) = r.public_id), 0)
      AS execute_idempotency_rows,
    COALESCE((SELECT COUNT(*) FROM operation_idempotency oi
      WHERE oi.operation_scope = 'OPS_PAYMENT_REFUND_RECONCILE'
        AND oi.status = 'COMPLETED'
        AND oi.actor_user_id = r.executed_by_user_id
        AND oi.request_fingerprint = LOWER(SHA2(CONCAT(
          'java.lang.String:', r.public_id, '|java.lang.Boolean:true|'), 256))
        AND JSON_UNQUOTE(JSON_EXTRACT(oi.response_json, '$.refundId')) = r.public_id), 0)
      AS reconcile_idempotency_rows,
    COALESCE((SELECT COUNT(*) FROM operation_idempotency oi
      WHERE oi.operation_scope = 'OPS_PAYMENT_REFUND_EXECUTE'
        AND oi.actor_user_id = r.executed_by_user_id
        AND oi.request_fingerprint = LOWER(SHA2(CONCAT(
          'java.lang.String:', r.public_id, '|java.lang.Boolean:false|'), 256))
        AND JSON_UNQUOTE(JSON_EXTRACT(oi.response_json, '$.refundId')) = r.public_id), 0)
      AS execute_fingerprint_count,
    COALESCE((SELECT COUNT(*) FROM operation_idempotency oi
      WHERE oi.operation_scope = 'OPS_PAYMENT_REFUND_RECONCILE'
        AND oi.actor_user_id = r.executed_by_user_id
        AND oi.request_fingerprint = LOWER(SHA2(CONCAT(
          'java.lang.String:', r.public_id, '|java.lang.Boolean:true|'), 256))
        AND JSON_UNQUOTE(JSON_EXTRACT(oi.response_json, '$.refundId')) = r.public_id), 0)
      AS reconcile_fingerprint_count
    FROM refund_application r
    JOIN recharge_order o ON o.id = r.recharge_order_id
    WHERE r.public_id = '$refund_ref'"
fi
printf '%s;\n%s;\n' "$schema_sql" "$sql" | mysql_query
unset database_secret MYSQL_PWD
"""


def _state_path(config: LedgerConfig) -> Path:
    return Path(config.state_dir) / ("m5-refund-" + _sha256(config.run_id)[:32] + ".json")


def _run_query(config: LedgerConfig, phase: str, order_ref: str, refund_ref: str | None) -> list[int]:
    if phase not in {"start", "collect"}:
        raise LedgerEvidenceError("CONFIGURATION")
    if not ORDER_REF_RE.fullmatch(order_ref):
        raise LedgerEvidenceError("CONFIGURATION")
    if phase == "collect" and (refund_ref is None or not REFUND_ID_RE.fullmatch(refund_ref)):
        raise LedgerEvidenceError("CONFIGURATION")
    input_value = order_ref + "\n" + ((refund_ref or "") + "\n" if phase == "collect" else "")
    script = "export M5_REFUND_PHASE=" + phase + "\n" + MYSQL_LEDGER_SCRIPT
    try:
        completed = subprocess.run(
            [config.docker_bin, "exec", "-i", config.container, "/bin/sh", "-c", script],
            cwd="/",
            env=dict(config.docker_env),
            input=input_value,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=90,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise LedgerEvidenceError("DB_UNAVAILABLE") from exc
    if completed.returncode != 0:
        raise LedgerEvidenceError("DB_UNAVAILABLE")
    lines = completed.stdout.splitlines()
    expected_marker_count = 3 if phase == "start" else 28
    if len(lines) != 2 or lines[0] not in {"SCHEMA_OK", "SCHEMA_MISSING"}:
        raise LedgerEvidenceError("INVALID_MARKER")
    if lines[0] != "SCHEMA_OK":
        raise LedgerEvidenceError("SCHEMA_MISSING")
    fields = lines[1].split("\t")
    expected = expected_marker_count
    if len(fields) != expected:
        raise LedgerEvidenceError("INVALID_MARKER")
    try:
        values = [int(field) for field in fields]
    except ValueError as exc:
        raise LedgerEvidenceError("INVALID_MARKER") from exc
    if any(value < 0 for value in values):
        raise LedgerEvidenceError("INVALID_MARKER")
    return values


def _write_state(path: Path, state: Mapping[str, object]) -> None:
    try:
        if not path.parent.is_dir() or path.parent.is_symlink():
            raise LedgerEvidenceError("STATE")
        parent_mode = path.parent.stat().st_mode & 0o777
    except OSError as exc:
        raise LedgerEvidenceError("STATE") from exc
    if parent_mode & 0o077:
        raise LedgerEvidenceError("STATE")
    if path.exists() or path.is_symlink():
        raise LedgerEvidenceError("STATE")
    temp_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", dir=path.parent, prefix=".m5-refund-state-", delete=False
        ) as temp:
            temp_path = Path(temp.name)
            os.chmod(temp_path, 0o600)
            json.dump(state, temp, sort_keys=True, separators=(",", ":"))
            temp.write("\n")
            temp.flush()
            os.fsync(temp.fileno())
        os.replace(temp_path, path)
    except OSError as exc:
        if temp_path is not None:
            try:
                temp_path.unlink(missing_ok=True)
            except OSError:
                pass
        raise LedgerEvidenceError("STATE") from exc


def _read_state(path: Path, expected_run_hash: str) -> dict[str, object]:
    if not path.is_file() or path.is_symlink():
        raise LedgerEvidenceError("STATE")
    try:
        mode = path.stat().st_mode & 0o777
        if mode & 0o077:
            raise LedgerEvidenceError("STATE")
        with path.open("r", encoding="utf-8") as stream:
            value = json.load(stream)
    except (OSError, ValueError, TypeError) as exc:
        raise LedgerEvidenceError("STATE") from exc
    if not isinstance(value, dict) or value.get("schemaVersion") != SCHEMA_VERSION:
        raise LedgerEvidenceError("STATE")
    if value.get("runIdHash") != expected_run_hash:
        raise LedgerEvidenceError("STATE")
    if value.get("consumed") is not False:
        raise LedgerEvidenceError("STATE")
    if not isinstance(value.get("orderRefSha256"), str) or not SHA256_RE.fullmatch(value["orderRefSha256"]):
        raise LedgerEvidenceError("STATE")
    baseline = value.get("baseline")
    if not isinstance(baseline, dict) or set(baseline) != {"orderRows", "eligibleOrderRows", "refundRows"}:
        raise LedgerEvidenceError("STATE")
    if any(type(baseline[key]) is not int or baseline[key] < 0 for key in baseline):
        raise LedgerEvidenceError("STATE")
    return value


def start(config: LedgerConfig, order_ref: str) -> None:
    values = _run_query(config, "start", order_ref, None)
    if values[0] != 1 or values[1] != 1 or values[2] != 0:
        raise LedgerEvidenceError("STATE")
    path = _state_path(config)
    _write_state(
        path,
        {
            "schemaVersion": SCHEMA_VERSION,
            "runIdHash": _sha256(config.run_id),
            "orderRefSha256": _sha256(order_ref),
            "baseline": {
                "orderRows": values[0],
                "eligibleOrderRows": values[1],
                "refundRows": values[2],
            },
            "startedAtEpoch": int(time.time()),
            "consumed": False,
        },
    )


def collect(config: LedgerConfig, order_ref: str, refund_ref: str) -> dict[str, object]:
    path = _state_path(config)
    state = _read_state(path, _sha256(config.run_id))
    if state["orderRefSha256"] != _sha256(order_ref):
        raise LedgerEvidenceError("STATE")
    values = _run_query(config, "collect", order_ref, refund_ref)
    # The start marker is a three-column order baseline.  The collect marker
    # has an explicit, stable aggregate-only order below; construct by name so
    # an added evidence column can never silently shift a safety check.
    snapshot = LedgerSnapshot(
        order_rows=values[0],
        eligible_order_rows=0,
        refund_rows=values[0],
        completed_rows=values[1],
        refunded_rows=values[2],
        order_match_rows=values[3],
        alipay_refund_rows=values[4],
        reserve_debit_count=values[5],
        reserve_release_credit_count=values[6],
        reserve_journal_count=values[7],
        reserve_posting_count=values[8],
        reserve_unbalanced_count=values[9],
        operation_idempotency_rows=values[10],
        order_succeeded_rows=values[11],
        order_alipay_rows=values[12],
        order_provider_order_rows=values[13],
        order_currency_rows=values[14],
        refund_provider_order_match_count=values[15],
        refund_amount_match_count=values[16],
        refund_out_request_match_count=values[17],
        reviewed_actor_count=values[18],
        executed_actor_count=values[19],
        distinct_finance_actor_count=values[20],
        reviewer_not_owner_count=values[21],
        executor_not_owner_count=values[22],
        reserve_amount_match_count=values[23],
        execute_idempotency_rows=values[24],
        reconcile_idempotency_rows=values[25],
        execute_fingerprint_count=values[26],
        reconcile_fingerprint_count=values[27],
    )
    baseline = state["baseline"]
    assert isinstance(baseline, dict)
    if snapshot.refund_rows != int(baseline["refundRows"]) + 1:
        raise LedgerEvidenceError("STATE")
    if not (
        snapshot.refund_rows == 1
        and snapshot.completed_rows == 1
        and snapshot.refunded_rows == 1
        and snapshot.order_match_rows == 1
        and snapshot.alipay_refund_rows == 1
        and snapshot.reserve_debit_count == 1
        and snapshot.reserve_release_credit_count == 0
        and snapshot.reserve_journal_count == 1
        and snapshot.reserve_posting_count == 2
        and snapshot.reserve_unbalanced_count == 0
        and snapshot.order_succeeded_rows == 1
        and snapshot.order_alipay_rows == 1
        and snapshot.order_provider_order_rows == 1
        and snapshot.order_currency_rows == 1
        and snapshot.refund_provider_order_match_count == 1
        and snapshot.refund_amount_match_count == 1
        and snapshot.refund_out_request_match_count == 1
        and snapshot.reviewed_actor_count == 1
        and snapshot.executed_actor_count == 1
        and snapshot.distinct_finance_actor_count == 1
        and snapshot.reviewer_not_owner_count == 1
        and snapshot.executor_not_owner_count == 1
        and snapshot.reserve_amount_match_count == 1
        and snapshot.execute_idempotency_rows >= 1
        and snapshot.execute_fingerprint_count >= 1
        and snapshot.reconcile_idempotency_rows >= 0
        and snapshot.reconcile_fingerprint_count >= 0
    ):
        raise LedgerEvidenceError("STATE")
    if (
        snapshot.reconcile_idempotency_rows != snapshot.reconcile_fingerprint_count
        or snapshot.execute_idempotency_rows != snapshot.execute_fingerprint_count
    ):
        raise LedgerEvidenceError("STATE")
    _write_consumed(path, state)
    return {
        "reserveDebitCount": snapshot.reserve_debit_count,
        "reserveReleaseCreditCount": snapshot.reserve_release_credit_count,
        "reserveJournalCount": snapshot.reserve_journal_count,
        "reservePostingCount": snapshot.reserve_posting_count,
        "reserveUnbalancedCount": snapshot.reserve_unbalanced_count,
        "operationIdempotencyRows": snapshot.operation_idempotency_rows,
        "executeIdempotencyRows": snapshot.execute_idempotency_rows,
        "reconcileIdempotencyRows": snapshot.reconcile_idempotency_rows,
        "executeFingerprintCount": snapshot.execute_fingerprint_count,
        "reconcileFingerprintCount": snapshot.reconcile_fingerprint_count,
        "reviewedActorCount": snapshot.reviewed_actor_count,
        "executedActorCount": snapshot.executed_actor_count,
        "distinctFinanceActorCount": snapshot.distinct_finance_actor_count,
        "ownerDistinctReviewerCount": snapshot.reviewer_not_owner_count,
        "ownerDistinctExecutorCount": snapshot.executor_not_owner_count,
        "outRequestMatchCount": snapshot.refund_out_request_match_count,
        "reserveAmountMatchCount": snapshot.reserve_amount_match_count,
        "refundProviderOrderMatchCount": snapshot.refund_provider_order_match_count,
        "refundAmountMatchCount": snapshot.refund_amount_match_count,
        "balancedReserveJournalCount": 1,
        "ledgerImbalanceCount": snapshot.reserve_unbalanced_count,
    }


def _write_consumed(path: Path, state: Mapping[str, object]) -> None:
    updated = dict(state)
    updated["consumed"] = True
    # The state is deliberately retained as a consumed marker.  It prevents
    # replay while avoiding deletion races and keeps post-run auditability.
    try:
        if not path.parent.is_dir() or path.parent.is_symlink():
            raise LedgerEvidenceError("STATE")
        parent_mode = path.parent.stat().st_mode & 0o777
    except OSError as exc:
        raise LedgerEvidenceError("STATE") from exc
    if parent_mode & 0o077:
        raise LedgerEvidenceError("STATE")
    temp_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", dir=path.parent, prefix=".m5-refund-state-", delete=False
        ) as temp:
            temp_path = Path(temp.name)
            os.chmod(temp_path, 0o600)
            json.dump(updated, temp, sort_keys=True, separators=(",", ":"))
            temp.write("\n")
            temp.flush()
            os.fsync(temp.fileno())
        os.replace(temp_path, path)
    except OSError as exc:
        if temp_path is not None:
            try:
                temp_path.unlink(missing_ok=True)
            except OSError:
                pass
        raise LedgerEvidenceError("STATE") from exc


def _public_self_test() -> int:
    if "MYSQL_PWD=" not in MYSQL_LEDGER_SCRIPT or "MYSQL_ROOT_PASSWORD" not in MYSQL_LEDGER_SCRIPT:
        raise AssertionError("credential handling changed")
    for forbidden in (
        "SELECT r.public_id",
        "SELECT o.order_no",
        "SELECT r.provider_refund_id",
        "SELECT r.amount_minor",
        "SELECT oi.request_fingerprint",
    ):
        if forbidden in MYSQL_LEDGER_SCRIPT:
            raise AssertionError("raw identifier projection added")
    for required in (
        "execute_idempotency_rows",
        "reconcile_idempotency_rows",
        "request_fingerprint = LOWER(SHA2",
        "JSON_UNQUOTE(JSON_EXTRACT(oi.response_json, '$.refundId')) = r.public_id",
    ):
        if required not in MYSQL_LEDGER_SCRIPT:
            raise AssertionError("strict operation evidence missing")
    if "--execute" in MYSQL_LEDGER_SCRIPT:
        raise AssertionError("query must travel via mysql stdin")
    if "docker exec -i" not in inspect_command_source():
        raise AssertionError("stdin docker contract missing")
    print("self-test=PASS")
    return 0


def inspect_command_source() -> str:
    return "docker exec -i container /bin/sh -c script"


def _parser() -> argparse.ArgumentParser:
    class _SafeArgumentParser(argparse.ArgumentParser):
        def error(self, _message: str) -> None:
            raise LedgerEvidenceError("CONFIGURATION")

    parser = _SafeArgumentParser(
        description="Read-only M5 Alipay refund ledger evidence"
    )
    modes = parser.add_mutually_exclusive_group(required=True)
    modes.add_argument("--self-test", action="store_true")
    modes.add_argument("--start", action="store_true")
    modes.add_argument("--collect", action="store_true")
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    try:
        args = _parser().parse_args(list(argv) if argv is not None else None)
    except SystemExit as error:
        return int(error.code)
    except LedgerEvidenceError as error:
        print(
            json.dumps(
                {
                    "status": "FAIL",
                    "schemaVersion": SCHEMA_VERSION,
                    "category": error.category,
                },
                separators=(",", ":"),
            )
        )
        return 2
    if args.self_test:
        try:
            return _public_self_test()
        except AssertionError:
            return 1
    try:
        config = read_config()
        order_ref = os.environ.get("QA_M5_REFUND_ORDER_NO", "")
        if args.start:
            start(config, order_ref)
            print(json.dumps({"status": "STARTED", "schemaVersion": SCHEMA_VERSION}, separators=(",", ":")))
            return 0
        refund_ref = os.environ.get("QA_M5_REFUND_ID", "")
        result = collect(config, order_ref, refund_ref)
        result.update({"status": "PASS", "schemaVersion": SCHEMA_VERSION})
        print(json.dumps(result, sort_keys=True, separators=(",", ":")))
        return 0
    except LedgerEvidenceError as exc:
        print(json.dumps({"status": "FAIL", "schemaVersion": SCHEMA_VERSION, "category": exc.category}, separators=(",", ":")))
        return 2
    except Exception:
        # Never echo an unexpected driver/filesystem traceback into a QA log.
        print(json.dumps({"status": "FAIL", "schemaVersion": SCHEMA_VERSION, "category": "STATE"}, separators=(",", ":")))
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
