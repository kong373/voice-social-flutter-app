# First-party room audio lifecycle

Local Flutter plugin; no RTC engine, HTTP, secrets, background runner, wake lock,
boot receiver, or service restart. Created from Flutter commit
`87ccc5ec55b9ea953200b1fd3e9545dea1f298c5` on `codex/rtc-background-native`.
Only this package is in scope. AppDependencies, root pubspec/lock, Runner plist,
RtcAdapter, RoomController and backend integration belong to the main task.

## Frozen public Dart contract

```dart
final audio = FirstPartyRoomAudio(); // Exactly one owner per Flutter engine.
// Optional test seam: channelTimeout; production default is 5 seconds.
Future<bool> start({required String sessionId, required bool microphone});
Future<void> stop({required String sessionId});
Future<bool> isActive({required String sessionId});
Stream<RoomAudioActivity> get events;
Future<void> dispose();

const RoomAudioActivity({required String sessionId, required bool active});
// final String sessionId; final bool active;
```

`sessionId` is an opaque, locally generated UUID per transport generation, never
a token, account or room identifier. Only the exact 36-character hex UUID shape
is accepted, case sensitive for identity. Do not change spelling within a lease.

MethodChannel `voice_social_app/room_audio`:

| Method | Exact arguments | Result |
| --- | --- | --- |
| start | `{sessionId: String, microphone: bool}` | bool |
| stop | `{sessionId: String}` | null |
| isActive | `{sessionId: String}` | bool |
| renew (private to plugin) | `{sessionId: String}` | bool |

EventChannel `voice_social_app/room_audio/events` takes no listen arguments.
Every event is exactly `{sessionId: String, active: bool}`. Unknown fields,
numeric booleans and malformed UUIDs are rejected. Invalid native method
arguments return `invalid_arguments` with a constant message and no details;
unknown methods are not implemented. Dart invalid UUIDs throw `ArgumentError`;
malformed events produce `FormatException` on the stream. Native start denial
returns false. Dart maps PlatformException/MissingPluginException for bool
operations to false; stop/dispose propagate channel errors rather than pretend
cleanup succeeded. Neither layer logs identifiers or platform exception text.

Every method invocation has a five-second wait limit (covers Android's
four-second launch deadline). Tests can inject a positive `channelTimeout`.
start/isActive/renew timeout or unknown results return false and invalidate the
matching locally owned generation, immediately cancelling its renewal timer.
An explicit false start remains a rejected promotion and preserves an existing
listen lease. Uncertain starts receive a bounded best-effort stop addressed to
the original UUID. Late responses and positive events cannot revive an
invalidated generation. A query for an unowned UUID never cleans up another
generation.

Malformed events first invalidate the current/pending generation, emit its
inactive event and issue bounded best-effort cleanup, then deliver
`FormatException`. They cannot keep renewing a lease. Inactive here means local
lease validity was revoked, not that native stop was confirmed. Unconfirmed
stops are retained for disposal to retry. Explicit stop/dispose propagate
`TimeoutException` or channel errors; non-null stop responses are
`invalid_response`. Repeated dispose returns the same result, including failure.
Disposal also bounds subscription cancellation and stream closure. The limit is
per operation, not a promise that queued disposal plus all cleanup stages ends
within five seconds. Native lease expiry remains the fallback if cleanup has
no acknowledgement. Use a fresh UUID for each replacement generation.

Events retain generation identity: consumers must ignore stale generations.
The Dart wrapper only clears its current lease on a matching inactive event.
Subscribe before start. Stream is broadcast, not replayed. The native event
listener is installed at first start and retained until dispose. The event
transport is single-owner; do not construct competing wrappers on one engine.

`true` means the native runtime lease is currently valid. It never proves
audio capture, audible playback, Agora membership, packet delivery or network
quality. Android additionally requires successful `Service.startForeground`.

## Lifecycle and integration boundaries

- Initial start requires foreground UI. Host must call it from a user action;
  a channel cannot independently attest the origin of a Dart call. Android
  requires resumed, focused, non-finishing Activity; headless starts fail.
- Same generation/mode is idempotent, including in background. A microphone
  lease must still have microphone permission. Conflicting generations fail
  closed. Stop for an old generation cannot stop the current one.
- Same generation `false -> true` requires foreground and already-granted mic
  permission. Plugin never requests permission. Failed promotion retains the
  listen lease; it never commits a microphone lease before platform success.
- Same generation `true -> false` is allowed in background. Android failure
  to demote closes that generation, avoiding a residual microphone lease.
  Host must also mute/disable RTC capture: changing FGS types does not mute Agora.
- Dart internally renews every 10 seconds; each successful renewal extends a
  45-second native lease. Queries do not renew. Expired leases cannot be revived
  by renew. Event cancellation, engine/activity detach (including rotation on
  Android), explicit stop/dispose and native invalidation clean up the lease.
  After invalidation the host must perform an explicit eligible start again.
- This local renew is unrelated to the server's authenticated POST heartbeat.
  No backend request is made or implied. A server lease must rely on actual
  server-received requests, according to the host contract.
- If Dart stops running while Android native execution continues, the service
  stops after 45 seconds without renewal. Timers do not wake sleeping devices;
  expiration is also checked against monotonic time on the next channel call.
  iOS suspended execution cannot run a cleanup timer: cleanup/check occurs when
  execution resumes. No infinite native self-renewal or background task is used.
  Process termination cannot deliver an event into a dead Dart engine.

## Android 24–36

Reuses existing `first_party_native_permissions` build approach and exact
AGP 9.0.1 / Kotlin 2.3.20, compileSdk 36, minSdk 24 and Java 17; adds no library
dependency. Plugin manifest declares `FOREGROUND_SERVICE`,
`FOREGROUND_SERVICE_MEDIA_PLAYBACK`, `FOREGROUND_SERVICE_MICROPHONE`,
`RECORD_AUDIO`; service is `exported=false`, `stopWithTask=true` and returns
`START_NOT_STICKY`.

Listen-only uses mediaPlayback. Microphone adds the microphone type on API 30+;
earlier supported platforms use their available FGS APIs with permission checks.
Launch confirmation has a four-second timeout. A private per-request nonce
rejects delayed launch intents, and teardown refuses new starts until the old
service is destroyed. Pending launch is not an active lease. onDestroy and
onTaskRemoved invalidate observable state where the OS delivers those callbacks.
With stopWithTask, task removal can go directly to service destruction.

The ongoing notification uses generic text and an immutable pending intent to
return to the app, with no content/account/session extras. No notification
permission is requested. OS policy controls drawer presentation when permission
is denied; successful FGS establishment remains distinct from presentation.

## iOS 13+: observe SDK-owned AudioSession

Agora Flutter 6.6.3 documents that both SDK and app can operate AudioSession by
default. Its `setAudioSessionOperationRestriction` can restrict SDK category,
configuration, deactivation or all operations. This plugin deliberately calls
none of those APIs and never calls AVAudioSession `setCategory`, `setMode`,
`setActive` or changes routes. Agora retains activation and teardown ownership.

Eligibility requires host `UIBackgroundModes` containing `audio`, no ongoing
interruption, and category `.playback` or `.playAndRecord`. Microphone additionally
requires `.playAndRecord` and granted record permission. Host should call start
after the SDK has established the desired configuration.

**There is no reliable public AVAudioSession isActive getter.** Category and
permission checks are configuration evidence only. The plugin's active value is
its own bounded observation lease, not proof of an activated AVAudioSession.
If the host needs proof of real audio, it must use RTC callbacks and physical
playback/capture acceptance, independently of this API.

Interruption begin/unknown interruption, media services loss/reset, termination,
invalid configuration on route/foreground/query/renew and engine detach clear
the lease. Interruption end never restores it automatically. Stop only removes
the matching observation lease; it does not deactivate the SDK's AudioSession.
The registrar publishes the plugin so Flutter delivers engine-detach cleanup.
The main task must add the host background mode and own SDK stop/mute/wiring.

## Verification and remaining acceptance

Small tests only; no devices, Docker, actual RTC/vendor call, Gradle build,
Xcode build or full app test suite was started.

Initial delivery: 9 Dart tests passed (21 seconds), Dart analysis reported no
issues, pure Kotlin boundary checks passed, Swift parse and Ruby podspec syntax
checks passed. The renewal test uses a bounded real timer; an earlier fake-clock
test attempt hung and was replaced before this passing run.

Follow-up bounded-channel regression: the old implementation (with only the
constructor test seam added) reproduced a hung-start timeout and missing
inactive event. The corrected package adds hanging start/renew/stop/dispose,
isActive timeout, late response, stale cleanup and malformed-event/no-renew
tests. Android notification/channel labels are now Simplified Chinese.
Final follow-up result: all 17 package tests passed in 21 seconds, Dart analysis
reported no issues, and the patch passed `git diff --check`.
This follow-up does not add native compilation or device evidence.

- Dart test-first initial failure: missing implementation, then package tests.
- `flutter test --no-pub`: public contract, malformed events, generation
  isolation, deferred start confirmation, failed promotion and bounded renewal.
- `flutter analyze --no-pub`: package static analysis.
- `AudioLeaseTest.kt`: standalone pure JVM boundary checks compiled with cached
  Kotlin 2.3.20, JVM target 17, max compiler heap 256 MB; no Android runtime.
- `xcrun swiftc -frontend -parse ios/Classes/FirstPartyRoomAudioPlugin.swift`:
  syntax only, not SDK type checking or linking.

**Not verified:** native Android plugin compilation/manifest merge, Swift SDK
type checking/linking, physical FGS startup and downgrade, background/lock-screen
sound, permission revocation, interruption recovery, engine teardown and task
removal on devices. These are main-task integration/acceptance gates, not passed
by the pure state checks.

## Official references checked 2026-09-08

- [Android FGS types](https://developer.android.com/develop/background-work/services/fgs/service-types)
- [Android FGS launch and promotion](https://developer.android.com/develop/background-work/services/fgs/launch)
- [Apple playAndRecord and background audio](https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/playandrecord)
- [Agora Flutter AudioSession restrictions and defaults](https://doc.shengwang.cn/api-ref/rtc/flutter/API/toc_audio_basic)
- [Agora Flutter 6.6.3 restriction enum](https://pub.dev/documentation/agora_rtc_engine/latest/agora_rtc_engine/AudioSessionOperationRestriction.html)

Also checked the installed 6.6.3 Dart API comments and FlutterPlugin.h's explicit
requirement to publish plugins for engine-detach callbacks.
