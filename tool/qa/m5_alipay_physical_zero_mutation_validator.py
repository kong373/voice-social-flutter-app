#!/usr/bin/env python3
"""Validate redacted, zero-mutation evidence for the physical cancel lane.

The validator emits only four zero counters.  It never echoes JSON values,
serials, order strings, or provider payloads.
"""

from __future__ import annotations

import json
import sys
import time
from pathlib import Path


SCHEMA = "alipay-physical-cancel-v1"
SHA1_HEX_LENGTH = 40
RUN_ID_MAX_LENGTH = 96
COUNTER_KEYS = (
    "payment_provider_events",
    "wallet_transactions",
    "ledger_journals",
    "ledger_entries",
)
TOP_LEVEL_KEYS = frozenset(
    {
        "schema",
        "status",
        "serial",
        "flutterSha",
        "backendSha",
        "runId",
        "runStartedAt",
        "observedAt",
        "evidenceSource",
        "payment",
        "writeCounters",
        "secrets",
    }
)


def _require_sha(value: object, expected: str) -> None:
    if (
        not isinstance(value, str)
        or len(value) != SHA1_HEX_LENGTH
        or any(character not in "0123456789abcdefABCDEF" for character in value)
        or value.lower() != expected.lower()
    ):
        raise ValueError("sha binding")


def _require_run_id(value: object, expected: str) -> None:
    if (
        not isinstance(value, str)
        or not value
        or len(value) > RUN_ID_MAX_LENGTH
        or value != expected
        or any(character not in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.:-" for character in value)
    ):
        raise ValueError("run binding")


def _require_epoch(value: object, expected: int | None = None) -> int:
    if type(value) is not int or value <= 0:
        raise ValueError("timestamp")
    if expected is not None and value != expected:
        raise ValueError("run start binding")
    return value


def validate(
    path: str,
    serial: str,
    run_id: str,
    run_started_at: int,
    flutter_sha: str,
    backend_sha: str,
) -> tuple[int, int, int, int]:
    value = Path(path)
    if not value.is_absolute() or value.is_symlink() or not value.is_file():
        raise ValueError("evidence unavailable")
    payload = json.loads(value.read_text(encoding="utf-8"))
    if not isinstance(payload, dict) or set(payload) != TOP_LEVEL_KEYS:
        raise ValueError("schema")
    if payload.get("schema") != SCHEMA or payload.get("status") != "OK":
        raise ValueError("schema")
    if payload.get("secrets") is not False:
        raise ValueError("secrets")
    if payload.get("serial") != serial:
        raise ValueError("serial binding")
    _require_sha(payload.get("flutterSha"), flutter_sha)
    _require_sha(payload.get("backendSha"), backend_sha)
    _require_run_id(payload.get("runId"), run_id)
    _require_epoch(payload.get("runStartedAt"), run_started_at)
    observed_at = _require_epoch(payload.get("observedAt"))
    if observed_at < run_started_at or observed_at > int(time.time()) + 60:
        raise ValueError("observation timestamp")
    if payload.get("evidenceSource") != "read-only-db":
        raise ValueError("evidence source")
    payment = payload.get("payment")
    if (
        not isinstance(payment, dict)
        or set(payment)
        != {"provider", "status", "databaseStatus", "canceledOrderCount"}
        or payment.get("provider") != "alipay-sandbox"
        or payment.get("status") != "CANCELED"
        or payment.get("databaseStatus") != "CANCELLED"
        or type(payment.get("canceledOrderCount")) is not int
        or payment.get("canceledOrderCount") != 1
    ):
        raise ValueError("cancelled order binding")
    counters = payload.get("writeCounters")
    if not isinstance(counters, dict) or set(counters) != set(COUNTER_KEYS):
        raise ValueError("counter schema")
    result: list[int] = []
    for name in COUNTER_KEYS:
        if type(counters.get(name)) is not int or counters.get(name) != 0:
            raise ValueError("counter")
        result.append(0)
    return tuple(result)  # type: ignore[return-value]


def main(argv: list[str]) -> int:
    if len(argv) != 7:
        return 2
    try:
        counters = validate(
            argv[1],
            argv[2],
            argv[3],
            int(argv[4]),
            argv[5],
            argv[6],
        )
    except (OSError, UnicodeError, ValueError, json.JSONDecodeError):
        return 1
    print(" ".join(str(item) for item in counters))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
