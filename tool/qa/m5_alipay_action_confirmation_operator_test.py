#!/usr/bin/env python3
"""Provider-free tests for the action-confirmation operator transport."""

from __future__ import annotations

import http.server
import json
from pathlib import Path
import stat
import tempfile
import threading
import unittest

from m5_alipay_action_confirmation_operator import (
    EXPECTED_SUCCESS_CONFIRMATION,
    _get_pending,
    _post,
    _read_token,
    _safe_private_file,
    approve_pending,
)
from m5_alipay_action_gate import (
    ACTION_CONFIRMATION_REQUIRED,
    ActionConfirmationGate,
    ActionGateError,
    ActionIdentity,
)


class RedirectHandler(http.server.BaseHTTPRequestHandler):
    seen_paths: list[str] = []
    seen_authorizations: list[str | None] = []

    def do_POST(self) -> None:
        type(self).seen_paths.append(self.path)
        type(self).seen_authorizations.append(self.headers.get("Authorization"))
        self.send_response(302)
        self.send_header(
            "Location",
            f"http://127.0.0.1:{self.server.server_port}/captured",
        )
        self.end_headers()

    def do_GET(self) -> None:
        type(self).seen_paths.append(self.path)
        type(self).seen_authorizations.append(self.headers.get("Authorization"))
        self.send_response(302)
        self.send_header(
            "Location",
            f"http://127.0.0.1:{self.server.server_port}/captured",
        )
        self.end_headers()

    def log_message(self, *_args) -> None:
        return


class OversizedResponseHandler(http.server.BaseHTTPRequestHandler):
    def _reply(self) -> None:
        body = b"{" + b"a" * 4096 + b"}"
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:
        self._reply()

    def do_POST(self) -> None:
        self._reply()

    def log_message(self, *_args) -> None:
        return


class OperatorTransportTest(unittest.TestCase):
    def test_canonical_0600_operator_file_is_accepted(self) -> None:
        with tempfile.TemporaryDirectory() as raw_directory:
            directory = Path(raw_directory).resolve(strict=True)
            directory.chmod(0o700)
            operator_file = directory / "operator-token"
            operator_file.write_text("a" * 64, encoding="ascii")
            operator_file.chmod(0o600)
            self.assertEqual(
                stat.S_IMODE(operator_file.stat().st_mode),
                0o600,
            )
            self.assertEqual(_safe_private_file(str(operator_file)), operator_file)
            self.assertEqual(_read_token(operator_file), "a" * 64)

    def test_redirect_is_rejected_without_forwarding_bearer(self) -> None:
        RedirectHandler.seen_paths = []
        RedirectHandler.seen_authorizations = []
        server = http.server.ThreadingHTTPServer(
            ("127.0.0.1", 0),
            RedirectHandler,
        )
        worker = threading.Thread(target=server.serve_forever, daemon=True)
        worker.start()
        try:
            payload = {
                "runId": "m5-redirect-test",
                "avd": "AVD-A",
                "serial": "emulator-5554",
                "backendSha": "a" * 40,
                "flutterSha": "b" * 40,
                "orderNo": "order-redirect-test",
                "requestId": "request-redirect-test",
                "account": "development-account-001",
                "productId": "recharge-product-001",
                "amountMinor": 100,
                "giftCoinAmount": 100,
                "provider": "ALIPAY",
                "status": "CREATED",
                "confirmation": "I_UNDERSTAND_SANDBOX_SUCCESS_PAYMENT",
            }
            accepted = _post(server.server_port, "a" * 64, payload)
            self.assertFalse(accepted)
            self.assertEqual(
                RedirectHandler.seen_paths,
                ["/m5/alipay/action-confirmation/approve"],
            )
            self.assertEqual(
                RedirectHandler.seen_authorizations,
                ["Bearer " + "a" * 64],
            )
            RedirectHandler.seen_paths = []
            RedirectHandler.seen_authorizations = []
            with self.assertRaisesRegex(ValueError, "pending"):
                _get_pending(server.server_port, "b" * 64)
            self.assertEqual(
                RedirectHandler.seen_paths,
                ["/m5/alipay/action-confirmation/pending"],
            )
            self.assertEqual(
                RedirectHandler.seen_authorizations,
                ["Bearer " + "b" * 64],
            )
        finally:
            server.shutdown()
            server.server_close()
            worker.join(timeout=2)

    def test_oversized_pending_or_approval_response_is_rejected(self) -> None:
        server = http.server.ThreadingHTTPServer(
            ("127.0.0.1", 0),
            OversizedResponseHandler,
        )
        worker = threading.Thread(target=server.serve_forever, daemon=True)
        worker.start()
        try:
            with self.assertRaisesRegex(ValueError, "pending"):
                _get_pending(server.server_port, "a" * 64)
            self.assertFalse(
                _post(
                    server.server_port,
                    "a" * 64,
                    {"confirmation": EXPECTED_SUCCESS_CONFIRMATION},
                )
            )
        finally:
            server.shutdown()
            server.server_close()
            worker.join(timeout=2)


class PendingApprovalHandler(http.server.BaseHTTPRequestHandler):
    pending = {
        "runId": "m5-pending-test",
        "avd": "AVD-A",
        "serial": "emulator-5554",
        "backendSha": "a" * 40,
        "flutterSha": "b" * 40,
        "orderNo": "vs-alipay-pending-001",
        "requestId": "alipay-pending-request-001",
        "account": "development-account-001",
        "productId": "recharge-product-001",
        "amountMinor": 100,
        "giftCoinAmount": 100,
        "provider": "ALIPAY",
        "status": "CREATED",
    }
    operator_token = "c" * 64
    gate: ActionConfirmationGate
    markers: list[str] = []
    approved_payload: dict[str, object] | None = None

    @classmethod
    def identity(cls) -> ActionIdentity:
        return ActionIdentity(
            run_id=cls.pending["runId"],
            avd=cls.pending["avd"],
            serial=cls.pending["serial"],
            backend_sha=cls.pending["backendSha"],
            flutter_sha=cls.pending["flutterSha"],
            order_no=cls.pending["orderNo"],
            request_id=cls.pending["requestId"],
            account=cls.pending["account"],
            product_id=cls.pending["productId"],
            amount_minor=cls.pending["amountMinor"],
            gift_coin_amount=cls.pending["giftCoinAmount"],
            provider=cls.pending["provider"],
            status=cls.pending["status"],
        )

    @classmethod
    def reset(cls) -> None:
        cls.approved_payload = None
        cls.markers = []
        identity = cls.identity()
        cls.gate = ActionConfirmationGate(
            enabled=True,
            expected_run_id=identity.run_id,
            expected_avd=identity.avd,
            expected_serial=identity.serial,
            expected_backend_sha=identity.backend_sha,
            expected_flutter_sha=identity.flutter_sha,
            ttl_seconds=30,
            marker_sink=cls.markers.append,
        )
        cls.gate.request(identity)

    def _authorized(self) -> bool:
        return self.headers.get("Authorization") == (
            "Bearer " + type(self).operator_token
        )

    def _reply(self, status: int, value: object) -> None:
        body = json.dumps(value, separators=(",", ":")).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:
        if self.path != "/m5/alipay/action-confirmation/pending":
            self._reply(404, {"error": "not_found"})
            return
        if not self._authorized():
            self._reply(401, {"error": "unauthorized"})
            return
        self._reply(200, {"pending": True, **type(self).pending})

    def do_POST(self) -> None:
        if self.path != "/m5/alipay/action-confirmation/approve":
            self._reply(404, {"error": "not_found"})
            return
        if not self._authorized():
            self._reply(401, {"error": "unauthorized"})
            return
        length = int(self.headers.get("Content-Length", "0"))
        payload = json.loads(self.rfile.read(length))
        type(self).approved_payload = payload
        identity_fields = {
            key: payload[key]
            for key in type(self).pending
        }
        try:
            type(self).gate.approve(
                ActionIdentity(
                    run_id=identity_fields["runId"],
                    avd=identity_fields["avd"],
                    serial=identity_fields["serial"],
                    backend_sha=identity_fields["backendSha"],
                    flutter_sha=identity_fields["flutterSha"],
                    order_no=identity_fields["orderNo"],
                    request_id=identity_fields["requestId"],
                    account=identity_fields["account"],
                    product_id=identity_fields["productId"],
                    amount_minor=identity_fields["amountMinor"],
                    gift_coin_amount=identity_fields["giftCoinAmount"],
                    provider=identity_fields["provider"],
                    status=identity_fields["status"],
                ),
                payload["confirmation"],
            )
        except (KeyError, TypeError, ActionGateError):
            self._reply(409, {"accepted": False})
            return
        self._reply(200, {"accepted": True})

    def log_message(self, *_args) -> None:
        return


class PendingIdentityOperatorTest(unittest.TestCase):
    def test_operator_approves_relay_pending_identity_without_reconstruction(self) -> None:
        PendingApprovalHandler.reset()
        server = http.server.ThreadingHTTPServer(
            ("127.0.0.1", 0),
            PendingApprovalHandler,
        )
        worker = threading.Thread(target=server.serve_forever, daemon=True)
        worker.start()
        try:
            self.assertTrue(
                approve_pending(
                    server.server_port,
                    PendingApprovalHandler.operator_token,
                    EXPECTED_SUCCESS_CONFIRMATION,
                )
            )
            self.assertEqual(
                PendingApprovalHandler.markers,
                [ACTION_CONFIRMATION_REQUIRED],
            )
            self.assertEqual(
                PendingApprovalHandler.approved_payload,
                {
                    **PendingApprovalHandler.pending,
                    "confirmation": EXPECTED_SUCCESS_CONFIRMATION,
                },
            )
            self.assertTrue(
                PendingApprovalHandler.gate.consume(PendingApprovalHandler.identity())
            )
        finally:
            server.shutdown()
            server.server_close()
            worker.join(timeout=2)


if __name__ == "__main__":
    unittest.main()
