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

### Tencent Cloud IM session contract

Phase 1 wires only the no-UI session lifecycle. It does not send or receive
messages. In a live build the lifecycle is selected only when
`ENABLE_TENCENT_IM=true`; the default is blocked. After consent and a
first-party login, the client sends an authenticated request with no body or
client-supplied uid:

```text
POST /app-mini-api/mini/v1/im/credential
X-Request-Id: <client-generated opaque id>
Cache-Control: no-store
```

The response must carry `Cache-Control: no-store` and the common envelope. Its
`data` object is an exact allow-list: `provider=tencent-im`, positive integer
`sdkAppId`, canonical `userId=u-<positive platform user id>`, bounded
server-issued `userSig`, ISO-8601 `expiresAt`, bounded `ttlSeconds`,
`imStatus=READY`, and the bounded public `systemAccount` used to identify
first-party refresh-hint senders. The client never accepts an SDK app id from a
dart-define, generates a UserSig, or writes a UserSig to storage. A provider
identity that does not match the authenticated platform session fails closed.
The adapter proactively refetches and renews at the five-minute expiry window,
and also refetches after the SDK expiry or reconnect callbacks; readiness is
fail-closed inside the renewal window or while offline. A C2C custom element is
eligible only when its transient sender exactly matches the active credential's
`systemAccount`, `groupId=null`, and `isSelf=false`; its payload is then reduced
to the allow-listed `messageId` and positive signed-64-bit `eventVersion`
metadata. No provider message content is displayed or passed to the UI.

### Tencent AVChatRoom contract

An HTTP room enter/reconnect response may include the following exact
provider projection inside the full room snapshot:

```json
{
  "roomId": "room-public-id",
  "sessionId": "first-party-session-id",
  "version": 2147483648,
  "realtimeGroup": {
    "provider": "tencent-im",
    "type": "AVCHATROOM",
    "groupType": "AVChatRoom",
    "groupId": "server-authorized-group-id",
    "status": "READY",
    "messageMode": "METADATA_HINT",
    "contentAuthority": "HTTP"
  }
}
```

`sessionId` plus the room controller's navigation generation is the active
first-party lease fence; V8 does not expose a `leaseExpiresAt` field. The
client joins only when all seven nested fields are present and `status=READY`.
`status=PENDING` remains a successful HTTP room state and is retained for a
bounded background readiness poll through the authenticated
`GET /app-room-api/room/com/v1/queryRoomOtherInfo?roomId=<room-id>` projection;
it never authorizes an SDK join by itself. A readiness response must match the
same room, session, group, group type, and non-decreasing room version before
it can replace the pending binding. If the projection is absent, malformed,
stale, or the IM provider is unavailable, the room stays HTTP-only.

After a `READY` binding, the client performs the official AVChatRoom
`joinGroup` for the server group. At most one current group is fenced per
account; switching or leaving clears the local fence first and starts bounded
best-effort `quitGroup` cleanup without delaying the first-party HTTP exit. A
group custom element is accepted only from the active public `systemAccount`,
with `isSelf=false` and the current `groupId`; duplicate or non-increasing
`eventVersion` values, old session fences, and wrong groups are discarded. The
element carries no renderable content or authorization. It can only trigger
the current room's authoritative HTTP `public-messages`/snapshot refresh,
which is the sole source of rendered public messages.

Public message send/history responses support both
`deliveryMode=HTTP_PERSISTED_NO_REALTIME` with `realtimeStatus=VENDOR_BLOCKED`
and `deliveryMode=HTTP_PERSISTED_METADATA_HINT` with an allow-listed dynamic
`realtimeStatus` and signed-64-bit `eventVersion`. Both modes render only the
HTTP-persisted content; realtime metadata never becomes UI content or an
authorization decision.

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
