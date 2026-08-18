# Delivery Roadmap

## Completed baseline — M0 to M2.4

Merged into `main`:

- Flutter foundation and fixed 69 Page IDs.
- Account, compliance, discovery, social, room, message, commerce, community, and PK business layers.
- Fixed eight-seat room model and in-room ordinary-gift Bottom Sheet.
- Mock-backed offline flows, role/state fixtures, and fail-closed provider boundaries.
- Android dual-emulator acceptance for the 69-page mock baseline.

## M3 — Authorized development integration — current

### M3.1 Development gateway readiness

- Redacted runtime profiles and configuration validation.
- HTTPS and timeout policy.
- Side-effect-free gateway reachability probe.
- Manual protected-environment CI preflight.
- No SMS, login, payment, RTC, or IM side effects.

### M3.2 Authentication and read-only contracts

- Non-production SMS and login account.
- Secure live session persistence and expiry recovery.
- Home recommendation, search, user profile, and room validation reads.
- HTTP room snapshot and exit behavior without RTC publication.
- Wallet, order, earnings, and withdrawal read-only verification.

### M3.3 Room transport integration

- Approved RTC driver, token renewal, join/leave, publication, and audio route.
- Approved room realtime/IM transport, heartbeat, reconnect, and event allowlist.
- Multi-device and token-expiry recovery.

## M4 — Provider and commercial integration

- Tencent IM private messaging and notification sync.
- Android WeChat Pay and Alipay.
- iOS Apple IAP.
- Object storage, push, native permission, and share adapters.
- Server-authoritative reconciliation, refund, earnings, and withdrawal verification.

## M5 — Release readiness

- Android physical-device matrix.
- iOS Simulator and iPhone matrix.
- Release signing, app-store bundles, privacy manifests, and compliance evidence.
- Performance, accessibility, security, rollback, and operations rehearsal.
