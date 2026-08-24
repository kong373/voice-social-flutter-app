#!/usr/bin/env python3
"""Loopback-only, read-only DB evidence endpoint for the M4 AVD runner.

MySQL is queried only from inside the configured MySQL container. The database
password is expanded there and is never a host subprocess argument or response
field. The HTTP response contains aggregate counters and boolean invariants
only. A read-only aggregate baseline is captured before the loopback listener
binds; successful responses expose only non-negative first-party write deltas
from the exact per-AVD snapshot. Fixture-scoped counters are resolved through
the independently derived nickname and never expose a user id or phone.
Use --self-test to run local tests without Docker or runtime settings.
"""

from __future__ import annotations

import dataclasses
import hashlib
import hmac
import http.server
import json
import os
import re
import secrets as secrets_module
import shutil
import shlex
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
    # QA_BACKEND_SHA is the documented, protected runtime input. The legacy
    # aliases remain accepted only through _first_value(), which rejects any
    # conflicting non-empty value.
    "QA_BACKEND_SHA",
    "M4_EXPECTED_BACKEND_SHA",
    "M4_DB_EVIDENCE_EXPECTED_BACKEND_SHA",
    "QA_EXPECTED_BACKEND_SHA",
)
BACKEND_REPO_ENV_NAMES = (
    "QA_BACKEND_REPO",
    "M4_BACKEND_REPO",
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
        "scopedCounters",
    }
)
CONTAINER_NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$")
SHA_RE = re.compile(r"^[0-9a-fA-F]{40}$")
CONTENT_DIGEST_RE = re.compile(r"^[0-9a-fA-F]{64}$")
COUNT_RE = re.compile(r"^[0-9]+$")
RUN_ID_RE = re.compile(r"^[A-Za-z0-9_.:-]{1,80}$")
AVD_RE = re.compile(r"^AVD-[AB]$")
START_NONCE_RE = re.compile(r"^[A-Za-z0-9_.~=-]{16,256}$")
MARKER_RE = re.compile(r"^[CFIOPS](?:\|[A-Za-z0-9_.-]+|\|[0-9]+){1,6}$")
WRITE_COUNTER_KEYS = (
    "auth_sessions",
    "room_activity",
    "commerce_activity",
    "social_community_messages",
    "social_user_reports",
    "idempotency_audit",
)
SCOPED_COUNTER_KEYS = (
    "refresh_session_user",
    "user_report_reporter",
    "operation_idempotency_actor",
)
FIXTURE_ID_RE = re.compile(r"^m4-fresh-[A-Za-z0-9_.:-]{1,64}$")
FIXTURE_NICKNAME_RE = re.compile(r"^m4-[0-9a-f]{16}$")
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


def _fixture_nickname(fixture_id: str) -> str:
    if not FIXTURE_ID_RE.fullmatch(fixture_id):
        raise EvidenceError("invalid fixture id")
    digest = hashlib.sha256(fixture_id.encode("utf-8")).hexdigest()
    nickname = "m4-" + digest[:16]
    if not FIXTURE_NICKNAME_RE.fullmatch(nickname):
        raise EvidenceError("fixture nickname derivation failed")
    return nickname


def _valid_bearer_header(values: Sequence[str], token: str) -> bool:
    if len(values) != 1:
        return False
    value = values[0]
    prefix = "Bearer "
    presented = value[len(prefix):] if value.startswith(prefix) else ""
    # compare_digest is intentional, including for malformed prefixes.
    return _constant_time_equal(presented, token) and value.startswith(prefix)


def _run_checked_command(
    arguments: Sequence[str],
    *,
    cwd: str = "/",
    timeout: float = 12.0,
    environment: Mapping[str, str] | None = None,
) -> str:
    """Run a local attestation command without exposing its diagnostics."""

    try:
        completed = subprocess.run(
            list(arguments),
            cwd=cwd,
            env=dict(environment or {"PATH": os.environ.get("PATH", "/usr/bin:/bin")}),
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=timeout,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise ConfigurationError("backend attestation command unavailable") from error
    if completed.returncode != 0:
        raise ConfigurationError("backend attestation command failed")
    return completed.stdout


def _attest_backend_checkout(repo: str, expected_sha: str) -> tuple[str, str]:
    """Return (real checkout path, source digest) for an immutable checkout.

    The commit SHA is checked with Git and the content digest is produced by
    the tracked backend script. Ignored build output is intentionally absent
    from ``git status``; tracked edits and non-ignored untracked inputs are not.
    """

    repo_path = os.path.realpath(repo)
    if not os.path.isdir(repo_path) or not os.path.exists(os.path.join(repo_path, ".git")):
        raise ConfigurationError("backend repository is unavailable")
    git_path = shutil.which("git")
    if not git_path:
        raise ConfigurationError("git command is unavailable")
    command_environment = {"PATH": os.environ.get("PATH", "/usr/bin:/bin")}
    head = _run_checked_command(
        [git_path, "-C", repo_path, "rev-parse", "--verify", "HEAD"],
        environment=command_environment,
    ).strip()
    if not SHA_RE.fullmatch(head) or not _constant_time_equal(head.lower(), expected_sha.lower()):
        raise ConfigurationError("backend repository SHA mismatch")
    status = _run_checked_command(
        [
            git_path,
            "-C",
            repo_path,
            "status",
            "--porcelain=v1",
            "--untracked-files=all",
            "--ignore-submodules=none",
        ],
        environment=command_environment,
    )
    if status.strip():
        raise ConfigurationError("backend repository is dirty")
    ignored_status = _run_checked_command(
        [
            git_path,
            "-C",
            repo_path,
            "status",
            "--porcelain=v1",
            "--ignored=matching",
            "--untracked-files=all",
            "--ignore-submodules=none",
        ],
        environment=command_environment,
    )
    for line in ignored_status.splitlines():
        if not line.startswith("!! "):
            continue
        ignored_path = line[3:].rstrip("/")
        if ignored_path == ".mvn" or ignored_path.startswith(".mvn/"):
            raise ConfigurationError("ignored backend build input")
        if ignored_path == "src" or ignored_path.startswith("src/"):
            raise ConfigurationError("ignored backend build input")
    digest_script = os.path.join(repo_path, "scripts", "compute-backend-source-digest.sh")
    if not os.path.isfile(digest_script) or not os.access(digest_script, os.X_OK):
        raise ConfigurationError("backend source digest script is unavailable")
    for tracked_input in (
        "Dockerfile",
        "mvnw",
        "pom.xml",
        "scripts/compute-backend-source-digest.sh",
    ):
        _run_checked_command(
            [git_path, "-C", repo_path, "ls-files", "--error-unmatch", "--", tracked_input],
            environment=command_environment,
        )
    digest_output = _run_checked_command(
        [digest_script],
        cwd=repo_path,
        timeout=30.0,
        environment=command_environment,
    )
    digest_lines = [line.strip() for line in digest_output.splitlines() if line.strip()]
    if len(digest_lines) != 1 or not CONTENT_DIGEST_RE.fullmatch(digest_lines[0]):
        raise ConfigurationError("backend source digest is invalid")
    return repo_path, digest_lines[0].lower()


@dataclasses.dataclass(frozen=True)
class Config:
    host: str
    port: int
    token: str
    docker_bin: str
    docker_env: Mapping[str, str]
    backend_container: str
    mysql_container: str
    backend_repo: str
    expected_backend_sha: str
    expected_backend_digest: str


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
    expected_sha = _first_value(env, EXPECTED_SHA_ENV_NAMES)
    if not SHA_RE.fullmatch(expected_sha or ""):
        raise ConfigurationError("invalid expected backend SHA")
    backend_repo = _first_value(env, BACKEND_REPO_ENV_NAMES)
    if not backend_repo:
        raise ConfigurationError("backend repository is required")
    backend_repo, expected_digest = _attest_backend_checkout(backend_repo, expected_sha)
    docker_path = shutil.which("docker")
    if not docker_path:
        raise ConfigurationError("docker command is unavailable")
    # Do not inherit unrelated host environment values. When no socket is
    # supplied, the Docker CLI's configured local context is used.
    docker_env = {"PATH": env.get("PATH", "/usr/bin:/bin")}
    if docker_socket:
        docker_env["DOCKER_HOST"] = docker_socket

    return Config(
        host=LOOPBACK_HOST,
        port=port,
        token=token,
        docker_bin=docker_path,
        docker_env=docker_env,
        backend_container=backend_container,
        mysql_container=mysql_container,
        backend_repo=backend_repo,
        expected_backend_sha=expected_sha.lower(),
        expected_backend_digest=expected_digest,
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

    def read_backend_source_digest(self, container: str) -> str:
        """Read the image's explicit source-content attestation file."""

        value = self.exec_shell(
            container,
            "test -f /app/backend-source.sha256 && cat /app/backend-source.sha256",
            timeout=8.0,
        ).strip()
        if not CONTENT_DIGEST_RE.fullmatch(value):
            raise EvidenceError("backend source digest is missing or invalid")
        return value.lower()

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

fixture_nickname="\${M4_FIXTURE_NICKNAME:-m4-no-fixture}"
case "\$fixture_nickname" in
  m4-[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) ;;
  m4-no-fixture) ;;
  *) exit 29 ;;
esac

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

fixture_account_count=0
if [ "\$(table_exists m4_development_fixture_user)" = 1 ] && [ "\$(table_exists app_user)" = 1 ]; then
  value="\$(mysql_query "SELECT COUNT(*) FROM m4_development_fixture_user f JOIN app_user u ON u.id = f.user_id WHERE u.nickname = '\$fixture_nickname'")"
  case "\$value" in *[!0-9]*|"") exit 34 ;; *) fixture_account_count="\$value" ;; esac
fi
printf 'F|%s\n' "\$fixture_account_count"

scoped_count() {
  label="\$1"
  table="\$2"
  column="\$3"
  value=0
  if [ "\$fixture_account_count" -gt 0 ] && [ "\$(table_exists "\$table")" = 1 ] && column_exists "\$table" "\$column" && [ "\$(table_exists m4_development_fixture_user)" = 1 ] && [ "\$(table_exists app_user)" = 1 ]; then
    value="\$(mysql_query "SELECT COUNT(*) FROM \$table WHERE \$column IN (SELECT f.user_id FROM m4_development_fixture_user f JOIN app_user u ON u.id = f.user_id WHERE u.nickname = '\$fixture_nickname'")"
    case "\$value" in *[!0-9]*|"") exit 35 ;; esac
  fi
  printf 'S|%s|%s\n' "\$label" "\$value"
}

# These counters are deliberately scoped through the fixture account. Global
# table deltas are retained as context only; they can never satisfy the live
# evidence gate on their own.
scoped_count refresh_session_user refresh_session user_id
scoped_count user_report_reporter user_report reporter_user_id
scoped_count operation_idempotency_actor operation_idempotency actor_user_id

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
  [ "$value" = development_outbox ]
}

development_environment() {
  value="$(printenv APP_ENV 2>/dev/null || true)"
  [ "$value" = development ]
}

development_profile() {
  value="$(printenv SPRING_PROFILES_ACTIVE 2>/dev/null || true)"
  [ "$value" = development ]
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
""".strip()

def _parse_marker_lines(output: str) -> list[list[str]]:
    lines = output.splitlines()
    if not lines or any(not line or not MARKER_RE.fullmatch(line) for line in lines):
        raise EvidenceError("invalid aggregate evidence")
    return [line.split("|") for line in lines]


def _parse_backend_evidence(output: str) -> dict[str, bool]:
    states: dict[str, bool] = {}
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
    return states


def _parse_mysql_evidence(output: str) -> dict[str, int]:
    counters: dict[str, int] = {}
    for fields in _parse_marker_lines(output):
        marker = fields[0]
        if marker == "F" and len(fields) == 2 and COUNT_RE.fullmatch(fields[1]):
            counters["fixture_account_count"] = int(fields[1])
        elif marker == "S" and len(fields) == 3:
            if fields[1] not in SCOPED_COUNTER_KEYS or not COUNT_RE.fullmatch(fields[2]):
                raise EvidenceError("invalid scoped fixture counter evidence")
            counters[fields[1]] = int(fields[2])
        elif marker == "C" and len(fields) == 3:
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
        "fixture_account_count",
        *SCOPED_COUNTER_KEYS,
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
    scoped_counters: Mapping[str, int]
    fixture_account_count: int
    database_invariants: Mapping[str, bool]
    provider_evidence: int
    backend_sha_ok: bool


def _counter_delta(
    current: Mapping[str, int],
    baseline: Mapping[str, int],
    keys: Sequence[str] = WRITE_COUNTER_KEYS,
) -> dict[str, int]:
    if set(current) != set(keys) or set(baseline) != set(keys):
        raise EvidenceError("incomplete write counter snapshot")
    delta: dict[str, int] = {}
    for key in keys:
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


def _require_scoped_writes(delta: Mapping[str, int]) -> int:
    if set(delta) != set(SCOPED_COUNTER_KEYS) or any(
        value < 0 for value in delta.values()
    ):
        raise EvidenceError("invalid scoped fixture counter delta")
    if any(delta[key] <= 0 for key in SCOPED_COUNTER_KEYS):
        raise EvidenceError("fixture-scoped mutation evidence is missing")
    return sum(delta.values())


def _backend_sha_matches(
    runner: DockerRunner,
    config: Config,
) -> bool:
    actual_digest = runner.read_backend_source_digest(config.backend_container)
    if not _constant_time_equal(actual_digest, config.expected_backend_digest):
        return False

    # OCI revision labels are useful corroboration, but they are not the
    # attestation. A missing label is allowed; a present, well-formed label
    # that disagrees with the independently verified checkout is rejected.
    expected = config.expected_backend_sha
    labels = runner.inspect_labels(config.backend_container)
    for key in (
        "org.opencontainers.image.revision",
        "org.opencontainers.image.source-revision",
        "org.opencontainers.image.commit",
        "com.openai.backend.sha",
    ):
        value = labels.get(key, "")
        if SHA_RE.fullmatch(value):
            if not _constant_time_equal(value.lower(), expected):
                return False
    return True


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
    scoped = payload.get("scopedCounters")
    if not isinstance(scoped, dict) or set(scoped) != set(SCOPED_COUNTER_KEYS):
        raise EvidenceError("scoped fixture counter keys are not fixed")
    if any(type(value) is not int or value <= 0 for value in scoped.values()):
        raise EvidenceError("scoped fixture mutation evidence is missing")
    invariants = payload.get("authorityInvariants")
    actual_invariant_keys = set(invariants) if isinstance(invariants, dict) else set()
    required_invariants = REQUIRED_INVARIANT_KEYS | {"expected_backend_sha_matches"}
    if actual_invariant_keys != required_invariants:
        raise EvidenceError("authority invariant keys are not fixed")
    if any(value is not True for value in invariants.values()):
        raise EvidenceError("first-party write evidence is missing")
    if payload.get("providerCalls") != 0 or type(payload.get("providerCalls")) is not int:
        raise EvidenceError("provider calls are not zero")
    binding = payload.get("evidenceBinding")
    if not isinstance(binding, dict) or set(binding) != {
        "runId", "avd", "startNonce", "fixtureId", "fixtureAccountState", "mutationKeys"
    }:
        raise EvidenceError("evidence binding is missing")
    if (
        not isinstance(binding["runId"], str)
        or not RUN_ID_RE.fullmatch(binding["runId"])
        or not isinstance(binding["avd"], str)
        or not AVD_RE.fullmatch(binding["avd"])
        or not isinstance(binding["startNonce"], str)
        or not START_NONCE_RE.fullmatch(binding["startNonce"])
        or not isinstance(binding["fixtureId"], str)
        or not FIXTURE_ID_RE.fullmatch(binding["fixtureId"])
        or binding["fixtureAccountState"] not in {
            "created_during_run",
            "preexisting_fixture",
        }
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
    fixture_id: str
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

    def _capture_snapshot(self, fixture_id: str | None = None) -> EvidenceSnapshot:
        fixture_nickname = "m4-no-fixture"
        if fixture_id is not None:
            fixture_nickname = _fixture_nickname(fixture_id)
        backend_output = self._docker.exec_shell(
            self._config.backend_container,
            BACKEND_EVIDENCE_SCRIPT,
            timeout=12.0,
        )
        backend_states = _parse_backend_evidence(backend_output)
        backend_sha_ok = _backend_sha_matches(self._docker, self._config)
        if not backend_sha_ok:
            raise EvidenceError("backend SHA mismatch")

        mysql_script = (
            "M4_FIXTURE_NICKNAME="
            + shlex.quote(fixture_nickname)
            + "\nexport M4_FIXTURE_NICKNAME\n"
            + MYSQL_EVIDENCE_SCRIPT
        )
        mysql_output = self._docker.exec_shell(
            self._config.mysql_container,
            mysql_script,
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
        scoped_counters = {key: database[key] for key in SCOPED_COUNTER_KEYS}
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
            scoped_counters=scoped_counters,
            fixture_account_count=database["fixture_account_count"],
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

    def start(self, run_id: str, avd: str, fixture_id: str) -> Mapping[str, object]:
        with self._lock:
            if not RUN_ID_RE.fullmatch(run_id) or not AVD_RE.fullmatch(avd):
                raise EvidenceError("evidence context is invalid")
            _fixture_nickname(fixture_id)
            key = (run_id, avd)
            if key in self._starts:
                raise EvidenceError("evidence context already started")
            snapshot = self._capture_snapshot(fixture_id)
            expected_count = 0 if avd == "AVD-A" else 1
            if snapshot.fixture_account_count != expected_count:
                raise EvidenceError("fixture account start state is invalid")
            start_nonce = secrets_module.token_urlsafe(24)
            if not START_NONCE_RE.fullmatch(start_nonce):
                raise EvidenceError("evidence nonce generation failed")
            self._starts[key] = EvidenceStart(
                run_id=run_id,
                avd=avd,
                fixture_id=fixture_id,
                start_nonce=start_nonce,
                snapshot=snapshot,
            )
            return {
                "status": "STARTED",
                "runId": run_id,
                "avd": avd,
                "fixtureId": fixture_id,
                "fixtureAccountState": (
                    "absent_at_start" if avd == "AVD-A" else "present_at_start"
                ),
                "startNonce": start_nonce,
            }

    def collect(
        self,
        run_id: str,
        avd: str,
        start_nonce: str,
        fixture_id: str,
    ) -> Mapping[str, object]:
        with self._lock:
            if not RUN_ID_RE.fullmatch(run_id) or not AVD_RE.fullmatch(avd):
                raise EvidenceError("evidence context is invalid")
            if not START_NONCE_RE.fullmatch(start_nonce):
                raise EvidenceError("evidence nonce is invalid")
            _fixture_nickname(fixture_id)
            start = self._starts.get((run_id, avd))
            if start is None or start.consumed or not hmac.compare_digest(
                start.start_nonce, start_nonce
            ):
                raise EvidenceError("evidence context is stale or unrelated")
            if not _constant_time_equal(start.fixture_id, fixture_id):
                raise EvidenceError("fixture binding is stale or unrelated")
            current = self._capture_snapshot(fixture_id)
            if current.fixture_account_count != 1:
                raise EvidenceError("fixture account collect state is invalid")
            expected_start_count = 0 if avd == "AVD-A" else 1
            if start.snapshot.fixture_account_count != expected_start_count:
                raise EvidenceError("fixture account start state changed")
            if avd == "AVD-A" and current.fixture_account_count != 1:
                raise EvidenceError("new fixture account was not established")
            delta = _counter_delta(current.counters, start.snapshot.counters)
            write_total = _require_new_writes(delta)
            scoped_delta = _counter_delta(
                current.scoped_counters,
                start.snapshot.scoped_counters,
                SCOPED_COUNTER_KEYS,
            )
            _require_scoped_writes(scoped_delta)

            invariants = dict(current.database_invariants)
            invariants.update(
                {
                    "backend_environment_development": current.backend_states["backend_environment"],
                    "backend_profile_development": current.backend_states["backend_profile"],
                    "development_outbox_or_blocked_sms": current.backend_states["development_outbox_mode"],
                    "formal_vendor_adapters_blocked": current.backend_states["formal_vendor_adapters_disabled"],
                    "provider_invocation_rows_zero": current.provider_evidence == 0,
                    "first_party_writes_observed_since_start": write_total > 0,
                    "expected_backend_sha_matches": current.backend_sha_ok,
                }
            )
            payload: Mapping[str, object] = {
                "status": "OK",
                "writeCounters": delta,
                "scopedCounters": scoped_delta,
                "authorityInvariants": invariants,
                "providerCalls": current.provider_evidence,
                "secrets": False,
                "evidenceBinding": {
                    "runId": run_id,
                    "avd": avd,
                    "startNonce": start_nonce,
                    "fixtureId": fixture_id,
                    "fixtureAccountState": (
                        "created_during_run"
                        if avd == "AVD-A"
                        else "preexisting_fixture"
                    ),
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
        fixture_id = self._single_header("X-M4-Fixture-ID")
        start_nonce = self._single_header("X-M4-Start-Nonce")
        if (
            not RUN_ID_RE.fullmatch(run_id)
            or not AVD_RE.fullmatch(avd)
            or not FIXTURE_ID_RE.fullmatch(fixture_id)
        ):
            self._json(400, {"status": "BAD_REQUEST"})
            return
        try:
            if phase == "start" and not start_nonce:
                payload = self.server.collector.start(run_id, avd, fixture_id)
                self._json(201, payload)
                return
            if phase == "collect" and START_NONCE_RE.fullmatch(start_nonce):
                payload = self.server.collector.collect(
                    run_id, avd, start_nonce, fixture_id
                )
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
    try:
        read_config(
            {
                "M4_DB_EVIDENCE_TOKEN": token,
                "M4_DB_EVIDENCE_BACKEND_CONTAINER": "backend",
                "M4_DB_EVIDENCE_MYSQL_CONTAINER": "mysql",
                "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
            }
        )
    except ConfigurationError:
        pass
    else:
        raise AssertionError("missing expected backend SHA was accepted")
    try:
        read_config(
            {
                "M4_DB_EVIDENCE_TOKEN": token,
                "QA_BACKEND_SHA": "1" * 40,
                "M4_DB_EVIDENCE_BACKEND_CONTAINER": "backend",
                "M4_DB_EVIDENCE_MYSQL_CONTAINER": "mysql",
                "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
            }
        )
    except ConfigurationError:
        pass
    else:
        raise AssertionError("missing backend repository was accepted")

    backend_output = "\n".join(
        [
            "I|backend_environment|1",
            "I|backend_profile|1",
            "I|development_outbox_mode|1",
            "I|formal_vendor_adapters_disabled|1",
        ]
    )
    backend_states = _parse_backend_evidence(backend_output)
    if not all(backend_states.values()):
        raise AssertionError("backend evidence parser failed")

    attestation_config = Config(
        host=LOOPBACK_HOST,
        port=0,
        token=token,
        docker_bin="docker",
        docker_env={},
        backend_container="backend",
        mysql_container="mysql",
        backend_repo="/backend",
        expected_backend_sha="2" * 40,
        expected_backend_digest="3" * 64,
    )

    class FakeAttestationRunner:
        def __init__(self, digest: str, labels: Mapping[str, str]):
            self.digest = digest
            self.labels = labels

        def read_backend_source_digest(self, _container: str) -> str:
            return self.digest

        def inspect_labels(self, _container: str) -> Mapping[str, str]:
            return self.labels

    if not _backend_sha_matches(
        FakeAttestationRunner("3" * 64, {}), attestation_config
    ):
        raise AssertionError("valid source digest attestation was rejected")
    if _backend_sha_matches(
        FakeAttestationRunner(
            "3" * 64,
            {"org.opencontainers.image.revision": "2" * 40},
        ),
        dataclasses.replace(attestation_config, expected_backend_digest="4" * 64),
    ):
        raise AssertionError("OCI label was accepted without matching content digest")
    if _backend_sha_matches(
        FakeAttestationRunner(
            "3" * 64,
            {"org.opencontainers.image.revision": "1" * 40},
        ),
        attestation_config,
    ):
        raise AssertionError("mismatched OCI corroboration was accepted")

    mysql_output = "\n".join(
        [
            "C|auth_sessions|2",
            "C|room_activity|4",
            "C|commerce_activity|6",
            "C|social_community_messages|5",
            "C|social_user_reports|1",
            "C|idempotency_audit|3",
            "F|1",
            "S|refresh_session_user|1",
            "S|user_report_reporter|1",
            "S|operation_idempotency_actor|1",
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
        "scopedCounters": {key: 1 for key in SCOPED_COUNTER_KEYS},
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
            "expected_backend_sha_matches": True,
        },
        "providerCalls": 0,
        "secrets": False,
        "evidenceBinding": {
            "runId": "m4-self-test",
            "avd": "AVD-A",
            "startNonce": "N" * 32,
            "fixtureId": "m4-fresh-self-test",
            "fixtureAccountState": "created_during_run",
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
        scoped_counters={key: 10 for key in SCOPED_COUNTER_KEYS},
        fixture_account_count=0,
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
                    backend_repo="/backend",
                    expected_backend_sha="2" * 40,
                    expected_backend_digest="3" * 64,
                )
            )
            self._snapshots = [base_snapshot, next_snapshot]

        def _capture_snapshot(self, _fixture_id: str | None = None) -> EvidenceSnapshot:
            return self._snapshots.pop(0)

    fake_collector = FakeCollector()
    fake_collector._snapshots[0] = dataclasses.replace(
        fake_collector._snapshots[0], fixture_account_count=0
    )
    fake_collector._snapshots[1] = dataclasses.replace(
        fake_collector._snapshots[1],
        fixture_account_count=1,
        scoped_counters={key: 11 for key in SCOPED_COUNTER_KEYS},
    )
    started = fake_collector.start("m4-self-test", "AVD-A", "m4-fresh-self-test")
    nonce = started["startNonce"]
    collected = fake_collector.collect(
        "m4-self-test", "AVD-A", nonce, "m4-fresh-self-test"
    )
    if collected["evidenceBinding"]["runId"] != "m4-self-test":
        raise AssertionError("run binding was not echoed")
    try:
        fake_collector.collect(
            "m4-self-test", "AVD-A", nonce, "m4-fresh-self-test"
        )
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
    for forbidden in ("BACKEND_SHA", "QA_BACKEND_SHA", "BUILD_SHA"):
        if forbidden in BACKEND_EVIDENCE_SCRIPT:
            raise AssertionError("container SHA environment attestation is accepted")
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
