#!/usr/bin/env python3
"""Safely hand off one verified Alipay sandbox order to Finance QA.

The M5 success runner deliberately does not print or persist the order
reference in its public evidence.  This small, post-success handoff bridges
that boundary without putting protected values in a command line, log, or
artifact.  A fixture state file is created by the protected runner and
contains the customer and Finance actor credentials.  This helper reads it,
queries only the serving *development* MySQL container, and atomically adds
the one eligible order number to the same private file.

The SQL projection is intentionally narrow.  It requires a unique order
owned by the fixture customer after the captured baseline, a verified
Alipay-success provider event, the wallet credit, and a balanced first-party
ledger journal.  Zero and multiple matches fail closed.  The order number is
used only in memory and in the protected state file; it never enters stdout,
stderr, a Docker argument, or an exception message.

``--self-test`` is provider-free and does not require Docker, credentials, or
the fixture state file.
"""

from __future__ import annotations

import argparse
import dataclasses
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import tempfile
from typing import Mapping, Sequence


FLOW_SCHEMA_VERSION = "m5-alipay-success-handoff-v1"
FIXTURE_STATE_VERSION = 1
EXPECTED_DEVELOPMENT_MYSQL_CONTAINER = "voice-social-m3-development-mysql-1"

FIXTURE_FIELDS = frozenset(
    {
        "runId",
        "backendSha",
        "customerPhone",
        "customerBearer",
        "customerUserId",
        "reviewerBearer",
        "reviewerUserId",
        "executorBearer",
        "executorUserId",
        "orderBaselineId",
    }
)
STATE_VERSION_FIELDS = frozenset({"schemaVersion", "version"})
HANDOFF_FIELDS = FIXTURE_FIELDS | frozenset({"orderNo"}) | STATE_VERSION_FIELDS

STATE_ENV_NAMES = (
    "QA_M5_ALIPAY_SUCCESS_HANDOFF_STATE_FILE",
    "QA_M5_HANDOFF_STATE_FILE",
    "QA_M5_ALIPAY_FINANCE_STATE_FILE",
    "QA_M5_ALIPAY_SUCCESS_STATE_FILE",
    "QA_M5_FINANCE_FIXTURE_STATE_FILE",
    "QA_M5_REFUND_PROTECTED_STATE_FILE",
)
MYSQL_ENV_NAMES = (
    "QA_M5_ALIPAY_SUCCESS_MYSQL_CONTAINER",
    "QA_M5_HANDOFF_MYSQL_CONTAINER",
    "QA_M5_FINANCE_MYSQL_CONTAINER",
    "QA_M5_REFUND_MYSQL_CONTAINER",
    "QA_M5_MYSQL_CONTAINER",
    "QA_MYSQL_CONTAINER",
)
BACKEND_SHA_ENV_NAMES = (
    "QA_M5_BACKEND_SHA",
    "QA_M5_HANDOFF_BACKEND_SHA",
    "QA_BACKEND_SHA",
    "M5_BACKEND_SHA",
)
RUN_ID_ENV_NAMES = (
    "QA_M5_ALIPAY_SUCCESS_RUN_ID",
    "QA_M5_HANDOFF_RUN_ID",
    "QA_M5_FINANCE_RUN_ID",
    "QA_M5_REFUND_RUN_ID",
)
DOCKER_SOCKET_ENV_NAMES = ("QA_DOCKER_SOCKET", "M5_DOCKER_SOCKET")

SHA1_RE = re.compile(r"^[0-9a-fA-F]{40}$")
ORDER_REF_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:-]{0,79}$")
RUN_ID_RE = re.compile(r"^[A-Za-z0-9_.:-]{1,96}$")
TOKEN_RE = re.compile(r"^[\x21-\x7e]{16,4096}$")

ALLOWED_ERROR_CATEGORIES = frozenset(
    {
        "CONFIGURATION",
        "STATE",
        "DB_UNAVAILABLE",
        "SCHEMA_MISSING",
        "ORDER_NOT_ELIGIBLE",
        "OUTPUT_WRITE",
        "INVARIANT_VIOLATION",
    }
)


class HandoffError(RuntimeError):
    """A safe category that never embeds a protected value."""

    def __init__(self, category: str):
        if category not in ALLOWED_ERROR_CATEGORIES:
            category = "INVARIANT_VIOLATION"
        super().__init__(category)
        self.category = category


@dataclasses.dataclass(frozen=True, repr=False)
class FixtureState:
    """Validated protected fixture state; repr hides every sensitive field."""

    run_id: str = dataclasses.field(repr=False)
    backend_sha: str = dataclasses.field(repr=False)
    customer_phone: str = dataclasses.field(repr=False)
    customer_bearer: str = dataclasses.field(repr=False)
    customer_user_id: int = dataclasses.field(repr=False)
    reviewer_bearer: str = dataclasses.field(repr=False)
    reviewer_user_id: int = dataclasses.field(repr=False)
    executor_bearer: str = dataclasses.field(repr=False)
    executor_user_id: int = dataclasses.field(repr=False)
    order_baseline_id: int = dataclasses.field(repr=False)
    order_no: str | None = dataclasses.field(default=None, repr=False)
    version_key: str | None = dataclasses.field(default=None, repr=False)
    version_value: object = dataclasses.field(default=FIXTURE_STATE_VERSION, repr=False)


@dataclasses.dataclass(frozen=True, repr=False)
class HandoffConfig:
    state_file: Path = dataclasses.field(repr=False)
    mysql_container: str = dataclasses.field(repr=False)
    expected_backend_sha: str = dataclasses.field(repr=False)
    expected_run_id: str = dataclasses.field(repr=False)
    docker_bin: str = dataclasses.field(repr=False)
    docker_env: Mapping[str, str] = dataclasses.field(repr=False)


def _is_int(value: object) -> bool:
    return type(value) is int and value > 0


def _protected_text(value: object, *, max_length: int) -> str:
    if not isinstance(value, str) or not value or len(value) > max_length:
        raise HandoffError("STATE")
    if not value.isascii() or any(ord(character) < 0x20 for character in value):
        raise HandoffError("STATE")
    return value


def _bearer(value: object) -> str:
    raw = _protected_text(value, max_length=4096).strip()
    if raw.startswith("Bearer "):
        raw = raw[7:]
    if not TOKEN_RE.fullmatch(raw):
        raise HandoffError("STATE")
    return "Bearer " + raw


def _require_state_version(value: Mapping[str, object]) -> tuple[str, object]:
    present = [key for key in STATE_VERSION_FIELDS if key in value]
    if len(present) != 1:
        raise HandoffError("STATE")
    key = present[0]
    version = value[key]
    # The fixture producer may use either a numeric v1 marker or its stable
    # string name.  No other schema can enter the handoff boundary.
    if version not in {
        1,
        "1",
        "v1",
        "m5-alipay-finance-fixture-v1",
        "m5-alipay-success-fixture-v1",
        FLOW_SCHEMA_VERSION,
    }:
        raise HandoffError("STATE")
    return key, version


def validate_fixture_state(
    value: object,
    *,
    expected_backend_sha: str,
    expected_run_id: str | None = None,
    require_order: bool = False,
    require_unbound: bool = False,
) -> FixtureState:
    """Validate the private JSON v1 contract without exposing its values."""

    if not isinstance(value, dict):
        raise HandoffError("STATE")
    if not SHA1_RE.fullmatch(expected_backend_sha or ""):
        raise HandoffError("CONFIGURATION")
    keys = set(value)
    if not keys.issubset(HANDOFF_FIELDS) or not FIXTURE_FIELDS.issubset(keys):
        raise HandoffError("STATE")
    version_key, version_value = _require_state_version(value)

    run_id = value.get("runId")
    if not isinstance(run_id, str) or not RUN_ID_RE.fullmatch(run_id):
        raise HandoffError("STATE")
    if expected_run_id is not None and run_id != expected_run_id:
        raise HandoffError("STATE")

    backend_sha = value.get("backendSha")
    if not isinstance(backend_sha, str) or not SHA1_RE.fullmatch(backend_sha):
        raise HandoffError("STATE")
    if backend_sha.lower() != expected_backend_sha.lower():
        raise HandoffError("STATE")

    customer_phone = _protected_text(value.get("customerPhone"), max_length=64)
    customer_bearer = _bearer(value.get("customerBearer"))
    reviewer_bearer = _bearer(value.get("reviewerBearer"))
    executor_bearer = _bearer(value.get("executorBearer"))
    if len({customer_bearer, reviewer_bearer, executor_bearer}) != 3:
        raise HandoffError("STATE")

    user_id = value.get("customerUserId")
    reviewer_id = value.get("reviewerUserId")
    executor_id = value.get("executorUserId")
    baseline_id = value.get("orderBaselineId")
    if not all(_is_int(item) for item in (user_id, reviewer_id, executor_id)):
        raise HandoffError("STATE")
    if type(baseline_id) is not int or baseline_id < 0:
        raise HandoffError("STATE")
    assert isinstance(user_id, int)
    assert isinstance(reviewer_id, int)
    assert isinstance(executor_id, int)
    assert isinstance(baseline_id, int)
    if len({user_id, reviewer_id, executor_id}) != 3:
        raise HandoffError("STATE")

    order_no: str | None = None
    if "orderNo" in value:
        raw_order = value.get("orderNo")
        if not isinstance(raw_order, str) or not ORDER_REF_RE.fullmatch(raw_order):
            raise HandoffError("STATE")
        order_no = raw_order
    if require_order and order_no is None:
        raise HandoffError("STATE")
    if require_unbound and order_no is not None:
        raise HandoffError("STATE")

    return FixtureState(
        run_id=run_id,
        backend_sha=backend_sha.lower(),
        customer_phone=customer_phone,
        customer_bearer=customer_bearer,
        customer_user_id=user_id,
        reviewer_bearer=reviewer_bearer,
        reviewer_user_id=reviewer_id,
        executor_bearer=executor_bearer,
        executor_user_id=executor_id,
        order_baseline_id=baseline_id,
        order_no=order_no,
        version_key=version_key,
        version_value=version_value,
    )


def _secure_parent(path: Path) -> None:
    """Require every state-file path component to be a real private directory."""

    if not path.is_absolute() or str(path) != os.path.normpath(str(path)):
        raise HandoffError("STATE")
    if "\x00" in str(path) or path.name in {"", ".", ".."}:
        raise HandoffError("STATE")
    parent = path.parent
    if not parent.is_absolute() or not parent.exists():
        raise HandoffError("STATE")
    try:
        if os.path.realpath(str(parent)) != str(parent):
            raise HandoffError("STATE")
        current = Path(parent.anchor)
        for part in parent.parts[1:]:
            current /= part
            metadata = current.lstat()
            if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
                raise HandoffError("STATE")
        parent_mode = parent.lstat().st_mode
    except HandoffError:
        raise
    except OSError:
        raise HandoffError("STATE") from None
    if not stat.S_ISDIR(parent_mode) or parent_mode & 0o077:
        raise HandoffError("STATE")


def validate_state_path(raw_path: str) -> Path:
    if not isinstance(raw_path, str) or not raw_path:
        raise HandoffError("CONFIGURATION")
    path = Path(raw_path)
    _secure_parent(path)
    try:
        metadata = path.lstat()
    except OSError:
        raise HandoffError("STATE") from None
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
        raise HandoffError("STATE")
    if stat.S_IMODE(metadata.st_mode) != 0o600:
        raise HandoffError("STATE")
    return path


def _read_json(path: Path) -> object:
    """Open without following a final symlink and verify mode before parsing."""

    try:
        flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0)
        descriptor = os.open(path, flags)
        metadata = os.fstat(descriptor)
        if not stat.S_ISREG(metadata.st_mode) or stat.S_IMODE(metadata.st_mode) != 0o600:
            os.close(descriptor)
            raise HandoffError("STATE")
        with os.fdopen(descriptor, "r", encoding="utf-8") as stream:
            return json.load(stream)
    except HandoffError:
        raise
    except (OSError, UnicodeDecodeError, ValueError, TypeError):
        raise HandoffError("STATE") from None


def _write_json_atomically(path: Path, value: Mapping[str, object]) -> None:
    _secure_parent(path)
    try:
        metadata = path.lstat()
    except OSError:
        raise HandoffError("STATE") from None
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
        raise HandoffError("STATE")
    if stat.S_IMODE(metadata.st_mode) != 0o600:
        raise HandoffError("STATE")
    temporary: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            dir=path.parent,
            prefix=".m5-alipay-success-state-",
            delete=False,
        ) as stream:
            temporary = Path(stream.name)
            os.chmod(temporary, 0o600)
            json.dump(value, stream, sort_keys=True, separators=(",", ":"))
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        # os.replace preserves the temporary mode, but assert the postcondition
        # explicitly so a platform/umask change cannot weaken the boundary.
        if stat.S_IMODE(path.lstat().st_mode) != 0o600 or path.is_symlink():
            raise HandoffError("OUTPUT_WRITE")
    except HandoffError:
        if temporary is not None:
            try:
                temporary.unlink(missing_ok=True)
            except OSError:
                pass
        raise
    except (OSError, TypeError, ValueError):
        if temporary is not None:
            try:
                temporary.unlink(missing_ok=True)
            except OSError:
                pass
        raise HandoffError("OUTPUT_WRITE") from None


def read_state_file(
    path: Path,
    *,
    expected_backend_sha: str,
    expected_run_id: str | None = None,
    require_order: bool = False,
    require_unbound: bool = False,
) -> tuple[FixtureState, dict[str, object]]:
    """Read and validate a state file, returning the validated value privately."""

    validate_state_path(str(path))
    value = _read_json(path)
    if not isinstance(value, dict):
        raise HandoffError("STATE")
    state = validate_fixture_state(
        value,
        expected_backend_sha=expected_backend_sha,
        expected_run_id=expected_run_id,
        require_order=require_order,
        require_unbound=require_unbound,
    )
    return state, dict(value)


def _first_env_value(environment: Mapping[str, str], names: Sequence[str]) -> str:
    values: list[str] = []
    for name in names:
        value = environment.get(name, "")
        if value:
            values.append(value.strip())
    if len(set(values)) > 1:
        raise HandoffError("CONFIGURATION")
    return values[0] if values else ""


def _validate_development_container(value: str) -> str:
    if value != EXPECTED_DEVELOPMENT_MYSQL_CONTAINER:
        raise HandoffError("CONFIGURATION")
    return value


def read_config(environment: Mapping[str, str] | None = None) -> HandoffConfig:
    env = os.environ if environment is None else environment
    state_file_value = _first_env_value(env, STATE_ENV_NAMES)
    if not state_file_value:
        raise HandoffError("CONFIGURATION")
    state_file = validate_state_path(state_file_value)

    expected_backend_sha = _first_env_value(env, BACKEND_SHA_ENV_NAMES)
    if not SHA1_RE.fullmatch(expected_backend_sha or ""):
        raise HandoffError("CONFIGURATION")
    expected_run_id = _first_env_value(env, RUN_ID_ENV_NAMES)
    if not RUN_ID_RE.fullmatch(expected_run_id):
        raise HandoffError("CONFIGURATION")
    mysql_container = _validate_development_container(
        _first_env_value(env, MYSQL_ENV_NAMES)
    )
    docker_bin = shutil.which("docker")
    if not docker_bin:
        raise HandoffError("CONFIGURATION")
    docker_env = {"PATH": env.get("PATH", "/usr/bin:/bin")}
    socket = _first_env_value(env, DOCKER_SOCKET_ENV_NAMES)
    if not socket.startswith("unix://"):
        raise HandoffError("CONFIGURATION")
    socket_path = socket.removeprefix("unix://")
    if not socket_path or not os.path.isabs(socket_path) or os.path.normpath(socket_path) != socket_path:
        raise HandoffError("CONFIGURATION")
    try:
        socket_metadata = os.lstat(socket_path)
    except OSError:
        raise HandoffError("CONFIGURATION") from None
    if not stat.S_ISSOCK(socket_metadata.st_mode):
        raise HandoffError("CONFIGURATION")
    docker_env["DOCKER_HOST"] = socket
    return HandoffConfig(
        state_file=state_file,
        mysql_container=mysql_container,
        expected_backend_sha=expected_backend_sha.lower(),
        expected_run_id=expected_run_id,
        docker_bin=docker_bin,
        docker_env=docker_env,
    )


# This script is passed as a fixed ``/bin/sh -c`` argument.  The only values
# it consumes from stdin are validated positive decimal IDs.  The DB password
# is expanded inside the development container and never crosses the host.
MYSQL_HANDOFF_SCRIPT = r"""
set -eu
database="${MYSQL_DATABASE:-}"
database_user="${MYSQL_USER:-${MYSQL_APP_USER:-root}}"
database_secret="${MYSQL_PASSWORD:-${MYSQL_APP_PASSWORD:-${MYSQL_ROOT_PASSWORD:-}}}"
[ -n "$database" ] && [ -n "$database_secret" ] || exit 20
IFS="$(printf '\t')" read -r customer_user_id order_baseline_id
case "$customer_user_id" in ''|*[!0-9]*) exit 21 ;; esac
case "$order_baseline_id" in ''|*[!0-9]*) exit 22 ;; esac
    [ "$customer_user_id" -gt 0 ] && [ "$order_baseline_id" -ge 0 ] || exit 23

mysql_query() {
  printf '%s\n' "$1" | MYSQL_PWD="$database_secret" mysql \
    --protocol=socket --connect-timeout=5 \
    --user="$database_user" --database="$database" \
    --batch --skip-column-names --raw
}

required_tables="app_user recharge_order payment_provider_event wallet wallet_transaction ledger_journal ledger_posting ledger_account"
for table in $required_tables; do
  count="$(mysql_query "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = '$table'")"
  [ "$count" = 1 ] || { printf '%s\n' SCHEMA_MISSING; exit 0; }
done
printf '%s\n' SCHEMA_OK

# The query deliberately requires all authoritative settlement projections:
# verified provider event, one first-party wallet credit, and a balanced
# PAYMENT_RECHARGE journal owned by the fixture user.  LIMIT 2 preserves the
# distinction between zero, one, and multiple matches without overfetching.
candidate_query="
SELECT o.order_no
FROM recharge_order o
WHERE o.user_id = $customer_user_id
  AND o.id > $order_baseline_id
  AND o.amount_minor > 0
  AND o.gift_coin_amount > 0
  AND o.payment_provider = 'alipay-sandbox'
  AND o.status = 'SUCCEEDED'
  AND o.provider_status IN ('TRADE_SUCCESS', 'TRADE_FINISHED')
  AND o.provider_order_id IS NOT NULL
  AND o.provider_order_id <> ''
  AND (
      SELECT COUNT(*) FROM payment_provider_event pe
      WHERE pe.provider = 'alipay-sandbox'
        AND pe.order_no = o.order_no
  ) = 1
  AND (
      SELECT COUNT(*) FROM payment_provider_event pe
      WHERE pe.provider = 'alipay-sandbox'
        AND pe.order_no = o.order_no
        AND pe.status = 'PROCESSED'
        AND pe.observed_status IN ('TRADE_SUCCESS', 'TRADE_FINISHED')
        AND pe.provider_event_id <> ''
        AND pe.event_fingerprint REGEXP '^[0-9a-fA-F]{64}$'
  ) = 1
  AND (
      SELECT COUNT(*) FROM wallet_transaction wt
      WHERE wt.business_type = 'PAYMENT_RECHARGE'
        AND wt.business_id = o.order_no
  ) = 1
  AND (
      SELECT COUNT(*) FROM wallet_transaction wt
      JOIN wallet w ON w.id = wt.wallet_id
      WHERE wt.business_type = 'PAYMENT_RECHARGE'
        AND wt.business_id = o.order_no
        AND wt.transaction_type = 'CREDIT'
        AND wt.amount_minor = o.gift_coin_amount
        AND w.user_id = o.user_id
        AND w.currency_code = 'GIFT_COIN'
  ) = 1
  AND (
      SELECT COUNT(*) FROM ledger_journal lj
      WHERE lj.actor_user_id = o.user_id
        AND lj.business_type = 'PAYMENT_RECHARGE'
        AND lj.business_id = o.order_no
  ) = 1
  AND EXISTS (
      SELECT 1
      FROM ledger_journal lj
      JOIN ledger_posting lp ON lp.journal_id = lj.id
      JOIN ledger_account la ON la.id = lp.account_id
      WHERE lj.actor_user_id = o.user_id
        AND lj.business_type = 'PAYMENT_RECHARGE'
        AND lj.business_id = o.order_no
      GROUP BY lj.id
      HAVING COUNT(*) = 2
         AND SUM(lp.amount_minor) = 0
         AND SUM(CASE WHEN lp.currency_code = 'GIFT_COIN' THEN 1 ELSE 0 END) = 2
         AND SUM(CASE WHEN la.user_id = o.user_id
                           AND la.account_type = 'USER_AVAILABLE'
                           AND la.currency_code = 'GIFT_COIN'
                           AND lp.amount_minor = o.gift_coin_amount
                      THEN 1 ELSE 0 END) = 1
         AND SUM(CASE WHEN la.user_id IS NULL
                           AND la.account_type = 'SYSTEM_CLEARING'
                           AND la.currency_code = 'GIFT_COIN'
                           AND lp.amount_minor = -o.gift_coin_amount
                      THEN 1 ELSE 0 END) = 1
  )
ORDER BY o.id
LIMIT 2
"
mysql_query "$candidate_query"
unset database_secret MYSQL_PWD
"""


def _run_mysql_query(config: HandoffConfig, state: FixtureState) -> list[str]:
    input_value = f"{state.customer_user_id}\t{state.order_baseline_id}\n"
    try:
        completed = subprocess.run(
            [
                config.docker_bin,
                "exec",
                "-i",
                config.mysql_container,
                "/bin/sh",
                "-c",
                MYSQL_HANDOFF_SCRIPT,
            ],
            cwd="/",
            env=dict(config.docker_env),
            input=input_value,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=90,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        raise HandoffError("DB_UNAVAILABLE") from None
    if completed.returncode != 0:
        raise HandoffError("DB_UNAVAILABLE")
    lines = completed.stdout.splitlines()
    if not lines or lines[0] not in {"SCHEMA_OK", "SCHEMA_MISSING"}:
        raise HandoffError("INVARIANT_VIOLATION")
    if lines[0] == "SCHEMA_MISSING":
        raise HandoffError("SCHEMA_MISSING")
    candidates = [line.strip() for line in lines[1:] if line.strip()]
    if any(not ORDER_REF_RE.fullmatch(candidate) for candidate in candidates):
        raise HandoffError("INVARIANT_VIOLATION")
    if len(candidates) != 1:
        raise HandoffError("ORDER_NOT_ELIGIBLE")
    return candidates


def run_handoff(config: HandoffConfig) -> dict[str, object]:
    state, raw_state = read_state_file(
        config.state_file,
        expected_backend_sha=config.expected_backend_sha,
        expected_run_id=config.expected_run_id,
        require_unbound=True,
    )
    candidates = _run_mysql_query(config, state)
    if len(candidates) != 1:
        raise HandoffError("ORDER_NOT_ELIGIBLE")
    raw_state["orderNo"] = candidates[0]
    _write_json_atomically(config.state_file, raw_state)
    # Do not include the order number, SHA, user ID, phone, or bearer in this
    # result.  The private file is the only handoff channel for those values.
    return {
        "schemaVersion": FLOW_SCHEMA_VERSION,
        "status": "PASS",
        "orderBound": True,
        "provider": "ALIPAY_SANDBOX",
        "settlementVerified": True,
    }


def _public_self_test() -> int:
    if "docker exec -i" not in inspect_command_source():
        raise AssertionError("stdin Docker boundary missing")
    if "MYSQL_PWD=\"$database_secret\"" not in MYSQL_HANDOFF_SCRIPT:
        raise AssertionError("container-only database secret boundary missing")
    for forbidden in ("SELECT o.user_id", "SELECT o.provider_order_id", "Bearer"):
        if forbidden in MYSQL_HANDOFF_SCRIPT:
            raise AssertionError("raw protected projection added")
    temporary_root = "/private/tmp" if os.path.isdir("/private/tmp") else None
    with tempfile.TemporaryDirectory(
        prefix="m5-success-handoff-self-test-", dir=temporary_root
    ) as directory:
        private = Path(directory)
        os.chmod(private, 0o700)
        state_path = private / "fixture.json"
        state_path.write_text(
            json.dumps(
                {
                    "schemaVersion": FIXTURE_STATE_VERSION,
                    "runId": "m5-success-self-test",
                    "backendSha": "a" * 40,
                    "customerPhone": "fixture-customer-phone",
                    "customerBearer": "customer-token-value",
                    "customerUserId": 1,
                    "reviewerBearer": "reviewer-token-value",
                    "reviewerUserId": 2,
                    "executorBearer": "executor-token-value",
                    "executorUserId": 3,
                    "orderBaselineId": 1,
                }
            ),
            encoding="utf-8",
        )
        os.chmod(state_path, 0o600)
        state, _ = read_state_file(
            state_path,
            expected_backend_sha="a" * 40,
            expected_run_id="m5-success-self-test",
            require_unbound=True,
        )
        if state.customer_user_id != 1 or state.order_no is not None:
            raise AssertionError("fixture state validation changed")
        try:
            validate_fixture_state(
                {
                    "schemaVersion": FIXTURE_STATE_VERSION,
                    "runId": "m5-success-self-test",
                    "backendSha": "a" * 40,
                    "customerPhone": "fixture-customer-phone",
                    "customerBearer": "same-token-value",
                    "customerUserId": 1,
                    "reviewerBearer": "same-token-value",
                    "reviewerUserId": 2,
                    "executorBearer": "executor-token-value",
                    "executorUserId": 3,
                    "orderBaselineId": 1,
                },
                expected_backend_sha="a" * 40,
            )
        except HandoffError:
            pass
        else:
            raise AssertionError("duplicate bearer accepted")
    print("self-test=PASS")
    return 0


def inspect_command_source() -> str:
    return "docker exec -i development-mysql /bin/sh -c fixed-script; protected IDs via stdin"


def _parser() -> argparse.ArgumentParser:
    class _SafeArgumentParser(argparse.ArgumentParser):
        def error(self, _message: str) -> None:
            raise HandoffError("CONFIGURATION")

    parser = _SafeArgumentParser(
        description="Bind exactly one verified Alipay sandbox order to a private Finance fixture state"
    )
    modes = parser.add_mutually_exclusive_group(required=True)
    modes.add_argument("--self-test", action="store_true")
    modes.add_argument("--run", action="store_true")
    return parser


def _emit(value: Mapping[str, object]) -> None:
    print(json.dumps(value, sort_keys=True, separators=(",", ":")))


def main(argv: Sequence[str] | None = None) -> int:
    try:
        args = _parser().parse_args(list(argv) if argv is not None else None)
    except SystemExit as error:
        return int(error.code)
    except HandoffError:
        _emit(
            {
                "schemaVersion": FLOW_SCHEMA_VERSION,
                "status": "FAIL",
                "category": "CONFIGURATION",
                "orderBound": False,
            }
        )
        return 2
    if args.self_test:
        try:
            return _public_self_test()
        except AssertionError:
            print("self-test=FAIL")
            return 1
    try:
        config = read_config()
        _emit(run_handoff(config))
        return 0
    except HandoffError as error:
        _emit(
            {
                "schemaVersion": FLOW_SCHEMA_VERSION,
                "status": "FAIL",
                "category": error.category,
                "orderBound": False,
            }
        )
        return 2
    except Exception:
        # Unexpected parser/filesystem/library failures must not leak a state
        # value or traceback into the operator console.
        _emit(
            {
                "schemaVersion": FLOW_SCHEMA_VERSION,
                "status": "FAIL",
                "category": "INVARIANT_VIOLATION",
                "orderBound": False,
            }
        )
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
