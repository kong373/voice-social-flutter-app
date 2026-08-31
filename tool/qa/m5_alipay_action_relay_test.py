#!/usr/bin/env python3
"""Exercise the focused runner relay without a device or payment provider."""

from __future__ import annotations

import http.client
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time
import unittest


PROJECT_ROOT = Path(__file__).resolve().parents[2]
RUNNER = PROJECT_ROOT / "tool/qa/run_alipay_focused_success.sh"
FULL_RUNNER = PROJECT_ROOT / "tool/qa/run_m5_vendor_live_avd.sh"
APP_TOKEN = "a" * 64
RECEIVER_TOKEN = "e" * 64
OPERATOR_TOKEN = "b" * 64
READY_TOKEN = "f" * 64
RUN_ID = "m5-relay-test"
BACKEND_SHA = "c" * 40
FLUTTER_SHA = "d" * 40
IDENTITY = {
    "runId": RUN_ID,
    "avd": "AVD-A",
    "serial": "emulator-5554",
    "backendSha": BACKEND_SHA,
    "flutterSha": FLUTTER_SHA,
    "orderNo": "vs-alipay-relay-test-001",
    "requestId": "alipay-relay-request-001",
    "account": "development-account-001",
    "productId": "recharge-product-001",
    "amountMinor": 100,
    "giftCoinAmount": 100,
    "provider": "ALIPAY",
    "status": "CREATED",
}


def _relay_source() -> str:
    source = RUNNER.read_text(encoding="utf-8")
    match = re.search(
        r"python3 -u - >/dev/null 2>&1 <<'PY' &\n"
        r"(?P<python>.*?)\nPY\n",
        source,
        flags=re.DOTALL,
    )
    if match is None:
        raise AssertionError("focused relay heredoc is missing")
    return match.group("python")


def _full_relay_source() -> str:
    source = FULL_RUNNER.read_text(encoding="utf-8")
    match = re.search(
        r"PYTHONDONTWRITEBYTECODE=1 \\\n"
        r"\s+PYTHONPATH=\"\$PROJECT_ROOT/tool/qa\$\{PYTHONPATH:\+:\$PYTHONPATH\}\" \\\n"
        r"\s+python3 -B -u - >/dev/null 2>&1 <<'PY' &\n"
        r"(?P<python>.*?)\nPY\n",
        source,
        flags=re.DOTALL,
    )
    if match is None:
        raise AssertionError("full M5 relay heredoc is missing")
    return match.group("python")


def _full_sanitizer_source() -> str:
    source = FULL_RUNNER.read_text(encoding="utf-8")
    match = re.search(
        r"sanitize_stream\(\) \{\n.*?python3 -u -c '\n"
        r"(?P<python>.*?)\n'\n\}",
        source,
        flags=re.DOTALL,
    )
    if match is None:
        raise AssertionError("full M5 sanitizer source is missing")
    return match.group("python")


def _request(
    port: int,
    method: str,
    path: str,
    token: str,
    payload: dict[str, object] | None = None,
) -> tuple[int, dict[str, object]]:
    body = json.dumps(payload, separators=(",", ":")).encode() if payload else b""
    connection = http.client.HTTPConnection("127.0.0.1", port, timeout=3)
    try:
        connection.request(
            method,
            path,
            body=body,
            headers={
                "Authorization": "Bearer " + token,
                "Content-Type": "application/json",
                "Content-Length": str(len(body)),
            },
        )
        response = connection.getresponse()
        value = json.loads(response.read())
        return response.status, value
    finally:
        connection.close()


def _request_with_authorizations(
    port: int,
    method: str,
    path: str,
    authorizations: list[str],
    payload: dict[str, object] | None = None,
) -> tuple[int, dict[str, object]]:
    body = json.dumps(payload, separators=(",", ":")).encode() if payload else b""
    connection = http.client.HTTPConnection("127.0.0.1", port, timeout=3)
    try:
        connection.putrequest(method, path)
        for value in authorizations:
            connection.putheader("Authorization", value)
        connection.putheader("Content-Type", "application/json")
        connection.putheader("Content-Length", str(len(body)))
        connection.endheaders(body)
        response = connection.getresponse()
        value = json.loads(response.read())
        return response.status, value
    finally:
        connection.close()


def _full_environment(marker: Path, ready: Path) -> dict[str, str]:
    return {
        "QA_LIVE_PHONE": "13800000001",
        "QA_M5_RECEIVER_PHONE": "13800000002",
        "QA_OAUTH_CLIENT_ID": "voice-social-mobile-public",
        "QA_M5_RELAY_TOKEN_A": APP_TOKEN,
        "QA_M5_RELAY_TOKEN_B": RECEIVER_TOKEN,
        "QA_M5_RUN_ID": RUN_ID,
        "QA_M5_ACTION_GATE_ENABLED": "true",
        "QA_M5_BACKEND_SHA": BACKEND_SHA,
        "QA_M5_FLUTTER_SHA": FLUTTER_SHA,
        "QA_M5_ACTION_SERIAL": "emulator-5554",
        "QA_M5_AVD_B_SERIAL": "emulator-5556",
        "QA_M5_ACTION_OPERATOR_TOKEN": OPERATOR_TOKEN,
        "QA_M5_ACTION_MARKER_FILE": str(marker),
        "QA_M5_ACTION_READY_FILE": str(ready),
        "QA_M5_READY_TOKEN": READY_TOKEN,
        "PYTHONPATH": str(PROJECT_ROOT / "tool/qa"),
        "PYTHONDONTWRITEBYTECODE": "1",
    }


def _wait_for_relay(process: subprocess.Popen[bytes], ready: Path) -> int:
    for _ in range(60):
        if process.poll() is not None:
            raise AssertionError("relay exited before becoming ready")
        try:
            value = json.loads(ready.read_text(encoding="ascii"))
            if (
                value.get("pid") == process.pid
                and type(value.get("port")) is int
                and 1 <= value["port"] <= 65535
            ):
                return value["port"]
        except (FileNotFoundError, json.JSONDecodeError, OSError):
            pass
        time.sleep(0.05)
    raise AssertionError("relay did not become ready")


class FocusedRelayTest(unittest.TestCase):
    def test_full_relay_launcher_disables_python_bytecode_writes(self) -> None:
        source = FULL_RUNNER.read_text(encoding="utf-8")
        self.assertRegex(
            source,
            r"PYTHONDONTWRITEBYTECODE=1 \\\n"
            r"\s+PYTHONPATH=\"\$PROJECT_ROOT/tool/qa\$\{PYTHONPATH:\+:\$PYTHONPATH\}\" \\\n"
            r"\s+python3 -B -u - >/dev/null 2>&1 <<'PY' &",
        )

    def test_full_sanitizer_drops_signed_payment_payload_lines(self) -> None:
        raw_lines = (
            "orderStr=app_id=public&sign=signed-payload\n"
            "ORDERINFO:method=alipay.trade.app.pay&biz_content=payload\n"
            "orderString=opaque-payment-blob\n"
            '{"orderStr":"quoted-payment-blob"}\n'
            "alipay_sdk=alipay-sdk-java-4.0&sign_type=RSA2\n"
            "method=alipay.trade.app.pay&app_id=public\n"
            "safe-marker\n"
        )
        environment = {
            name: ""
            for name in (
                "M5_SECRET_PHONE",
                "M5_SECRET_RECEIVER_PHONE",
                "M5_SECRET_CLIENT",
                "M5_SECRET_DB_TOKEN",
                "M5_SECRET_RELAY_A",
                "M5_SECRET_RELAY_B",
                "M5_SECRET_ACTION_OPERATOR",
            )
        }
        completed = subprocess.run(
            [sys.executable, "-u", "-c", _full_sanitizer_source()],
            input=raw_lines,
            text=True,
            capture_output=True,
            env=environment,
            check=True,
        )
        self.assertEqual(
            completed.stdout,
            "[REDACTED_ALIPAY_PAYMENT_PAYLOAD]\n" * 6 + "safe-marker\n",
        )
        for forbidden in (
            "orderStr",
            "ORDERINFO",
            "orderString",
            "alipay_sdk",
            "alipay.trade.app.pay",
        ):
            self.assertNotIn(forbidden, completed.stdout)

    def test_request_pending_operator_approve_consume_sequence(self) -> None:
        source = _relay_source()
        with tempfile.TemporaryDirectory(prefix="m5-relay-test-") as directory:
            private_directory = Path(directory).resolve()
            private_directory.chmod(0o700)
            marker = private_directory / "marker"
            ready = private_directory / "relay-ready"
            marker.touch(mode=0o600)
            environment = {
                "QA_M5_ACTION_APP_TOKEN": APP_TOKEN,
                "QA_M5_ACTION_OPERATOR_TOKEN": OPERATOR_TOKEN,
                "QA_M5_ACTION_MARKER_FILE": str(marker),
                "QA_M5_ACTION_READY_FILE": str(ready),
                "QA_M5_ACTION_RUN_ID": RUN_ID,
                "QA_M5_ACTION_BACKEND_SHA": BACKEND_SHA,
                "QA_M5_ACTION_FLUTTER_SHA": FLUTTER_SHA,
                "PYTHONPATH": str(PROJECT_ROOT / "tool/qa"),
                "PYTHONDONTWRITEBYTECODE": "1",
            }
            process = subprocess.Popen(
                [sys.executable, "-u", "-c", source],
                env=environment,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            try:
                port = 0
                for _ in range(60):
                    if process.poll() is not None:
                        self.fail("focused relay exited before becoming ready")
                    try:
                        value = json.loads(ready.read_text(encoding="ascii"))
                        candidate = value.get("port")
                        ready_pid = value.get("pid")
                        if (
                            type(candidate) is int
                            and 1 <= candidate <= 65535
                            and ready_pid == process.pid
                        ):
                            port = candidate
                            break
                    except (FileNotFoundError, json.JSONDecodeError, OSError):
                        time.sleep(0.05)
                else:
                    self.fail("focused relay did not become ready")

                for method, path, token, payload in (
                    (
                        "POST",
                        "/m5/alipay/action-confirmation/request",
                        "wrong-token",
                        IDENTITY,
                    ),
                    (
                        "GET",
                        "/m5/alipay/action-confirmation/pending",
                        "wrong-token",
                        None,
                    ),
                    (
                        "POST",
                        "/m5/alipay/action-confirmation/approve",
                        "wrong-token",
                        {**IDENTITY, "confirmation": "I_UNDERSTAND_SANDBOX_SUCCESS_PAYMENT"},
                    ),
                    (
                        "POST",
                        "/m5/alipay/action-confirmation/consume",
                        "wrong-token",
                        IDENTITY,
                    ),
                ):
                    with self.subTest(path=path):
                        status, _ = _request(port, method, path, token, payload)
                        self.assertEqual(status, 401)

                duplicate_status, _ = _request_with_authorizations(
                    port,
                    "POST",
                    "/m5/alipay/action-confirmation/request",
                    ["Bearer " + APP_TOKEN, "Bearer " + APP_TOKEN],
                    IDENTITY,
                )
                self.assertEqual(duplicate_status, 401)

                status, value = _request(
                    port,
                    "POST",
                    "/m5/alipay/action-confirmation/request",
                    APP_TOKEN,
                    IDENTITY,
                )
                self.assertEqual(status, 200)
                self.assertEqual(value, {"accepted": True, "status": "PENDING"})

                status, value = _request(
                    port,
                    "GET",
                    "/m5/alipay/action-confirmation/pending",
                    OPERATOR_TOKEN,
                )
                self.assertEqual(status, 200)
                self.assertEqual(value, {"pending": True, **IDENTITY})
                self.assertEqual(marker.read_text(encoding="ascii"), "ACTION_CONFIRMATION_REQUIRED\n")

                status, value = _request(
                    port,
                    "POST",
                    "/m5/alipay/action-confirmation/approve",
                    OPERATOR_TOKEN,
                    {
                        **IDENTITY,
                        "confirmation": "I_UNDERSTAND_SANDBOX_SUCCESS_PAYMENT",
                    },
                )
                self.assertEqual(status, 200)
                self.assertEqual(value, {"accepted": True})

                status, value = _request(
                    port,
                    "POST",
                    "/m5/alipay/action-confirmation/consume",
                    APP_TOKEN,
                    IDENTITY,
                )
                self.assertEqual(status, 200)
                self.assertEqual(value, {"approved": True})

                replay_status, replay_value = _request(
                    port,
                    "POST",
                    "/m5/alipay/action-confirmation/consume",
                    APP_TOKEN,
                    IDENTITY,
                )
                self.assertEqual(replay_status, 409)
                self.assertEqual(replay_value.get("error"), "REPLAY")

                status, value = _request(
                    port,
                    "GET",
                    "/m5/alipay/action-confirmation/pending",
                    OPERATOR_TOKEN,
                )
                self.assertEqual(status, 409)
                self.assertEqual(value, {"pending": False})
            finally:
                process.terminate()
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=3)

    def test_full_relay_enforces_auth_identity_and_one_time_consumption(self) -> None:
        source = _full_relay_source()
        with tempfile.TemporaryDirectory(prefix="m5-full-relay-test-") as directory:
            private_directory = Path(directory).resolve()
            private_directory.chmod(0o700)
            marker = private_directory / "marker"
            ready = private_directory / "relay-ready"
            marker.touch(mode=0o600)
            process = subprocess.Popen(
                [sys.executable, "-u", "-c", source],
                env=_full_environment(marker, ready),
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            try:
                port = _wait_for_relay(process, ready)

                status, value = _request(
                    port, "GET", "/m5/relay/status", READY_TOKEN
                )
                self.assertEqual((status, value), (200, {"ready": True}))
                status, _ = _request(
                    port,
                    "POST",
                    "/m5/alipay/action-confirmation/request",
                    RECEIVER_TOKEN,
                    {**IDENTITY, "avd": "AVD-B", "serial": "emulator-5556"},
                )
                self.assertEqual(status, 409)
                status, _ = _request(
                    port,
                    "POST",
                    "/m5/alipay/action-confirmation/request",
                    "wrong-token",
                    IDENTITY,
                )
                self.assertEqual(status, 401)
                duplicate_status, _ = _request_with_authorizations(
                    port,
                    "POST",
                    "/m5/alipay/action-confirmation/request",
                    ["Bearer " + APP_TOKEN, "Bearer " + APP_TOKEN],
                    IDENTITY,
                )
                self.assertEqual(duplicate_status, 401)

                status, value = _request(
                    port,
                    "POST",
                    "/m5/alipay/action-confirmation/request",
                    APP_TOKEN,
                    IDENTITY,
                )
                self.assertEqual((status, value), (200, {"accepted": True, "status": "PENDING"}))
                status, value = _request(
                    port,
                    "GET",
                    "/m5/alipay/action-confirmation/pending",
                    OPERATOR_TOKEN,
                )
                self.assertEqual(status, 200)
                self.assertEqual(value, {"pending": True, **IDENTITY})
                self.assertEqual(marker.read_text(encoding="ascii"), "ACTION_CONFIRMATION_REQUIRED\n")

                status, value = _request(
                    port,
                    "POST",
                    "/m5/alipay/action-confirmation/approve",
                    OPERATOR_TOKEN,
                    {
                        **IDENTITY,
                        "confirmation": "I_UNDERSTAND_SANDBOX_SUCCESS_PAYMENT",
                    },
                )
                self.assertEqual((status, value), (200, {"accepted": True}))
                status, value = _request(
                    port,
                    "POST",
                    "/m5/alipay/action-confirmation/consume",
                    APP_TOKEN,
                    IDENTITY,
                )
                self.assertEqual((status, value), (200, {"approved": True}))
                status, value = _request(
                    port,
                    "POST",
                    "/m5/alipay/action-confirmation/consume",
                    APP_TOKEN,
                    IDENTITY,
                )
                self.assertEqual(status, 409)
                self.assertEqual(value.get("error"), "REPLAY")
            finally:
                process.terminate()
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=3)

    def test_full_relay_requires_exact_receiver_group_ready_before_sender_proceeds(self) -> None:
        source = _full_relay_source()
        with tempfile.TemporaryDirectory(prefix="m5-full-relay-avchatroom-") as directory:
            private_directory = Path(directory).resolve()
            private_directory.chmod(0o700)
            marker = private_directory / "marker"
            ready = private_directory / "relay-ready"
            marker.touch(mode=0o600)
            process = subprocess.Popen(
                [sys.executable, "-u", "-c", source],
                env=_full_environment(marker, ready),
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            try:
                port = _wait_for_relay(process, ready)
                room_id = "m5-room-001"

                status, value = _request(
                    port,
                    "POST",
                    "/m5/avchatroom/ready",
                    APP_TOKEN,
                    {"roomId": room_id},
                )
                self.assertEqual((status, value), (200, {"accepted": True}))

                status, value = _request(
                    port,
                    "GET",
                    "/m5/avchatroom/receiver-joined",
                    APP_TOKEN,
                )
                self.assertEqual(
                    (status, value),
                    (200, {"ready": False, "roomId": None}),
                )

                for payload in (
                    {"runId": "stale-run", "role": "receiver", "roomId": room_id},
                    {"runId": RUN_ID, "role": "sender", "roomId": room_id},
                    {"runId": RUN_ID, "role": "receiver", "roomId": "m5-room-002"},
                ):
                    with self.subTest(payload=payload):
                        status, _ = _request(
                            port,
                            "POST",
                            "/m5/avchatroom/receiver-joined",
                            RECEIVER_TOKEN,
                            payload,
                        )
                        self.assertEqual(status, 409)
                        status, value = _request(
                            port,
                            "GET",
                            "/m5/avchatroom/receiver-joined",
                            APP_TOKEN,
                        )
                        self.assertEqual(
                            (status, value),
                            (200, {"ready": False, "roomId": None}),
                        )

                status, value = _request(
                    port,
                    "POST",
                    "/m5/avchatroom/receiver-joined",
                    RECEIVER_TOKEN,
                    {"runId": RUN_ID, "role": "receiver", "roomId": room_id},
                )
                self.assertEqual((status, value), (200, {"accepted": True}))

                status, value = _request(
                    port,
                    "GET",
                    "/m5/avchatroom/receiver-joined",
                    APP_TOKEN,
                )
                self.assertEqual(
                    (status, value),
                    (200, {"ready": True, "roomId": room_id}),
                )

                status, value = _request(
                    port,
                    "POST",
                    "/m5/avchatroom/receiver-joined",
                    RECEIVER_TOKEN,
                    {"runId": RUN_ID, "role": "receiver", "roomId": "m5-room-002"},
                )
                self.assertEqual(status, 409)
                self.assertEqual(value.get("error"), "room_id_mismatch")
            finally:
                process.terminate()
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=3)

    def test_full_relay_expiry_hides_identity_and_rejects_approval(self) -> None:
        source = _full_relay_source().replace(
            "ttl_seconds=120", "ttl_seconds=0.05", 1
        )
        self.assertIn("ttl_seconds=0.05", source)
        with tempfile.TemporaryDirectory(prefix="m5-full-relay-expiry-") as directory:
            private_directory = Path(directory).resolve()
            private_directory.chmod(0o700)
            marker = private_directory / "marker"
            ready = private_directory / "relay-ready"
            marker.touch(mode=0o600)
            process = subprocess.Popen(
                [sys.executable, "-u", "-c", source],
                env=_full_environment(marker, ready),
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            try:
                port = _wait_for_relay(process, ready)
                status, _ = _request(
                    port,
                    "POST",
                    "/m5/alipay/action-confirmation/request",
                    APP_TOKEN,
                    IDENTITY,
                )
                self.assertEqual(status, 200)
                time.sleep(0.08)
                status, value = _request(
                    port,
                    "GET",
                    "/m5/alipay/action-confirmation/pending",
                    OPERATOR_TOKEN,
                )
                self.assertEqual((status, value), (409, {"pending": False}))
                status, value = _request(
                    port,
                    "GET",
                    "/m5/alipay/action-confirmation/status",
                    OPERATOR_TOKEN,
                )
                self.assertEqual(
                    (status, value),
                    (
                        200,
                        {
                            "pending": False,
                            "approved": False,
                            "consumed": False,
                            "expired": True,
                        },
                    ),
                )
                status, value = _request(
                    port,
                    "POST",
                    "/m5/alipay/action-confirmation/approve",
                    OPERATOR_TOKEN,
                    {
                        **IDENTITY,
                        "confirmation": "I_UNDERSTAND_SANDBOX_SUCCESS_PAYMENT",
                    },
                )
                self.assertEqual(status, 409)
                self.assertEqual(value.get("error"), "EXPIRED")
            finally:
                process.terminate()
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=3)

    def test_http_expiry_hides_pending_identity(self) -> None:
        source = _relay_source().replace("ttl_seconds=120", "ttl_seconds=0.05", 1)
        self.assertIn("ttl_seconds=0.05", source)
        with tempfile.TemporaryDirectory(prefix="m5-relay-expiry-") as directory:
            private_directory = Path(directory).resolve()
            private_directory.chmod(0o700)
            marker = private_directory / "marker"
            ready = private_directory / "relay-ready"
            marker.touch(mode=0o600)
            environment = {
                "QA_M5_ACTION_APP_TOKEN": APP_TOKEN,
                "QA_M5_ACTION_OPERATOR_TOKEN": OPERATOR_TOKEN,
                "QA_M5_ACTION_MARKER_FILE": str(marker),
                "QA_M5_ACTION_READY_FILE": str(ready),
                "QA_M5_ACTION_RUN_ID": RUN_ID,
                "QA_M5_ACTION_BACKEND_SHA": BACKEND_SHA,
                "QA_M5_ACTION_FLUTTER_SHA": FLUTTER_SHA,
                "PYTHONPATH": str(PROJECT_ROOT / "tool/qa"),
                "PYTHONDONTWRITEBYTECODE": "1",
            }
            process = subprocess.Popen(
                [sys.executable, "-u", "-c", source],
                env=environment,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            try:
                port = 0
                for _ in range(60):
                    try:
                        value = json.loads(ready.read_text(encoding="ascii"))
                        if value.get("pid") == process.pid and type(value.get("port")) is int:
                            port = value["port"]
                            break
                    except (FileNotFoundError, json.JSONDecodeError, OSError):
                        pass
                    time.sleep(0.05)
                self.assertGreater(port, 0)
                status, _ = _request(
                    port,
                    "POST",
                    "/m5/alipay/action-confirmation/request",
                    APP_TOKEN,
                    IDENTITY,
                )
                self.assertEqual(status, 200)
                time.sleep(0.08)
                status, value = _request(
                    port,
                    "GET",
                    "/m5/alipay/action-confirmation/pending",
                    OPERATOR_TOKEN,
                )
                self.assertEqual(status, 409)
                self.assertEqual(value, {"pending": False})
            finally:
                process.terminate()
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=3)


if __name__ == "__main__":
    unittest.main()
