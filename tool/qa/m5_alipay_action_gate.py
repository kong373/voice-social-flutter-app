#!/usr/bin/env python3
"""Fail-closed, action-time confirmation state for the M5 Alipay lane.

The M5 runner already has a private localhost relay for AVD coordination.  It
uses this small state machine for the one extra invariant that cannot be
represented by build-time ``QA_M5_*`` values: a success PayTask is only
allowed after the host operator approves the exact order while it is pending.

Only digests of the sensitive order identity and an internal digest of the
one-shot grant are retained.  The raw order number, account identity, and
confirmation value are never included in reprs or errors.  The relay is
responsible for transporting the raw identity over its authenticated
localhost connection; this module is deliberately unaware of HTTP and has no
persistence API.
"""

from __future__ import annotations

from dataclasses import dataclass
import hashlib
import hmac
import re
import secrets
import threading
import time
from typing import Callable


ACTION_CONFIRMATION_REQUIRED = "ACTION_CONFIRMATION_REQUIRED"
EXPECTED_SUCCESS_CONFIRMATION = "I_UNDERSTAND_SANDBOX_SUCCESS_PAYMENT"
DEFAULT_TTL_SECONDS = 120

_ACCOUNT_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.:@+-]{0,127}$")
_PRODUCT_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$")
_ATTRIBUTE_RE = re.compile(r"^[A-Z][A-Z0-9_.:-]{0,31}$")
_CREATED_MARKER_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.:+-]{0,127}$")
_MAX_AMOUNT_MINOR = 10**12
_MAX_GIFT_COIN_AMOUNT = 10**12
_EXPECTED_PROVIDER = "ALIPAY"
_EXPECTED_STATUS = "CREATED"

_IDENTITY_RE = re.compile(r"^[A-Za-z0-9_.:-]{1,80}$")
_AVD_RE = re.compile(r"^AVD-[A-Z0-9_.:-]{1,32}$")
_SERIAL_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$")
_SHA1_RE = re.compile(r"^[0-9a-f]{40}$")
_ORDER_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$")
_REQUEST_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$")

_ERROR_CODES = frozenset(
    {
        "DISABLED",
        "MARKER_UNAVAILABLE",
        "IDENTITY_INVALID",
        "BINDING_MISMATCH",
        "PREMATURE",
        "DUPLICATE",
        "EXPIRED",
        "CONFIRMATION_MISMATCH",
        "NOT_APPROVED",
        "REPLAY",
    }
)


class ActionGateError(RuntimeError):
    """A safe category that never embeds a run, device, or order value."""

    def __init__(self, code: str):
        self.code = code if code in _ERROR_CODES else "IDENTITY_INVALID"
        super().__init__(self.code)


@dataclass(frozen=True, repr=False)
class ActionIdentity:
    """Transient raw identity received from the app/operator.

    ``repr`` intentionally omits every field because callers may hold this
    object while constructing an HTTP request or a test failure.
    """

    run_id: str
    avd: str
    serial: str
    backend_sha: str
    flutter_sha: str
    order_no: str
    request_id: str
    # Values copied from the authoritative create-order response. Defaults
    # preserve object-construction compatibility only; validation rejects an
    # old-shaped identity before it can reach a gate.
    account: str = ""
    product_id: str = ""
    amount_minor: int = 0
    gift_coin_amount: int = 0
    provider: str | None = None
    status: str | None = None
    # The backend currently does not return an immutable creation timestamp
    # for this lane. If it starts returning one, pass its exact response
    # marker; never replace a missing marker with a client clock value.
    created_marker: str | None = None

    def __repr__(self) -> str:
        return "ActionIdentity(<redacted>)"


@dataclass(frozen=True, repr=False)
class _IdentityDigest:
    run_id: str
    avd: str
    serial: str
    backend_sha: str
    flutter_sha: str
    account_digest: bytes
    product_digest: bytes
    order_digest: bytes
    request_digest: bytes
    attributes_digest: bytes

    def __repr__(self) -> str:
        return "_IdentityDigest(<redacted>)"


class ActionConfirmationGate:
    """One pending order, one short-lived host approval, one consumption.

    The gate is intentionally single-use.  There is no reset operation: a
    duplicate, expired, consumed, or mismatched attempt cannot revive an old
    grant.  A new process/run gets a new gate instance and a new relay token.
    """

    def __init__(
        self,
        *,
        enabled: bool,
        expected_run_id: str,
        expected_avd: str,
        expected_serial: str = "emulator-5554",
        expected_backend_sha: str,
        expected_flutter_sha: str,
        ttl_seconds: float = DEFAULT_TTL_SECONDS,
        clock: Callable[[], float] = time.monotonic,
        marker_sink: Callable[[str], None] | None = None,
    ) -> None:
        if not isinstance(enabled, bool):
            raise ValueError("enabled must be bool")
        if not _IDENTITY_RE.fullmatch(expected_run_id):
            raise ValueError("expected run identity is invalid")
        if not _AVD_RE.fullmatch(expected_avd):
            raise ValueError("expected AVD identity is invalid")
        if expected_serial != "emulator-5554":
            raise ValueError("expected serial identity is invalid")
        if not _SHA1_RE.fullmatch(expected_backend_sha):
            raise ValueError("expected backend SHA is invalid")
        if not _SHA1_RE.fullmatch(expected_flutter_sha):
            raise ValueError("expected Flutter SHA is invalid")
        if not isinstance(ttl_seconds, (int, float)) or not 0 < ttl_seconds <= 600:
            raise ValueError("ttl_seconds must be between 0 and 600")
        self._enabled = enabled
        self._expected_run_id = expected_run_id
        self._expected_avd = expected_avd
        self._expected_serial = expected_serial
        self._expected_backend_sha = expected_backend_sha
        self._expected_flutter_sha = expected_flutter_sha
        self._ttl_seconds = float(ttl_seconds)
        self._clock = clock
        self._marker_sink = marker_sink
        self._pending: _IdentityDigest | None = None
        self._requested_at: float | None = None
        self._grant_digest: bytes | None = None
        self._approved = False
        self._consumed = False
        self._lock = threading.Lock()

    def __repr__(self) -> str:
        state = "disabled" if not self._enabled else self._state_name()
        return f"ActionConfirmationGate(state={state!r})"

    @property
    def enabled(self) -> bool:
        return self._enabled

    def request(self, identity: ActionIdentity) -> None:
        """Record the exact order immediately before its first PayTask.

        The marker callback runs before the pending state is committed.  If a
        host marker cannot be delivered, the app cannot accidentally continue
        into PayTask.
        """

        digest = self._digest_identity(identity)
        with self._lock:
            if not self._enabled:
                raise ActionGateError("DISABLED")
            if self._pending is not None:
                if self._is_expired_locked():
                    raise ActionGateError("EXPIRED")
                if self._same_identity(self._pending, digest):
                    raise ActionGateError("DUPLICATE")
                raise ActionGateError("BINDING_MISMATCH")
            if self._marker_sink is None:
                raise ActionGateError("MARKER_UNAVAILABLE")
            try:
                # The callback receives this fixed literal only.  It must not
                # be changed to include an order number or an operator value.
                self._marker_sink(ACTION_CONFIRMATION_REQUIRED)
            except Exception:
                raise ActionGateError("MARKER_UNAVAILABLE") from None
            self._pending = digest
            self._requested_at = self._clock()
            self._grant_digest = None
            self._approved = False
            self._consumed = False

    def approve(self, identity: ActionIdentity, confirmation: str) -> bool:
        """Issue an internal one-shot grant after explicit host approval."""

        digest = self._digest_identity(identity)
        with self._lock:
            self._require_pending_locked()
            if self._is_expired_locked():
                raise ActionGateError("EXPIRED")
            assert self._pending is not None
            if not self._same_identity(self._pending, digest):
                raise ActionGateError("BINDING_MISMATCH")
            if self._consumed or self._approved:
                raise ActionGateError("REPLAY")
            if confirmation != EXPECTED_SUCCESS_CONFIRMATION:
                raise ActionGateError("CONFIRMATION_MISMATCH")
            # The raw token is never returned, serialized, or logged.  A
            # random digest records that a fresh grant was issued and makes
            # the one-shot state explicit without retaining a bearer secret.
            grant = secrets.token_bytes(32)
            self._grant_digest = hashlib.sha256(grant).digest()
            self._approved = True
            return True

    def consume(self, identity: ActionIdentity) -> bool:
        """Atomically consume the grant for the first PayTask invocation."""

        digest = self._digest_identity(identity)
        with self._lock:
            self._require_pending_locked()
            if self._is_expired_locked():
                raise ActionGateError("EXPIRED")
            assert self._pending is not None
            if not self._same_identity(self._pending, digest):
                raise ActionGateError("BINDING_MISMATCH")
            if self._consumed:
                raise ActionGateError("REPLAY")
            if not self._approved or self._grant_digest is None:
                raise ActionGateError("NOT_APPROVED")
            self._consumed = True
            # Retain only a boolean consumed state; even the internal grant
            # digest is no longer needed after the atomic transition.
            self._grant_digest = None
            return True

    def public_status(self) -> dict[str, bool]:
        """Return safe status fields for a local operator poll endpoint."""

        with self._lock:
            if self._pending is not None and self._is_expired_locked():
                # Expiry is terminal. Never advertise an expired order as
                # pending because the operator endpoint must not make it
                # approvable again.
                return {
                    "pending": False,
                    "approved": False,
                    "consumed": False,
                    "expired": True,
                }
            return {
                "pending": self._pending is not None,
                "approved": self._approved,
                "consumed": self._consumed,
                "expired": False,
            }

    def _digest_identity(self, identity: ActionIdentity) -> _IdentityDigest:
        if not isinstance(identity, ActionIdentity):
            raise ActionGateError("IDENTITY_INVALID")
        if not all(isinstance(value, str) for value in (
            identity.run_id,
            identity.avd,
            identity.serial,
            identity.backend_sha,
            identity.flutter_sha,
            identity.order_no,
            identity.request_id,
            identity.account,
            identity.product_id,
        )):
            raise ActionGateError("IDENTITY_INVALID")
        if (
            not _IDENTITY_RE.fullmatch(identity.run_id)
            or not _AVD_RE.fullmatch(identity.avd)
            or not _SERIAL_RE.fullmatch(identity.serial)
            or not _SHA1_RE.fullmatch(identity.backend_sha)
            or not _SHA1_RE.fullmatch(identity.flutter_sha)
            or not _ORDER_RE.fullmatch(identity.order_no)
            or not _REQUEST_RE.fullmatch(identity.request_id)
            or not _ACCOUNT_RE.fullmatch(identity.account)
            or not _PRODUCT_RE.fullmatch(identity.product_id)
        ):
            raise ActionGateError("IDENTITY_INVALID")
        # bool is an int subclass, so use exact type checks for the monetary
        # and entitlement fields. This prevents JSON true/false coercion.
        if (
            type(identity.amount_minor) is not int
            or not 1 <= identity.amount_minor <= _MAX_AMOUNT_MINOR
            or type(identity.gift_coin_amount) is not int
            or not 1 <= identity.gift_coin_amount <= _MAX_GIFT_COIN_AMOUNT
        ):
            raise ActionGateError("IDENTITY_INVALID")
        if (
            not isinstance(identity.provider, str)
            or not _ATTRIBUTE_RE.fullmatch(identity.provider)
            or identity.provider != _EXPECTED_PROVIDER
            or not isinstance(identity.status, str)
            or not _ATTRIBUTE_RE.fullmatch(identity.status)
            or identity.status != _EXPECTED_STATUS
        ):
            raise ActionGateError("IDENTITY_INVALID")
        if identity.created_marker is not None and (
            not isinstance(identity.created_marker, str)
            or not _CREATED_MARKER_RE.fullmatch(identity.created_marker)
        ):
            raise ActionGateError("IDENTITY_INVALID")
        if (
            identity.run_id != self._expected_run_id
            or identity.avd != self._expected_avd
            or identity.serial != self._expected_serial
            or identity.backend_sha != self._expected_backend_sha
            or identity.flutter_sha != self._expected_flutter_sha
        ):
            raise ActionGateError("BINDING_MISMATCH")
        def digest_text(value: str) -> bytes:
            return hashlib.sha256(value.encode("utf-8")).digest()

        def digest_attributes() -> bytes:
            # Length-prefix each value so concatenation cannot create an
            # alternate identity with the same byte representation.
            values = (
                str(identity.amount_minor),
                str(identity.gift_coin_amount),
                identity.provider or "",
                identity.status or "",
                identity.created_marker or "",
            )
            encoded = bytearray()
            for value in values:
                raw = value.encode("utf-8")
                encoded.extend(len(raw).to_bytes(4, "big"))
                encoded.extend(raw)
            return hashlib.sha256(bytes(encoded)).digest()

        return _IdentityDigest(
            run_id=identity.run_id,
            avd=identity.avd,
            serial=identity.serial,
            backend_sha=identity.backend_sha,
            flutter_sha=identity.flutter_sha,
            account_digest=digest_text(identity.account),
            product_digest=digest_text(identity.product_id),
            order_digest=digest_text(identity.order_no),
            request_digest=digest_text(identity.request_id),
            attributes_digest=digest_attributes(),
        )

    def _same_identity(self, left: _IdentityDigest, right: _IdentityDigest) -> bool:
        return (
            left.run_id == right.run_id
            and left.avd == right.avd
            and left.serial == right.serial
            and left.backend_sha == right.backend_sha
            and left.flutter_sha == right.flutter_sha
            and hmac.compare_digest(left.account_digest, right.account_digest)
            and hmac.compare_digest(left.product_digest, right.product_digest)
            and hmac.compare_digest(left.order_digest, right.order_digest)
            and hmac.compare_digest(left.request_digest, right.request_digest)
            and hmac.compare_digest(
                left.attributes_digest,
                right.attributes_digest,
            )
        )

    def _require_pending_locked(self) -> None:
        if not self._enabled:
            raise ActionGateError("DISABLED")
        if self._pending is None:
            raise ActionGateError("PREMATURE")

    def _is_expired_locked(self) -> bool:
        assert self._pending is not None
        assert self._requested_at is not None
        return self._clock() - self._requested_at >= self._ttl_seconds

    def _state_name(self) -> str:
        if self._pending is None:
            return "idle"
        if self._is_expired_locked():
            return "expired"
        if self._consumed:
            return "consumed"
        if self._approved:
            return "approved"
        return "pending"
