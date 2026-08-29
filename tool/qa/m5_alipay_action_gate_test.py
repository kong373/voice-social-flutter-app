#!/usr/bin/env python3
"""Provider-free tests for the M5 Alipay action-time confirmation gate."""

from __future__ import annotations

import unittest

from m5_alipay_action_gate import (
    ACTION_CONFIRMATION_REQUIRED,
    EXPECTED_SUCCESS_CONFIRMATION,
    ActionConfirmationGate,
    ActionGateError,
    ActionIdentity,
)


RUN_ID = "m5-action-gate-test"
ORDER_NO = "vs-alipay-action-001"
REQUEST_ID = "alipay-action-request-001"
BACKEND_SHA = "a" * 40
FLUTTER_SHA = "b" * 40
ACCOUNT = "development-account-001"
PRODUCT_ID = "recharge-product-001"
AMOUNT_MINOR = 100
GIFT_COIN_AMOUNT = 100


class Clock:
    def __init__(self) -> None:
        self.value = 100.0

    def __call__(self) -> float:
        return self.value


def identity(
    *,
    run_id: str = RUN_ID,
    avd: str = "AVD-A",
    serial: str = "emulator-5554",
    backend_sha: str = BACKEND_SHA,
    flutter_sha: str = FLUTTER_SHA,
    order_no: str = ORDER_NO,
    request_id: str = REQUEST_ID,
    account: str = ACCOUNT,
    product_id: str = PRODUCT_ID,
    amount_minor: int = AMOUNT_MINOR,
    gift_coin_amount: int = GIFT_COIN_AMOUNT,
    provider: str = "ALIPAY",
    status: str = "CREATED",
    created_marker: str | None = None,
) -> ActionIdentity:
    return ActionIdentity(
        run_id=run_id,
        avd=avd,
        serial=serial,
        backend_sha=backend_sha,
        flutter_sha=flutter_sha,
        order_no=order_no,
        request_id=request_id,
        account=account,
        product_id=product_id,
        amount_minor=amount_minor,
        gift_coin_amount=gift_coin_amount,
        provider=provider,
        status=status,
        created_marker=created_marker,
    )


class M5AlipayActionGateTest(unittest.TestCase):
    def setUp(self) -> None:
        self.clock = Clock()
        self.markers: list[str] = []
        self.gate = ActionConfirmationGate(
            enabled=True,
            expected_run_id=RUN_ID,
            expected_avd="AVD-A",
            expected_serial="emulator-5554",
            expected_backend_sha=BACKEND_SHA,
            expected_flutter_sha=FLUTTER_SHA,
            ttl_seconds=30,
            clock=self.clock,
            marker_sink=self.markers.append,
        )

    def test_gate_is_disabled_by_default_and_does_not_emit_marker(self) -> None:
        disabled = ActionConfirmationGate(
            enabled=False,
            expected_run_id=RUN_ID,
            expected_avd="AVD-A",
            expected_serial="emulator-5554",
            expected_backend_sha=BACKEND_SHA,
            expected_flutter_sha=FLUTTER_SHA,
            clock=self.clock,
            marker_sink=self.markers.append,
        )
        with self.assertRaisesRegex(ActionGateError, "DISABLED"):
            disabled.request(identity())
        self.assertEqual(self.markers, [])

    def test_operator_cannot_approve_before_runtime_order_request(self) -> None:
        with self.assertRaisesRegex(ActionGateError, "PREMATURE"):
            self.gate.approve(identity(), EXPECTED_SUCCESS_CONFIRMATION)
        self.assertEqual(self.markers, [])

    def test_order_request_emits_only_fixed_marker_and_binds_identity(self) -> None:
        self.gate.request(identity())
        self.assertEqual(self.markers, [ACTION_CONFIRMATION_REQUIRED])
        self.assertNotIn(ORDER_NO, repr(self.gate))
        with self.assertRaisesRegex(ActionGateError, "DUPLICATE"):
            self.gate.request(identity())

    def test_valid_action_confirmation_is_one_shot(self) -> None:
        self.gate.request(identity())
        issued = self.gate.approve(identity(), EXPECTED_SUCCESS_CONFIRMATION)
        self.assertTrue(issued)
        self.assertTrue(self.gate.consume(identity()))
        with self.assertRaisesRegex(ActionGateError, "REPLAY"):
            self.gate.consume(identity())

    def test_wrong_run_device_or_order_is_rejected_at_approval_and_consume(self) -> None:
        self.gate.request(identity())
        for wrong in (
            identity(run_id="m5-other-run"),
            identity(avd="AVD-B"),
            identity(serial="emulator-5556"),
            identity(backend_sha="c" * 40),
            identity(flutter_sha="d" * 40),
            identity(order_no="vs-alipay-action-002"),
            identity(request_id="alipay-action-request-002"),
            identity(account="development-account-002"),
            identity(product_id="recharge-product-002"),
            identity(amount_minor=200),
            identity(gift_coin_amount=200),
            identity(created_marker="server-create-marker-002"),
        ):
            with self.subTest(wrong=wrong):
                with self.assertRaisesRegex(ActionGateError, "BINDING_MISMATCH"):
                    self.gate.approve(wrong, EXPECTED_SUCCESS_CONFIRMATION)
                with self.assertRaisesRegex(ActionGateError, "BINDING_MISMATCH"):
                    self.gate.consume(wrong)

    def test_wrong_confirmation_and_repeated_approval_are_rejected(self) -> None:
        self.gate.request(identity())
        with self.assertRaisesRegex(ActionGateError, "CONFIRMATION_MISMATCH"):
            self.gate.approve(identity(), "I_UNDERSTAND_A_DIFFERENT_ACTION")
        self.gate.approve(identity(), EXPECTED_SUCCESS_CONFIRMATION)
        with self.assertRaisesRegex(ActionGateError, "REPLAY"):
            self.gate.approve(identity(), EXPECTED_SUCCESS_CONFIRMATION)

    def test_expiry_is_fail_closed_for_approval_and_consume(self) -> None:
        self.gate.request(identity())
        self.clock.value += 30.001
        self.assertEqual(
            self.gate.public_status(),
            {
                "pending": False,
                "approved": False,
                "consumed": False,
                "expired": True,
            },
        )
        with self.assertRaisesRegex(ActionGateError, "EXPIRED"):
            self.gate.approve(identity(), EXPECTED_SUCCESS_CONFIRMATION)
        with self.assertRaisesRegex(ActionGateError, "EXPIRED"):
            self.gate.consume(identity())

    def test_invalid_identity_is_rejected_without_echoing_order(self) -> None:
        with self.assertRaisesRegex(ActionGateError, "IDENTITY_INVALID") as error:
            self.gate.request(
                ActionIdentity(
                    run_id=RUN_ID,
                    avd="AVD-A",
                    serial="emulator-5554",
                    backend_sha=BACKEND_SHA,
                    flutter_sha=FLUTTER_SHA,
                    order_no="bad order",
                    request_id=REQUEST_ID,
                    account=ACCOUNT,
                    product_id=PRODUCT_ID,
                    amount_minor=AMOUNT_MINOR,
                    gift_coin_amount=GIFT_COIN_AMOUNT,
                    provider="ALIPAY",
                    status="CREATED",
                )
            )
        self.assertNotIn("bad order", str(error.exception))

    def test_provider_status_and_boolean_money_fail_closed(self) -> None:
        for invalid in (
            identity(provider="WECHAT"),
            identity(status="CONFIRMING"),
            identity(amount_minor=True),
            identity(gift_coin_amount=False),
        ):
            with self.subTest(invalid=invalid):
                with self.assertRaisesRegex(ActionGateError, "IDENTITY_INVALID"):
                    self.gate.request(invalid)


if __name__ == "__main__":
    unittest.main()
