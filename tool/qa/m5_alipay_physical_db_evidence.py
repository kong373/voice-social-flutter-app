#!/usr/bin/env python3
"""Read-only two-phase DB evidence for the physical Alipay cancel lane.

The physical diagnostic invokes this file as a private hook twice.  ``start``
captures one MySQL ``UTC_TIMESTAMP(6)`` and the ``MAX(id)`` for each table
needed by the lane.  ``collect`` takes stable before/after snapshots and only
returns aggregate markers: one new ``alipay-sandbox`` order in the database
``CANCELLED`` state with a known safe provider status, and no rows added to
the four financial tables.

The database password is expanded inside the selected MySQL container.  The
host process never receives it, never places it in an argument, and never
prints database output.  The final object is deliberately shaped exactly for
``m5_alipay_physical_zero_mutation_validator.py``; database identifiers and
order numbers never cross into that object.
"""

from __future__ import annotations

import argparse
import dataclasses
from datetime import datetime
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
from typing import Callable, Mapping, Sequence


SCHEMA = "alipay-physical-cancel-v1"
PHYSICAL_EVIDENCE_SCHEMA = SCHEMA
TABLES = (
    "recharge_order",
    "payment_provider_event",
    "wallet_transaction",
    "ledger_journal",
    "ledger_posting",
)
FINANCIAL_TABLES = TABLES[1:]
COUNTER_KEYS = (
    "payment_provider_events",
    "wallet_transactions",
    "ledger_journals",
    "ledger_entries",
)
SAFE_PROVIDER_STATUSES = frozenset({"TRADE_CLOSED", "TRADE_NOT_EXIST"})
MYSQL_CONTAINER_ENV_NAMES = (
    "QA_ALIPAY_PHYSICAL_MYSQL_CONTAINER",
    "QA_M5_MYSQL_CONTAINER",
    "M5_MYSQL_CONTAINER",
    "M5_DB_EVIDENCE_MYSQL_CONTAINER",
    "QA_MYSQL_CONTAINER",
    "MYSQL_CONTAINER",
)
DOCKER_BIN_ENV_NAMES = (
    "QA_ALIPAY_PHYSICAL_DOCKER_BIN",
    "QA_DOCKER_BIN",
)
DOCKER_SOCKET_ENV_NAMES = ("QA_DOCKER_SOCKET", "M5_DOCKER_SOCKET", "DOCKER_HOST")
RUN_ID_RE = re.compile(r"^[A-Za-z0-9_.:-]{1,96}$")
SERIAL_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$")
SHA1_RE = re.compile(r"^[0-9a-fA-F]{40}$")
CREATE_REQUEST_ID_RE = re.compile(r"^qa-alipay-[a-f0-9]{32}$")
EPOCH_RE = re.compile(r"^[1-9][0-9]{0,11}$")
CONTAINER_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$")
DB_TIMESTAMP_RE = re.compile(
    r"^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{6}$"
)
MAX_UNSIGNED_BIGINT = (1 << 64) - 1
MAX_MARKER_BYTES = 16 * 1024


class CollectorError(RuntimeError):
    """A fixed safe category; underlying DB/OS details are never emitted."""

    CATEGORIES = frozenset(
        {
            "CONFIGURATION",
            "DB_UNAVAILABLE",
            "SCHEMA_MISSING",
            "INVALID_MARKER",
            "INVALID_BASELINE",
            "CONCURRENT_WRITE",
            "INVARIANT_VIOLATION",
            "STATE",
            "OUTPUT_WRITE",
        }
    )

    def __init__(self, category: str):
        normalized = category if category in self.CATEGORIES else "STATE"
        super().__init__(normalized)
        self.category = normalized


@dataclasses.dataclass(frozen=True, repr=False)
class Config:
    phase: str
    serial: str
    run_id: str
    run_started_at: int
    flutter_sha: str = dataclasses.field(repr=False)
    backend_sha: str = dataclasses.field(repr=False)
    create_request_id: str = dataclasses.field(repr=False)
    evidence_file: str = dataclasses.field(repr=False)
    state_dir: str = dataclasses.field(repr=False)
    baseline_file: str = dataclasses.field(repr=False)
    mysql_container: str = dataclasses.field(repr=False)
    docker_bin: str = dataclasses.field(repr=False)
    docker_env: Mapping[str, str] = dataclasses.field(repr=False)


@dataclasses.dataclass(frozen=True)
class DbSnapshot:
    utc_timestamp: str
    max_ids: Mapping[str, int]


@dataclasses.dataclass(frozen=True)
class DbMetrics:
    new_order_count: int
    alipay_order_count: int
    cancelled_order_count: int
    safe_provider_order_count: int
    unsafe_provider_order_count: int
    missing_provider_status_count: int
    payment_provider_events: int
    wallet_transactions: int
    ledger_journals: int
    ledger_postings: int


@dataclasses.dataclass(frozen=True)
class DbResult:
    start_snapshot: DbSnapshot | None = None
    before_snapshot: DbSnapshot | None = None
    metrics: DbMetrics | None = None
    middle_snapshot: DbSnapshot | None = None
    metrics_repeat: DbMetrics | None = None
    after_snapshot: DbSnapshot | None = None


@dataclasses.dataclass(frozen=True)
class _Baseline:
    utc_timestamp: str
    max_ids: Mapping[str, int]
    create_request_id_sha256: str
    consumed: bool


def _first_env(environment: Mapping[str, str], names: Sequence[str]) -> str:
    """Read one alias and reject conflicting values rather than guessing."""

    values = [environment[name] for name in names if environment.get(name) not in (None, "")]
    if not values:
        return ""
    if any(value != values[0] for value in values[1:]):
        raise CollectorError("CONFIGURATION")
    return values[0]


def _require_safe_path(value: str, *, must_exist: bool, directory: bool = False) -> Path:
    if not value or "\x00" in value:
        raise CollectorError("CONFIGURATION")
    path = Path(value)
    if not path.is_absolute() or Path(os.path.normpath(value)) != path:
        raise CollectorError("CONFIGURATION")
    if any(part in {"..", ""} for part in path.parts):
        raise CollectorError("CONFIGURATION")
    try:
        if path != path.resolve(strict=False):
            raise CollectorError("CONFIGURATION")
        metadata = path.lstat()
    except FileNotFoundError:
        if must_exist:
            raise CollectorError("CONFIGURATION") from None
        return path
    except OSError:
        raise CollectorError("CONFIGURATION") from None
    if stat.S_ISLNK(metadata.st_mode):
        raise CollectorError("CONFIGURATION")
    if directory and not stat.S_ISDIR(metadata.st_mode):
        raise CollectorError("CONFIGURATION")
    if not directory and stat.S_ISDIR(metadata.st_mode):
        raise CollectorError("CONFIGURATION")
    if must_exist and metadata.st_mode & 0o077:
        # State and evidence files are private even when the parent is private.
        raise CollectorError("CONFIGURATION")
    return path


def _require_private_directory(value: str) -> Path:
    path = _require_safe_path(value, must_exist=True, directory=True)
    try:
        metadata = path.lstat()
    except OSError:
        raise CollectorError("CONFIGURATION") from None
    if metadata.st_mode & 0o077:
        raise CollectorError("CONFIGURATION")
    return path


def _require_private_parent(path: Path) -> None:
    try:
        metadata = path.parent.lstat()
    except OSError:
        raise CollectorError("CONFIGURATION") from None
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
        raise CollectorError("CONFIGURATION")
    if metadata.st_mode & 0o077:
        raise CollectorError("CONFIGURATION")


def _resolve_docker(environment: Mapping[str, str]) -> tuple[str, dict[str, str]]:
    configured = _first_env(environment, DOCKER_BIN_ENV_NAMES)
    if configured:
        path = Path(configured)
        if not path.is_absolute() or not path.is_file() or path.is_symlink() or not os.access(path, os.X_OK):
            raise CollectorError("CONFIGURATION")
        docker_bin = str(path)
    else:
        docker_bin = shutil.which("docker") or ""
    if not docker_bin:
        raise CollectorError("CONFIGURATION")
    docker_env = {"PATH": environment.get("PATH", "/usr/bin:/bin")}
    socket = _first_env(environment, DOCKER_SOCKET_ENV_NAMES)
    if socket:
        if socket.startswith("unix://"):
            socket_path = socket.removeprefix("unix://")
        elif socket.startswith("/"):
            socket_path = socket
        else:
            raise CollectorError("CONFIGURATION")
        if not socket_path or not os.path.isabs(socket_path):
            raise CollectorError("CONFIGURATION")
        try:
            metadata = os.lstat(socket_path)
        except OSError:
            raise CollectorError("CONFIGURATION") from None
        if not stat.S_ISSOCK(metadata.st_mode):
            raise CollectorError("CONFIGURATION")
        docker_env["DOCKER_HOST"] = socket if socket.startswith("unix://") else "unix://" + socket
    return docker_bin, docker_env


def read_config(environment: Mapping[str, str] | None = None) -> Config:
    """Validate the runner's binding and all private file targets."""

    env = os.environ if environment is None else environment
    phase = _first_env(env, ("QA_ALIPAY_PHYSICAL_EVIDENCE_PHASE",))
    if phase not in {"start", "collect"}:
        raise CollectorError("CONFIGURATION")
    serial = _first_env(env, ("QA_ALIPAY_PHYSICAL_SERIAL", "QA_ALIPAY_SERIAL"))
    if not SERIAL_RE.fullmatch(serial or ""):
        raise CollectorError("CONFIGURATION")
    serial_lower = serial.lower()
    if "emulator" in serial_lower or "qemu" in serial_lower:
        raise CollectorError("CONFIGURATION")
    run_id = _first_env(env, ("QA_ALIPAY_PHYSICAL_RUN_ID",))
    if not RUN_ID_RE.fullmatch(run_id or ""):
        raise CollectorError("CONFIGURATION")
    run_started_at_value = _first_env(env, ("QA_ALIPAY_PHYSICAL_RUN_STARTED_AT",))
    if not EPOCH_RE.fullmatch(run_started_at_value or ""):
        raise CollectorError("CONFIGURATION")
    run_started_at = int(run_started_at_value)
    flutter_sha = _first_env(env, ("QA_ALIPAY_PHYSICAL_FLUTTER_SHA",)).lower()
    backend_sha = _first_env(env, ("QA_ALIPAY_PHYSICAL_BACKEND_SHA",)).lower()
    if not SHA1_RE.fullmatch(flutter_sha or "") or not SHA1_RE.fullmatch(backend_sha or ""):
        raise CollectorError("CONFIGURATION")
    create_request_id = _first_env(env, ("QA_ALIPAY_PHYSICAL_CREATE_REQUEST_ID",))
    if not CREATE_REQUEST_ID_RE.fullmatch(create_request_id or ""):
        raise CollectorError("CONFIGURATION")

    state_dir_value = _first_env(env, ("QA_ALIPAY_PHYSICAL_EVIDENCE_STATE_DIR",))
    state_dir = _require_private_directory(state_dir_value)
    baseline_value = _first_env(env, ("QA_ALIPAY_PHYSICAL_EVIDENCE_BASELINE_FILE",))
    baseline = _require_safe_path(
        baseline_value or str(state_dir / "baseline.json"),
        must_exist=phase == "collect",
    )
    if baseline.parent != state_dir:
        raise CollectorError("CONFIGURATION")
    if phase == "start" and (baseline.exists() or baseline.is_symlink()):
        raise CollectorError("CONFIGURATION")
    if phase == "collect":
        try:
            if baseline.stat().st_mode & 0o077:
                raise CollectorError("CONFIGURATION")
        except OSError:
            raise CollectorError("CONFIGURATION") from None

    evidence_value = _first_env(env, ("QA_ALIPAY_PHYSICAL_DB_EVIDENCE_FILE",))
    evidence_file = _require_safe_path(evidence_value, must_exist=False)
    _require_private_parent(evidence_file)
    if evidence_file == baseline:
        raise CollectorError("CONFIGURATION")
    if evidence_file.exists() or evidence_file.is_symlink():
        raise CollectorError("CONFIGURATION")

    mysql_container = _first_env(env, MYSQL_CONTAINER_ENV_NAMES)
    if not CONTAINER_RE.fullmatch(mysql_container or ""):
        raise CollectorError("CONFIGURATION")
    docker_bin, docker_env = _resolve_docker(env)
    return Config(
        phase=phase,
        serial=serial,
        run_id=run_id,
        run_started_at=run_started_at,
        flutter_sha=flutter_sha,
        backend_sha=backend_sha,
        create_request_id=create_request_id,
        evidence_file=str(evidence_file),
        state_dir=str(state_dir),
        baseline_file=str(baseline),
        mysql_container=mysql_container,
        docker_bin=docker_bin,
        docker_env=docker_env,
    )


# This is a fixed script.  It expands the database credentials only inside
# the selected container and emits aggregate markers rather than row values.
# The host sends the start snapshot plus the request id to the script over
# stdin in collect so the exact current-run binding never enters a command line.
MYSQL_PHYSICAL_EVIDENCE_SCRIPT = r"""
set -eu
database="${MYSQL_DATABASE:-}"
database_user="${MYSQL_USER:-${MYSQL_APP_USER:-root}}"
database_secret="${MYSQL_PASSWORD:-${MYSQL_APP_PASSWORD:-${MYSQL_ROOT_PASSWORD:-}}}"
[ -n "$database" ] && [ -n "$database_secret" ] || exit 20
phase="${M5_ALIPAY_PHYSICAL_PHASE:-}"
[ "$phase" = start ] || [ "$phase" = collect ] || exit 21

mysql_query() {
  MYSQL_PWD="$database_secret" mysql \
    --protocol=socket --connect-timeout=5 \
    --user="$database_user" --database="$database" \
    --batch --skip-column-names --raw --execute="SET SESSION TRANSACTION READ ONLY; $1"
}

table_exists() {
  value="$(mysql_query "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = '$1'")"
  [ "$value" = 1 ]
}

column_exists() {
  value="$(mysql_query "SELECT COUNT(*) FROM information_schema.columns WHERE table_schema = DATABASE() AND table_name = '$1' AND column_name = '$2'")"
  [ "$value" = 1 ]
}

# Presence checks are deliberately explicit so a partially applied migration
# cannot be reported as a safe cancel.
for table in recharge_order payment_provider_event wallet_transaction ledger_journal ledger_posting; do
  table_exists "$table" || { printf '%s\n' SCHEMA_MISSING; exit 0; }
  column_exists "$table" id || { printf '%s\n' SCHEMA_MISSING; exit 0; }
done
for column in payment_provider status provider_status; do
  column_exists recharge_order "$column" || { printf '%s\n' SCHEMA_MISSING; exit 0; }
done
for column in created_at idempotency_key; do
  column_exists recharge_order "$column" || { printf '%s\n' SCHEMA_MISSING; exit 0; }
done
printf '%s\n' SCHEMA_OK

# mysql --batch separates columns with tabs.  Emit one explicitly delimited
# scalar so the host-side strict marker parser sees the same wire format in a
# real container that the offline contract fixtures exercise.
snapshot_query="SELECT CONCAT_WS('|', UTC_TIMESTAMP(6), COALESCE((SELECT MAX(id) FROM recharge_order), 0), COALESCE((SELECT MAX(id) FROM payment_provider_event), 0), COALESCE((SELECT MAX(id) FROM wallet_transaction), 0), COALESCE((SELECT MAX(id) FROM ledger_journal), 0), COALESCE((SELECT MAX(id) FROM ledger_posting), 0))"
snapshot() {
  value="$(mysql_query "$snapshot_query")"
  case "$value" in *$'\n'*) exit 30 ;; esac
  printf '%s' "$value"
}

if [ "$phase" = start ]; then
  printf 'S|%s\n' "$(snapshot)"
  unset database_secret MYSQL_PWD
  exit 0
fi

IFS= read -r baseline_timestamp || exit 31
IFS= read -r baseline_recharge || exit 32
IFS= read -r baseline_provider_event || exit 33
IFS= read -r baseline_wallet_transaction || exit 34
IFS= read -r baseline_ledger_journal || exit 35
IFS= read -r baseline_ledger_posting || exit 36
IFS= read -r create_request_id || exit 41
case "$baseline_timestamp" in
  ????-??-??\ ??\:??\:??.??????) ;;
  *) exit 37 ;;
esac
for value in "$baseline_recharge" "$baseline_provider_event" "$baseline_wallet_transaction" "$baseline_ledger_journal" "$baseline_ledger_posting"; do
  case "$value" in ''|*[!0-9]*) exit 38 ;; esac
done
case "$create_request_id" in
  qa-alipay-[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) ;;
  *) exit 42 ;;
esac

before="$(snapshot)"
metrics_query="SELECT CONCAT_WS('|', COUNT(*), COALESCE(SUM(payment_provider = 'alipay-sandbox'), 0), COALESCE(SUM(payment_provider = 'alipay-sandbox' AND status = 'CANCELLED'), 0), COALESCE(SUM(payment_provider = 'alipay-sandbox' AND status = 'CANCELLED' AND provider_status IN ('TRADE_CLOSED', 'TRADE_NOT_EXIST')), 0), COALESCE(SUM(payment_provider = 'alipay-sandbox' AND status = 'CANCELLED' AND provider_status IS NOT NULL AND provider_status NOT IN ('TRADE_CLOSED', 'TRADE_NOT_EXIST')), 0), COALESCE(SUM(payment_provider = 'alipay-sandbox' AND status = 'CANCELLED' AND provider_status IS NULL), 0), (SELECT COUNT(*) FROM payment_provider_event WHERE id > $baseline_provider_event), (SELECT COUNT(*) FROM wallet_transaction WHERE id > $baseline_wallet_transaction), (SELECT COUNT(*) FROM ledger_journal WHERE id > $baseline_ledger_journal), (SELECT COUNT(*) FROM ledger_posting WHERE id > $baseline_ledger_posting)) FROM recharge_order WHERE id > $baseline_recharge AND created_at >= STR_TO_DATE('$baseline_timestamp', '%Y-%m-%d %H:%i:%s.%f') AND idempotency_key = '$create_request_id'"
metrics="$(mysql_query "$metrics_query")"
middle="$(snapshot)"
metrics_repeat="$(mysql_query "$metrics_query")"
after="$(snapshot)"
case "$metrics" in *$'\n'*|'') exit 39 ;; esac
case "$metrics_repeat" in *$'\n'*|'') exit 40 ;; esac
printf 'B|%s\nM|%s\nC|%s\nF|%s\nE|%s\n' "$before" "$metrics" "$middle" "$metrics_repeat" "$after"
unset database_secret MYSQL_PWD
"""
MYSQL_SCRIPT = MYSQL_PHYSICAL_EVIDENCE_SCRIPT


def _sha256(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def _parse_timestamp(value: object) -> str:
    if not isinstance(value, str) or not DB_TIMESTAMP_RE.fullmatch(value):
        raise CollectorError("INVALID_MARKER")
    try:
        parsed = datetime.strptime(value, "%Y-%m-%d %H:%M:%S.%f")
    except ValueError:
        raise CollectorError("INVALID_MARKER") from None
    # Round-tripping catches impossible calendar/time values while preserving
    # the exact six-digit value returned by MySQL.
    if parsed.strftime("%Y-%m-%d %H:%M:%S.%f") != value:
        raise CollectorError("INVALID_MARKER")
    return value


def _parse_uint(value: str) -> int:
    if not re.fullmatch(r"(?:0|[1-9][0-9]*)", value or ""):
        raise CollectorError("INVALID_MARKER")
    parsed = int(value)
    if parsed < 0 or parsed > MAX_UNSIGNED_BIGINT:
        raise CollectorError("INVALID_MARKER")
    return parsed


def _parse_snapshot_line(line: str, prefix: str) -> DbSnapshot:
    fields = line.split("|")
    if len(fields) != 7 or fields[0] != prefix:
        raise CollectorError("INVALID_MARKER")
    timestamp = _parse_timestamp(fields[1])
    max_ids = {name: _parse_uint(value) for name, value in zip(TABLES, fields[2:])}
    return DbSnapshot(timestamp, max_ids)


def _parse_metrics_line(line: str, prefix: str) -> DbMetrics:
    fields = line.split("|")
    if len(fields) != 11 or fields[0] != prefix:
        raise CollectorError("INVALID_MARKER")
    values = [_parse_uint(value) for value in fields[1:]]
    return DbMetrics(*values)


def _parse_db_output(output: str, phase: str) -> DbResult:
    if not isinstance(output, str) or len(output.encode("utf-8", "ignore")) > MAX_MARKER_BYTES:
        raise CollectorError("INVALID_MARKER")
    lines = output.splitlines()
    if not lines or lines[0] == "SCHEMA_MISSING":
        raise CollectorError("SCHEMA_MISSING")
    if lines[0] != "SCHEMA_OK":
        raise CollectorError("INVALID_MARKER")
    if phase == "start":
        if len(lines) != 2:
            raise CollectorError("INVALID_MARKER")
        return DbResult(start_snapshot=_parse_snapshot_line(lines[1], "S"))
    if len(lines) != 6:
        raise CollectorError("INVALID_MARKER")
    return DbResult(
        before_snapshot=_parse_snapshot_line(lines[1], "B"),
        metrics=_parse_metrics_line(lines[2], "M"),
        middle_snapshot=_parse_snapshot_line(lines[3], "C"),
        metrics_repeat=_parse_metrics_line(lines[4], "F"),
        after_snapshot=_parse_snapshot_line(lines[5], "E"),
    )


def _run_mysql(config: Config, phase: str, baseline: _Baseline | None = None) -> DbResult:
    if phase not in {"start", "collect"} or config.phase != phase:
        raise CollectorError("CONFIGURATION")
    input_value = ""
    if phase == "collect":
        if baseline is None:
            raise CollectorError("INVALID_BASELINE")
        input_value = baseline.utc_timestamp + "\n" + "\n".join(
            str(baseline.max_ids[name]) for name in TABLES
        ) + "\n" + config.create_request_id + "\n"
    script = "export M5_ALIPAY_PHYSICAL_PHASE=" + phase + "\n" + MYSQL_PHYSICAL_EVIDENCE_SCRIPT
    try:
        completed = subprocess.run(
            [config.docker_bin, "exec", "-i", config.mysql_container, "/bin/sh", "-c", script],
            cwd="/",
            env=dict(config.docker_env),
            input=input_value,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=120,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        raise CollectorError("DB_UNAVAILABLE") from None
    if completed.returncode != 0:
        raise CollectorError("DB_UNAVAILABLE")
    return _parse_db_output(completed.stdout, phase)


def _validate_config_object(config: Config) -> None:
    if config.phase not in {"start", "collect"}:
        raise CollectorError("CONFIGURATION")
    if not SERIAL_RE.fullmatch(config.serial or "") or "emulator" in config.serial.lower() or "qemu" in config.serial.lower():
        raise CollectorError("CONFIGURATION")
    if not RUN_ID_RE.fullmatch(config.run_id or "") or not SHA1_RE.fullmatch(config.flutter_sha or "") or not SHA1_RE.fullmatch(config.backend_sha or ""):
        raise CollectorError("CONFIGURATION")
    if not CREATE_REQUEST_ID_RE.fullmatch(config.create_request_id or ""):
        raise CollectorError("CONFIGURATION")
    if type(config.run_started_at) is not int or config.run_started_at <= 0:
        raise CollectorError("CONFIGURATION")
    if not CONTAINER_RE.fullmatch(config.mysql_container or ""):
        raise CollectorError("CONFIGURATION")


def _baseline_from_result(config: Config, result: DbResult) -> dict[str, object]:
    snapshot = result.start_snapshot
    if snapshot is None:
        raise CollectorError("INVALID_BASELINE")
    _parse_timestamp(snapshot.utc_timestamp)
    if set(snapshot.max_ids) != set(TABLES) or any(
        type(snapshot.max_ids.get(name)) is not int
        or snapshot.max_ids[name] < 0
        or snapshot.max_ids[name] > MAX_UNSIGNED_BIGINT
        for name in TABLES
    ):
        raise CollectorError("INVALID_BASELINE")
    return {
        "schema": SCHEMA,
        "runIdSha256": _sha256(config.run_id),
        "serialSha256": _sha256(config.serial),
        "runStartedAt": config.run_started_at,
        "flutterSha": config.flutter_sha,
        "backendSha": config.backend_sha,
        "createRequestIdSha256": _sha256(config.create_request_id),
        "utcTimestamp": snapshot.utc_timestamp,
        "maxIds": {name: snapshot.max_ids[name] for name in TABLES},
        "consumed": False,
    }


def _read_baseline(config: Config) -> _Baseline:
    path = Path(config.baseline_file)
    if not path.is_file() or path.is_symlink():
        raise CollectorError("INVALID_BASELINE")
    try:
        metadata = path.stat()
        if metadata.st_mode & 0o077:
            raise CollectorError("INVALID_BASELINE")
        raw = path.read_bytes()
    except CollectorError:
        raise
    except (OSError, ValueError):
        raise CollectorError("INVALID_BASELINE") from None
    if len(raw) > MAX_MARKER_BYTES:
        raise CollectorError("INVALID_BASELINE")
    try:
        value = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        raise CollectorError("INVALID_BASELINE") from None
    if not isinstance(value, dict) or set(value) != {
        "schema",
        "runIdSha256",
        "serialSha256",
        "runStartedAt",
        "flutterSha",
        "backendSha",
        "createRequestIdSha256",
        "utcTimestamp",
        "maxIds",
        "consumed",
    }:
        raise CollectorError("INVALID_BASELINE")
    if value["schema"] != SCHEMA or value["consumed"] is not False:
        raise CollectorError("INVALID_BASELINE")
    if value["runIdSha256"] != _sha256(config.run_id) or value["serialSha256"] != _sha256(config.serial):
        raise CollectorError("INVALID_BASELINE")
    if value["createRequestIdSha256"] != _sha256(config.create_request_id):
        raise CollectorError("INVALID_BASELINE")
    if value["runStartedAt"] != config.run_started_at or value["flutterSha"] != config.flutter_sha or value["backendSha"] != config.backend_sha:
        raise CollectorError("INVALID_BASELINE")
    timestamp = _parse_timestamp(value["utcTimestamp"])
    create_request_id_sha256 = value["createRequestIdSha256"]
    if not isinstance(create_request_id_sha256, str) or not re.fullmatch(r"[0-9a-f]{64}", create_request_id_sha256):
        raise CollectorError("INVALID_BASELINE")
    max_ids = value["maxIds"]
    if not isinstance(max_ids, dict) or set(max_ids) != set(TABLES):
        raise CollectorError("INVALID_BASELINE")
    parsed_ids: dict[str, int] = {}
    for name in TABLES:
        item = max_ids[name]
        if type(item) is not int or item < 0 or item > MAX_UNSIGNED_BIGINT:
            raise CollectorError("INVALID_BASELINE")
        parsed_ids[name] = item
    return _Baseline(timestamp, parsed_ids, create_request_id_sha256, False)


def _atomic_json_write(path: Path, value: Mapping[str, object], *, replace: bool) -> None:
    _require_private_parent(path)
    if path.exists() or path.is_symlink():
        if not replace:
            raise CollectorError("OUTPUT_WRITE")
        try:
            metadata = path.lstat()
        except OSError:
            raise CollectorError("OUTPUT_WRITE") from None
        if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
            raise CollectorError("OUTPUT_WRITE")
    payload = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True) + "\n"
    temporary: Path | None = None
    try:
        fd, name = tempfile.mkstemp(prefix=".alipay-physical-evidence-", dir=str(path.parent))
        temporary = Path(name)
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            stream.write(payload)
            stream.flush()
            os.fsync(stream.fileno())
        if replace:
            os.replace(temporary, path)
            temporary = None
        else:
            # A hard-link publish is atomic and fails instead of clobbering a
            # path that appeared concurrently after the initial validation.
            os.link(temporary, path)
            os.unlink(temporary)
            temporary = None
        directory_fd = os.open(path.parent, os.O_RDONLY)
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
    except (OSError, ValueError, TypeError):
        raise CollectorError("OUTPUT_WRITE") from None
    finally:
        if temporary is not None:
            try:
                temporary.unlink(missing_ok=True)
            except OSError:
                pass


def _mark_consumed(config: Config) -> None:
    path = Path(config.baseline_file)
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        raise CollectorError("STATE") from None
    if not isinstance(value, dict):
        raise CollectorError("STATE")
    value["consumed"] = True
    _atomic_json_write(path, value, replace=True)


def _validate_collect(baseline: _Baseline, result: DbResult) -> None:
    before = result.before_snapshot
    middle = getattr(result, "middle_snapshot", None)
    after = result.after_snapshot
    metrics = result.metrics
    metrics_repeat = result.metrics_repeat
    if before is None or middle is None or after is None or metrics is None or metrics_repeat is None:
        raise CollectorError("INVALID_MARKER")
    snapshots = (before, middle, after)
    if any(set(snapshot.max_ids) != set(TABLES) for snapshot in snapshots):
        raise CollectorError("INVALID_MARKER")
    if before.max_ids != middle.max_ids or middle.max_ids != after.max_ids or metrics != metrics_repeat:
        raise CollectorError("CONCURRENT_WRITE")
    if any(
        snapshot.max_ids[name] < baseline.max_ids[name]
        for snapshot in snapshots
        for name in TABLES
    ):
        raise CollectorError("CONCURRENT_WRITE")
    if any(after.max_ids[name] != baseline.max_ids[name] for name in FINANCIAL_TABLES):
        raise CollectorError("CONCURRENT_WRITE")
    if after.max_ids["recharge_order"] <= baseline.max_ids["recharge_order"]:
        raise CollectorError("INVALID_BASELINE")
    if not (
        metrics.new_order_count == 1
        and metrics.alipay_order_count == 1
        and metrics.cancelled_order_count == 1
        and metrics.safe_provider_order_count == 1
        and metrics.unsafe_provider_order_count == 0
        and metrics.missing_provider_status_count == 0
        and metrics.payment_provider_events == 0
        and metrics.wallet_transactions == 0
        and metrics.ledger_journals == 0
        and metrics.ledger_postings == 0
    ):
        raise CollectorError("INVARIANT_VIOLATION")


def _payload(config: Config, observed_at: int) -> dict[str, object]:
    return {
        "schema": SCHEMA,
        "status": "OK",
        "serial": config.serial,
        "flutterSha": config.flutter_sha,
        "backendSha": config.backend_sha,
        "runId": config.run_id,
        "runStartedAt": config.run_started_at,
        "observedAt": observed_at,
        "evidenceSource": "read-only-db",
        "payment": {
            "provider": "alipay-sandbox",
            "status": "CANCELED",
            "databaseStatus": "CANCELLED",
            "canceledOrderCount": 1,
        },
        "writeCounters": {key: 0 for key in COUNTER_KEYS},
        "secrets": False,
    }


def start(
    config: Config,
    db_runner: Callable[[Config, str, _Baseline | None], DbResult] | None = None,
) -> None:
    _validate_config_object(config)
    if config.phase != "start":
        raise CollectorError("CONFIGURATION")
    db_runner = db_runner or _run_mysql
    result = db_runner(config, "start", None)
    state = _baseline_from_result(config, result)
    _atomic_json_write(Path(config.baseline_file), state, replace=False)


def collect(
    config: Config,
    db_runner: Callable[[Config, str, _Baseline | None], DbResult] | None = None,
) -> dict[str, object]:
    _validate_config_object(config)
    if config.phase != "collect":
        raise CollectorError("CONFIGURATION")
    db_runner = db_runner or _run_mysql
    baseline = _read_baseline(config)
    result = db_runner(config, "collect", baseline)
    _validate_collect(baseline, result)
    observed_at = int(time.time())
    if observed_at < config.run_started_at:
        raise CollectorError("INVARIANT_VIOLATION")
    payload = _payload(config, observed_at)
    _atomic_json_write(Path(config.evidence_file), payload, replace=False)
    _mark_consumed(config)
    return payload


def self_test() -> int:
    """Offline contract check; this path never resolves Docker or MySQL."""

    required = (
        *TABLES,
        "UTC_TIMESTAMP(6)",
        "MYSQL_PWD=",
        "TRADE_CLOSED",
        "TRADE_NOT_EXIST",
        "idempotency_key",
        "create_request_id",
    )
    if any(item not in MYSQL_PHYSICAL_EVIDENCE_SCRIPT for item in required):
        return 1
    upper = MYSQL_PHYSICAL_EVIDENCE_SCRIPT.upper()
    if any(item in upper for item in ("INSERT ", "UPDATE ", "DELETE ", "DROP ", "ALTER ", "TRUNCATE ")):
        return 1
    if "--EXECUTE" not in upper or "SET SESSION TRANSACTION READ ONLY" not in upper:
        return 1
    print("self-test=PASS")
    return 0


class _ArgumentParser(argparse.ArgumentParser):
    def error(self, _message: str) -> None:
        raise CollectorError("CONFIGURATION")


def main(argv: Sequence[str] | None = None) -> int:
    parser = _ArgumentParser(add_help=True, description="Physical Alipay read-only DB evidence")
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--phase", choices=("start", "collect"))
    try:
        args = parser.parse_args(list(argv) if argv is not None else None)
        if args.self_test:
            return self_test()
        if args.phase:
            existing = os.environ.get("QA_ALIPAY_PHYSICAL_EVIDENCE_PHASE", "")
            if existing and existing != args.phase:
                raise CollectorError("CONFIGURATION")
            os.environ["QA_ALIPAY_PHYSICAL_EVIDENCE_PHASE"] = args.phase
        config = read_config()
        if config.phase == "start":
            start(config)
            print("status=STARTED")
        else:
            collect(config)
            print("status=OK")
        return 0
    except CollectorError as error:
        print(f"status=FAIL category={error.category}")
        return 2
    except Exception:
        print("status=FAIL category=STATE")
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
