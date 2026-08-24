# Delivery Roadmap

## Frozen scope and status

- The C-end denominator is exactly 69 Page IDs.
- `UI_SCOPE=COMPLETE_69_PAGE_C_END`: all approved C-end UI surfaces and their
  scoped interactions are implemented in the Flutter candidate.
- `FIRST_PARTY_READS=READY`: F3 can exercise first-party HTTP/read contracts,
  including the recharge catalog read.
- `LIVE_DUAL_AVD_ACCEPTANCE=PENDING`: the authoritative live run on AVD-A and
  AVD-B has not been accepted in this checkout. UI implementation, local
  tests, or a single-device screenshot run cannot be promoted to live AVD
  `PASS`.

## Completed baseline — M0 to M3.3

- Flutter foundation and fixed 69 Page IDs.
- Account, compliance, discovery, social, room, message, commerce, community,
  and PK business layers.
- Fixed eight-seat room model and in-room ordinary-gift Bottom Sheet.
- Mock-backed offline flows, role/state fixtures, and fail-closed provider
  boundaries.
- UI/interaction scope and visual baselines for all 69 C-end pages.

## F3 — First-party live integration — current

F3 integrates the first-party HTTP graph and read authority while preserving
provider boundaries. It is not a provider-activation milestone.

### F3.1 First-party read and authority contracts

- Redacted runtime profiles, configuration validation, and gateway reachability
  preflight.
- First-party account/session, discovery, search, profile, room snapshot,
  wallet, order, community, and notification read contracts as available from
  the development backend.
- First-party recharge catalog read (`CM-002`).
- Development Outbox OTP only for controlled development testing; it is not
  formal SMS delivery.
- Recharge order creation and payment-channel invocation remain blocked.
- C-end exposes no backend-ops navigation.

### F3.2 Formal provider boundary

All six formal vendor capabilities remain `VENDOR_BLOCKED` and fail closed:

| Capability | Status | Rule |
| --- | --- | --- |
| SMS | `VENDOR_BLOCKED` | Development Outbox is not formal SMS. |
| RTC | `VENDOR_BLOCKED` | No media join/publication. |
| IM | `VENDOR_BLOCKED` | No realtime/private-message transport. |
| PAYMENT | `VENDOR_BLOCKED` | No order creation, SDK launch, or payment success. |
| PUSH | `VENDOR_BLOCKED` | OS permission is separate from delivery. |
| OBJECT_STORAGE | `VENDOR_BLOCKED` | No provider-backed upload. |

## M4 — First-party live acceptance

M4 runs the F3 live graph on the exact AVD-A/AVD-B matrix, with protected
development inputs, redacted evidence, route/authority markers, provider-call
count `0`, and no secrets. Its current status is
`LIVE_DUAL_AVD_ACCEPTANCE=PENDING`; no live AVD `PASS` is recorded until both
AVDs and the aggregate gate complete on the same candidate SHA.

## B7 ops and C-end boundary

Backend B7/ops capability is available as a protected backend surface. The
Flutter 69-page C-end deliberately has no B7 route or operator navigation:
`C_END_B7_SCOPE=INTENTIONALLY_OUT_OF_SCOPE`. The canonical audit/review state
for this boundary is `VERIFIED`. See
[`m4-native-permissions-ops-audit.md`](m4-native-permissions-ops-audit.md).

Guild membership and member/application governance remain part of SC-001 and
SC-002. This boundary excludes only the separate commercial VIP/membership
and gift-backpack surfaces, whose routes are permanently `RETIRED` /
`OUT_OF_SCOPE`.

## M5 — Release readiness

- Android physical-device matrix.
- iOS Simulator and iPhone matrix.
- Release signing, app-store bundles, privacy manifests, and compliance
  evidence.
- Performance, accessibility, security, rollback, and operations rehearsal.
