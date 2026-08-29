#!/usr/bin/env python3
"""Host-side, interactive approval for the M5 Alipay action-time gate.

The command reads the short-lived operator bearer from a 0600 file, fetches
the exact pending identity from the authenticated localhost relay, and keeps
that identity in memory only while posting the approval.  It never accepts
identity values from argv or environment and never prints the fetched order or
request identity.  The relay never returns the internal one-shot grant, so the
grant value cannot enter terminal output, logs, artifacts, shell history, or
command arguments.

Operator sequence:
1. Wait for the runner's exact ACTION_CONFIRMATION_REQUIRED marker.  An
   ACTION_GATE::armed or ACTION_GATE::waiting_for_order line only means that
   the gate is ready; it is not an approval request.
2. Run --approve.  The operator authenticates a localhost pending-identity
   fetch using the 0600 operator file; the raw orderNo/requestId/account remain
   in process memory and are never printed or passed as command arguments.
3. Enter only the exact success confirmation through this TTY prompt or as
   the protected stdin field ``{"confirmation": "..."}``; approval is
   single-use and short-lived.
"""

from __future__ import annotations

import argparse
import getpass
import json
import os
from pathlib import Path
import re
import stat
import sys
import urllib.error
import urllib.request

from m5_alipay_action_gate import EXPECTED_SUCCESS_CONFIRMATION


_TOKEN_RE = re.compile(r"^[A-Za-z0-9_-]{64,256}$")
_RUN_RE = re.compile(r"^[A-Za-z0-9_.:-]{1,80}$")
_AVD_RE = re.compile(r"^AVD-A$")
_SERIAL_RE = re.compile(r"^emulator-5554$")
_SHA1_RE = re.compile(r"^[0-9a-f]{40}$")
_ACCOUNT_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.:@+-]{0,127}$")
_PRODUCT_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$")
_ORDER_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$")
_REQUEST_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$")
_ATTRIBUTE_RE = re.compile(r"^[A-Z][A-Z0-9_.:-]{0,31}$")
_CREATED_MARKER_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.:+-]{0,127}$")
_MAX_AMOUNT_MINOR = 10**12
_MAX_GIFT_COIN_AMOUNT = 10**12
_ERROR_RE = re.compile(r"^[A-Z_]{1,32}$")
_MAX_RESPONSE_BYTES = 4096


class _NoRedirectHandler(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *_args, **_kwargs):
        return None


def _safe_private_file(raw: str) -> Path:
    path = Path(raw)
    if not path.is_absolute() or os.path.normpath(raw) != raw:
        raise ValueError("operator file")
    parent = path.parent
    if not parent.exists() or os.path.realpath(str(parent)) != str(parent):
        raise ValueError("operator file")
    current = Path(parent.anchor)
    for part in parent.parts[1:]:
        current /= part
        metadata = current.lstat()
        if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
            raise ValueError("operator file")
    if parent.lstat().st_mode & 0o077:
        raise ValueError("operator file")
    metadata = path.lstat()
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
        raise ValueError("operator file")
    if stat.S_IMODE(metadata.st_mode) != 0o600:
        raise ValueError("operator file")
    return path


def _read_token(path: Path) -> str:
    flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0)
    descriptor = os.open(path, flags)
    try:
        metadata = os.fstat(descriptor)
        if not stat.S_ISREG(metadata.st_mode) or stat.S_IMODE(metadata.st_mode) != 0o600:
            raise ValueError("operator file")
        token = os.read(descriptor, 4096).decode("ascii").strip()
    finally:
        os.close(descriptor)
    if not _TOKEN_RE.fullmatch(token):
        raise ValueError("operator file")
    return token


def _prompt_confirmation(amount_minor: int) -> str:
    try:
        tty = open("/dev/tty", "r+", encoding="utf-8", buffering=1)
    except OSError:
        raise ValueError("interactive input unavailable") from None
    try:
        major, minor = divmod(amount_minor, 100)
        tty.write(
            "Pending sandbox success action amount "
            f"{major}.{minor:02d} CNY on AVD-A / emulator-5554. "
            "Type the exact success confirmation (input hidden): "
        )
        tty.flush()
        return getpass.getpass(stream=tty)
    finally:
        tty.close()


def _stdin_confirmation() -> str:
    try:
        value = json.load(sys.stdin)
    except (json.JSONDecodeError, TypeError, ValueError):
        raise ValueError("stdin payload") from None
    if not isinstance(value, dict):
        raise ValueError("stdin payload")
    if set(value) != {"confirmation"} or not isinstance(value["confirmation"], str):
        raise ValueError("stdin payload")
    return value["confirmation"]


def _validate_pending_identity(payload: object) -> dict[str, object]:
    required = {
        "runId",
        "avd",
        "serial",
        "backendSha",
        "flutterSha",
        "orderNo",
        "requestId",
        "account",
        "productId",
        "amountMinor",
        "giftCoinAmount",
        "provider",
        "status",
    }
    optional = {"createdMarker"}
    if (
        not isinstance(payload, dict)
        or not required.issubset(payload)
        or not set(payload).issubset(required | optional)
    ):
        raise ValueError("pending identity")
    if not all(isinstance(payload[key], str) for key in required - {
        "amountMinor",
        "giftCoinAmount",
    }):
        raise ValueError("pending identity")
    result = {key: payload[key] for key in payload}
    if (
        not _RUN_RE.fullmatch(result["runId"])
        or not _AVD_RE.fullmatch(result["avd"])
        or not _SERIAL_RE.fullmatch(result["serial"])
        or not _SHA1_RE.fullmatch(result["backendSha"])
        or not _SHA1_RE.fullmatch(result["flutterSha"])
        or not _ORDER_RE.fullmatch(result["orderNo"])
        or not _REQUEST_RE.fullmatch(result["requestId"])
        or not _ACCOUNT_RE.fullmatch(result["account"])
        or not _PRODUCT_RE.fullmatch(result["productId"])
        or result["provider"] != "ALIPAY"
        or not _ATTRIBUTE_RE.fullmatch(result["provider"])
        or result["status"] != "CREATED"
        or not _ATTRIBUTE_RE.fullmatch(result["status"])
        or type(result["amountMinor"]) is not int
        or not 1 <= result["amountMinor"] <= _MAX_AMOUNT_MINOR
        or type(result["giftCoinAmount"]) is not int
        or not 1 <= result["giftCoinAmount"] <= _MAX_GIFT_COIN_AMOUNT
    ):
        raise ValueError("pending identity")
    if "createdMarker" in result and (
        not isinstance(result["createdMarker"], str)
        or not _CREATED_MARKER_RE.fullmatch(result["createdMarker"])
    ):
        raise ValueError("pending identity")
    return result


def _validate_payload(payload: dict[str, object]) -> None:
    if (
        not isinstance(payload, dict)
        or set(payload) != {
            "runId",
            "avd",
            "serial",
            "backendSha",
            "flutterSha",
            "orderNo",
            "requestId",
            "account",
            "productId",
            "amountMinor",
            "giftCoinAmount",
            "provider",
            "status",
            "confirmation",
        }
        and set(payload) != {
            "runId",
            "avd",
            "serial",
            "backendSha",
            "flutterSha",
            "orderNo",
            "requestId",
            "account",
            "productId",
            "amountMinor",
            "giftCoinAmount",
            "provider",
            "status",
            "createdMarker",
            "confirmation",
        }
    ):
        raise ValueError("confirmation payload")
    if not isinstance(payload.get("confirmation"), str):
        raise ValueError("confirmation payload")
    _validate_pending_identity(
        {key: value for key, value in payload.items() if key != "confirmation"}
    )
    if payload["confirmation"] != EXPECTED_SUCCESS_CONFIRMATION:
        raise ValueError("confirmation payload")


def _read_response_json(response: urllib.response.addinfourl) -> object:
    length = response.headers.get("Content-Length")
    if length is not None:
        try:
            if int(length) < 0 or int(length) > _MAX_RESPONSE_BYTES:
                raise ValueError("response size")
        except (TypeError, ValueError):
            raise ValueError("response size") from None
    raw = response.read(_MAX_RESPONSE_BYTES + 1)
    if len(raw) > _MAX_RESPONSE_BYTES:
        raise ValueError("response size")
    return json.loads(raw)


def _get_pending(port: int, token: str) -> dict[str, object]:
    request = urllib.request.Request(
        f"http://127.0.0.1:{port}/m5/alipay/action-confirmation/pending",
        headers={"Authorization": "Bearer " + token},
        method="GET",
    )
    opener = urllib.request.build_opener(
        urllib.request.ProxyHandler({}),
        _NoRedirectHandler(),
    )
    try:
        with opener.open(request, timeout=5) as response:
            if response.geturl() != request.full_url or response.status != 200:
                raise ValueError("pending identity")
            value = _read_response_json(response)
        if not isinstance(value, dict) or value.get("pending") is not True:
            raise ValueError("pending identity")
        return _validate_pending_identity(
            {key: value[key] for key in value if key != "pending"}
        )
    except urllib.error.HTTPError as error:
        error.close()
        raise ValueError("pending identity") from None
    except (OSError, ValueError, json.JSONDecodeError, urllib.error.URLError):
        raise ValueError("pending identity") from None


def approve_pending(port: int, token: str, confirmation: str) -> bool:
    """Fetch and approve the exact relay-pending identity in one process."""

    pending = _get_pending(port, token)
    payload = {**pending, "confirmation": confirmation}
    _validate_payload(payload)
    return _post(port, token, payload)


def _post(port: int, token: str, payload: dict[str, object]) -> bool:
    body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
    request = urllib.request.Request(
        f"http://127.0.0.1:{port}/m5/alipay/action-confirmation/approve",
        data=body,
        headers={
            "Authorization": "Bearer " + token,
            "Content-Type": "application/json",
            "Content-Length": str(len(body)),
        },
        method="POST",
    )
    opener = urllib.request.build_opener(
        urllib.request.ProxyHandler({}),
        _NoRedirectHandler(),
    )
    try:
        with opener.open(request, timeout=5) as response:
            if 300 <= response.status < 400:
                return False
            if response.geturl() != request.full_url or response.status != 200:
                return False
            value = _read_response_json(response)
            return isinstance(value, dict) and value == {"accepted": True}
    except urllib.error.HTTPError as error:
        error.close()
        return False
    except (OSError, ValueError, json.JSONDecodeError, urllib.error.URLError):
        return False


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(add_help=True)
    parser.add_argument("--relay-port", type=int, required=False)
    parser.add_argument("--operator-file")
    parser.add_argument("--approve", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args(argv)
    if args.self_test:
        print("ACTION_GATE_OPERATOR_SELF_TEST::PASS")
        return 0
    if not args.approve or args.relay_port is None or not args.operator_file:
        return 2
    if not 1 <= args.relay_port <= 65535:
        return 2
    try:
        token = _read_token(_safe_private_file(args.operator_file))
        pending = _get_pending(args.relay_port, token)
        confirmation = (
            _prompt_confirmation(int(pending["amountMinor"]))
            if sys.stdin.isatty()
            else _stdin_confirmation()
        )
        payload = {**pending, "confirmation": confirmation}
        _validate_payload(payload)
    except (OSError, UnicodeError, ValueError):
        print("ACTION_CONFIRMATION_REJECTED::PENDING_OR_INPUT")
        return 2
    if _post(args.relay_port, token, payload):
        print("ACTION_CONFIRMATION_ACCEPTED")
        return 0
    print("ACTION_CONFIRMATION_REJECTED::RELAY")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
