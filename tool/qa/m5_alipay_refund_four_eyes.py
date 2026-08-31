#!/usr/bin/env python3
"""Controlled M5 Alipay sandbox refund acceptance harness.

This module is intentionally QA-only.  It drives the already deployed
first-party HTTP contracts and a read-only ledger evidence helper; it does
not discover an order, create a payment, or print provider/customer
identifiers.  A real run is blocked unless two independent, exact
confirmation environment variables opt into the provider-facing execute
operation.

The flow is:

    successful Alipay order read -> user refund application -> finance review
    -> finance execute -> (pending/unknown only) finance reconcile -> result
    -> aggregate ledger evidence

Execute and reconcile receive the same refund public id.  A second request
with the same request id is sent for each operation, proving that the
backend's idempotency record is used instead of issuing another economic
write.  A provider that returns a terminal REFUNDED result is not queried a
second time: the terminal server state is authoritative and a provider query
after completion would be an unsafe extra call.
"""

from __future__ import annotations

import argparse
import dataclasses
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import stat
import tempfile
from typing import Any, Mapping, Sequence
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlencode, urlsplit
from urllib.request import (
    HTTPRedirectHandler,
    OpenerDirector,
    ProxyHandler,
    Request,
    build_opener,
)

from m5_alipay_refund_ledger_evidence import (
    LedgerConfig,
    LedgerEvidenceError,
    collect as collect_ledger,
    read_config as read_ledger_config,
    start as start_ledger,
)
from m5_alipay_success_handoff import (
    HandoffError,
    read_state_file,
)


FLOW_SCHEMA_VERSION = "m5-alipay-refund-four-eyes-v2"
EXPECTED_DEVELOPMENT_MYSQL_CONTAINER = "voice-social-m3-development-mysql-1"
EXPECTED_CONFIRMATION = "I_UNDERSTAND_ALIPAY_SANDBOX_REFUND"
EXPECTED_CONFIRMATION_2 = "I_UNDERSTAND_ALIPAY_SANDBOX_REFUND_SECOND_OPERATOR"

ORDER_REF_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:-]{0,79}$")
RUN_ID_RE = re.compile(r"^m5-refund-[A-Za-z0-9_.:-]{1,80}$")
FIXTURE_ID_RE = re.compile(r"^m5-fresh-[A-Za-z0-9_.:-]{1,64}$")
MAX_REFUND_REASON_LENGTH = 256
UUID_RE = re.compile(
    r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-"
    r"[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$"
)
SHA1_RE = re.compile(r"^[0-9a-fA-F]{40}$")

PROTECTED_STATE_ENV = "QA_M5_REFUND_PROTECTED_STATE_FILE"
PROTECTED_BACKEND_SHA_ENV_NAMES = (
    "QA_M5_REFUND_BACKEND_SHA",
    "QA_M5_BACKEND_SHA",
    "QA_BACKEND_SHA",
    "M5_BACKEND_SHA",
)
PROTECTED_FIXTURE_ID_ENV = "QA_M5_FINANCE_FIXTURE_ID"
LEGACY_PROTECTED_INPUT_ENV_NAMES = (
    "QA_M5_REFUND_ORDER_NO",
    "QA_M5_REFUND_USER_BEARER",
    "QA_M5_REFUND_REVIEWER_BEARER",
    "QA_M5_REFUND_EXECUTOR_BEARER",
)

ORDER_SUCCESS_STATUSES = frozenset({"TRADE_SUCCESS", "TRADE_FINISHED"})
REFUND_PENDING_STATUSES = frozenset({"PENDING", "UNKNOWN", "PROCESSING"})
REFUND_STATUS_VALUES = frozenset(
    {"SUBMITTED", "REVIEWING", "APPROVED", "REJECTED", "COMPLETED", "CANCELLED"}
)
PROVIDER_STATUS_VALUES = frozenset(
    {
        "",
        "VENDOR_BLOCKED",
        "SUBMITTED",
        "APPROVED",
        "PROCESSING",
        "PENDING",
        "UNKNOWN",
        "REFUNDED",
        "REJECTED",
        "CANCELLED",
        "TRADE_SUCCESS",
        "TRADE_FINISHED",
    }
)
SAFE_SUMMARY_STATUS_VALUES = REFUND_STATUS_VALUES | PROVIDER_STATUS_VALUES | {
    "PASS",
    "FAIL",
    "BLOCKED",
    "NOT_REQUIRED",
    "SUCCEEDED",
}
ALLOWED_ERROR_CATEGORIES = frozenset(
    {
        "CONFIGURATION",
        "PROVIDER_CONFIRMATION_REQUIRED",
        "API_UNAVAILABLE",
        "API_CONTRACT",
        "ORDER_NOT_ELIGIBLE",
        "DB_UNAVAILABLE",
        "SCHEMA_MISSING",
        "INVALID_MARKER",
        "STATE",
        "INVARIANT_VIOLATION",
        "OUTPUT_WRITE",
    }
)


class RefundHarnessError(RuntimeError):
    """A safe category that never carries a response body or input value."""

    def __init__(self, category: str):
        if category not in ALLOWED_ERROR_CATEGORIES:
            category = "INVARIANT_VIOLATION"
        super().__init__(category)
        self.category = category


@dataclasses.dataclass(frozen=True, repr=False)
class RefundHarnessConfig:
    """Validated configuration; protected fields deliberately have no repr."""

    base_url: str
    fixture_id: str = dataclasses.field(repr=False)
    order_no: str = dataclasses.field(repr=False)
    user_bearer: str = dataclasses.field(repr=False)
    reviewer_bearer: str = dataclasses.field(repr=False)
    executor_bearer: str = dataclasses.field(repr=False)
    reason: str = dataclasses.field(repr=False)
    run_id: str = dataclasses.field(repr=False)
    mysql_container: str = dataclasses.field(repr=False)
    state_dir: str = dataclasses.field(repr=False)
    expected_customer_user_id: int | None = dataclasses.field(default=None, repr=False)
    expected_reviewer_user_id: int | None = dataclasses.field(default=None, repr=False)
    expected_executor_user_id: int | None = dataclasses.field(default=None, repr=False)
    allow_provider: bool = False
    confirmation: str = dataclasses.field(default="", repr=False)
    confirmation_2: str = dataclasses.field(default="", repr=False)
    artifact_dir: str | None = None
    allow_insecure_http: bool = False
    ledger_config: LedgerConfig | None = dataclasses.field(default=None, repr=False)
    protected_state_file: str | None = dataclasses.field(default=None, repr=False)


class LedgerPort:
    """Small seam used by offline behavior tests and the real Docker helper."""

    def start(self, order_no: str) -> None:
        raise NotImplementedError

    def collect(self, order_no: str, refund_id: str) -> dict[str, object]:
        raise NotImplementedError


class DockerLedger(LedgerPort):
    """Adapter around the read-only aggregate helper."""

    def __init__(self, config: LedgerConfig):
        self._config = config

    def start(self, order_no: str) -> None:
        try:
            start_ledger(self._config, order_no)
        except LedgerEvidenceError as error:
            raise RefundHarnessError(error.category) from None

    def collect(self, order_no: str, refund_id: str) -> dict[str, object]:
        try:
            return collect_ledger(self._config, order_no, refund_id)
        except LedgerEvidenceError as error:
            raise RefundHarnessError(error.category) from None


class RefundApiClient:
    """HTTP contract seam.  Production implementation is JsonRefundApiClient."""

    def order_status(self, order_no: str, bearer: str) -> dict[str, object]:
        raise NotImplementedError

    def apply_refund(
        self, order_no: str, reason: str, bearer: str, request_id: str
    ) -> dict[str, object]:
        raise NotImplementedError

    def approve_refund(
        self, refund_id: str, bearer: str, request_id: str
    ) -> dict[str, object]:
        raise NotImplementedError

    def execute_refund(
        self, refund_id: str, bearer: str, request_id: str
    ) -> dict[str, object]:
        raise NotImplementedError

    def reconcile_refund(
        self, refund_id: str, bearer: str, request_id: str
    ) -> dict[str, object]:
        raise NotImplementedError

    def refund_result(self, refund_id: str, bearer: str) -> dict[str, object]:
        raise NotImplementedError


class _NoRedirect(HTTPRedirectHandler):
    """Never follow a backend redirect into an untrusted destination."""

    def redirect_request(self, *_args: object, **_kwargs: object) -> Request:
        raise RefundHarnessError("API_UNAVAILABLE")


class JsonRefundApiClient(RefundApiClient):
    """Minimal, redirect-free JSON client with redacted failure handling."""

    MAX_RESPONSE_BYTES = 512 * 1024

    def __init__(self, base_url: str, *, timeout_seconds: float = 30.0):
        self._base_url = base_url.rstrip("/") + "/"
        self._timeout_seconds = timeout_seconds
        self._opener: OpenerDirector = build_opener(
            ProxyHandler({}), _NoRedirect()
        )

    def _request(
        self,
        method: str,
        route: str,
        bearer: str,
        *,
        query: Mapping[str, str] | None = None,
        body: Mapping[str, object] | None = None,
        request_id: str | None = None,
    ) -> dict[str, object]:
        if not route.startswith("/") or "?" in route or "#" in route:
            raise RefundHarnessError("CONFIGURATION")
        url = self._base_url + route[1:]
        if query:
            url += "?" + urlencode(list(query.items()))
        headers = {
            "Accept": "application/json",
            "Cache-Control": "no-store",
            "Authorization": bearer,
        }
        payload: bytes | None = None
        if body is not None:
            payload = json.dumps(body, separators=(",", ":")).encode("utf-8")
            headers["Content-Type"] = "application/json"
        if request_id is not None:
            headers["X-Request-Id"] = request_id
        request = Request(url, data=payload, headers=headers, method=method)
        try:
            with self._opener.open(request, timeout=self._timeout_seconds) as response:
                raw = response.read(self.MAX_RESPONSE_BYTES + 1)
        except RefundHarnessError:
            raise
        except (HTTPError, URLError, OSError, TimeoutError):
            raise RefundHarnessError("API_UNAVAILABLE") from None
        if len(raw) > self.MAX_RESPONSE_BYTES:
            raise RefundHarnessError("API_CONTRACT")
        try:
            decoded = json.loads(raw.decode("utf-8"))
        except (UnicodeDecodeError, ValueError, TypeError):
            raise RefundHarnessError("API_CONTRACT") from None
        if not isinstance(decoded, dict) or decoded.get("code") != 200:
            raise RefundHarnessError("API_CONTRACT")
        data = decoded.get("data")
        if not isinstance(data, dict):
            raise RefundHarnessError("API_CONTRACT")
        return data

    def order_status(self, order_no: str, bearer: str) -> dict[str, object]:
        return self._request(
            "GET",
            "/app-economy-api/pay/ali/order/status",
            bearer,
            query={"orderNo": order_no},
        )

    def apply_refund(
        self, order_no: str, reason: str, bearer: str, request_id: str
    ) -> dict[str, object]:
        return self._request(
            "POST",
            "/app-api/refund/application",
            bearer,
            body={"orderNo": order_no, "reason": reason},
            request_id=request_id,
        )

    def approve_refund(
        self, refund_id: str, bearer: str, request_id: str
    ) -> dict[str, object]:
        return self._request(
            "POST",
            f"/internal/ops/v1/finance/refunds/{quote(refund_id, safe='')}/approve",
            bearer,
            request_id=request_id,
        )

    def execute_refund(
        self, refund_id: str, bearer: str, request_id: str
    ) -> dict[str, object]:
        return self._request(
            "POST",
            f"/internal/ops/v1/finance/refunds/{quote(refund_id, safe='')}/execute",
            bearer,
            request_id=request_id,
        )

    def reconcile_refund(
        self, refund_id: str, bearer: str, request_id: str
    ) -> dict[str, object]:
        return self._request(
            "POST",
            f"/internal/ops/v1/finance/refunds/{quote(refund_id, safe='')}/reconcile",
            bearer,
            request_id=request_id,
        )

    def refund_result(self, refund_id: str, bearer: str) -> dict[str, object]:
        return self._request(
            "GET",
            "/app-api/refund/result",
            bearer,
            query={"refundId": refund_id},
        )


def _is_true(value: str | None) -> bool:
    return (value or "").strip().lower() in {"1", "true", "yes"}


def _sha256(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def _private_directory(value: str, *, allow_missing: bool = False) -> str:
    if not value or "\x00" in value:
        raise RefundHarnessError("CONFIGURATION")
    path = Path(value)
    if not path.is_absolute() or path != Path(os.path.normpath(value)):
        raise RefundHarnessError("CONFIGURATION")
    try:
        if path.resolve(strict=False) != path:
            raise RefundHarnessError("CONFIGURATION")
    except OSError:
        raise RefundHarnessError("CONFIGURATION") from None
    if allow_missing and not path.exists():
        try:
            path.mkdir(mode=0o700, parents=True, exist_ok=False)
        except OSError:
            raise RefundHarnessError("CONFIGURATION") from None
    try:
        metadata = path.lstat()
        mode = metadata.st_mode
    except OSError:
        raise RefundHarnessError("CONFIGURATION") from None
    if stat.S_ISLNK(mode) or not stat.S_ISDIR(mode) or mode & 0o077:
        raise RefundHarnessError("CONFIGURATION")
    return str(path)


def validate_base_url(value: str, *, allow_insecure_http: bool = False) -> None:
    if not isinstance(value, str) or not value or any(ord(c) < 0x20 for c in value):
        raise RefundHarnessError("CONFIGURATION")
    try:
        parsed = urlsplit(value)
        hostname = parsed.hostname
        port = parsed.port
    except ValueError:
        raise RefundHarnessError("CONFIGURATION") from None
    scheme = parsed.scheme.lower()
    # This orchestrator runs on the Mac host. Android's 10.0.2.2 gateway is
    # only special inside an emulator and must not be treated as host-local
    # when transmitting bearer credentials over plain HTTP.
    allowed_http_hosts = {"127.0.0.1", "localhost", "::1"}
    if scheme == "https":
        pass
    elif (
        allow_insecure_http
        and scheme == "http"
        and hostname is not None
        and hostname.lower() in allowed_http_hosts
    ):
        pass
    else:
        raise RefundHarnessError("CONFIGURATION")
    if (
        not hostname
        or parsed.username is not None
        or parsed.password is not None
        or parsed.query
        or parsed.fragment
        or parsed.path not in {"", "/"}
        or (port is not None and not 1 <= port <= 65535)
    ):
        raise RefundHarnessError("CONFIGURATION")


def _validate_refund_reason(value: str) -> str:
    if (
        not value
        or len(value) > MAX_REFUND_REASON_LENGTH
        or any(ord(c) < 0x20 for c in value)
    ):
        raise RefundHarnessError("CONFIGURATION")
    return value


def _validate_development_mysql_container(value: str) -> str:
    if value != EXPECTED_DEVELOPMENT_MYSQL_CONTAINER:
        raise RefundHarnessError("CONFIGURATION")
    return value


def _first_protected_env_value(
    environment: Mapping[str, str], names: Sequence[str]
) -> str:
    """Resolve aliases only when they agree; never include values in errors."""

    values = [environment.get(name, "").strip() for name in names]
    present = [value for value in values if value]
    if len(set(present)) > 1:
        raise RefundHarnessError("CONFIGURATION")
    return present[0] if present else ""


def _read_protected_refund_state(
    environment: Mapping[str, str],
    *,
    run_id: str,
) -> tuple[str, str, str, str, int, int, int, str, str]:
    """Read one protected handoff and return only values needed by the flow."""

    state_file = environment.get(PROTECTED_STATE_ENV, "").strip()
    if not state_file:
        raise RefundHarnessError("CONFIGURATION")
    expected_fixture_id = environment.get(PROTECTED_FIXTURE_ID_ENV, "").strip()
    if not FIXTURE_ID_RE.fullmatch(expected_fixture_id):
        raise RefundHarnessError("CONFIGURATION")
    # Direct order/bearer inputs are retired.  Reject even matching stale
    # exports so the protected v2 state file remains the sole source of truth.
    if any(environment.get(name, "") for name in LEGACY_PROTECTED_INPUT_ENV_NAMES):
        raise RefundHarnessError("CONFIGURATION")
    expected_backend_sha = _first_protected_env_value(
        environment, PROTECTED_BACKEND_SHA_ENV_NAMES
    )
    if not SHA1_RE.fullmatch(expected_backend_sha):
        raise RefundHarnessError("CONFIGURATION")
    try:
        state, _raw = read_state_file(
            Path(state_file),
            expected_backend_sha=expected_backend_sha,
            expected_fixture_id=expected_fixture_id,
            expected_run_id=run_id,
            require_order=True,
        )
    except HandoffError as error:
        category = error.category
        if category not in ALLOWED_ERROR_CATEGORIES:
            category = "INVARIANT_VIOLATION"
        raise RefundHarnessError(category) from None
    if state.order_no is None:
        raise RefundHarnessError("STATE")
    return (
        state.order_no,
        state.customer_bearer,
        state.reviewer_bearer,
        state.executor_bearer,
        state.customer_user_id,
        state.reviewer_user_id,
        state.executor_user_id,
        state_file,
        state.fixture_id,
    )


def read_config(environment: Mapping[str, str] | None = None) -> RefundHarnessConfig:
    env = os.environ if environment is None else environment
    allow_insecure_http = _is_true(env.get("QA_M5_REFUND_ALLOW_INSECURE_HTTP"))
    base_url = env.get("QA_M5_REFUND_BASE_URL", "").strip()
    validate_base_url(base_url, allow_insecure_http=allow_insecure_http)
    reason = _validate_refund_reason(
        env.get("QA_M5_REFUND_REASON", "M5 Alipay sandbox refund acceptance")
    )
    run_id = env.get("QA_M5_REFUND_RUN_ID", "")
    if not RUN_ID_RE.fullmatch(run_id):
        raise RefundHarnessError("CONFIGURATION")

    protected_state_file = env.get(PROTECTED_STATE_ENV, "").strip()
    if not protected_state_file:
        raise RefundHarnessError("CONFIGURATION")
    (
        order_no,
        user_bearer,
        reviewer_bearer,
        executor_bearer,
        expected_customer_user_id,
        expected_reviewer_user_id,
        expected_executor_user_id,
        protected_state_file,
        fixture_id,
    ) = _read_protected_refund_state(env, run_id=run_id)
    if len({user_bearer, reviewer_bearer, executor_bearer}) != 3:
        raise RefundHarnessError("CONFIGURATION")

    mysql_container = _validate_development_mysql_container(
        env.get("QA_M5_REFUND_MYSQL_CONTAINER", "")
    )
    state_dir = _private_directory(env.get("QA_M5_REFUND_LEDGER_STATE_DIR", ""))
    artifact_dir_value = env.get("QA_M5_REFUND_ARTIFACT_DIR", "")
    artifact_dir = (
        _private_directory(artifact_dir_value, allow_missing=True)
        if artifact_dir_value
        else None
    )
    ledger_config = read_ledger_config(env)
    return RefundHarnessConfig(
        base_url=base_url,
        fixture_id=fixture_id,
        order_no=order_no,
        user_bearer=user_bearer,
        reviewer_bearer=reviewer_bearer,
        executor_bearer=executor_bearer,
        reason=reason,
        run_id=run_id,
        mysql_container=mysql_container,
        state_dir=state_dir,
        expected_customer_user_id=expected_customer_user_id,
        expected_reviewer_user_id=expected_reviewer_user_id,
        expected_executor_user_id=expected_executor_user_id,
        allow_provider=_is_true(env.get("QA_M5_REFUND_ALLOW_PROVIDER")),
        confirmation=env.get("QA_M5_REFUND_CONFIRMATION", ""),
        confirmation_2=env.get("QA_M5_REFUND_CONFIRMATION_2", ""),
        artifact_dir=artifact_dir,
        allow_insecure_http=allow_insecure_http,
        ledger_config=ledger_config,
        protected_state_file=protected_state_file,
    )


def authorize_provider(config: RefundHarnessConfig) -> None:
    """Fail closed unless two explicit operator confirmations are present."""

    if (
        not config.allow_provider
        or config.confirmation != EXPECTED_CONFIRMATION
        or config.confirmation_2 != EXPECTED_CONFIRMATION_2
    ):
        raise RefundHarnessError("PROVIDER_CONFIRMATION_REQUIRED")


def _request_id(stage: str) -> str:
    return f"m5-refund-{stage}-{secrets.token_hex(8)}"


def _mapping(value: object) -> Mapping[str, object]:
    if not isinstance(value, Mapping):
        raise RefundHarnessError("API_CONTRACT")
    return value


def _status(value: object, allowed: frozenset[str]) -> str:
    if not isinstance(value, str):
        raise RefundHarnessError("API_CONTRACT")
    normalized = value.strip().upper()
    if normalized not in allowed:
        raise RefundHarnessError("API_CONTRACT")
    return normalized


def _required_bool(row: Mapping[str, object], key: str, expected: bool) -> None:
    value = row.get(key)
    if key not in row or type(value) is not bool or value is not expected:
        raise RefundHarnessError("API_CONTRACT")


def _optional_bool(row: Mapping[str, object], key: str, expected: bool) -> None:
    if key in row:
        _required_bool(row, key, expected)


def _required_id(row: Mapping[str, object], key: str) -> int:
    value = row.get(key)
    if type(value) is not int or value <= 0:
        raise RefundHarnessError("API_CONTRACT")
    return value


def _validate_order(row: Mapping[str, object], order_no: str) -> None:
    if row.get("orderNo") != order_no:
        raise RefundHarnessError("ORDER_NOT_ELIGIBLE")
    if row.get("provider") != "alipay-sandbox":
        raise RefundHarnessError("ORDER_NOT_ELIGIBLE")
    if row.get("status") != "SUCCEEDED":
        raise RefundHarnessError("ORDER_NOT_ELIGIBLE")
    if row.get("providerStatus") not in ORDER_SUCCESS_STATUSES:
        raise RefundHarnessError("ORDER_NOT_ELIGIBLE")
    if row.get("bool") is not True:
        raise RefundHarnessError("ORDER_NOT_ELIGIBLE")
    _required_bool(row, "providerInvocation", False)


def _validate_application(row: Mapping[str, object], order_no: str) -> str:
    refund_id = row.get("refundId")
    if not isinstance(refund_id, str) or not UUID_RE.fullmatch(refund_id):
        raise RefundHarnessError("API_CONTRACT")
    if row.get("orderNo") != order_no or row.get("status") != "SUBMITTED":
        raise RefundHarnessError("API_CONTRACT")
    _required_bool(row, "completed", False)
    # The C-end application/result projection predates providerInvocation and
    # intentionally omits it; if a richer deployment includes the flag it
    # must still prove that application did not call the provider.
    _optional_bool(row, "providerInvocation", False)
    return refund_id


def _validate_review(
    row: Mapping[str, object], refund_id: str
) -> tuple[int, int]:
    if row.get("refundId") != refund_id:
        raise RefundHarnessError("API_CONTRACT")
    if row.get("status") != "APPROVED" or row.get("providerStatus") != "APPROVED":
        raise RefundHarnessError("API_CONTRACT")
    _required_bool(row, "fourEyesRequired", True)
    _required_bool(row, "providerInvocation", False)
    owner_id = _required_id(row, "userId")
    reviewer_id = _required_id(row, "reviewedByUserId")
    if owner_id == reviewer_id:
        raise RefundHarnessError("INVARIANT_VIOLATION")
    return owner_id, reviewer_id


def _validate_provider_result(
    row: Mapping[str, object],
    refund_id: str,
    owner_id: int,
    reviewer_id: int,
) -> tuple[str, str, int]:
    if row.get("refundId") != refund_id:
        raise RefundHarnessError("API_CONTRACT")
    status = _status(row.get("status"), REFUND_STATUS_VALUES)
    provider_status = _status(row.get("providerStatus"), PROVIDER_STATUS_VALUES)
    if type(row.get("providerInvocation")) is not bool or not row.get(
        "providerInvocation"
    ):
        raise RefundHarnessError("INVARIANT_VIOLATION")
    _required_bool(row, "fourEyesRequired", True)
    if status == "COMPLETED" and provider_status != "REFUNDED":
        raise RefundHarnessError("API_CONTRACT")
    if status == "APPROVED" and provider_status not in REFUND_PENDING_STATUSES:
        raise RefundHarnessError("API_CONTRACT")
    if status not in {"APPROVED", "COMPLETED"}:
        raise RefundHarnessError("API_CONTRACT")
    executed_id = _required_id(row, "executedByUserId")
    response_reviewer_id = _required_id(row, "reviewedByUserId")
    response_owner_id = _required_id(row, "userId")
    if (
        response_owner_id != owner_id
        or response_reviewer_id != reviewer_id
        or executed_id in {owner_id, reviewer_id}
    ):
        raise RefundHarnessError("INVARIANT_VIOLATION")
    _required_bool(row, "completed", status == "COMPLETED")
    return status, provider_status, executed_id


def _validate_replay(
    first: Mapping[str, object],
    replay: Mapping[str, object],
    refund_id: str,
) -> None:
    if replay.get("refundId") != refund_id:
        raise RefundHarnessError("API_CONTRACT")
    for key in (
        "status",
        "providerStatus",
        "completed",
        "providerInvocation",
        "fourEyesRequired",
        "userId",
        "reviewedByUserId",
        "executedByUserId",
    ):
        if replay.get(key) != first.get(key):
            raise RefundHarnessError("INVARIANT_VIOLATION")


def _validate_final(
    row: Mapping[str, object], refund_id: str, order_no: str
) -> None:
    if (
        row.get("refundId") != refund_id
        or row.get("orderNo") != order_no
        or row.get("status") != "COMPLETED"
        or row.get("providerStatus") != "REFUNDED"
        or row.get("completed") is not True
    ):
        raise RefundHarnessError("INVARIANT_VIOLATION")
    # The C-end refund result endpoint is DB-only and currently omits this
    # field.  Reject an explicit true value while accepting that contract.
    _optional_bool(row, "providerInvocation", False)


def _validate_ledger(result: Mapping[str, object], *, reconcile_required: bool) -> None:
    expected = {
        "reserveDebitCount": 1,
        "reserveReleaseCreditCount": 0,
        "reserveJournalCount": 1,
        "reservePostingCount": 2,
        "reserveUnbalancedCount": 0,
        "balancedReserveJournalCount": 1,
        "ledgerImbalanceCount": 0,
        "reviewedActorCount": 1,
        "executedActorCount": 1,
        "distinctFinanceActorCount": 1,
        "ownerDistinctReviewerCount": 1,
        "ownerDistinctExecutorCount": 1,
        "outRequestMatchCount": 1,
        "reserveAmountMatchCount": 1,
        "refundProviderOrderMatchCount": 1,
        "refundAmountMatchCount": 1,
        "executeFingerprintCount": 1,
        "reconcileFingerprintCount": 1 if reconcile_required else 0,
        "operationIdempotencyRows": 2 if reconcile_required else 1,
    }
    for key, value in expected.items():
        if type(result.get(key)) is not int or result.get(key) != value:
            raise RefundHarnessError("INVARIANT_VIOLATION")
    expected_idempotency = {
        "executeIdempotencyRows": 1,
        "reconcileIdempotencyRows": 1 if reconcile_required else 0,
    }
    for key, expected_value in expected_idempotency.items():
        value = result.get(key)
        if type(value) is not int or value != expected_value:
            raise RefundHarnessError("INVARIANT_VIOLATION")


def run_flow(
    config: RefundHarnessConfig,
    *,
    api: RefundApiClient | None = None,
    ledger: LedgerPort | None = None,
) -> dict[str, object]:
    """Run one explicitly authorized refund lane and return safe evidence."""

    if not FIXTURE_ID_RE.fullmatch(config.fixture_id):
        raise RefundHarnessError("CONFIGURATION")
    authorize_provider(config)
    client = api or JsonRefundApiClient(config.base_url)
    evidence = ledger or DockerLedger(
        config.ledger_config
        or read_ledger_config(
            {
                "QA_M5_REFUND_MYSQL_CONTAINER": config.mysql_container,
                "QA_M5_REFUND_LEDGER_STATE_DIR": config.state_dir,
                "QA_M5_REFUND_RUN_ID": config.run_id,
            }
        )
    )

    order = _mapping(client.order_status(config.order_no, config.user_bearer))
    _validate_order(order, config.order_no)

    # The baseline is captured before the customer mutation.  The helper's
    # start query also rechecks the same order's succeeded Alipay state.
    evidence.start(config.order_no)
    application = _mapping(
        client.apply_refund(
            config.order_no,
            config.reason,
            config.user_bearer,
            _request_id("apply"),
        )
    )
    refund_id = _validate_application(application, config.order_no)

    review = _mapping(
        client.approve_refund(
            refund_id,
            config.reviewer_bearer,
            _request_id("review"),
        )
    )
    owner_id, reviewer_id = _validate_review(review, refund_id)
    if config.expected_customer_user_id is not None and owner_id != config.expected_customer_user_id:
        raise RefundHarnessError("INVARIANT_VIOLATION")
    if config.expected_reviewer_user_id is not None and reviewer_id != config.expected_reviewer_user_id:
        raise RefundHarnessError("INVARIANT_VIOLATION")

    execute_request_id = _request_id("execute")
    execute = _mapping(
        client.execute_refund(
            refund_id,
            config.executor_bearer,
            execute_request_id,
        )
    )
    execute_status, execute_provider_status, executor_id = _validate_provider_result(
        execute, refund_id, owner_id, reviewer_id
    )
    if config.expected_executor_user_id is not None and executor_id != config.expected_executor_user_id:
        raise RefundHarnessError("INVARIANT_VIOLATION")
    execute_replay = _mapping(
        client.execute_refund(
            refund_id,
            config.executor_bearer,
            execute_request_id,
        )
    )
    _validate_replay(execute, execute_replay, refund_id)

    reconcile_required = execute_status != "COMPLETED"
    reconcile_replay = False
    reconcile_status = "NOT_REQUIRED"
    reconcile_provider_status = execute_provider_status
    if reconcile_required:
        if execute_provider_status not in REFUND_PENDING_STATUSES:
            raise RefundHarnessError("API_CONTRACT")
        reconcile_request_id = _request_id("reconcile")
        reconciled = _mapping(
            client.reconcile_refund(
                refund_id,
                config.executor_bearer,
                reconcile_request_id,
            )
        )
        reconcile_status, reconcile_provider_status, reconcile_executor_id = _validate_provider_result(
            reconciled, refund_id, owner_id, reviewer_id
        )
        if (
            config.expected_executor_user_id is not None
            and reconcile_executor_id != config.expected_executor_user_id
        ):
            raise RefundHarnessError("INVARIANT_VIOLATION")
        if reconcile_status != "COMPLETED" or reconcile_provider_status != "REFUNDED":
            raise RefundHarnessError("INVARIANT_VIOLATION")
        reconcile_repeat_value = _mapping(
            client.reconcile_refund(
                refund_id,
                config.executor_bearer,
                reconcile_request_id,
            )
        )
        _validate_replay(reconciled, reconcile_repeat_value, refund_id)
        reconcile_replay = True

    final = _mapping(client.refund_result(refund_id, config.user_bearer))
    _validate_final(final, refund_id, config.order_no)
    ledger_result = _mapping(evidence.collect(config.order_no, refund_id))
    _validate_ledger(ledger_result, reconcile_required=reconcile_required)

    summary = build_safe_summary(
        fixture_id=config.fixture_id,
        order_no=config.order_no,
        refund_id=refund_id,
        order_status="SUCCEEDED",
        refund_status="COMPLETED",
        provider_status="REFUNDED",
        ledger=dict(ledger_result),
        idempotency={
            "sameRefundId": True,
            "sameOutRequestNo": True,
            "executeReplay": True,
            "reconcileRequired": reconcile_required,
            "reconcileReplay": reconcile_replay,
            "executeStatus": execute_status,
            "reconcileStatus": reconcile_status,
        },
    )
    return summary


def _safe_metric(value: object) -> int | bool | str | None:
    if type(value) is bool:
        return value
    if type(value) is int and value >= 0:
        return value
    if isinstance(value, str) and value in SAFE_SUMMARY_STATUS_VALUES:
        return value
    return None


def sanitize_response(value: Mapping[str, object]) -> dict[str, object]:
    """Keep only typed statuses/booleans; drop every identifier and amount."""

    safe: dict[str, object] = {}
    for key in ("status", "providerStatus", "reserveState"):
        metric = value.get(key)
        if isinstance(metric, str) and metric in SAFE_SUMMARY_STATUS_VALUES:
            safe[key] = metric
    for key in ("completed", "providerInvocation", "fourEyesRequired"):
        metric = value.get(key)
        if type(metric) is bool:
            safe[key] = metric
    return safe


def build_safe_summary(
    *,
    fixture_id: str | None = None,
    order_no: str,
    refund_id: str,
    order_status: str,
    refund_status: str,
    provider_status: str,
    ledger: Mapping[str, object],
    idempotency: Mapping[str, object],
) -> dict[str, object]:
    """Build the fixed artifact/stdout shape without protected values."""

    if fixture_id is not None and not FIXTURE_ID_RE.fullmatch(fixture_id):
        raise RefundHarnessError("INVARIANT_VIOLATION")
    if order_status not in SAFE_SUMMARY_STATUS_VALUES:
        raise RefundHarnessError("INVARIANT_VIOLATION")
    if refund_status not in SAFE_SUMMARY_STATUS_VALUES:
        raise RefundHarnessError("INVARIANT_VIOLATION")
    if provider_status not in SAFE_SUMMARY_STATUS_VALUES:
        raise RefundHarnessError("INVARIANT_VIOLATION")
    safe_ledger: dict[str, int | bool | str] = {}
    for key, value in ledger.items():
        metric = _safe_metric(value)
        if metric is not None and key in {
            "reserveDebitCount",
            "reserveReleaseCreditCount",
            "reserveJournalCount",
            "reservePostingCount",
            "reserveUnbalancedCount",
            "balancedReserveJournalCount",
            "ledgerImbalanceCount",
            "operationIdempotencyRows",
            "executeIdempotencyRows",
            "reconcileIdempotencyRows",
            "executeFingerprintCount",
            "reconcileFingerprintCount",
            "reviewedActorCount",
            "executedActorCount",
            "distinctFinanceActorCount",
            "ownerDistinctReviewerCount",
            "ownerDistinctExecutorCount",
            "outRequestMatchCount",
            "reserveAmountMatchCount",
            "refundProviderOrderMatchCount",
            "refundAmountMatchCount",
        }:
            safe_ledger[key] = metric
    safe_idempotency: dict[str, int | bool | str] = {}
    for key, value in idempotency.items():
        metric = _safe_metric(value)
        if metric is not None and key in {
            "sameRefundId",
            "sameOutRequestNo",
            "executeReplay",
            "reconcileRequired",
            "reconcileReplay",
            "executeStatus",
            "reconcileStatus",
        }:
            safe_idempotency[key] = metric
    summary: dict[str, object] = {
        "schemaVersion": FLOW_SCHEMA_VERSION,
        "status": "PASS",
        "providerInvocation": True,
        "order": {"eligible": True, "status": order_status},
        "refund": {
            "application": "SUBMITTED",
            "review": "APPROVED",
            "execute": refund_status,
            "providerStatus": provider_status,
            "completed": True,
        },
        "fourEyes": {
            "required": True,
            "reviewerDistinctFromOwner": True,
            "executorDistinctFromReviewer": True,
            "executorDistinctFromOwner": True,
        },
        "idempotency": safe_idempotency,
        "ledger": safe_ledger,
        "hashes": {
            "orderRefSha256": _sha256(order_no),
            "refundRefSha256": _sha256(refund_id),
        },
    }
    if fixture_id is not None:
        summary["fixtureId"] = fixture_id
    return summary


def _write_artifact(directory: str, summary: Mapping[str, object]) -> None:
    path = Path(directory) / "m5-alipay-refund-summary.json"
    if path.is_symlink() or path.exists():
        raise RefundHarnessError("OUTPUT_WRITE")
    temporary: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            dir=directory,
            prefix=".m5-alipay-refund-summary-",
            delete=False,
        ) as stream:
            temporary = Path(stream.name)
            os.chmod(temporary, 0o600)
            json.dump(summary, stream, sort_keys=True, separators=(",", ":"))
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    except OSError:
        if temporary is not None:
            try:
                temporary.unlink(missing_ok=True)
            except OSError:
                pass
        raise RefundHarnessError("OUTPUT_WRITE") from None


def _public_self_test() -> int:
    if EXPECTED_CONFIRMATION == EXPECTED_CONFIRMATION_2:
        raise AssertionError("confirmations must be independent")
    blocked = RefundHarnessConfig(
        base_url="https://backend.example.test/",
        fixture_id="m5-fresh-refund-self-test",
        order_no="m5-order",
        user_bearer="user-token-value",
        reviewer_bearer="reviewer-token-value",
        executor_bearer="executor-token-value",
        reason="test",
        run_id="m5-refund-self-test",
        mysql_container="mysql",
        state_dir="/private/tmp/m5-refund-self-test",
    )
    try:
        authorize_provider(blocked)
    except RefundHarnessError as error:
        if error.category != "PROVIDER_CONFIRMATION_REQUIRED":
            raise AssertionError("provider gate category changed") from error
    else:
        raise AssertionError("provider gate opened by default")
    hostile = sanitize_response(
        {
            "refundId": "00000000-0000-4000-8000-000000000001",
            "orderNo": "sensitive-order",
            "userId": 1,
            "amountMinor": 100,
            "providerRefundId": "provider-refund",
            "status": "COMPLETED",
            "providerStatus": "REFUNDED",
            "completed": True,
        }
    )
    encoded = json.dumps(hostile, sort_keys=True)
    if any(term in encoded for term in ("refundId", "orderNo", "userId", "amountMinor")):
        raise AssertionError("sensitive field entered safe output")
    try:
        validate_base_url("https://example.test/?token=secret")
    except RefundHarnessError:
        pass
    else:
        raise AssertionError("URL query was accepted")
    print("self-test=PASS")
    return 0


def _parser() -> argparse.ArgumentParser:
    class _SafeArgumentParser(argparse.ArgumentParser):
        def error(self, _message: str) -> None:
            raise RefundHarnessError("CONFIGURATION")

    parser = _SafeArgumentParser(
        description="Controlled M5 Alipay sandbox Finance four-eyes refund QA"
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
    except RefundHarnessError:
        _emit(
            {
                "schemaVersion": FLOW_SCHEMA_VERSION,
                "status": "FAIL",
                "category": "CONFIGURATION",
                "providerInvocation": False,
            }
        )
        return 2
    if args.self_test:
        try:
            return _public_self_test()
        except AssertionError:
            print("self-test=FAIL")
            return 1

    # Check the double gate before reading any other environment value or
    # opening a network/database connection.  A bare invocation is therefore
    # a harmless, provider-free BLOCKED result.
    if not (
        _is_true(os.environ.get("QA_M5_REFUND_ALLOW_PROVIDER"))
        and os.environ.get("QA_M5_REFUND_CONFIRMATION", "") == EXPECTED_CONFIRMATION
        and os.environ.get("QA_M5_REFUND_CONFIRMATION_2", "")
        == EXPECTED_CONFIRMATION_2
    ):
        _emit(
            {
                "schemaVersion": FLOW_SCHEMA_VERSION,
                "status": "BLOCKED",
                "category": "PROVIDER_CONFIRMATION_REQUIRED",
                "providerInvocation": False,
            }
        )
        return 3
    try:
        config = read_config()
        summary = run_flow(config)
        if config.artifact_dir is not None:
            _write_artifact(config.artifact_dir, summary)
        _emit(summary)
        return 0
    except RefundHarnessError as error:
        _emit(
            {
                "schemaVersion": FLOW_SCHEMA_VERSION,
                "status": "FAIL",
                "category": error.category,
                # Once the explicit provider gate is open, a later failure
                # may happen before or after the backend reached Alipay.  A
                # local exception cannot prove the negative, so preserve the
                # ambiguity instead of publishing a false zero-call claim.
                "providerInvocation": "UNKNOWN",
            }
        )
        return 2
    except Exception:
        # Never let an unexpected library/JSON/filesystem traceback echo a
        # route, request value, response field, or secret into QA output.
        _emit(
            {
                "schemaVersion": FLOW_SCHEMA_VERSION,
                "status": "FAIL",
                "category": "INVARIANT_VIOLATION",
                "providerInvocation": "UNKNOWN",
            }
        )
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
