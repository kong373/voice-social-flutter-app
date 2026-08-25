#!/usr/bin/env python3
"""Behavior tests for the deterministic M3.2 review contract server."""

from __future__ import annotations

import unittest

from m32_review_contract_server import (
    CONVERSATIONS,
    ENTER_ROOM,
    EXIT_ROOM,
    LEGACY_ROOM_SNAPSHOT,
    ORDERS,
    PERSONAL_DATA,
    PUBLIC_MESSAGES,
    PUBLIC_CLIENT_ID,
    REQUIRED_ENDPOINTS,
    WALLET,
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
        self.assertIn(PUBLIC_MESSAGES, REQUIRED_ENDPOINTS)
        self.assertIn(CONVERSATIONS, REQUIRED_ENDPOINTS)
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
        self.assertEqual(len(entered["seats"]), 8)
        for seat in entered["seats"]:
            if seat["userId"] is None:
                self.assertEqual(seat["status"], 0)
            else:
                self.assertEqual(seat["status"], 3)

        exited = self.handler._data_for(
            EXIT_ROOM,
            "",
            {"roomId": "880217"},
        )
        self.assertEqual(
            exited,
            {"roomId": "880217", "exited": True, "status": "EXITED"},
        )

    def test_public_message_history_is_an_authoritative_empty_page(self) -> None:
        self.handler.command = "GET"
        self.handler.path = (
            f"{PUBLIC_MESSAGES}?roomId=880217&pageNum=1&pageSize=50"
        )
        self.assertIsNone(
            self.handler._validate_request(PUBLIC_MESSAGES, self.headers, None)
        )
        self.handler.path = f"{PUBLIC_MESSAGES}?roomId=880217&pageNum=2&pageSize=50"
        self.assertEqual(
            self.handler._validate_request(PUBLIC_MESSAGES, self.headers, None),
            "PUBLIC_MESSAGES_PAGE_NUM_INVALID",
        )
        self.assertEqual(
            self.handler._data_for(
                PUBLIC_MESSAGES,
                "roomId=880217&pageNum=1&pageSize=50",
                None,
            ),
            {"current": 1, "size": 50, "total": 0, "pages": 0, "list": []},
        )

    def test_conversation_list_is_first_party_empty_page(self) -> None:
        self.handler.command = "GET"
        self.handler.path = f"{CONVERSATIONS}?pageNum=1&pageSize=100"
        self.assertIsNone(
            self.handler._validate_request(CONVERSATIONS, self.headers, None)
        )
        self.handler.path = f"{CONVERSATIONS}?pageNum=1&pageSize=99"
        self.assertEqual(
            self.handler._validate_request(CONVERSATIONS, self.headers, None),
            "CONVERSATIONS_PAGE_SIZE_INVALID",
        )
        self.assertEqual(
            self.handler._data_for(
                CONVERSATIONS,
                "pageNum=1&pageSize=100",
                None,
            ),
            {
                "pageNum": 1,
                "pageSize": 100,
                "total": 0,
                "pages": 0,
                "hasMore": False,
                "list": [],
            },
        )

    def test_personal_data_contains_the_profile_fallback_authority(self) -> None:
        profile = self.handler._data_for(PERSONAL_DATA, "", None)
        self.assertEqual(profile["userId"], 30001)
        self.assertEqual(profile["nickName"], "岛民小新")
        self.assertEqual(profile["headImageUrl"], "")
        self.assertEqual(profile["sex"], 1)
        self.assertEqual(profile["birthday"], "1999-04-02")

    def test_wallet_contains_explicit_optional_authority(self) -> None:
        wallet = self.handler._data_for(WALLET, "", None)
        self.assertEqual(wallet["balance"], 35.80)
        self.assertEqual(wallet["frozenBalance"], 0)
        self.assertEqual(wallet["yesterdayEarnings"], 0)
        self.assertEqual(wallet["totalWithdraw"], 0)
        self.assertFalse(wallet["isRealName"])
        self.assertIsNone(wallet["agentEarnings"])
        self.assertEqual(wallet["agentEarningsStatus"], "UNAVAILABLE")
        self.assertIsNone(wallet["superAgentEarnings"])
        self.assertEqual(wallet["superAgentEarningsStatus"], "UNAVAILABLE")

    def test_orders_echo_the_authoritative_requested_page_size(self) -> None:
        for page_size in (20, 50):
            orders = self.handler._data_for(
                ORDERS,
                "",
                {"pageNum": 1, "pageSize": page_size},
            )
            self.assertEqual(orders["current"], 1)
            self.assertEqual(orders["pageSize"], page_size)
            self.assertEqual(orders["total"], 1)
            self.assertEqual(orders["list"][0]["orderNo"], "P202608180001")


if __name__ == "__main__":
    unittest.main()
