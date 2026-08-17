# M1.2 Room operations and recovery checkpoint

This checkpoint continues the authorized clean-room Flutter reconstruction. It keeps the fixed 69-page denominator and implements the room operation pages that were placeholders in M1.1.

## Implemented Page IDs

- RM-005: direct mic selection plus an explicit approval-mode contract and cancellation state.
- RM-006: full online member and listener list with filters, pagination, refresh, and role/seat context.
- RM-007: member moderation, manager assignment, seat lock/mute controls, confirmation for high-risk removal, and consent-based mic invitations where supported.
- RM-008: authoritative room topic/announcement read, edit, conflict check, and limits matching the backend contract.
- RM-009: room-code and deep-link copy flow. Native channel sharing remains fail-closed until a platform adapter is added.
- RM-010: provider-neutral audio route and microphone page.
- RM-011: room reconnect and session recovery page that preserves room context and never fabricates public-screen history.
- RM-012: network, RTC, realtime, microphone, and audio-route diagnostics page.

## Confirmed backend contracts used

Only contracts verified in the authorized backend source are used in the live repository:

- `POST /app-api/rooms/getRoomOnlinePersonnel`
- `POST /app-api/rooms/getRoomMicDownOnlinePersonnel`
- `GET /app-api/roomUsers/getRoomManagers`
- `GET /app-api/roomUsers/getRoomMuteds`
- `PATCH /app-api/roomUsers/setMuted`
- `PATCH /app-api/roomUsers/setRole`
- `POST /app-api/room/com/kickout`
- `PUT /app-api/micUserBase/hugUserDownMic`
- `PUT /app-api/micBase/lockMike`
- `PUT /app-api/micBase/unlockMike`
- `PUT /app-api/micBase/closedMike`
- `PUT /app-api/micBase/openMike`
- `GET /app-api/rooms/getRoomTopics`
- `PATCH /app-api/rooms/setRoomTopics`

## Important protocol boundary

The legacy backend exposes a forced `hugUserUpMic` operation but no confirmed ordinary-room consent invitation/approval protocol. The Flutter client intentionally does not map forced mic placement to “invite to mic.”

- Live backend mode declares direct self-up-mic behavior.
- Mock mode exercises the future consent request/invitation contract.
- The production approval flow remains blocked until the backend supplies request, accept, reject, cancel, expiry, and authoritative-result endpoints/events.

## Safety

This public repository contains no APK, decompiled source, backend archive, private host, production credential, signing asset, or copied brand material. Runtime configuration and device-specific RTC/realtime drivers remain injected.
