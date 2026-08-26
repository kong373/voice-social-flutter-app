# M1 Redacted Backend Contract

This document records the minimum authorized client contract needed for M1. It contains no production host, credential, private key, or server source.

## Common response envelope

```json
{
  "code": 200,
  "message": "success",
  "data": {}
}
```

`code == 200` is treated as success. Other codes are mapped to authorization, validation, business, server, or protocol failures. Authenticated calls include the current authorization header. All calls include `Client-Type` and `Client-Inner-Version`.

## Account routes

| Method | Relative path | Purpose |
|---|---|---|
| PUT | `/app-register-api/util/v1/sendSmsCode` | Request SMS code |
| PUT | `/app-register-api/userAccount/v1/loginByMobileAndSmsCode` | SMS login |
| POST | `/app-register-api/userAccount/v1/registerByMobile` | Complete mobile registration |

The login response token model includes access token, token type, expiry, user ID, role string, mobile, and an optional bound room ID. Backend business code `10201` enters the registration-required branch rather than showing a generic login error.

Device and anti-abuse fields are supplied through `ClientDevice`; no fixed real device identifier is committed.

## Room routes

| Method | Relative path | Purpose |
|---|---|---|
| POST | `/app-room-api/room/com/v1/enterRoom` | Enter and obtain room/RTC entry data |
| GET | `/app-room-api/room/com/v1/queryRoomInfo` | Obtain authoritative room state |
| GET | `/app-room-api/room/com/v1/reConnectRoomInfo` | Recover room session data |
| GET | `/app-room-api/room/com/v1/queryRoomOtherInfo` | Recover room type and RTC solution |
| GET | `/app-room-api/room/com/v1/buildAgoraToken` | Refresh the Agora RTC token during recovery |
| GET | `/app-room-api/room/com/v1/exitRoom` | Exit room |
| POST | `/app-room-api/room/com/v1/roomScreenChat` | Send realtime public-screen text |
| POST | `/app-room-api/room/com/v1/sendGift` | Send an ordinary room gift |
| PUT | `/app-api/micUserBase/userInitiativeUpMic` | User requests an available mic seat |
| PUT | `/app-api/micUserBase/leaveMic` | User leaves own mic seat |
| PUT | `/app-api/micBase/closedMike` | Mute own occupied mic seat |
| PUT | `/app-api/micBase/openMike` | Unmute own occupied mic seat |

`enterRoom` sends room ID, optional password, and a numeric entry-source code. Home discovery uses source `0`; search uses `2`; share uses `4`; discovery post uses `10`; leaderboard uses `11`; message uses `19`.

### Agora RTC credential contract

When `ENABLE_AGORA_RTC=true`, the Flutter client obtains a short-lived public
credential immediately after `enterRoom`/`reConnectRoomInfo` and again for
token renewal:

```text
GET /app-room-api/room/com/v1/buildAgoraToken?roomId=<room-id>
X-Request-Id: <client-generated opaque id>
```

The authenticated response uses the common envelope and the client allow-list
accepts only `provider=agora`, public `appId`, `channelId` (or legacy
`channelName`), ephemeral `token`, numeric `uid`, `role`, and `expiresAt` or
positive `ttlSeconds`. The client rejects a response whose uid is not the
authenticated user or whose explicit room identity does not match the request;
an incomplete response leaves the room `HTTP_SNAPSHOT_ONLY`.

The mobile client never accepts or stores an App Certificate or provider
signing secret. Joining starts with `publishMicrophoneTrack=false`; only an
explicit, successful first-party microphone permission request may enable the
publisher track. Generated Android hosts apply an app-level manifest overlay
that removes the Agora library's audio-unneeded CAMERA and READ_PHONE_STATE
permissions while retaining RECORD_AUDIO, network, and required Bluetooth
permissions; it also removes Agora's screen-capture activity/service and
`FOREGROUND_SERVICE_MEDIA_PROJECTION` because this product surface is
audio-only. The `ffi: 2.2.0` dependency override is required because the
current Flutter secure-storage dependency requires ffi 2.x while
`agora_rtc_engine 6.6.3` still declares ffi 1.x; it can be removed after the
upstream constraint is widened and normal lockfile resolution succeeds.

The official Agora 6.6.3 Android set intentionally retains both its Iris
wrapper and RTC SDK AAR. They currently share the historical `io.agora.rtc`
package namespace, which AGP 9 validates by default. The generated-host
helper therefore exposes the app compile SDK to Agora's legacy Gradle helper
and applies the documented AGP migration setting
`android.uniquePackageNames=false`; it does not remove either AAR or bypass
manifest merging. Remove that setting when the upstream AARs publish distinct
namespaces.

## Legacy mic status mapping

| Backend status | Meaning | Flutter state |
|---:|---|---|
| 0 | empty | `available` |
| 1 | empty and locked | `locked` |
| 2 | empty and muted | `mutedAvailable` |
| 3 | occupied and normal | `occupied` |
| 4 | occupied and muted | `occupiedMuted` |

Special backend seat index `0` is translated by `FixedEightSeatAdapter`; the UI never renders a ninth seat.

## Realtime event allowlist

Only the following legacy event categories are accepted by the M1 gateway contract:

- mic up/down/open/close and full mic snapshot;
- room mute/unmute/kick;
- room topic, room name, auto-lock, and room unavailable;
- public-screen text;
- ordinary gift broadcast;
- basic room-PK lifecycle events reserved for RM-013/RM-014.

Unknown events and retired gameplay events are ignored. They do not create UI entries or routes.

## Known integration gaps

- The Flutter Agora driver is opt-in (`ENABLE_AGORA_RTC=true`); it requires the
  authenticated `buildAgoraToken` response to be complete before joining and
  remains snapshot-only when that readiness contract is unavailable.
- The approved realtime socket/MQTT/IM handshake and heartbeat are not configured.
- Wallet balance and server-backed gift catalog need their authoritative economy routes.
- The development gateway, database-backed accounts, and non-production credentials are not present in this public repository.
