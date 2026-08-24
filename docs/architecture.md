# Flutter Architecture

Current delivery status is `UI_SCOPE=COMPLETE_69_PAGE_C_END` and
`FIRST_PARTY_READS=READY`; `LIVE_DUAL_AVD_ACCEPTANCE=PENDING`. These are
separate states: implemented C-end UI and first-party read contracts do not
constitute live AVD acceptance or formal provider activation.

## Source-of-truth order

1. Frozen 69-page scope and explicit product constraints.
2. Authorized backend source for business rules, state, and transport contracts.
3. Authorized APK evidence for client behavior, layout, and message semantics.
4. New clean-room Flutter design system and implementation.

A legacy capability is not product scope by default. Retired and unconfirmed capabilities stay hidden even when old client or server code still exists.

## Application composition

```text
AppEnvironment
→ AppDependencies
  ├── AuthSessionManager
  ├── AuthRepository
  ├── RoomRepository
  ├── RtcAdapter
  └── RoomRealtimeGateway
→ AppGate
  ├── session restore
  ├── consent
  ├── SMS login / registration
  └── MainShell
```

`AppDependencies.mock()` provides deterministic test doubles. `AppDependencies.fromEnvironment()` uses secure storage and chooses mock or live backend contracts from dart defines.

## Account boundary

`AuthController` owns the explicit stages:

```text
initializing
→ consentRequired
→ signedOut
→ registrationRequired
→ signedIn
```

The access token is kept inside `AuthSessionManager` and persisted through `KeyValueStore`. UI widgets never receive OAuth client configuration or construct authorization headers themselves.

## Network boundary

`ApiClient` is a small JSON/HTTP client that:

- resolves paths against one authorized gateway base URI;
- injects `Client-Type` and `Client-Inner-Version`;
- injects the current authorization header only for authenticated calls;
- parses the backend result envelope;
- maps timeout, network, authorization, business, server, and protocol failures into `ApiException`.

No production host or credential is committed.

## Room boundary

The room feature is split into:

- `RoomController`: session orchestration and user-visible state.
- `RoomRepository`: HTTP command and snapshot contract.
- `RoomRealtimeGateway`: allowlisted realtime events only.
- `RtcAdapter`: provider-neutral audio lifecycle.
- `RoomPermissionPolicy`: role and state capabilities.
- `FixedEightSeatAdapter`: legacy backend seat model to fixed 8-seat UI.
- `GiftSheet`: ordinary in-room gift Bottom Sheet, never a room-exiting route.

### Session state

```text
idle → joining → joined
                 ├── reconnecting → joined / failed
                 ├── leaving → left / joined(error)
                 ├── kicked
                 └── closed
```

Weak-network recovery keeps the room UI, eight seats, public screen, and bottom actions visible. Successful recovery adds the exact warning that public-screen messages during disconnection may be missing.

### Fixed eight-seat adapter

The authorized backend can return special seat index `0` plus indices `1..8`. The app UI denominator remains eight seats:

- regular indices `1..8` map directly;
- an occupied index `0` is inserted into the first free UI slot while retaining its backend index for commands;
- nine simultaneously occupied backend seats are rejected as a protocol conflict instead of silently dropping a user.

### Transport status

Mock mode has executable RTC and realtime doubles. Live mode currently uses blocking adapters so an apparently successful HTTP entry cannot be mislabeled as a working voice room before the approved SDK drivers are configured.
