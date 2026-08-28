#!/usr/bin/env python3
"""Provision a private development finance fixture for M5 Alipay QA.

The fixture is deliberately smaller than an acceptance runner.  It creates
three synthetic first-party accounts through the public development auth
contract, grants two of them narrowly-scoped operations roles in the local
development MySQL container, and logs in again so the role-bearing tokens are
the ones persisted for a later four-eyes test.

This is a QA-only utility.  ``--self-test`` is provider-free.  ``--run``
accepts only a loopback development backend with the SMS vendor explicitly
disabled.  All runtime values are injected through the environment; no
runtime option accepts a phone, challenge, code, token, or database secret.
The state file is intentionally private and is not an artifact.  It contains
the exact hand-off values required by the next QA phase, while stdout/stderr
contains only a fixed redacted result.
"""

from __future__ import annotations

import argparse
import dataclasses
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
from typing import Any, Mapping, Sequence
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode, urlsplit
from urllib.request import (
    HTTPRedirectHandler,
    OpenerDirector,
    ProxyHandler,
    Request,
    build_opener,
)


SCHEMA_VERSION = 1
FLOW_SCHEMA_VERSION = "m5-alipay-dev-finance-fixture-v1"

RUN_ID_RE = re.compile(r"^[A-Za-z0-9_.:-]{1,96}$")
SHA1_RE = re.compile(r"^[0-9a-f]{40}$")
PHONE_RE = re.compile(r"^1[3-9][0-9]{9}$")
CLIENT_ID_RE = re.compile(r"^[\x21-\x7e]{1,160}$")
TOKEN_RE = re.compile(r"^[\x21-\x7e]{16,4096}$")
CHALLENGE_RE = re.compile(r"^[A-Za-z0-9._:-]{1,256}$")
CONTAINER_NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$")
DECIMAL_ID_RE = re.compile(r"^[1-9][0-9]{0,18}$")
BASELINE_RE = re.compile(r"^(0|[1-9][0-9]{0,18})$")

ROLE_USER = "ROLE_USER"
ROLE_FINANCE_APPROVER = "ROLE_OPS_FINANCE_APPROVER"
ROLE_FINANCE_EXECUTOR = "ROLE_OPS_FINANCE"

ALLOWED_ERROR_CATEGORIES = frozenset(
    {
        "CONFIGURATION",
        "API_UNAVAILABLE",
        "API_CONTRACT",
        "DB_UNAVAILABLE",
        "DB_CONTRACT",
        "STATE",
        "OUTPUT_WRITE",
        "INVARIANT_VIOLATION",
    }
)

STATE_KEYS = frozenset(
    {
        "schemaVersion",
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

# The names are intentionally QA-specific first.  The short aliases make the
# helper usable from the existing protected M5 runner without putting values
# on a command line.  A conflicting alias is rejected instead of guessed.
RUN_ID_ENV = (
    "QA_M5_FINANCE_RUN_ID",
    "M5_FINANCE_RUN_ID",
    "QA_FINANCE_FIXTURE_RUN_ID",
)
BACKEND_URL_ENV = (
    "QA_M5_FINANCE_BACKEND_URL",
    "M5_FINANCE_BACKEND_URL",
    "QA_BACKEND_URL",
)
BACKEND_SHA_ENV = (
    "QA_M5_FINANCE_BACKEND_SHA",
    "M5_FINANCE_BACKEND_SHA",
    "QA_BACKEND_SHA",
    "M5_BACKEND_SHA",
)
PROFILE_ENV = (
    "QA_M5_FINANCE_PROFILE",
    "M5_FINANCE_PROFILE",
    "APP_ENV",
)
SMS_VENDOR_ENABLED_ENV = (
    "QA_M5_FINANCE_SMS_VENDOR_ENABLED",
    "M5_FINANCE_SMS_VENDOR_ENABLED",
    "VENDOR_SMS_ADAPTER_ENABLED",
)
CUSTOMER_PHONE_ENV = (
    "QA_M5_FINANCE_CUSTOMER_PHONE",
    "M5_FINANCE_CUSTOMER_PHONE",
)
REVIEWER_PHONE_ENV = (
    "QA_M5_FINANCE_REVIEWER_PHONE",
    "M5_FINANCE_REVIEWER_PHONE",
)
EXECUTOR_PHONE_ENV = (
    "QA_M5_FINANCE_EXECUTOR_PHONE",
    "M5_FINANCE_EXECUTOR_PHONE",
)
PUBLIC_CLIENT_ENV = (
    "QA_M5_FINANCE_PUBLIC_CLIENT_ID",
    "M5_FINANCE_PUBLIC_CLIENT_ID",
    "QA_OAUTH_CLIENT_ID",
)
MYSQL_CONTAINER_ENV = (
    "QA_M5_FINANCE_MYSQL_CONTAINER",
    "M5_FINANCE_MYSQL_CONTAINER",
    "M5_MYSQL_CONTAINER",
    "QA_MYSQL_CONTAINER",
)
STATE_FILE_ENV = (
    "QA_M5_FINANCE_STATE_FILE",
    "M5_FINANCE_STATE_FILE",
    "QA_M5_FINANCE_STATE_PATH",
)
SYNTHETIC_MARKER_ENV = (
    "QA_M5_FINANCE_SYNTHETIC_PHONES",
    "M5_FINANCE_SYNTHETIC_PHONES",
)


class FinanceFixtureError(RuntimeError):
    """A safe category; exception text is never emitted by the CLI."""

    def __init__(self, category: str):
        normalized = category if category in ALLOWED_ERROR_CATEGORIES else "INVARIANT_VIOLATION"
        super().__init__(normalized)
        self.category = normalized


@dataclasses.dataclass(frozen=True, repr=False)
class FinanceFixtureConfig:
    """Validated run configuration; protected values have no repr."""

    base_url: str
    run_id: str = dataclasses.field(repr=False)
    backend_sha: str = dataclasses.field(repr=False)
    customer_phone: str = dataclasses.field(repr=False)
    reviewer_phone: str = dataclasses.field(repr=False)
    executor_phone: str = dataclasses.field(repr=False)
    public_client_id: str
    mysql_container: str = dataclasses.field(repr=False)
    state_file: str = dataclasses.field(repr=False)
    profile: str = "development"
    sms_vendor_enabled: bool = False
    synthetic_phones: bool = True

    @property
    def backend_url(self) -> str:
        """Compatibility name used by callers that call the URL backend URL."""

        return self.base_url


@dataclasses.dataclass(frozen=True, repr=False)
class AuthSession:
    access_bearer: str = dataclasses.field(repr=False)
    user_id: int
    roles: str = dataclasses.field(repr=False)


@dataclasses.dataclass(frozen=True, repr=False)
class Challenge:
    challenge_id: str = dataclasses.field(repr=False)
    code: str = dataclasses.field(repr=False)


def _first_env(environment: Mapping[str, str], names: Sequence[str]) -> str:
    """Return one protected value and reject conflicting aliases."""

    values = [environment[name] for name in names if environment.get(name) not in (None, "")]
    if not values:
        return ""
    if any(value != values[0] for value in values[1:]):
        raise FinanceFixtureError("CONFIGURATION")
    return values[0]


def _parse_bool(value: str, *, required: bool = True) -> bool:
    normalized = value.strip().lower()
    if normalized in {"1", "true", "yes"}:
        return True
    if normalized in {"0", "false", "no"}:
        return False
    if not required and normalized == "":
        return False
    raise FinanceFixtureError("CONFIGURATION")


def validate_base_url(value: str) -> str:
    """Require the first-party backend to be host-local and pathless."""

    if not isinstance(value, str) or not value or any(ord(char) < 0x20 for char in value):
        raise FinanceFixtureError("CONFIGURATION")
    try:
        parsed = urlsplit(value)
        hostname = parsed.hostname
        port = parsed.port
    except ValueError:
        raise FinanceFixtureError("CONFIGURATION") from None
    if parsed.scheme.lower() != "http" or hostname is None:
        raise FinanceFixtureError("CONFIGURATION")
    if hostname.lower() not in {"127.0.0.1", "localhost", "::1"}:
        raise FinanceFixtureError("CONFIGURATION")
    if (
        parsed.username is not None
        or parsed.password is not None
        or parsed.query
        or parsed.fragment
        or parsed.path not in {"", "/"}
        or (port is not None and not 1 <= port <= 65535)
    ):
        raise FinanceFixtureError("CONFIGURATION")
    return value.rstrip("/")


def validate_phone_triplet(
    customer_phone: str, reviewer_phone: str, executor_phone: str
) -> tuple[str, str, str]:
    values = (customer_phone.strip(), reviewer_phone.strip(), executor_phone.strip())
    if any(not PHONE_RE.fullmatch(value) for value in values) or len(set(values)) != 3:
        raise FinanceFixtureError("CONFIGURATION")
    return values


def _state_path_parts(path: Path) -> tuple[Path, list[Path]]:
    """Find the nearest existing ancestor without traversing symlinks."""

    missing: list[Path] = []
    cursor = path.parent
    while True:
        try:
            metadata = cursor.lstat()
            if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
                raise FinanceFixtureError("CONFIGURATION")
            return cursor, missing
        except FileNotFoundError:
            if cursor == cursor.parent:
                raise FinanceFixtureError("CONFIGURATION") from None
            missing.append(cursor)
            cursor = cursor.parent
        except FinanceFixtureError:
            raise
        except OSError:
            raise FinanceFixtureError("CONFIGURATION") from None


def _validate_private_state_target(value: str, *, require_new: bool = True) -> str:
    if not value or "\x00" in value:
        raise FinanceFixtureError("CONFIGURATION")
    path = Path(value)
    if not path.is_absolute() or Path(os.path.normpath(value)) != path:
        raise FinanceFixtureError("CONFIGURATION")
    if path.name in {"", ".", ".."} or path == Path("/"):
        raise FinanceFixtureError("CONFIGURATION")
    parent, missing = _state_path_parts(path)
    if not missing and (parent.lstat().st_mode & 0o777) != 0o700:
        raise FinanceFixtureError("CONFIGURATION")
    try:
        target_stat = path.lstat()
    except FileNotFoundError:
        target_stat = None
    except OSError:
        raise FinanceFixtureError("CONFIGURATION") from None
    if require_new and target_stat is not None:
        raise FinanceFixtureError("CONFIGURATION")
    if target_stat is not None and stat.S_ISLNK(target_stat.st_mode):
        raise FinanceFixtureError("CONFIGURATION")
    return str(path)


def prepare_state_target(value: str) -> Path:
    """Validate/create a 0700 parent and reserve a new state target."""

    if not value or "\x00" in value:
        raise FinanceFixtureError("CONFIGURATION")
    path = Path(value)
    if not path.is_absolute() or Path(os.path.normpath(value)) != path:
        raise FinanceFixtureError("CONFIGURATION")
    parent, missing = _state_path_parts(path)
    if not missing and (parent.lstat().st_mode & 0o777) != 0o700:
        raise FinanceFixtureError("CONFIGURATION")
    for directory in reversed(missing):
        try:
            directory.mkdir(mode=0o700, parents=False, exist_ok=False)
        except FileExistsError:
            # A concurrent creator is accepted only after the same strict
            # lstat/permission checks below; a symlink can never win.
            pass
        except OSError:
            raise FinanceFixtureError("CONFIGURATION") from None
    parent = path.parent
    try:
        parent_stat = parent.lstat()
    except OSError:
        raise FinanceFixtureError("CONFIGURATION") from None
    if stat.S_ISLNK(parent_stat.st_mode) or not stat.S_ISDIR(parent_stat.st_mode):
        raise FinanceFixtureError("CONFIGURATION")
    if (parent_stat.st_mode & 0o777) != 0o700:
        raise FinanceFixtureError("CONFIGURATION")
    try:
        target_stat = path.lstat()
    except FileNotFoundError:
        target_stat = None
    except OSError:
        raise FinanceFixtureError("CONFIGURATION") from None
    if target_stat is not None:
        raise FinanceFixtureError("CONFIGURATION")
    return path


def read_config(environment: Mapping[str, str] | None = None) -> FinanceFixtureConfig:
    """Read and validate all protected run inputs."""

    env = os.environ if environment is None else environment
    base_url = validate_base_url(_first_env(env, BACKEND_URL_ENV))
    run_id = _first_env(env, RUN_ID_ENV)
    backend_sha = _first_env(env, BACKEND_SHA_ENV).lower()
    profile = _first_env(env, PROFILE_ENV).strip().lower()
    sms_vendor_value = _first_env(env, SMS_VENDOR_ENABLED_ENV)
    if not RUN_ID_RE.fullmatch(run_id) or not SHA1_RE.fullmatch(backend_sha):
        raise FinanceFixtureError("CONFIGURATION")
    if profile != "development":
        raise FinanceFixtureError("CONFIGURATION")
    if not sms_vendor_value or _parse_bool(sms_vendor_value) is not False:
        raise FinanceFixtureError("CONFIGURATION")
    customer_phone, reviewer_phone, executor_phone = validate_phone_triplet(
        _first_env(env, CUSTOMER_PHONE_ENV),
        _first_env(env, REVIEWER_PHONE_ENV),
        _first_env(env, EXECUTOR_PHONE_ENV),
    )
    public_client_id = _first_env(env, PUBLIC_CLIENT_ENV).strip()
    mysql_container = _first_env(env, MYSQL_CONTAINER_ENV).strip()
    state_file = _first_env(env, STATE_FILE_ENV)
    if not CLIENT_ID_RE.fullmatch(public_client_id):
        raise FinanceFixtureError("CONFIGURATION")
    if any(term in public_client_id.lower() for term in ("secret", "password", "token")):
        raise FinanceFixtureError("CONFIGURATION")
    if not CONTAINER_NAME_RE.fullmatch(mysql_container):
        raise FinanceFixtureError("CONFIGURATION")
    _validate_private_state_target(state_file, require_new=True)
    marker = _first_env(env, SYNTHETIC_MARKER_ENV)
    synthetic_phones = _parse_bool(marker) if marker else True
    if not synthetic_phones:
        raise FinanceFixtureError("CONFIGURATION")
    return FinanceFixtureConfig(
        base_url=base_url,
        run_id=run_id,
        backend_sha=backend_sha,
        customer_phone=customer_phone,
        reviewer_phone=reviewer_phone,
        executor_phone=executor_phone,
        public_client_id=public_client_id,
        mysql_container=mysql_container,
        state_file=state_file,
        profile=profile,
        sms_vendor_enabled=False,
        synthetic_phones=True,
    )


class _NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, *_args: object, **_kwargs: object) -> Request:
        raise FinanceFixtureError("API_UNAVAILABLE")


def _mapping(value: object) -> Mapping[str, object]:
    if not isinstance(value, Mapping):
        raise FinanceFixtureError("API_CONTRACT")
    return value


def _parse_session(data: Mapping[str, object]) -> AuthSession:
    token = data.get("access_token")
    if not isinstance(token, str):
        raise FinanceFixtureError("API_CONTRACT")
    raw_token = token[7:] if token.startswith("Bearer ") else token
    if not TOKEN_RE.fullmatch(raw_token):
        raise FinanceFixtureError("API_CONTRACT")
    user_id = data.get("userId")
    if type(user_id) is not int or user_id <= 0:
        raise FinanceFixtureError("API_CONTRACT")
    roles = data.get("roles")
    if not isinstance(roles, str) or not roles.strip():
        raise FinanceFixtureError("API_CONTRACT")
    return AuthSession("Bearer " + raw_token, user_id, roles.strip())


class FirstPartyApi:
    """Redirect-free JSON client; it intentionally has no retry loop."""

    MAX_RESPONSE_BYTES = 512 * 1024

    def __init__(
        self,
        base_url: str,
        *,
        public_client_id: str | None = None,
        timeout_seconds: float = 30.0,
    ):
        self._base_url = validate_base_url(base_url) + "/"
        self._timeout_seconds = timeout_seconds
        self._opener: OpenerDirector = build_opener(ProxyHandler({}), _NoRedirect())
        self._public_client_id = public_client_id or ""

    def _request(
        self,
        method: str,
        route: str,
        *,
        headers: Mapping[str, str],
        query: Mapping[str, str] | None = None,
        body: Mapping[str, object] | None = None,
    ) -> Mapping[str, object]:
        if not route.startswith("/") or "?" in route or "#" in route:
            raise FinanceFixtureError("CONFIGURATION")
        url = self._base_url + route[1:]
        if query:
            url += "?" + urlencode(list(query.items()))
        request_headers = {"Accept": "application/json", "Cache-Control": "no-store"}
        request_headers.update(headers)
        payload: bytes | None = None
        if body is not None:
            payload = json.dumps(body, separators=(",", ":")).encode("utf-8")
            request_headers["Content-Type"] = "application/json"
        request = Request(url, data=payload, headers=request_headers, method=method)
        try:
            with self._opener.open(request, timeout=self._timeout_seconds) as response:
                raw = response.read(self.MAX_RESPONSE_BYTES + 1)
        except FinanceFixtureError:
            raise
        except (HTTPError, URLError, OSError, TimeoutError):
            raise FinanceFixtureError("API_UNAVAILABLE") from None
        if len(raw) > self.MAX_RESPONSE_BYTES:
            raise FinanceFixtureError("API_CONTRACT")
        try:
            decoded = json.loads(raw.decode("utf-8"))
        except (UnicodeDecodeError, ValueError, TypeError):
            raise FinanceFixtureError("API_CONTRACT") from None
        envelope = _mapping(decoded)
        if envelope.get("code") != 200:
            raise FinanceFixtureError("API_CONTRACT")
        return _mapping(envelope.get("data"))

    def send_code(self, phone: str, device_id: str) -> Challenge:
        data = self._request(
            "PUT",
            "/app-register-api/util/v1/sendSmsCode",
            headers={"Client-Id": self._client_id, "X-Device-Id": device_id},
            query={"mobileNumber": phone, "type": "1"},
        )
        challenge_id = data.get("challengeId")
        code = data.get("developmentCode")
        if (
            not isinstance(challenge_id, str)
            or not CHALLENGE_RE.fullmatch(challenge_id)
            or not isinstance(code, str)
            or not re.fullmatch(r"[0-9]{6}", code)
        ):
            raise FinanceFixtureError("API_CONTRACT")
        return Challenge(challenge_id, code)

    def register(self, phone: str, code: str, device_id: str, nickname: str) -> AuthSession:
        data = self._request(
            "POST",
            "/app-register-api/userAccount/v1/registerByMobile",
            headers={"Client-Id": self._client_id},
            body={
                "phone": phone,
                "smsCode": code,
                "nickname": nickname,
                "sex": 0,
                "birthday": None,
                "inviteCode": "",
                "deviceId": device_id,
                "deviceType": 1,
                "mobileKind": "android",
                "isEmulator": 1,
                "clientId": self._client_id,
            },
        )
        return _parse_session(data)

    def login(self, phone: str, code: str, device_id: str) -> AuthSession:
        data = self._request(
            "PUT",
            "/app-register-api/userAccount/v1/loginByMobileAndSmsCode",
            headers={"Client-Id": self._client_id},
            body={
                "phone": phone,
                "smsCode": code,
                "deviceId": device_id,
                "deviceType": 1,
                "mobileKind": "android",
                "isEmulator": 1,
                "clientId": self._client_id,
            },
        )
        return _parse_session(data)

    @property
    def _client_id(self) -> str:
        # Set by run_flow; a separately constructed client is only useful for
        # offline seams and will fail before a network call if unset.
        client_id = getattr(self, "_public_client_id", "")
        if not CLIENT_ID_RE.fullmatch(client_id):
            raise FinanceFixtureError("CONFIGURATION")
        return client_id

    def with_client_id(self, client_id: str) -> "FirstPartyApi":
        if not CLIENT_ID_RE.fullmatch(client_id):
            raise FinanceFixtureError("CONFIGURATION")
        self._public_client_id = client_id
        return self


MYSQL_CONTAINER_SHELL = r'''set -eu
test -n "${MYSQL_ROOT_PASSWORD:-}"
test -n "${MYSQL_DATABASE:-}"
command -v mysql >/dev/null 2>&1
exec mysql --protocol=socket --batch --skip-column-names --raw \
  --connect-timeout=5 -uroot -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE"
'''


class MysqlExecutor:
    """Run fixed SQL through the MySQL container, never through host creds."""

    def __init__(self, container: str, *, docker_bin: str | None = None):
        if not CONTAINER_NAME_RE.fullmatch(container):
            raise FinanceFixtureError("CONFIGURATION")
        self.container = container
        self.docker_bin = docker_bin or "docker"

    def run_sql(self, sql: str) -> list[str]:
        if not isinstance(sql, str) or not sql.strip() or "\x00" in sql:
            raise FinanceFixtureError("CONFIGURATION")
        try:
            completed = subprocess.run(
                [self.docker_bin, "exec", "-i", self.container, "/bin/sh", "-c", MYSQL_CONTAINER_SHELL],
                cwd="/",
                env=_docker_environment(),
                input=sql.encode("utf-8"),
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                timeout=30.0,
                check=False,
            )
        except (OSError, subprocess.TimeoutExpired):
            raise FinanceFixtureError("DB_UNAVAILABLE") from None
        if completed.returncode != 0:
            raise FinanceFixtureError("DB_UNAVAILABLE")
        try:
            output = completed.stdout.decode("utf-8")
        except (AttributeError, UnicodeDecodeError):
            raise FinanceFixtureError("DB_CONTRACT") from None
        lines = output.splitlines()
        if any(len(line) > 512 for line in lines):
            raise FinanceFixtureError("DB_CONTRACT")
        return lines

    def baseline_order_id(self) -> str:
        lines = self.run_sql("SELECT COALESCE(MAX(id), 0) FROM recharge_order;\n")
        if len(lines) != 1 or not BASELINE_RE.fullmatch(lines[0].strip()):
            raise FinanceFixtureError("DB_CONTRACT")
        return lines[0].strip()

    def assign_roles(self, customer_id: int, reviewer_id: int, executor_id: int) -> None:
        ids = (customer_id, reviewer_id, executor_id)
        if any(type(value) is not int or value <= 0 for value in ids) or len(set(ids)) != 3:
            raise FinanceFixtureError("INVARIANT_VIOLATION")
        sql = (
            "START TRANSACTION;\n"
            f"UPDATE app_user SET roles='ROLE_OPS_FINANCE_APPROVER' WHERE id={reviewer_id} AND status='ACTIVE';\n"
            "SELECT ROW_COUNT();\n"
            f"SELECT roles FROM app_user WHERE id={reviewer_id} AND status='ACTIVE';\n"
            f"UPDATE app_user SET roles='ROLE_OPS_FINANCE' WHERE id={executor_id} AND status='ACTIVE';\n"
            "SELECT ROW_COUNT();\n"
            f"SELECT roles FROM app_user WHERE id={executor_id} AND status='ACTIVE';\n"
            f"SELECT roles FROM app_user WHERE id={customer_id} AND status='ACTIVE';\n"
            "COMMIT;\n"
        )
        lines = self.run_sql(sql)
        if len(lines) != 5:
            raise FinanceFixtureError("DB_CONTRACT")
        if any(line.strip() not in {"0", "1"} for line in (lines[0], lines[2])):
            raise FinanceFixtureError("DB_CONTRACT")
        if lines[1].strip() != ROLE_FINANCE_APPROVER:
            raise FinanceFixtureError("DB_CONTRACT")
        if lines[3].strip() != ROLE_FINANCE_EXECUTOR:
            raise FinanceFixtureError("DB_CONTRACT")
        if lines[4].strip() != ROLE_USER:
            raise FinanceFixtureError("DB_CONTRACT")


def _docker_environment() -> dict[str, str]:
    """Pass only Docker routing metadata; never host secrets."""

    environment = {"PATH": os.environ.get("PATH", "/usr/bin:/bin")}
    for name in ("DOCKER_HOST", "DOCKER_CONTEXT"):
        value = os.environ.get(name)
        if value:
            environment[name] = value
    return environment


def _device_id(run_id: str, role: str) -> str:
    digest = hashlib.sha256((run_id + "\0" + role).encode("utf-8")).hexdigest()[:24]
    return "m5-finance-" + digest


def _nickname(role: str) -> str:
    return {"customer": "M5 Finance Customer", "reviewer": "M5 Finance Reviewer", "executor": "M5 Finance Executor"}[role]


def _new_code(api: FirstPartyApi, phone: str, device_id: str) -> str:
    # One send-code request per auth step.  There is deliberately no retry:
    # retrying an unknown response could create a second challenge or hit the
    # provider boundary when a caller misconfigures SMS mode.
    challenge = api.send_code(phone, device_id)
    return challenge.code


def _register(api: FirstPartyApi, phone: str, role: str, run_id: str) -> AuthSession:
    device_id = _device_id(run_id, role + "-register")
    code = _new_code(api, phone, device_id)
    return api.register(phone, code, device_id, _nickname(role))


def _login(api: FirstPartyApi, phone: str, role: str, run_id: str) -> AuthSession:
    device_id = _device_id(run_id, role + "-login")
    code = _new_code(api, phone, device_id)
    return api.login(phone, code, device_id)


def _require_roles(
    customer: AuthSession,
    reviewer: AuthSession,
    executor: AuthSession,
    *,
    expected_customer: str = ROLE_USER,
    expected_reviewer: str = ROLE_FINANCE_APPROVER,
    expected_executor: str = ROLE_FINANCE_EXECUTOR,
) -> None:
    sessions = (customer, reviewer, executor)
    if len({session.user_id for session in sessions}) != 3:
        raise FinanceFixtureError("INVARIANT_VIOLATION")
    expected = (expected_customer, expected_reviewer, expected_executor)
    if any(session.roles != role for session, role in zip(sessions, expected)):
        raise FinanceFixtureError("INVARIANT_VIOLATION")


def build_state(
    config: FinanceFixtureConfig,
    customer: AuthSession,
    reviewer: AuthSession,
    executor: AuthSession,
    order_baseline_id: str,
) -> dict[str, object]:
    _require_roles(customer, reviewer, executor)
    if not BASELINE_RE.fullmatch(order_baseline_id):
        raise FinanceFixtureError("INVARIANT_VIOLATION")
    state: dict[str, object] = {
        "schemaVersion": SCHEMA_VERSION,
        "runId": config.run_id,
        "backendSha": config.backend_sha,
        "customerPhone": config.customer_phone,
        "customerBearer": customer.access_bearer,
        "customerUserId": customer.user_id,
        "reviewerBearer": reviewer.access_bearer,
        "reviewerUserId": reviewer.user_id,
        "executorBearer": executor.access_bearer,
        "executorUserId": executor.user_id,
        "orderBaselineId": order_baseline_id,
    }
    _validate_state(state)
    return state


def _validate_state(state: Mapping[str, object]) -> None:
    if set(state) != STATE_KEYS or state.get("schemaVersion") != SCHEMA_VERSION:
        raise FinanceFixtureError("STATE")
    if not isinstance(state.get("runId"), str) or not RUN_ID_RE.fullmatch(state["runId"]):
        raise FinanceFixtureError("STATE")
    if not isinstance(state.get("backendSha"), str) or not SHA1_RE.fullmatch(state["backendSha"]):
        raise FinanceFixtureError("STATE")
    if not isinstance(state.get("customerPhone"), str) or not PHONE_RE.fullmatch(state["customerPhone"]):
        raise FinanceFixtureError("STATE")
    for key in ("customerBearer", "reviewerBearer", "executorBearer"):
        value = state.get(key)
        if not isinstance(value, str) or not value.startswith("Bearer ") or not TOKEN_RE.fullmatch(value[7:]):
            raise FinanceFixtureError("STATE")
    for key in ("customerUserId", "reviewerUserId", "executorUserId"):
        value = state.get(key)
        if type(value) is not int or value <= 0:
            raise FinanceFixtureError("STATE")
    if len({state["customerUserId"], state["reviewerUserId"], state["executorUserId"]}) != 3:
        raise FinanceFixtureError("STATE")
    if not isinstance(state.get("orderBaselineId"), str) or not BASELINE_RE.fullmatch(state["orderBaselineId"]):
        raise FinanceFixtureError("STATE")


def write_state(path_value: str, state: Mapping[str, object]) -> None:
    """Write one new 0600 regular file without replacing an existing target."""

    _validate_state(state)
    path = prepare_state_target(path_value)
    encoded = (json.dumps(state, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")
    file_descriptor: int | None = None
    try:
        flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
        no_follow = getattr(os, "O_NOFOLLOW", 0)
        file_descriptor = os.open(str(path), flags | no_follow, 0o600)
        os.fchmod(file_descriptor, 0o600)
        with os.fdopen(file_descriptor, "wb") as stream:
            file_descriptor = None
            stream.write(encoded)
            stream.flush()
            os.fsync(stream.fileno())
        metadata = path.lstat()
        if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode) or (metadata.st_mode & 0o777) != 0o600:
            raise FinanceFixtureError("STATE")
    except FinanceFixtureError:
        try:
            path.unlink(missing_ok=True)
        except OSError:
            pass
        raise
    except OSError:
        if file_descriptor is not None:
            try:
                os.close(file_descriptor)
            except OSError:
                pass
        try:
            path.unlink(missing_ok=True)
        except OSError:
            pass
        raise FinanceFixtureError("OUTPUT_WRITE") from None


def run_flow(
    config: FinanceFixtureConfig,
    *,
    api: FirstPartyApi | None = None,
    mysql: MysqlExecutor | None = None,
) -> dict[str, object]:
    """Create the three accounts, assign roles, relogin, and persist state."""

    if config.profile != "development" or config.sms_vendor_enabled or not config.synthetic_phones:
        raise FinanceFixtureError("CONFIGURATION")
    prepare_state_target(config.state_file)
    if api is None:
        client: Any = FirstPartyApi(
            config.base_url, public_client_id=config.public_client_id
        )
    else:
        # Offline seams can provide a tiny fake API.  They receive no
        # protected values from the runner and therefore need not implement
        # the concrete client's configuration mutator.
        client = api
    database = mysql or MysqlExecutor(config.mysql_container)
    baseline = database.baseline_order_id()

    customer_registered = _register(client, config.customer_phone, "customer", config.run_id)
    reviewer_registered = _register(client, config.reviewer_phone, "reviewer", config.run_id)
    executor_registered = _register(client, config.executor_phone, "executor", config.run_id)
    _require_roles(customer_registered, reviewer_registered, executor_registered,
                   expected_customer=ROLE_USER, expected_reviewer=ROLE_USER, expected_executor=ROLE_USER)
    database.assign_roles(
        customer_registered.user_id,
        reviewer_registered.user_id,
        executor_registered.user_id,
    )
    customer = _login(client, config.customer_phone, "customer", config.run_id)
    reviewer = _login(client, config.reviewer_phone, "reviewer", config.run_id)
    executor = _login(client, config.executor_phone, "executor", config.run_id)
    _require_roles(customer, reviewer, executor)
    state = build_state(config, customer, reviewer, executor, baseline)
    write_state(config.state_file, state)
    return {
        "status": "PASS",
        "schemaVersion": SCHEMA_VERSION,
        "providerInvocation": False,
        "customerCreated": True,
        "reviewerCreated": True,
        "executorCreated": True,
        "roleAssignments": 2,
        "stateWritten": True,
    }


def _safe_failure(category: str) -> dict[str, object]:
    normalized = category if category in ALLOWED_ERROR_CATEGORIES else "INVARIANT_VIOLATION"
    return {
        "status": "FAIL",
        "schemaVersion": SCHEMA_VERSION,
        "category": normalized,
        "providerInvocation": False,
    }


def _self_test() -> int:
    """Pure contract checks; no socket, subprocess, Docker, or provider."""

    validate_base_url("http://127.0.0.1:18080")
    validate_phone_triplet("13900000001", "13900000002", "13900000003")
    try:
        validate_base_url("http://10.0.2.2:18080")
    except FinanceFixtureError:
        pass
    else:
        raise AssertionError("non-loopback URL accepted")
    try:
        validate_phone_triplet("13900000001", "13900000001", "13900000003")
    except FinanceFixtureError:
        pass
    else:
        raise AssertionError("duplicate phone accepted")
    if "MYSQL_ROOT_PASSWORD" not in MYSQL_CONTAINER_SHELL or "-p\"$MYSQL_ROOT_PASSWORD\"" not in MYSQL_CONTAINER_SHELL:
        raise AssertionError("container-only password contract missing")
    for forbidden in ("INSERT", "UPDATE", "DELETE", "DROP", "TRUNCATE"):
        # The role SQL is intentionally not part of the shell command.  A
        # password or SQL statement cannot accidentally become a process arg.
        if forbidden in MYSQL_CONTAINER_SHELL:
            raise AssertionError("unexpected SQL in shell command")
    safe = _safe_failure("CONFIGURATION")
    encoded = json.dumps(safe, sort_keys=True)
    for forbidden in ("Bearer", "13900000001", "challenge", "password", "secret", "token"):
        if forbidden.lower() in encoded.lower():
            raise AssertionError("sensitive term in safe output")
    return 0


def _parser() -> argparse.ArgumentParser:
    class _SafeArgumentParser(argparse.ArgumentParser):
        def error(self, _message: str) -> None:
            # argparse normally echoes the offending argv value.  This CLI
            # accepts no protected values on argv, but fail closed even when
            # an operator accidentally supplies one.
            raise FinanceFixtureError("CONFIGURATION")

    parser = _SafeArgumentParser(description="M5 development Alipay finance fixture")
    modes = parser.add_mutually_exclusive_group(required=True)
    modes.add_argument("--self-test", action="store_true")
    modes.add_argument("--run", action="store_true")
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    try:
        args = _parser().parse_args(list(argv) if argv is not None else None)
    except SystemExit as error:
        return int(error.code)
    except FinanceFixtureError:
        print(json.dumps(_safe_failure("CONFIGURATION"), separators=(",", ":")))
        return 2
    if args.self_test:
        try:
            _self_test()
            print(json.dumps({"status": "PASS", "schemaVersion": SCHEMA_VERSION, "selfTest": True, "providerInvocation": False}, separators=(",", ":")))
            return 0
        except Exception:
            print(json.dumps(_safe_failure("INVARIANT_VIOLATION"), separators=(",", ":")))
            return 1
    try:
        config = read_config()
        result = run_flow(config)
        print(json.dumps(result, separators=(",", ":")))
        return 0
    except FinanceFixtureError as error:
        print(json.dumps(_safe_failure(error.category), separators=(",", ":")))
        return 2
    except Exception:
        # Do not leak an HTTP body, SQL diagnostic, path, or token into QA
        # logs even for an unexpected bug in this helper.
        print(json.dumps(_safe_failure("INVARIANT_VIOLATION"), separators=(",", ":")))
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
