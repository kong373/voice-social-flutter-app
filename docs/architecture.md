# M0 Architecture

## Source-of-truth order

1. The frozen 69-page scope and explicit product constraints.
2. Authorized backend source for business rules, state, and API contracts.
3. Authorized APK evidence for client behavior, layouts, and message semantics.
4. The new clean-room Flutter design system and implementation.

Backend or APK capabilities do not become product features automatically. Retired and unconfirmed capabilities remain hidden even when legacy code exists.

## Module plan

```text
lib/
├── app/                  # bootstrap, manifest, router
├── core/                 # design system, network, auth, RTC, realtime
├── features/
│   ├── account/          # AC-001..AC-012
│   ├── discovery/        # DS-001..DS-008
│   ├── social/           # US-001..US-010
│   ├── room/             # RM-001..RM-014
│   ├── message/          # MS-001..MS-006
│   ├── commerce/         # CM-001..CM-012
│   └── community/        # SC-001..SC-007
└── shared/
```

## Room boundary

The first executable slice deliberately separates:

- `RoomController`: client-side state orchestration.
- `MicSeat`: the fixed eight-seat UI model.
- `RoomSessionStatus`: join, reconnect, leave, and terminal states.
- `GiftSheet`: in-room bottom sheet, not a navigation page.
- placeholder adapters: future HTTP, realtime, RTC, and persistence ports.

The backend's legacy seat model, including any special host seat, must be translated through an adapter before reaching the fixed eight-seat UI.

## Current limitations

M0 uses local demonstration data. It contains no production endpoints, credentials, decompiled source, proprietary assets, or copied brand content. Real API and realtime integration starts only after a redacted contract map is committed.
