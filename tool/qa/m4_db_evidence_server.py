#!/usr/bin/env python3
"""Loopback-only, read-only DB evidence endpoint for the M4 AVD runner.

MySQL is queried only from inside the configured MySQL container. The database
password is expanded there and is never a host subprocess argument or response
field. The HTTP response contains aggregate counters and boolean invariants
only. A read-only aggregate baseline is captured before the loopback listener
binds; successful responses expose only non-negative first-party write deltas
from that baseline. Use --self-test to run local tests without Docker or
runtime settings.
"""

from __future__ import annotations

import dataclasses
import hmac
import http.server
import json
import os
import re
import secrets as secrets_module
import shutil
import subprocess
import sys
import threading
from typing import Mapping, Sequence
from urllib.parse import urlsplit


TOKEN_ENV_NAMES = (
    "M4_DB_EVIDENCE_TOKEN",
    "QA_DB_EVIDENCE_TOKEN",
    "DB_EVIDENCE_TOKEN",
)
HOST_ENV_NAMES = ("M4_DB_EVIDENCE_HOST", "QA_DB_EVIDENCE_HOST")
PORT_ENV_NAMES = ("M4_DB_EVIDENCE_PORT", "QA_DB_EVIDENCE_PORT", "DB_EVIDENCE_PORT")
DOCKER_SOCKET_ENV_NAMES = ("M4_DOCKER_SOCKET", "QA_DOCKER_SOCKET", "DOCKER_HOST")
MYSQL_CONTAINER_ENV_NAMES = (
    "M4_MYSQL_CONTAINER",
    "M4_DB_EVIDENCE_MYSQL_CONTAINER",
    "QA_MYSQL_CONTAINER",
    "QA_DB_EVIDENCE_MYSQL_CONTAINER",
    "MYSQL_CONTAINER",
)
BACKEND_CONTAINER_ENV_NAMES = (
    "M4_BACKEND_CONTAINER",
    "M4_DB_EVIDENCE_BACKEND_CONTAINER",
    "QA_BACKEND_CONTAINER",
    "QA_DB_EVIDENCE_BACKEND_CONTAINER",
    "BACKEND_CONTAINER",
)
EXPECTED_SHA_ENV_NAMES = (
    # Keep the harness checkout SHA separate: only an explicit image-attestation
    # variable opts into the Docker label/container-environment check.
    "M4_EXPECTED_BACKEND_SHA",
    "M4_DB_EVIDENCE_EXPECTED_BACKEND_SHA",
    "QA_EXPECTED_BACKEND_SHA",
)

LOOPBACK_HOST = "127.0.0.1"
DEFAULT_PORT = 0
ALLOWED_PATHS = frozenset({"/", "/m4/db-evidence", "/m4/db-evidence/"})
RESPONSE_KEYS = frozenset(
    {
        "status",
        "writeCounters",
        "authorityInvariants",
        "providerCalls",
        "secrets",
        "evidenceBinding",
    }
)
CONTAINER_NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$")
SHA_RE = re.compile(r"^[0-9a-fA-F]{40}$")
COUNT_RE = re.compile(r"^[0-9]+$")
RUN_ID_RE = re.compile(r"^[A-Za-z0-9_.:-]{1,80}$")
AVD_RE = re.compile(r"^AVD-[AB]$")
START_NONCE_RE = re.compile(r"^[A-Za-z0-9_.~=-]{16,256}$")
MARKER_RE = re.compile(r"^[CIOPS](?:\|[A-Za-z0-9_.-]+|\|[0-9]+){1,6}$")
WRITE_COUNTER_KEYS = (
    "auth_sessions",
    "room_activity",
    "commerce_activity",
    "social_community_messages",
    "social_user_reports",
    "idempotency_audit",
)
REQUIRED_INVARIANT_KEYS = frozenset(
    {
        "core_schema_present",
        "provider_outbox_allowed_states",
        "provider_outbox_attempts_zero",
        "private_message_delivery_blocked",
        "adapter_status_projection_blocked",
        "backend_environment_development",
        "backend_profile_development",
        "development_outbox_or_blocked_sms",
        "formal_vendor_adapters_blocked",
        "provider_invocation_rows_zero",
        "first_party_writes_observed_since_start",
    }
)


class EvidenceError(RuntimeError):
    """A redacted, client-safe collection failure."""


class ConfigurationError(EvidenceError):
    """Invalid or incomplete process configuration."""


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


def _valid_bearer_header(values: Sequence[str], token: str) -> bool:
    if len(values) != 1:
        return False
    value = values[0]
    prefix = "Bearer "
    presented = value[len(prefix):] if value.startswith(prefix) else ""
    # compare_digest is intentional, including for malformed prefixes.
    return _constant_time_equal(presented, token) and value.startswith(prefix)


@dataclasses.dataclass(frozen=True)
class Config:
    host: str
    port: int
    token: str
    docker_bin: str
    docker_env: Mapping[str, str]
    backend_container: str
    mysql_container: str
    expected_backend_sha: str | None


def read_config(environment: Mapping[str, str] | None = None) -> Config:
    """Read and validate only the supported runtime environment variables."""

    env = os.environ if environment is None else environment
    token = _first_value(env, TOKEN_ENV_NAMES)
    if len(token) < 32 or len(token) > 512 or not token.isascii() or any(
        character.isspace() or ord(character) < 0x20 for character in token
    ):
        raise ConfigurationError("invalid evidence token")
    if len(set(token)) < 3:
        raise ConfigurationError("invalid evidence token")

    configured_host = _first_value(env, HOST_ENV_NAMES) or LOOPBACK_HOST
    if configured_host not in {LOOPBACK_HOST, "localhost"}:
        raise ConfigurationError("evidence endpoint must bind loopback")

    configured_port = _first_value(env, PORT_ENV_NAMES)
    try:
        port = int(configured_port) if configured_port else DEFAULT_PORT
    except ValueError as error:
        raise ConfigurationError("invalid evidence port") from error
    if port < 0 or port > 65535:
        raise ConfigurationError("invalid evidence port")

    backend_container = _first_value(env, BACKEND_CONTAINER_ENV_NAMES)
    mysql_container = _first_value(env, MYSQL_CONTAINER_ENV_NAMES)
    if not CONTAINER_NAME_RE.fullmatch(backend_container or ""):
        raise ConfigurationError("invalid backend container name")
    if not CONTAINER_NAME_RE.fullmatch(mysql_container or ""):
        raise ConfigurationError("invalid mysql container name")

    docker_socket = _first_value(env, DOCKER_SOCKET_ENV_NAMES)
    if docker_socket and not (
        docker_socket.startswith("unix://") or docker_socket.startswith("/")
    ):
        raise ConfigurationError("docker socket must be local unix socket")
    docker_path = shutil.which("docker")
    if not docker_path:
        raise ConfigurationError("docker command is unavailable")
    # Do not inherit unrelated host environment values. When no socket is
    # supplied, the Docker CLI's configured local context is used.
    docker_env = {"PATH": env.get("PATH", "/usr/bin:/bin")}
    if docker_socket:
        docker_env["DOCKER_HOST"] = docker_socket

    expected_sha = _first_value(env, EXPECTED_SHA_ENV_NAMES) or None
    if expected_sha is not None and not SHA_RE.fullmatch(expected_sha):
        raise ConfigurationError("invalid expected backend SHA")

    return Config(
        host=LOOPBACK_HOST,
        port=port,
        token=token,
        docker_bin=docker_path,
        docker_env=docker_env,
        backend_container=backend_container,
        mysql_container=mysql_container,
        expected_backend_sha=expected_sha.lower() if expected_sha else None,
    )


class DockerRunner:
    """Run only the Docker operations needed by evidence collection."""

    def __init__(self, config: Config):
        self._config = config

    def _run(self, arguments: Sequence[str], timeout: float = 12.0) -> str:
        argv = [self._config.docker_bin, *arguments]
        if any(self._config.token in argument for argument in argv):
            raise EvidenceError("protected value reached subprocess argv")
        try:
            completed = subprocess.run(
                argv,
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
            raise EvidenceError("docker operation unavailable") from error
        if completed.returncode != 0:
            # Docker diagnostics can include environment details or mounted paths.
            raise EvidenceError("docker operation failed")
        return completed.stdout

    def exec_shell(self, container: str, script: str, timeout: float = 20.0) -> str:
        if not CONTAINER_NAME_RE.fullmatch(container):
            raise EvidenceError("invalid container name")
        return self._run(("exec", container, "/bin/sh", "-c", script), timeout=timeout)

    def inspect_labels(self, container: str) -> Mapping[str, str]:
        output = self._run(
            ("inspect", "--format", "{{json .Config.Labels}}", container),
            timeout=8.0,
        ).strip()
        if not output or output == "null":
            return {}
        try:
            labels = json.loads(output)
        except (TypeError, ValueError) as error:
            raise EvidenceError("invalid container metadata") from error
        if not isinstance(labels, dict):
            raise EvidenceError("invalid container metadata")
        return {
            str(key): str(value)
            for key, value in labels.items()
            if isinstance(key, str) and isinstance(value, (str, int, float, bool))
        }


# Password variables are expanded only inside the MySQL container. Every SQL
# statement below is a SELECT aggregate. The host receives typed markers only.
MYSQL_EVIDENCE_SCRIPT = r"""
set -eu
database="${MYSQL_DATABASE:-}"
database_user="${MYSQL_USER:-${MYSQL_APP_USER:-root}}"
database_password="${MYSQL_PASSWORD:-${MYSQL_APP_PASSWORD:-${MYSQL_ROOT_PASSWORD:-}}}"
[ -n "\$database" ] && [ -n "\$database_password" ] || exit 20

mysql_query() {
  MYSQL_PWD="\$database_password" mysql \
    --protocol=socket --connect-timeout=5 \
    --user="\$database_user" --database="\$database" \
    --batch --skip-column-names --raw --execute="\$1"
}

valid_name() {
  case "\$1" in
    ""|*[!A-Za-z0-9_]* ) return 1 ;;
    * ) return 0 ;;
  esac
}

table_exists() {
  valid_name "\$1" || exit 21
  value="\$(mysql_query "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = '\$1'")"
  case "\$value" in 0|1) printf '%s' "\$value" ;; *) exit 22 ;; esac
}

column_exists() {
  valid_name "\$1" || exit 23
  valid_name "\$2" || exit 24
  value="\$(mysql_query "SELECT COUNT(*) FROM information_schema.columns WHERE table_schema = DATABASE() AND table_name = '\$1' AND column_name = '\$2'")"
  case "\$value" in
    0) return 1 ;;
    1) return 0 ;;
    *) exit 25 ;;
  esac
}

table_count() {
  table="\$1"
  [ "\$(table_exists "\$table")" = 1 ] || { printf '0'; return; }
  value="\$(mysql_query "SELECT COUNT(*) FROM \$table")"
  case "\$value" in *[!0-9]*|"") exit 26 ;; *) printf '%s' "\$value" ;; esac
}

sum_tables() {
  label="\$1"
  shift
  total=0
  for table in "\$@"; do
    value="\$(table_count "\$table")"
    total=\$((total + value))
  done
  printf 'C|%s|%s\n' "\$label" "\$total"
}

# Core/F3 write-bearing records. Missing later tables count as zero.
sum_tables auth_sessions app_user refresh_session sms_challenge
sum_tables room_activity room_member room_session room_join_request room_public_message room_audit_log room_mic_request room_pk_battle room_pk_invitation room_favorite room_ban
sum_tables commerce_activity wallet_transaction gift_transfer ledger_journal ledger_posting withdrawal_application refund_application wallet_adjustment_request wallet_reconciliation
sum_tables social_community_messages private_message notification_event daily_sign_in guild_sign_in task_progress_event dynamic_post dynamic_comment dynamic_like friend_request user_follow user_block support_ticket
sum_tables social_user_reports user_report
sum_tables idempotency_audit operation_idempotency user_audit_log operations_audit_log

schema_core=1
for table in app_user refresh_session room; do
  [ "\$(table_exists "\$table")" = 1 ] || schema_core=0
done
printf 'I|schema_core|%s\n' "\$schema_core"

outbox_rows=0
outbox_bad_status=0
outbox_bad_attempts=0
outbox_unknown=0
outbox_seen=0

# Only aggregate SELECTs are issued. Known migration names are checked
# individually; an unrecognized outbox table fails closed.
outbox_table_count="\$(mysql_query "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND LOWER(table_name) LIKE '%outbox%'")"
case "\$outbox_table_count" in *[!0-9]*|"") exit 27 ;; 0) ;; *) outbox_seen=1 ;; esac

is_development_outbox_name() {
  case "\$1" in
    development_*|*development*|sms_outbox|sms_challenge_outbox) return 0 ;;
    *) return 1 ;;
  esac
}

known_outbox_count=0
for table in provider_delivery_outbox development_outbox development_sms_outbox sms_outbox sms_challenge_outbox; do
  if [ "\$(table_exists "\$table")" = 1 ]; then
    known_outbox_count=\$((known_outbox_count + 1))
    rows="\$(table_count "\$table")"
    outbox_rows=\$((outbox_rows + rows))
    if column_exists "\$table" status; then
      if is_development_outbox_name "\$table"; then
        bad="\$(mysql_query "SELECT COUNT(*) FROM \$table WHERE status IS NULL OR UPPER(TRIM(status)) NOT IN ('VENDOR_BLOCKED','DEVELOPMENT_OUTBOX','DEVELOPMENT-OUTBOX','DEVELOPMENT OUTBOX','PENDING','AVAILABLE','CONSUMED','EXPIRED')")"
      else
        bad="\$(mysql_query "SELECT COUNT(*) FROM \$table WHERE status IS NULL OR UPPER(TRIM(status)) <> 'VENDOR_BLOCKED'")"
      fi
      case "\$bad" in *[!0-9]*|"") exit 28 ;; *) outbox_bad_status=\$((outbox_bad_status + bad)) ;;
      esac
    else
      is_development_outbox_name "\$table" || outbox_unknown=1
    fi
    if column_exists "\$table" attempt_count; then
      attempts="\$(mysql_query "SELECT COUNT(*) FROM \$table WHERE COALESCE(attempt_count, 0) <> 0")"
      case "\$attempts" in *[!0-9]*|"") exit 30 ;; *) outbox_bad_attempts=\$((outbox_bad_attempts + attempts)) ;;
      esac
    fi
  fi
done
[ "\$outbox_table_count" -ge "\$known_outbox_count" ] || exit 31
[ "\$outbox_table_count" = "\$known_outbox_count" ] || outbox_unknown=1
printf 'O|%s|%s|%s|%s|%s\n' "\$outbox_rows" "\$outbox_bad_status" "\$outbox_bad_attempts" "\$outbox_unknown" "\$outbox_seen"

delivery_status_bad=0
if [ "\$(table_exists private_message)" = 1 ]; then
  if column_exists private_message delivery_status; then
    bad="\$(mysql_query "SELECT COUNT(*) FROM private_message WHERE delivery_status IS NULL OR UPPER(TRIM(delivery_status)) <> 'VENDOR_BLOCKED'")"
    case "\$bad" in *[!0-9]*|"") exit 33 ;; *) delivery_status_bad=\$bad ;;
    esac
  else
    delivery_status_bad=1
  fi
fi
printf 'I|delivery_status_bad|%s\n' "\$delivery_status_bad"

# Any provider invocation table is conservative evidence of a provider call.
provider_rows="\$(mysql_query "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND (LOWER(table_name) LIKE '%provider%call%' OR LOWER(table_name) LIKE '%provider%invoc%' OR LOWER(table_name) LIKE '%provider%attempt%' OR LOWER(table_name) LIKE '%vendor%call%' OR LOWER(table_name) LIKE '%vendor%invoc%' OR LOWER(table_name) LIKE '%vendor%attempt%')")"
case "\$provider_rows" in *[!0-9]*|"") exit 32 ;; esac
printf 'P|%s\n' "\$provider_rows"

adapter_bad=0
for table in vendor_adapter_status vendor_adapter_state provider_adapter_status; do
  if [ "\$(table_exists "\$table")" = 1 ]; then
    if column_exists "\$table" status; then
      bad="\$(mysql_query "SELECT COUNT(*) FROM \$table WHERE status IS NULL OR UPPER(TRIM(status)) <> 'VENDOR_BLOCKED'")"
      case "\$bad" in *[!0-9]*|"") exit 32 ;; *) adapter_bad=\$((adapter_bad + bad)) ;;
      esac
    else
      adapter_bad=1
    fi
  fi
done
printf 'I|adapter_status_bad|%s\n' "\$adapter_bad"

unset database_password MYSQL_PWD
""".strip().replace(r"\$", "$")


BACKEND_EVIDENCE_SCRIPT = r"""
set -eu

truthy() {
  case "$1" in 1|true|TRUE|yes|YES|on|ON) return 0 ;; *) return 1 ;; esac
}

flag_disabled() {
  for name in "$@"; do
    value="$(printenv "$name" 2>/dev/null || true)"
    if truthy "$value"; then return 1; fi
  done
  return 0
}

dev_or_empty() {
  value="$(printenv SMS_DELIVERY_MODE 2>/dev/null || true)"
  [ -z "$value" ] || [ "$value" = development_outbox ]
}

development_environment() {
  value="$(printenv APP_ENV 2>/dev/null || true)"
  [ -z "$value" ] || [ "$value" = development ]
}

development_profile() {
  value="$(printenv SPRING_PROFILES_ACTIVE 2>/dev/null || true)"
  [ -z "$value" ] || [ "$value" = development ]
}

if development_environment; then printf 'I|backend_environment|1\n'; else printf 'I|backend_environment|0\n'; fi
if development_profile; then printf 'I|backend_profile|1\n'; else printf 'I|backend_profile|0\n'; fi
if dev_or_empty; then printf 'I|development_outbox_mode|1\n'; else printf 'I|development_outbox_mode|0\n'; fi

all_disabled=1
if ! flag_disabled VENDOR_SMS_ADAPTER_ENABLED APP_VENDOR_SMS_ADAPTER_ENABLED; then all_disabled=0; fi
if ! flag_disabled VENDOR_RTC_ADAPTER_ENABLED APP_VENDOR_RTC_ADAPTER_ENABLED; then all_disabled=0; fi
if ! flag_disabled VENDOR_IM_ADAPTER_ENABLED APP_VENDOR_IM_ADAPTER_ENABLED; then all_disabled=0; fi
if ! flag_disabled VENDOR_PAYMENT_ADAPTER_ENABLED APP_VENDOR_PAYMENT_ADAPTER_ENABLED; then all_disabled=0; fi
if ! flag_disabled VENDOR_PUSH_ADAPTER_ENABLED APP_VENDOR_PUSH_ADAPTER_ENABLED; then all_disabled=0; fi
if ! flag_disabled VENDOR_OBJECT_STORAGE_ADAPTER_ENABLED APP_VENDOR_OBJECT_STORAGE_ADAPTER_ENABLED; then all_disabled=0; fi
printf 'I|formal_vendor_adapters_disabled|%s\n' "$all_disabled"

is_sha() {
  value="$1"
  length="$(printf '%s' "$value" | wc -c | tr -d ' ')"
  [ "$length" = 40 ] || return 1
  invalid="$(printf '%s' "$value" | tr -d '0123456789abcdefABCDEF')"
  [ -z "$invalid" ]
}

for name in BACKEND_SHA QA_BACKEND_SHA BUILD_SHA; do
  value="$(printenv "$name" 2>/dev/null || true)"
  if is_sha "$value"; then
    printf 'S|%s\n' "$value"
  fi
done
""".strip()

def _parse_marker_lines(output: str) -> list[list[str]]:
    lines = output.splitlines()
    if not lines or any(not line or not MARKER_RE.fullmatch(line) for line in lines):
        raise EvidenceError("invalid aggregate evidence")
    return [line.split("|") for line in lines]


def _parse_backend_evidence(output: str) -> tuple[dict[str, bool], list[str]]:
    states: dict[str, bool] = {}
    shas: list[str] = []
    for fields in _parse_marker_lines(output):
        marker = fields[0]
        if marker == "I" and len(fields) == 3 and fields[1] in {
            "backend_environment",
            "backend_profile",
            "development_outbox_mode",
            "formal_vendor_adapters_disabled",
        }:
            if fields[2] not in {"0", "1"}:
                raise EvidenceError("invalid backend evidence")
            states[fields[1]] = fields[2] == "1"
        elif marker == "S" and len(fields) == 2 and SHA_RE.fullmatch(fields[1]):
            shas.append(fields[1].lower())
        else:
            raise EvidenceError("invalid backend evidence")
    required = {
        "backend_environment",
        "backend_profile",
        "development_outbox_mode",
        "formal_vendor_adapters_disabled",
    }
    if set(states) != required:
        raise EvidenceError("incomplete backend evidence")
    return states, shas


def _parse_mysql_evidence(output: str) -> dict[str, int]:
    counters: dict[str, int] = {}
    for fields in _parse_marker_lines(output):
        marker = fields[0]
        if marker == "C" and len(fields) == 3:
            if fields[1] not in {
                "auth_sessions",
                "room_activity",
                "commerce_activity",
                "social_community_messages",
                "social_user_reports",
                "idempotency_audit",
            } or not COUNT_RE.fullmatch(fields[2]):
                raise EvidenceError("invalid write counter evidence")
            counters[fields[1]] = int(fields[2])
        elif marker == "I" and len(fields) == 3:
            if fields[1] not in {
                "schema_core",
                "adapter_status_bad",
                "delivery_status_bad",
            } or not COUNT_RE.fullmatch(fields[2]):
                raise EvidenceError("invalid invariant evidence")
            counters[fields[1]] = int(fields[2])
        elif marker == "O" and len(fields) == 6:
            if not all(COUNT_RE.fullmatch(value) for value in fields[1:]):
                raise EvidenceError("invalid outbox evidence")
            counters["outbox_rows"] = int(fields[1])
            counters["outbox_bad_status"] = int(fields[2])
            counters["outbox_bad_attempts"] = int(fields[3])
            counters["outbox_unknown"] = int(fields[4])
            counters["outbox_seen"] = int(fields[5])
        elif marker == "P" and len(fields) == 2 and COUNT_RE.fullmatch(fields[1]):
            counters["provider_rows"] = int(fields[1])
        else:
            raise EvidenceError("invalid database evidence")

    required = {
        "auth_sessions",
        "room_activity",
        "commerce_activity",
        "social_community_messages",
        "social_user_reports",
        "idempotency_audit",
        "schema_core",
        "adapter_status_bad",
        "delivery_status_bad",
        "outbox_rows",
        "outbox_bad_status",
        "outbox_bad_attempts",
        "outbox_unknown",
        "outbox_seen",
        "provider_rows",
    }
    if set(counters) != required:
        raise EvidenceError("incomplete database evidence")
    return counters


@dataclasses.dataclass(frozen=True)
class EvidenceSnapshot:
    backend_states: Mapping[str, bool]
    counters: Mapping[str, int]
    database_invariants: Mapping[str, bool]
    provider_evidence: int
    backend_sha_ok: bool


def _counter_delta(
    current: Mapping[str, int],
    baseline: Mapping[str, int],
) -> dict[str, int]:
    if set(current) != set(WRITE_COUNTER_KEYS) or set(baseline) != set(WRITE_COUNTER_KEYS):
        raise EvidenceError("incomplete write counter snapshot")
    delta: dict[str, int] = {}
    for key in WRITE_COUNTER_KEYS:
        current_value = current[key]
        baseline_value = baseline[key]
        if current_value < baseline_value:
            raise EvidenceError("write counter moved backwards")
        delta[key] = current_value - baseline_value
    return delta


def _require_new_writes(delta: Mapping[str, int]) -> int:
    if set(delta) != set(WRITE_COUNTER_KEYS) or any(value < 0 for value in delta.values()):
        raise EvidenceError("invalid write counter delta")
    if delta["social_user_reports"] <= 0:
        raise EvidenceError("current-run user report mutation is missing")
    total = sum(delta.values())
    if total <= 0:
        raise EvidenceError("no first-party writes observed since baseline")
    return total


def _backend_sha_matches(
    runner: DockerRunner,
    config: Config,
    backend_shas: Sequence[str],
) -> bool:
    expected = config.expected_backend_sha
    if expected is None:
        return True
    labels = runner.inspect_labels(config.backend_container)
    candidates = list(backend_shas)
    for key in (
        "org.opencontainers.image.revision",
        "org.opencontainers.image.source-revision",
        "org.opencontainers.image.commit",
        "com.openai.backend.sha",
    ):
        value = labels.get(key, "")
        if SHA_RE.fullmatch(value):
            candidates.append(value.lower())
    if not candidates:
        raise EvidenceError("backend SHA is not attestable")
    unique = set(candidates)
    return len(unique) == 1 and _constant_time_equal(next(iter(unique)), expected)


def _validate_payload(payload: Mapping[str, object]) -> None:
    if set(payload) != RESPONSE_KEYS:
        raise EvidenceError("response field violation")
    if payload.get("status") != "OK" or payload.get("secrets") is not False:
        raise EvidenceError("response status violation")
    counters = payload.get("writeCounters")
    if not isinstance(counters, dict) or set(counters) != set(WRITE_COUNTER_KEYS):
        raise EvidenceError("write counter keys are not fixed")
    if any(type(value) is not int or value < 0 for value in counters.values()):
        raise EvidenceError("write counter delta is invalid")
    if sum(counters.values()) <= 0:
        raise EvidenceError("write counter delta is empty")
    invariants = payload.get("authorityInvariants")
    allowed_invariants = REQUIRED_INVARIANT_KEYS | {"expected_backend_sha_matches"}
    actual_invariant_keys = set(invariants) if isinstance(invariants, dict) else set()
    if actual_invariant_keys != REQUIRED_INVARIANT_KEYS and actual_invariant_keys != allowed_invariants:
        raise EvidenceError("authority invariant keys are not fixed")
    if any(value is not True for value in invariants.values()):
        raise EvidenceError("first-party write evidence is missing")
    if payload.get("providerCalls") != 0 or type(payload.get("providerCalls")) is not int:
        raise EvidenceError("provider calls are not zero")
    binding = payload.get("evidenceBinding")
    if not isinstance(binding, dict) or set(binding) != {
        "runId", "avd", "startNonce", "mutationKeys"
    }:
        raise EvidenceError("evidence binding is missing")
    if (
        not isinstance(binding["runId"], str)
        or not RUN_ID_RE.fullmatch(binding["runId"])
        or not isinstance(binding["avd"], str)
        or not AVD_RE.fullmatch(binding["avd"])
        or not isinstance(binding["startNonce"], str)
        or not START_NONCE_RE.fullmatch(binding["startNonce"])
        or binding["mutationKeys"] != list(WRITE_COUNTER_KEYS)
    ):
        raise EvidenceError("evidence binding is invalid")
    encoded = json.dumps(payload, ensure_ascii=False, separators=(",", ":"))
    forbidden = re.compile(
        r"(?i)(?:bearer\s+|access[_-]?token|refresh[_-]?token|password|client[_-]?secret|oauth|手机号|phone)"
    )
    if forbidden.search(encoded):
        raise EvidenceError("forbidden response content")


@dataclasses.dataclass
class EvidenceStart:
    run_id: str
    avd: str
    start_nonce: str
    snapshot: EvidenceSnapshot
    consumed: bool = False


class EvidenceCollector:
    def __init__(self, config: Config):
        self._config = config
        self._docker = DockerRunner(config)
        self._lock = threading.Lock()
        self._baseline: EvidenceSnapshot | None = None
        self._starts: dict[tuple[str, str], EvidenceStart] = {}

    def _capture_snapshot(self) -> EvidenceSnapshot:
        backend_output = self._docker.exec_shell(
            self._config.backend_container,
            BACKEND_EVIDENCE_SCRIPT,
            timeout=12.0,
        )
        backend_states, backend_shas = _parse_backend_evidence(backend_output)
        backend_sha_ok = _backend_sha_matches(self._docker, self._config, backend_shas)
        if not backend_sha_ok:
            raise EvidenceError("backend SHA mismatch")

        mysql_output = self._docker.exec_shell(
            self._config.mysql_container,
            MYSQL_EVIDENCE_SCRIPT,
            timeout=30.0,
        )
        database = _parse_mysql_evidence(mysql_output)

        provider_evidence = (
            database["provider_rows"]
            + database["outbox_bad_status"]
            + database["outbox_bad_attempts"]
            + database["outbox_unknown"]
            + database["delivery_status_bad"]
            + database["adapter_status_bad"]
        )
        if provider_evidence != 0:
            raise EvidenceError("provider boundary evidence is not clean")
        if not all(backend_states.values()) or not backend_sha_ok:
            raise EvidenceError("backend boundary evidence is not clean")
        if database["schema_core"] != 1:
            raise EvidenceError("core schema evidence is incomplete")

        counters = {key: database[key] for key in WRITE_COUNTER_KEYS}
        database_invariants = {
            "core_schema_present": database["schema_core"] == 1,
            "provider_outbox_allowed_states": database["outbox_bad_status"] == 0
            and database["outbox_unknown"] == 0,
            "provider_outbox_attempts_zero": database["outbox_bad_attempts"] == 0,
            "private_message_delivery_blocked": database["delivery_status_bad"] == 0,
            "adapter_status_projection_blocked": database["adapter_status_bad"] == 0,
        }
        return EvidenceSnapshot(
            backend_states=dict(backend_states),
            counters=counters,
            database_invariants=database_invariants,
            provider_evidence=provider_evidence,
            backend_sha_ok=backend_sha_ok,
        )

    def capture_baseline(self) -> None:
        with self._lock:
            if self._baseline is not None:
                raise EvidenceError("baseline already captured")
            # This runs before the HTTP socket is bound.
            self._baseline = self._capture_snapshot()

    def start(self, run_id: str, avd: str) -> Mapping[str, object]:
        with self._lock:
            if not RUN_ID_RE.fullmatch(run_id) or not AVD_RE.fullmatch(avd):
                raise EvidenceError("evidence context is invalid")
            key = (run_id, avd)
            if key in self._starts:
                raise EvidenceError("evidence context already started")
            snapshot = self._capture_snapshot()
            start_nonce = secrets_module.token_urlsafe(24)
            if not START_NONCE_RE.fullmatch(start_nonce):
                raise EvidenceError("evidence nonce generation failed")
            self._starts[key] = EvidenceStart(
                run_id=run_id,
                avd=avd,
                start_nonce=start_nonce,
                snapshot=snapshot,
            )
            return {
                "status": "STARTED",
                "runId": run_id,
                "avd": avd,
                "startNonce": start_nonce,
            }

    def collect(
        self,
        run_id: str,
        avd: str,
        start_nonce: str,
    ) -> Mapping[str, object]:
        with self._lock:
            if not RUN_ID_RE.fullmatch(run_id) or not AVD_RE.fullmatch(avd):
                raise EvidenceError("evidence context is invalid")
            if not START_NONCE_RE.fullmatch(start_nonce):
                raise EvidenceError("evidence nonce is invalid")
            start = self._starts.get((run_id, avd))
            if start is None or start.consumed or not hmac.compare_digest(
                start.start_nonce, start_nonce
            ):
                raise EvidenceError("evidence context is stale or unrelated")
            current = self._capture_snapshot()
            delta = _counter_delta(current.counters, start.snapshot.counters)
            write_total = _require_new_writes(delta)

            invariants = dict(current.database_invariants)
            invariants.update(
                {
                    "backend_environment_development": current.backend_states["backend_environment"],
                    "backend_profile_development": current.backend_states["backend_profile"],
                    "development_outbox_or_blocked_sms": current.backend_states["development_outbox_mode"],
                    "formal_vendor_adapters_blocked": current.backend_states["formal_vendor_adapters_disabled"],
                    "provider_invocation_rows_zero": current.provider_evidence == 0,
                    "first_party_writes_observed_since_start": write_total > 0,
                }
            )
            if self._config.expected_backend_sha is not None:
                invariants["expected_backend_sha_matches"] = current.backend_sha_ok
            payload: Mapping[str, object] = {
                "status": "OK",
                "writeCounters": delta,
                "authorityInvariants": invariants,
                "providerCalls": current.provider_evidence,
                "secrets": False,
                "evidenceBinding": {
                    "runId": run_id,
                    "avd": avd,
                    "startNonce": start_nonce,
                    "mutationKeys": list(WRITE_COUNTER_KEYS),
                },
            }
            _validate_payload(payload)
            start.consumed = True
            return payload


class EvidenceHandler(http.server.BaseHTTPRequestHandler):
    """Silent, bounded, single-route HTTP handler."""

    server_version = "M4Evidence"
    sys_version = ""

    def setup(self) -> None:
        super().setup()
        self.connection.settimeout(6.0)

    def log_message(self, _format: str, *_arguments: object) -> None:
        return

    def log_error(self, _format: str, *_arguments: object) -> None:
        return

    def log_request(self, *_arguments: object) -> None:
        return

    def _json(self, status: int, payload: Mapping[str, object]) -> None:
        body = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
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

    def _method_not_allowed(self) -> None:
        self._json(405, {"status": "METHOD_NOT_ALLOWED"})

    def _single_header(self, name: str) -> str:
        values = self.headers.get_all(name) or []
        return values[0] if len(values) == 1 else ""

    def do_GET(self) -> None:
        parsed = urlsplit(self.path)
        if parsed.path not in ALLOWED_PATHS or parsed.query or parsed.fragment:
            self._json(404, {"status": "NOT_FOUND"})
            return
        if self.headers.get_all("Content-Length") not in (None, ["0"]):
            self._json(400, {"status": "BAD_REQUEST"})
            return
        if not _valid_bearer_header(self.headers.get_all("Authorization") or [], self.server.token):
            self._json(401, {"status": "UNAUTHORIZED"})
            return
        phase = self._single_header("X-M4-Evidence-Phase")
        run_id = self._single_header("X-M4-Run-ID")
        avd = self._single_header("X-M4-AVD")
        start_nonce = self._single_header("X-M4-Start-Nonce")
        if not RUN_ID_RE.fullmatch(run_id) or not AVD_RE.fullmatch(avd):
            self._json(400, {"status": "BAD_REQUEST"})
            return
        try:
            if phase == "start" and not start_nonce:
                payload = self.server.collector.start(run_id, avd)
                self._json(201, payload)
                return
            if phase == "collect" and START_NONCE_RE.fullmatch(start_nonce):
                payload = self.server.collector.collect(run_id, avd, start_nonce)
                self._json(200, payload)
                return
            self._json(400, {"status": "BAD_REQUEST"})
            return
        except EvidenceError:
            self._json(503, {"status": "UNAVAILABLE"})
            return

    def do_POST(self) -> None:
        self._method_not_allowed()

    def do_PUT(self) -> None:
        self._method_not_allowed()

    def do_PATCH(self) -> None:
        self._method_not_allowed()

    def do_DELETE(self) -> None:
        self._method_not_allowed()

    def do_HEAD(self) -> None:
        self._method_not_allowed()

    def do_OPTIONS(self) -> None:
        self._method_not_allowed()

    def do_CONNECT(self) -> None:
        self._method_not_allowed()

    def do_TRACE(self) -> None:
        self._method_not_allowed()


class EvidenceServer(http.server.ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = False

    def __init__(
        self,
        address: tuple[str, int],
        handler: type[EvidenceHandler],
        collector: EvidenceCollector,
        token: str,
    ):
        super().__init__(address, handler)
        self.collector = collector
        self.token = token


def _self_test() -> int:
    token = "A9" * 32
    if not _constant_time_equal(token, token) or _constant_time_equal(token, "B" * 64):
        raise AssertionError("constant-time token helper failed")
    if not _valid_bearer_header(["Bearer " + token], token):
        raise AssertionError("valid bearer token rejected")
    if _valid_bearer_header(["Bearer " + token + "x"], token):
        raise AssertionError("wrong bearer token accepted")
    if _valid_bearer_header(["Bearer " + token, "Bearer " + token], token):
        raise AssertionError("duplicate bearer token accepted")

    backend_output = "\n".join(
        [
            "I|backend_environment|1",
            "I|backend_profile|1",
            "I|development_outbox_mode|1",
            "I|formal_vendor_adapters_disabled|1",
        ]
    )
    backend_states, _ = _parse_backend_evidence(backend_output)
    if not all(backend_states.values()):
        raise AssertionError("backend evidence parser failed")

    mysql_output = "\n".join(
        [
            "C|auth_sessions|2",
            "C|room_activity|4",
            "C|commerce_activity|6",
            "C|social_community_messages|5",
            "C|social_user_reports|1",
            "C|idempotency_audit|3",
            "I|schema_core|1",
            "O|1|0|0|0|1",
            "I|delivery_status_bad|0",
            "P|0",
            "I|adapter_status_bad|0",
        ]
    )
    database = _parse_mysql_evidence(mysql_output)
    if database["provider_rows"] != 0 or database["outbox_bad_status"] != 0:
        raise AssertionError("database evidence parser failed")

    baseline = {
        "auth_sessions": 4,
        "room_activity": 8,
        "commerce_activity": 12,
        "social_community_messages": 14,
        "social_user_reports": 15,
        "idempotency_audit": 16,
    }
    unchanged = _counter_delta(dict(baseline), baseline)
    if any(unchanged.values()):
        raise AssertionError("zero write delta failed")
    try:
        _require_new_writes(unchanged)
    except EvidenceError:
        pass
    else:
        raise AssertionError("zero write delta was accepted")
    current = dict(baseline)
    current["auth_sessions"] += 1
    current["social_user_reports"] += 1
    current["idempotency_audit"] += 2
    delta = _counter_delta(current, baseline)
    if delta != {
        "auth_sessions": 1,
        "room_activity": 0,
        "commerce_activity": 0,
        "social_community_messages": 0,
        "social_user_reports": 1,
        "idempotency_audit": 2,
    } or _require_new_writes(delta) != 4:
        raise AssertionError("positive write delta failed")
    current["commerce_activity"] = baseline["commerce_activity"] - 1
    try:
        _counter_delta(current, baseline)
    except EvidenceError:
        pass
    else:
        raise AssertionError("counter rollback was accepted")

    payload = {
        "status": "OK",
        "writeCounters": delta,
        "authorityInvariants": {
            "core_schema_present": True,
            "provider_outbox_allowed_states": True,
            "provider_outbox_attempts_zero": True,
            "private_message_delivery_blocked": True,
            "adapter_status_projection_blocked": True,
            "backend_environment_development": True,
            "backend_profile_development": True,
            "development_outbox_or_blocked_sms": True,
            "formal_vendor_adapters_blocked": True,
            "provider_invocation_rows_zero": True,
            "first_party_writes_observed_since_start": True,
        },
        "providerCalls": 0,
        "secrets": False,
        "evidenceBinding": {
            "runId": "m4-self-test",
            "avd": "AVD-A",
            "startNonce": "N" * 32,
            "mutationKeys": list(WRITE_COUNTER_KEYS),
        },
    }
    _validate_payload(payload)
    invalid_payload = dict(payload)
    invalid_payload["authorityInvariants"] = {
        "first_party_writes_observed_since_start": False,
    }
    try:
        _validate_payload(invalid_payload)
    except EvidenceError:
        pass
    else:
        raise AssertionError("false first-party write invariant was accepted")

    base_snapshot = EvidenceSnapshot(
        backend_states={
            "backend_environment": True,
            "backend_profile": True,
            "development_outbox_mode": True,
            "formal_vendor_adapters_disabled": True,
        },
        counters={key: 10 for key in WRITE_COUNTER_KEYS},
        database_invariants={key: True for key in REQUIRED_INVARIANT_KEYS if key in {
            "core_schema_present",
            "provider_outbox_allowed_states",
            "provider_outbox_attempts_zero",
            "private_message_delivery_blocked",
            "adapter_status_projection_blocked",
        }},
        provider_evidence=0,
        backend_sha_ok=True,
    )
    next_snapshot = dataclasses.replace(
        base_snapshot,
        counters={
            **base_snapshot.counters,
            "auth_sessions": 11,
            "social_user_reports": 11,
        },
    )

    class FakeCollector(EvidenceCollector):
        def __init__(self) -> None:
            super().__init__(
                Config(
                    host=LOOPBACK_HOST,
                    port=0,
                    token="self-test-token",
                    docker_bin="docker",
                    docker_env={},
                    backend_container="backend",
                    mysql_container="mysql",
                    expected_backend_sha=None,
                )
            )
            self._snapshots = [base_snapshot, next_snapshot]

        def _capture_snapshot(self) -> EvidenceSnapshot:
            return self._snapshots.pop(0)

    fake_collector = FakeCollector()
    started = fake_collector.start("m4-self-test", "AVD-A")
    nonce = started["startNonce"]
    collected = fake_collector.collect("m4-self-test", "AVD-A", nonce)
    if collected["evidenceBinding"]["runId"] != "m4-self-test":
        raise AssertionError("run binding was not echoed")
    try:
        fake_collector.collect("m4-self-test", "AVD-A", nonce)
    except EvidenceError:
        pass
    else:
        raise AssertionError("reused evidence nonce was accepted")

    for sql_keyword in ("INSERT", "UPDATE", "DELETE", "ALTER", "DROP", "TRUNCATE", "CREATE"):
        if re.search(r"\b" + sql_keyword + r"\b", MYSQL_EVIDENCE_SCRIPT, re.IGNORECASE):
            raise AssertionError("non-read SQL keyword found")
    if "SELECT COUNT(*)" not in MYSQL_EVIDENCE_SCRIPT:
        raise AssertionError("aggregate SELECT missing")
    if "SELECT table_name" in MYSQL_EVIDENCE_SCRIPT:
        raise AssertionError("row-level metadata query found")
    if token in MYSQL_EVIDENCE_SCRIPT or token in BACKEND_EVIDENCE_SCRIPT:
        raise AssertionError("token entered evidence command")
    print("self-test=PASS")
    return 0


def main(argv: Sequence[str] | None = None) -> int:
    arguments = list(sys.argv[1:] if argv is None else argv)
    if arguments == ["--self-test"]:
        return _self_test()
    if arguments:
        return 64
    try:
        config = read_config()
        collector = EvidenceCollector(config)
        # Capture the read-only baseline before creating/binding the listener.
        collector.capture_baseline()
        server = EvidenceServer((config.host, config.port), EvidenceHandler, collector, config.token)
    except ConfigurationError:
        return 78
    except EvidenceError:
        return 74
    except OSError:
        return 73

    # This line contains no token or request data; it announces an ephemeral port.
    print(f"M4_DB_EVIDENCE_LISTENING={config.host}:{server.server_address[1]}", flush=True)
    try:
        server.serve_forever(poll_interval=0.25)
    except KeyboardInterrupt:
        return 0
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
