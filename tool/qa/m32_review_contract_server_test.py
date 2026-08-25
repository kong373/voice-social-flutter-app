#!/usr/bin/env python3
"""Behavior tests for the deterministic M3.2 review contract server."""

from __future__ import annotations

import unittest

from m32_review_contract_server import (
    ENTER_ROOM,
    EXIT_ROOM,
    LEGACY_ROOM_SNAPSHOT,
    PUBLIC_CLIENT_ID,
    REQUIRED_ENDPOINTS,
    ContractHandler,
)


class RoomLifecycleContractTest(unittest.TestCase):
    def setUp(self) -> None:
        self.handler = object.__new__(ContractHandler)
        self.handler.command = "POST"
        self.handler.path = ENTER_ROOM
        self.handler.headers = {}
        self.headers = {
            "client-id": PUBLIC_CLIENT_ID,
            "authorization": "Bearer access-1",
            "x-request-id": "m32-room-lifecycle-test",
        }

    def test_authoritative_room_lifecycle_is_required(self) -> None:
        self.assertIn(ENTER_ROOM, REQUIRED_ENDPOINTS)
        self.assertIn(EXIT_ROOM, REQUIRED_ENDPOINTS)
        self.assertNotIn(LEGACY_ROOM_SNAPSHOT, REQUIRED_ENDPOINTS)

    def test_enter_room_validates_method_authority_and_source(self) -> None:
        body = {"roomId": "880217", "source": 0}
        self.assertIsNone(self.handler._validate_request(ENTER_ROOM, self.headers, body))

        self.handler.command = "GET"
        self.assertEqual(
            self.handler._validate_request(ENTER_ROOM, self.headers, body),
            f"{ENTER_ROOM}_REQUIRES_POST",
        )
        self.handler.command = "POST"

        missing_request_id = dict(self.headers)
        missing_request_id.pop("x-request-id")
        self.assertEqual(
            self.handler._validate_request(ENTER_ROOM, missing_request_id, body),
            f"{ENTER_ROOM}_REQUEST_ID_REQUIRED",
        )
        self.assertEqual(
            self.handler._validate_request(
                ENTER_ROOM,
                self.headers,
                {"roomId": "880217", "source": 1},
            ),
            "ENTER_ROOM_SOURCE_INVALID",
        )

    def test_enter_and_exit_payloads_match_client_authority_checks(self) -> None:
        entered = self.handler._data_for(
            ENTER_ROOM,
            "",
            {"roomId": "880217", "source": 0},
        )
        self.assertEqual(entered["roomId"], "880217")
        self.assertEqual(entered["realtimeMode"], "HTTP_SNAPSHOT_ONLY")
        self.assertEqual(entered["rtcStatus"], "VENDOR_BLOCKED")
        self.assertEqual(entered["imStatus"], "VENDOR_BLOCKED")

        exited = self.handler._data_for(
            EXIT_ROOM,
            "",
            {"roomId": "880217"},
        )
        self.assertEqual(
            exited,
            {"roomId": "880217", "exited": True, "status": "EXITED"},
        )


if __name__ == "__main__":
    unittest.main()
