#!/usr/bin/env python3
"""Deterministic first-party contract server for M3.2 dual-AVD review.

It never contacts SMS, RTC, IM, payment, push, or object-storage providers. The
mobile app is treated as a public client and the protected development SMS
outbox is deliberately absent from the client flow.
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
MAX_REQUEST_BODY_BYTES = 1024 * 1024

HEALTH = "/health"
SEND_SMS = "/app-register-api/util/v1/sendSmsCode"
LOGIN = "/app-register-api/userAccount/v1/loginByMobileAndSmsCode"
REGISTER = "/app-register-api/userAccount/v1/registerByMobile"
REFRESH = "/app-register-api/userAccount/v1/refreshSession"
LOGOUT = "/app-register-api/userAccount/v1/logout"
HOME = "/app-api/rooms/v1/getRecommendRooms"
SEARCH = "/app-api/es/getSearchESResult"
LEGACY_ROOM_SNAPSHOT = "/app-api/rooms/getRoomById"
ENTER_ROOM = "/app-room-api/room/com/v1/enterRoom"
EXIT_ROOM = "/app-room-api/room/com/v1/exitRoom"
CURRENT_USER = "/app-register-api/userAccount/v1/current"
PERSONAL_DATA = "/app-api/user/getPersonalData"
YOUTH_MODE = "/app-api/user/other/getMatchButtonAndYouthMode"
ACCOUNT_CANCELLATION = "/app-api/user/queryUserLogout"
VERSION_INFORMATION = "/app-api/appBase/getVersionInformation"
ACCOUNT_REAL_NAME = "/app-mini-api/mini/v1/account/real-name"
ACCOUNT_SESSIONS = "/app-mini-api/mini/v1/account/sessions"
ACCOUNT_RESTRICTIONS = "/app-mini-api/mini/v1/account/restrictions"
NCOIN = "/app-economy-api/ncoin"
WALLET = "/app-mini-api/mini/v1/wallet/overview"
ORDERS = "/app-economy-api/pay/getOrders"
VENDOR_READINESS = "/app-register-api/vendor/v1/readiness"
SUMMARY = "/__qa__/summary"

REQUIRED_ENDPOINTS = {
    HEALTH,
    SEND_SMS,
    LOGIN,
    HOME,
    SEARCH,
    ENTER_ROOM,
    EXIT_ROOM,
    CURRENT_USER,
    PERSONAL_DATA,
    YOUTH_MODE,
    ACCOUNT_CANCELLATION,
    VERSION_INFORMATION,
    ACCOUNT_REAL_NAME,
    ACCOUNT_SESSIONS,
    ACCOUNT_RESTRICTIONS,
    NCOIN,
    WALLET,
    ORDERS,
    VENDOR_READINESS,
    LOGOUT,
}
PUBLIC_ENDPOINTS = {HEALTH, SEND_SMS, LOGIN, REGISTER, REFRESH, LOGOUT, SUMMARY}


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
                "publicClientIdValid": headers.get("client-id")
                in {None, PUBLIC_CLIENT_ID},
                "authorizationPresent": bool(headers.get("authorization")),
                "deviceIdPresent": bool(headers.get("x-device-id")),
                "forbiddenSecretHeadersPresent": any(
                    key in headers
                    for key in (
                        "client-secret",
                        "x-development-outbox-key",
                        "x-development-client-id",
                    )
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
            "contractVersion": "m3.2-review-contract-v3",
            "providerCallsMade": False,
            "publicClientSecretObserved": False,
            "developmentOutboxSecretObserved": False,
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
    server_version = "VoiceSocialM32Review/3.0"
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
        try:
            body = self._read_json_body()
        except ValueError as error:
            self._respond(
                path=path,
                headers=headers,
                body=None,
                status=HTTPStatus.BAD_REQUEST,
                payload={"code": 40001, "message": str(error), "data": None},
                violation=str(error),
            )
            return

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
                payload={"code": 40404, "message": "NOT_FOUND", "data": None},
            )
            return
        except ValueError as error:
            self._respond(
                path=path,
                headers=headers,
                body=body,
                status=HTTPStatus.BAD_REQUEST,
                payload={"code": 40001, "message": str(error), "data": None},
                violation=str(error),
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
        transfer_encoding = self.headers.get("Transfer-Encoding", "").lower()
        if "chunked" in transfer_encoding:
            raw = self._read_chunked_body()
        else:
            raw_length = self.headers.get("Content-Length")
            length = int(raw_length) if raw_length and raw_length.isdigit() else 0
            if length > MAX_REQUEST_BODY_BYTES:
                raise ValueError("REQUEST_BODY_TOO_LARGE")
            raw = self.rfile.read(length) if length > 0 else b""

        if not raw.strip():
            return None
        try:
            return json.loads(raw.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise ValueError("INVALID_JSON") from error

    def _read_chunked_body(self) -> bytes:
        chunks = bytearray()
        while True:
            size_line = self.rfile.readline()
            if not size_line:
                raise ValueError("INVALID_CHUNKED_BODY")
            try:
                size_token = size_line.split(b";", 1)[0].strip()
                size = int(size_token, 16)
            except ValueError as error:
                raise ValueError("INVALID_CHUNKED_BODY") from error
            if size < 0:
                raise ValueError("INVALID_CHUNKED_BODY")
            if size == 0:
                while True:
                    trailer = self.rfile.readline()
                    if trailer in {b"", b"\r\n", b"\n"}:
                        return bytes(chunks)
            if len(chunks) + size > MAX_REQUEST_BODY_BYTES:
                raise ValueError("REQUEST_BODY_TOO_LARGE")
            data = self.rfile.read(size)
            if len(data) != size or self.rfile.read(2) != b"\r\n":
                raise ValueError("INVALID_CHUNKED_BODY")
            chunks.extend(data)

    def _validate_request(
        self,
        path: str,
        headers: dict[str, str],
        body: Any,
    ) -> str | None:
        serialized_headers = json.dumps(headers, sort_keys=True).lower()
        serialized_body = json.dumps(body, sort_keys=True).lower() if body is not None else ""
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
        if any(
            token in serialized_headers or token in serialized_body
            for token in forbidden_tokens
        ):
            return "MOBILE_SECRET_BOUNDARY_VIOLATION"

        if path not in {HEALTH, SUMMARY}:
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

        expected_method = {
            ENTER_ROOM: "POST",
            EXIT_ROOM: "POST",
            PERSONAL_DATA: "GET",
            YOUTH_MODE: "GET",
            ACCOUNT_CANCELLATION: "GET",
            VERSION_INFORMATION: "GET",
            ACCOUNT_SESSIONS: "GET",
            ACCOUNT_RESTRICTIONS: "GET",
        }.get(path)
        if expected_method is not None and self.command != expected_method:
            return f"{path}_REQUIRES_{expected_method}"
        if path in {ENTER_ROOM, EXIT_ROOM}:
            if not isinstance(body, dict):
                return f"{path}_REQUIRES_JSON_OBJECT"
            if body.get("roomId") != "880217":
                return f"{path}_ROOM_ID_INVALID"
            if not headers.get("x-request-id"):
                return f"{path}_REQUEST_ID_REQUIRED"
        if path == ENTER_ROOM and body.get("source") != 0:
            return "ENTER_ROOM_SOURCE_INVALID"
        if path == ACCOUNT_REAL_NAME:
            if self.command not in {"GET", "POST"}:
                return "ACCOUNT_REAL_NAME_REQUIRES_GET_OR_POST"
            if self.command == "POST":
                if not isinstance(body, dict):
                    return "ACCOUNT_REAL_NAME_POST_REQUIRES_JSON_OBJECT"
                if set(body) != {"legalName", "identityNumber"}:
                    return "ACCOUNT_REAL_NAME_POST_FIELDS_INVALID"
                if not str(body.get("legalName", "")).strip() or not str(
                    body.get("identityNumber", "")
                ).strip():
                    return "ACCOUNT_REAL_NAME_POST_FIELDS_EMPTY"
                if not headers.get("x-request-id"):
                    return "ACCOUNT_REAL_NAME_POST_REQUEST_ID_REQUIRED"

        if path == VERSION_INFORMATION:
            query = parse_qs(urlparse(self.path).query)
            version_type = query.get("type", [])
            version_code = query.get("versionCode", [])
            if len(version_type) != 1 or version_type[0] not in {"1", "2"}:
                return "VERSION_INFORMATION_TYPE_REQUIRED"
            if len(version_code) != 1:
                return "VERSION_INFORMATION_VERSION_CODE_REQUIRED"
            try:
                if int(version_code[0]) <= 0:
                    raise ValueError
            except ValueError:
                return "VERSION_INFORMATION_VERSION_CODE_MUST_BE_POSITIVE_INTEGER"
        return None

    def _data_for(self, path: str, raw_query: str, body: Any) -> Any:
        query = parse_qs(raw_query)
        if path == HEALTH:
            return {
                "status": "UP",
                "environment": "development",
                "database": "UP",
                "redis": "UP",
                "providerCallsMade": False,
            }
        if path == SUMMARY:
            return self.state.snapshot()
        if path == SEND_SMS:
            if self.command != "PUT":
                raise ValueError("SEND_SMS_REQUIRES_PUT")
            if query.get("mobileNumber", [""])[0] != "13800138000":
                raise ValueError("UNEXPECTED_MOBILE_NUMBER")
            if not self.headers.get("X-Device-Id"):
                raise ValueError("DEVICE_ID_REQUIRED")
            return {"challengeId": "challenge-1", "expiresIn": 300, "retryAfter": 1}
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
            self._require_body_values(body, refreshToken="refresh-1")
            return None
        if path == HOME:
            return {
                "records": [
                    {
                        "roomIdStr": "880217",
                        "roomCode": "880217",
                        "roomName": "深夜陪伴电台",
                        "description": "聊聊今天发生的事",
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
                        "roomName": "城市夜话",
                        "description": "下班后的轻松陪伴",
                        "liveCount": 12,
                        "heatValue": 51,
                        "micUserHeadImgs": ["a"],
                        "userId": 20002,
                        "nickName": "星河",
                        "isLockRoom": 0,
                    },
                ],
                "current": 1,
                "pageSize": 20,
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
                        "description": f"搜索命中：{keyword}",
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
                "roomTotal": 1,
                "userTotal": 1,
                "pageNo": 1,
                "pageSize": 20,
            }
        if path in {LEGACY_ROOM_SNAPSHOT, ENTER_ROOM}:
            if path == LEGACY_ROOM_SNAPSHOT and query.get("roomId", [""])[0] != "880217":
                raise KeyError(path)
            seats = [
                {
                    "index": index,
                    "status": 3 if index <= 3 else 0,
                    "userId": 20000 + index if index <= 3 else None,
                    "userName": ["", "南风", "晚安", "小岛"][index]
                    if index <= 3
                    else "",
                    "avatarUrl": "",
                }
                for index in range(1, 9)
            ]
            return {
                "roomIdStr": "880217",
                "roomId": "880217",
                "roomCode": "880217",
                "roomName": "深夜陪伴电台",
                "description": "聊聊今天发生的事",
                "topicContent": "聊聊今天发生的事",
                "ownerId": 20001,
                "userId": 20001,
                "onlineNum": 27,
                "seatCount": 8,
                "seats": seats,
                "realtimeMode": "HTTP_SNAPSHOT_ONLY",
                "rtcStatus": "VENDOR_BLOCKED",
                "imStatus": "VENDOR_BLOCKED",
            }
        if path == EXIT_ROOM:
            return {
                "roomId": "880217",
                "exited": True,
                "status": "EXITED",
            }
        if path == CURRENT_USER:
            return {
                "userId": 30001,
                "loginName": "U30001",
                "nickName": "岛民小新",
                "mobile": "138****8000",
                "roles": "ROLE_USER",
                "status": "ACTIVE",
            }
        if path == PERSONAL_DATA:
            return {
                "userId": 30001,
                "loginName": "13800138000",
                "nickName": "岛民小新",
            }
        if path == YOUTH_MODE:
            return {
                "isYouthMode": 0,
                "youthModeEnabled": False,
            }
        if path == ACCOUNT_CANCELLATION:
            return {
                "canLogout": True,
                "eligible": True,
                "status": "NONE",
                "latestRequest": {},
                "requiresConfirmation": True,
                "immediateDeletion": False,
            }
        if path == VERSION_INFORMATION:
            return {
                "isUpdate": 0,
                "latest": {},
                "providerInvocation": False,
            }
        if path == ACCOUNT_REAL_NAME:
            if self.command == "POST":
                return {
                    "status": "PENDING",
                    "statusCode": 1,
                    "providerStatus": "FIRST_PARTY_REVIEW",
                    "reviewStatus": "FIRST_PARTY_REVIEW",
                    "reviewMode": "FIRST_PARTY_MANUAL_REVIEW",
                    "providerInvocation": False,
                }
            return {
                "status": "UNVERIFIED",
                "statusCode": 0,
                "providerStatus": "FIRST_PARTY_REVIEW",
                "reviewStatus": "FIRST_PARTY_REVIEW",
                "reviewMode": "FIRST_PARTY_MANUAL_REVIEW",
                "providerInvocation": False,
            }
        if path == ACCOUNT_SESSIONS:
            return {
                "total": 0,
                "list": [],
            }
        if path == ACCOUNT_RESTRICTIONS:
            return {
                "restricted": False,
                "accountUsable": True,
                "total": 0,
                "list": [],
            }
        if path == NCOIN:
            return {"integer": 12600, "value": 12600}
        if path == WALLET:
            return {
                "balanceMinor": 3580,
                "balance": 35.80,
                "frozenBalanceMinor": 0,
                "frozenBalance": 0,
                "totalEarnings": 0,
            }
        if path == ORDERS:
            return {
                "list": [
                    {
                        "orderNo": "P202608180001",
                        "amountMinor": 600,
                        "amount": 6.00,
                        "ncoin": 600,
                        "payType": "支付宝",
                        "status": "SUCCEEDED",
                        "createDate": "2026-08-18T12:00:00Z",
                    }
                ],
                "current": 1,
                "pageSize": 20,
                "total": 1,
            }
        if path == VENDOR_READINESS:
            return self._vendor_readiness()
        raise KeyError(path)

    @staticmethod
    def _token(access_token: str, refresh_token: str) -> dict[str, Any]:
        return {
            "access_token": access_token,
            "token_type": "Bearer",
            "expires_in": 600,
            "refresh_token": refresh_token,
            "refresh_expires_in": 2592000,
            "userId": 30001,
            "mobile": "138****8000",
            "roles": "ROLE_USER",
            "roomId": None,
        }

    @staticmethod
    def _vendor_readiness() -> dict[str, Any]:
        contracts = {
            "SMS": "VendorPorts.SmsDeliveryPort",
            "RTC": "VendorPorts.RtcTokenPort",
            "IM": "VendorPorts.ImCredentialPort",
            "PAYMENT": "VendorPorts.PaymentGatewayPort",
            "PUSH": "VendorPorts.PushNotificationPort",
            "OBJECT_STORAGE": "VendorPorts.ObjectStoragePort",
        }
        capabilities = {}
        for name, contract in contracts.items():
            capabilities[name] = {
                "capability": name,
                "boundaryStatus": "READY",
                "runtimeStatus": "VENDOR_BLOCKED",
                "provider": "UNCONFIGURED",
                "missingConfiguration": ["adapter-implementation"],
                "serverOnlySecretProperties": [],
                "adapterContract": contract,
                "adapterImplemented": False,
                "securityBoundary": (
                    "All secret values remain server-side and are never returned."
                ),
            }
        return {
            "contractVersion": "vendor-boundary-v2",
            "integrationStatus": "READY_FOR_PROVIDER_INTEGRATION",
            "runtimeStatus": "VENDOR_BLOCKED",
            "allBoundariesReady": True,
            "allRuntimeAdaptersReady": False,
            "capabilities": capabilities,
        }

    @staticmethod
    def _require_body_values(body: Any, **expected: str) -> None:
        if not isinstance(body, dict):
            raise ValueError("JSON_BODY_REQUIRED")
        for key, value in expected.items():
            if body.get(key) != value:
                raise ValueError(f"UNEXPECTED_{key.upper()}")

    def _respond(
        self,
        *,
        path: str,
        headers: dict[str, str],
        body: Any,
        status: int,
        payload: Any,
        violation: str | None = None,
    ) -> None:
        encoded = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(encoded)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(encoded)
        self.state.record(
            method=self.command,
            path=path,
            headers=headers,
            body=body,
            status=int(status),
            violation=violation,
        )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=18081)
    parser.add_argument("--request-log", type=Path, required=True)
    parser.add_argument("--summary-file", type=Path, required=True)
    parser.add_argument("--ready-file", type=Path)
    args = parser.parse_args()

    state = ServerState(args.request_log, args.summary_file)
    state._write_summary_locked()
    server = ThreadingHTTPServer((args.host, args.port), ContractHandler)
    server.state = state  # type: ignore[attr-defined]

    stop_event = threading.Event()

    def stop(_signum: int, _frame: Any) -> None:
        stop_event.set()
        threading.Thread(target=server.shutdown, daemon=True).start()

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    if args.ready_file:
        args.ready_file.parent.mkdir(parents=True, exist_ok=True)
        args.ready_file.write_text("READY\n", encoding="utf-8")
    try:
        server.serve_forever(poll_interval=0.2)
    finally:
        server.server_close()
        state._write_summary_locked()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
