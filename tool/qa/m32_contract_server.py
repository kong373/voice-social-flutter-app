#!/usr/bin/env python3
"""Deterministic M3.2 contract server for Android acceptance runs.

The server models only first-party development endpoints. It never contacts a
real SMS, RTC, IM, payment, push, or storage provider. Every request is checked
for the OAuth public-client boundary and recorded as redacted JSONL evidence.
"""

from __future__ import annotations

import argparse
import json
import signal
import threading
import time
from dataclasses import dataclass, field
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, urlparse

PUBLIC_CLIENT_ID = "voice-social-mobile-public"

SEND_SMS = "/app-register-api/util/v1/sendSmsCode"
LOGIN = "/app-register-api/userAccount/v1/loginByMobileAndSmsCode"
REGISTER = "/app-register-api/userAccount/v1/registerByMobile"
REFRESH = "/app-register-api/userAccount/v1/refreshSession"
LOGOUT = "/app-register-api/userAccount/v1/logout"
HOME = "/app-api/rooms/v1/getRecommendRooms"
SEARCH = "/app-api/es/getSearchESResult"
ROOM = "/app-api/rooms/getRoomById"
CURRENT_USER = "/app-register-api/userAccount/v1/current"
NCOIN = "/app-economy-api/ncoin"
WALLET = "/app-mini-api/mini/v1/wallet/overview"
ORDERS = "/app-economy-api/pay/getOrders"
VENDOR_READINESS = "/app-register-api/vendor/v1/readiness"
SUMMARY = "/__qa__/summary"

REQUIRED_ENDPOINTS = {
    SEND_SMS,
    LOGIN,
    HOME,
    SEARCH,
    ROOM,
    CURRENT_USER,
    NCOIN,
    WALLET,
    ORDERS,
    VENDOR_READINESS,
    LOGOUT,
}

PUBLIC_ENDPOINTS = {"/", SEND_SMS, LOGIN, REGISTER, REFRESH, SUMMARY}


@dataclass
class ServerState:
    request_log: Path
    summary_file: Path
    lock: threading.Lock = field(default_factory=threading.Lock)
    observed: set[str] = field(default_factory=set)
    violations: list[str] = field(default_factory=list)
    request_count: int = 0

    def record(
        self,
        *,
        method: str,
        path: str,
        headers: dict[str, str],
        body: Any,
        status: int,
        violation: str | None = None,
    ) -> None:
        with self.lock:
            self.request_count += 1
            if path != SUMMARY:
                self.observed.add(path)
            if violation:
                self.violations.append(violation)
            event = {
                "sequence": self.request_count,
                "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                "method": method,
                "path": path,
                "status": status,
                "clientId": headers.get("client-id"),
                "authorizationPresent": bool(headers.get("authorization")),
                "deviceIdPresent": bool(headers.get("x-device-id")),
                "confidentialOutboxHeadersPresent": bool(
                    headers.get("x-development-client-id")
                    or headers.get("x-development-outbox-key")
                ),
                "bodyKeys": sorted(body.keys()) if isinstance(body, dict) else [],
                "violation": violation,
            }
            self.request_log.parent.mkdir(parents=True, exist_ok=True)
            with self.request_log.open("a", encoding="utf-8") as handle:
                handle.write(json.dumps(event, ensure_ascii=False, sort_keys=True) + "\n")
            self._write_summary_locked()

    def snapshot(self) -> dict[str, Any]:
        with self.lock:
            return self._snapshot_locked()

    def _snapshot_locked(self) -> dict[str, Any]:
        missing = sorted(REQUIRED_ENDPOINTS - self.observed)
        return {
            "contractVersion": "m3.2-avd-contract-v2",
            "providerCallsMade": False,
            "publicClientId": PUBLIC_CLIENT_ID,
            "oauthClientSecretObserved": False,
            "confidentialOutboxCredentialObserved": False,
            "requestCount": self.request_count,
            "observedEndpoints": sorted(self.observed),
            "requiredEndpoints": sorted(REQUIRED_ENDPOINTS),
            "missingEndpoints": missing,
            "violations": list(self.violations),
            "conclusion": "PASS" if not missing and not self.violations else "INCOMPLETE",
        }

    def _write_summary_locked(self) -> None:
        self.summary_file.parent.mkdir(parents=True, exist_ok=True)
        self.summary_file.write_text(
            json.dumps(self._snapshot_locked(), ensure_ascii=False, indent=2, sort_keys=True),
            encoding="utf-8",
        )


class ContractHandler(BaseHTTPRequestHandler):
    server_version = "VoiceSocialM32Contract/2.0"
    protocol_version = "HTTP/1.1"

    @property
    def state(self) -> ServerState:
        return self.server.state  # type: ignore[attr-defined]

    def log_message(self, fmt: str, *args: Any) -> None:
        return

    def do_GET(self) -> None:  # noqa: N802
        self._dispatch()

    def do_POST(self) -> None:  # noqa: N802
        self._dispatch()

    def do_PUT(self) -> None:  # noqa: N802
        self._dispatch()

    def do_PATCH(self) -> None:  # noqa: N802
        self._dispatch()

    def do_DELETE(self) -> None:  # noqa: N802
        self._dispatch()

    def _dispatch(self) -> None:
        parsed = urlparse(self.path)
        path = parsed.path
        headers = {key.lower(): value for key, value in self.headers.items()}
        body = self._read_json_body()
        violation = self._validate_request(path, headers, body)
        if violation:
            self._respond(
                path=path,
                headers=headers,
                body=body,
                status=HTTPStatus.BAD_REQUEST,
                payload={"code": 40090, "message": violation, "data": None},
                violation=violation,
            )
            return

        try:
            data = self._data_for(path, parsed.query, body)
        except KeyError:
            self._respond(
                path=path,
                headers=headers,
                body=body,
                status=HTTPStatus.NOT_FOUND,
                payload={"code": 404, "message": "NOT_FOUND", "data": None},
            )
            return
        except ValueError as error:
            message = str(error)
            self._respond(
                path=path,
                headers=headers,
                body=body,
                status=HTTPStatus.BAD_REQUEST,
                payload={"code": 40091, "message": message, "data": None},
                violation=message,
            )
            return

        payload = data if path == SUMMARY else {"code": 200, "message": "OK", "data": data}
        self._respond(
            path=path,
            headers=headers,
            body=body,
            status=HTTPStatus.OK,
            payload=payload,
        )

    def _read_json_body(self) -> Any:
        raw_length = self.headers.get("Content-Length")
        length = int(raw_length) if raw_length and raw_length.isdigit() else 0
        if length <= 0:
            return None
        if length > 1024 * 1024:
            raise ValueError("REQUEST_BODY_TOO_LARGE")
        raw = self.rfile.read(length)
        if not raw.strip():
            return None
        try:
            return json.loads(raw.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise ValueError("INVALID_JSON") from error

    def _validate_request(
        self,
        path: str,
        headers: dict[str, str],
        body: Any,
    ) -> str | None:
        lowered_headers = json.dumps(headers, sort_keys=True).lower()
        lowered_body = json.dumps(body, sort_keys=True).lower() if body is not None else ""
        forbidden_tokens = (
            "oauth_client_secret",
            "client-secret",
            "clientsecret",
            "development_outbox_key",
            "x-development-outbox-key",
            "access-key-secret",
            "app-certificate",
            "secret-key",
            "private-key",
            "webhook-secret",
        )
        if any(token in lowered_headers or token in lowered_body for token in forbidden_tokens):
            return "MOBILE_SECRET_BOUNDARY_VIOLATION"

        if path not in {"/", SUMMARY}:
            if headers.get("client-id") != PUBLIC_CLIENT_ID:
                return "PUBLIC_CLIENT_ID_REQUIRED"

        authorization = headers.get("authorization", "")
        if path not in PUBLIC_ENDPOINTS and authorization not in {
            "Bearer access-1",
            "Bearer access-2",
        }:
            return "BEARER_TOKEN_REQUIRED"
        if path in {SEND_SMS, LOGIN, REGISTER, REFRESH} and authorization:
            return "PUBLIC_AUTH_ENDPOINT_MUST_NOT_SEND_BEARER"
        return None

    def _data_for(self, path: str, raw_query: str, body: Any) -> Any:
        query = parse_qs(raw_query)
        if path == "/":
            return {"status": "UP", "providerCallsMade": False}
        if path == SUMMARY:
            return self.state.snapshot()
        if path == SEND_SMS:
            if self.command != "PUT":
                raise ValueError("SEND_SMS_REQUIRES_PUT")
            if query.get("mobileNumber", [""])[0] != "13800138000":
                raise ValueError("UNEXPECTED_MOBILE_NUMBER")
            if not self.headers.get("X-Device-Id"):
                raise ValueError("DEVICE_ID_REQUIRED")
            return {
                "challengeId": "challenge-1",
                "expiresIn": 300,
                "retryAfter": 1,
                "developmentCode": "123456",
            }
        if path == LOGIN:
            self._require_body_values(
                body,
                phone="13800138000",
                smsCode="123456",
                clientId=PUBLIC_CLIENT_ID,
            )
            return self._token("access-1", "refresh-1")
        if path == REGISTER:
            return self._token("access-1", "refresh-1")
        if path == REFRESH:
            self._require_body_values(body, refreshToken="refresh-1")
            return self._token("access-2", "refresh-2")
        if path == LOGOUT:
            return None
        if path == HOME:
            return {
                "records": [
                    {
                        "roomIdStr": "880217",
                        "roomCode": "880217",
                        "roomName": "深夜陪伴电台",
                        "description": "轻松陪伴，分享今天发生的小确幸",
                        "liveCount": 27,
                        "heatValue": 88,
                        "micUserHeadImgs": ["a", "b", "c"],
                        "userId": 20001,
                        "nickName": "南风",
                        "isLockRoom": 0,
                    },
                    {
                        "roomIdStr": "990018",
                        "roomCode": "990018",
                        "roomName": "新朋友友好房",
                        "description": "先听听也很好，随时欢迎加入聊天",
                        "liveCount": 12,
                        "heatValue": 0,
                        "micUserHeadImgs": ["a"],
                        "userId": 20002,
                        "nickName": "小屿",
                        "isLockRoom": 0,
                    },
                ],
                "total": 2,
            }
        if path == SEARCH:
            keyword = str(body.get("keyword", "")) if isinstance(body, dict) else ""
            return {
                "roomsList": [
                    {
                        "roomIdStr": "880217",
                        "roomCode": "880217",
                        "roomName": "深夜陪伴电台",
                        "description": f"与“{keyword}”相关的语音房",
                        "liveCount": 27,
                        "heatValue": 88,
                        "micUserHeadImgs": ["a", "b", "c"],
                        "userId": 20001,
                        "nickName": "南风",
                    }
                ],
                "usersList": [
                    {
                        "userId": 20001,
                        "nickName": "南风",
                        "loginName": "NF20001",
                        "userType": "房主",
                        "isStayRoom": "880217",
                    }
                ],
                "total": 2,
                "pageNo": 1,
                "pageSize": 20,
            }
        if path == ROOM:
            room_id = query.get("roomId", [""])[0]
            if room_id != "880217":
                raise ValueError("UNKNOWN_ROOM_ID")
            return {
                "roomIdStr": "880217",
                "roomCode": "880217",
                "roomName": "深夜陪伴电台",
                "topicContent": "轻松陪伴，分享今天发生的小确幸",
                "ownerId": 20001,
                "onlineNum": 27,
                "realtimeMode": "HTTP_SNAPSHOT_ONLY",
                "rtcStatus": "VENDOR_BLOCKED",
                "imStatus": "VENDOR_BLOCKED",
                "seats": [
                    {"index": 1, "status": 1, "userId": 20001, "userName": "南风"},
                    {"index": 2, "status": 1, "userId": 20002, "userName": "听众甲"},
                    {"index": 3, "status": 0},
                    {"index": 4, "status": 0},
                    {"index": 5, "status": 0},
                    {"index": 6, "status": 0},
                    {"index": 7, "status": 0},
                    {"index": 8, "status": 0},
                ],
            }
        if path == CURRENT_USER:
            return {
                "userId": 10001,
                "loginName": "account-10001",
                "nickName": "开发验收用户",
                "mobile": "138****8000",
                "roles": "ROLE_USER",
                "status": "ACTIVE",
            }
        if path == NCOIN:
            return {"integer": 8800, "value": 8800}
        if path == WALLET:
            return {"balance": 12.34, "frozenBalance": 5.67}
        if path == ORDERS:
            return {
                "list": [
                    {
                        "orderNo": "P202608180001",
                        "amount": 6,
                        "ncoin": 600,
                        "payType": "微信支付",
                        "status": "SUCCEEDED",
                        "createDate": "2026-08-18T12:00:00Z",
                    }
                ],
                "total": 1,
            }
        if path == VENDOR_READINESS:
            return self._vendor_readiness()
        raise KeyError(path)

    @staticmethod
    def _require_body_values(body: Any, **expected: str) -> None:
        if not isinstance(body, dict):
            raise ValueError("JSON_OBJECT_REQUIRED")
        for key, value in expected.items():
            if str(body.get(key, "")) != value:
                raise ValueError(f"UNEXPECTED_{key.upper()}")

    @staticmethod
    def _token(access_token: str, refresh_token: str) -> dict[str, Any]:
        return {
            "access_token": access_token,
            "token_type": "Bearer",
            "expires_in": 3600,
            "refresh_token": refresh_token,
            "refresh_expires_in": 2592000,
            "userId": 10001,
            "mobile": "138****8000",
            "roles": "ROLE_USER",
            "roomId": None,
        }

    @staticmethod
    def _vendor_readiness() -> dict[str, Any]:
        requirements = {
            "SMS": [
                "app.vendor.sms.provider",
                "app.vendor.sms.access-key-id",
                "app.vendor.sms.access-key-secret",
                "app.vendor.sms.sign-name",
                "app.vendor.sms.login-template-id",
                "app.vendor.sms.adapter-enabled=true",
                "app.vendor.sms.adapter-bean",
            ],
            "RTC": [
                "app.vendor.rtc.provider",
                "app.vendor.rtc.app-id",
                "app.vendor.rtc.app-certificate",
                "app.vendor.rtc.adapter-enabled=true",
                "app.vendor.rtc.adapter-bean",
            ],
            "IM": [
                "app.vendor.im.provider",
                "app.vendor.im.sdk-app-id",
                "app.vendor.im.admin-user",
                "app.vendor.im.secret-key",
                "app.vendor.im.adapter-enabled=true",
                "app.vendor.im.adapter-bean",
            ],
            "PAYMENT": [
                "app.vendor.payment.provider",
                "app.vendor.payment.merchant-id",
                "app.vendor.payment.private-key",
                "app.vendor.payment.webhook-secret",
                "app.vendor.payment.adapter-enabled=true",
                "app.vendor.payment.adapter-bean",
            ],
            "PUSH": [
                "app.vendor.push.provider",
                "app.vendor.push.app-id",
                "app.vendor.push.server-key",
                "app.vendor.push.adapter-enabled=true",
                "app.vendor.push.adapter-bean",
            ],
            "OBJECT_STORAGE": [
                "app.vendor.object-storage.provider",
                "app.vendor.object-storage.bucket",
                "app.vendor.object-storage.region",
                "app.vendor.object-storage.access-key-id",
                "app.vendor.object-storage.access-key-secret",
                "app.vendor.object-storage.adapter-enabled=true",
                "app.vendor.object-storage.adapter-bean",
            ],
        }
        contracts = {
            "SMS": "VendorPorts.SmsDeliveryPort",
            "RTC": "VendorPorts.RtcTokenPort",
            "IM": "VendorPorts.ImCredentialPort",
            "PAYMENT": "VendorPorts.PaymentGatewayPort",
            "PUSH": "VendorPorts.PushNotificationPort",
            "OBJECT_STORAGE": "VendorPorts.ObjectStoragePort",
        }
        return {
            "contractVersion": "vendor-boundary-v2",
            "integrationStatus": "READY_FOR_PROVIDER_INTEGRATION",
            "runtimeStatus": "VENDOR_BLOCKED",
            "allBoundariesReady": True,
            "allRuntimeAdaptersReady": False,
            "capabilities": {
                capability: {
                    "capability": capability,
                    "boundaryStatus": "READY",
                    "runtimeStatus": "VENDOR_BLOCKED",
                    "provider": "UNCONFIGURED",
                    "missingConfiguration": missing,
                    "serverOnlySecretProperties": [
                        item for item in missing if any(
                            token in item
                            for token in (
                                "secret",
                                "certificate",
                                "private-key",
                                "server-key",
                            )
                        )
                    ],
                    "adapterContract": contracts[capability],
                    "securityBoundary": (
                        "All secret values remain server-side and are never returned "
                        "by this endpoint."
                    ),
                }
                for capability, missing in requirements.items()
            },
        }

    def _respond(
        self,
        *,
        path: str,
        headers: dict[str, str],
        body: Any,
        status: HTTPStatus,
        payload: Any,
        violation: str | None = None,
    ) -> None:
        raw = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        self.send_response(int(status))
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(raw)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(raw)
        self.wfile.flush()
        self.state.record(
            method=self.command,
            path=path,
            headers=headers,
            body=body,
            status=int(status),
            violation=violation,
        )


class ContractServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, address: tuple[str, int], state: ServerState):
        super().__init__(address, ContractHandler)
        self.state = state


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--request-log", type=Path, required=True)
    parser.add_argument("--summary-file", type=Path, required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    state = ServerState(args.request_log, args.summary_file)
    state.summary_file.parent.mkdir(parents=True, exist_ok=True)
    state._write_summary_locked()
    server = ContractServer((args.host, args.port), state)

    def stop_server(_signum: int, _frame: Any) -> None:
        threading.Thread(target=server.shutdown, daemon=True).start()

    signal.signal(signal.SIGTERM, stop_server)
    signal.signal(signal.SIGINT, stop_server)
    try:
        server.serve_forever(poll_interval=0.2)
    finally:
        state._write_summary_locked()
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
