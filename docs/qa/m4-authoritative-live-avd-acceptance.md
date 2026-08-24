# M4 authoritative live AVD acceptance

This document defines the acceptance contract for the Flutter client against
the first-party development backend at the fixed Android-emulator origin
`http://10.0.2.2:18080/`. It is a runner specification, not a record of a
successful run. The runner does not start a contract server or any formal SMS,
RTC, IM, payment, push, or object-storage vendor. Contract-server targets and
port `8765` are rejected before an emulator is launched.

## Current status

`LIVE_DUAL_AVD_ACCEPTANCE=PENDING`. The first-party live mutation graph and
the dual-AVD evidence gate are ready for a protected run, but this checkout
does not contain AVD-A/AVD-B evidence. Do not change this status to `PASS`
from a local Flutter test, a contract test, a single AVD, a screenshot, or the
`M4_ACCEPTANCE::PASS` marker alone. Only the aggregate gate may emit
`ANDROID_EMULATOR_PASS`.

## AVD matrix

The runner executes the two devices serially. It validates the Android API,
applies the physical size and density, and the live integration test asserts
the resulting logical viewport and device-pixel ratio.

| ID | Android | profile | installed AVD name | physical override | density | logical viewport | DPR marker |
| --- | ---: | --- | --- | --- | ---: | --- | ---: |
| AVD-A | API 36 | `pixel_7_pro` | `voice_social_m4_avd_a_api36` | `1170x2532` | `480` | `390x844` | `3.00` |
| AVD-B | API 35 | `pixel_2` | `voice_social_m4_avd_b_api35` | `864x1920` | `384` | `360x800` | `2.40` |

The expected log markers are `M4_VIEWPORT::AVD-A::390x844::3.00` and
`M4_VIEWPORT::AVD-B::360x800::2.40`. An already-running emulator can be
selected with `QA_AVD_A_SERIAL` or `QA_AVD_B_SERIAL`; otherwise the runner
starts the corresponding configured AVD. The shell defaults are
`pixel_7_pro`/`pixel_2`; the installed AVD names in the table must be exported
explicitly for this runtime. A partial or single-AVD run cannot pass.

## First-party live scope

`integration_test/m4_first_party_live_integration_test.dart` uses the real
`AppDependencies` live graph. It records route markers and authority
invariants for first-party reads and, when the authoritative precondition is
present, real first-party writes. Every write is followed by an authoritative
recovery read or a compensating action. An explicit domain/precondition state
may be recorded; a missing fixture, inferred response, network failure,
protocol failure, configuration failure, server failure, authorization failure,
or unknown exception is not converted into success.

The current required mutation capabilities are:

- `community.checkin` and `community.task.claim`; if another AVD has already
  completed an idempotent business-day operation, the test records
  `already_authoritative` instead of issuing a duplicate write.
- `commerce.gift.send` followed by `commerce.gift.receipt`, using an
  authoritative catalog item, wallet balance, room member, quantity, and
  request ID. The receipt must match the transfer and confirm
  `providerInvocation=false`.
- `commerce.withdraw.apply` followed by `commerce.withdraw.result` when the
  first-party wallet, real-name, balance, quote, and selectable payout-account
  preconditions allow manual review. An existing pending record is recovered
  instead of submitted twice.
- `commerce.refund.submit` followed by `commerce.refund.result`; a rejected
  result may use `commerce.refund.retry` only when the authoritative state
  allows retry. Payment providers are not involved.
- `room.enter`, `room.reconnect`, and `room.exit.cleanup`, plus direct-room
  moderation mute/restore, seat up/down compensation, public-message reads,
  and room PK recovery. The room writes are bound to the current user's own
  authoritative room and are compensated before the flow ends.
- `room.mic_requests.submit`, `room.mic_requests.get`, and
  `room.mic_requests.cancel` in a separate approval-mode room. The required
  sequence is submit → GET and verify the own pending request → cancel, then
  room exit.
- `message.private.send` followed by `message.private.history`, notification
  read/detail where an unread notification exists, and
  `message.notifications.clear`. These are first-party storage/projection
  writes; IM delivery, push delivery, and provider sessions remain blocked.

The principal M4 live write/read witnesses use these catalog routes:

| Capability | Method and route |
| --- | --- |
| Community check-in / task claim | `POST /app-api/taskSystem/completeDailySignIn`; `POST /app-api/taskSystem/receiveTaskReward` |
| Gift / receipt | `POST /app-room-api/room/com/v1/sendGift`; `GET /app-room-api/room/com/v1/giftReceipt` |
| Withdrawal / recovery | `POST /app-mini-api/mini/v1/withdrawal/apply`; `GET /app-mini-api/mini/v1/withdrawal/records` |
| Refund / result / retry | `POST /app-api/refund/application`; `GET /app-api/refund/result`; `POST /app-api/refund/repeat` |
| Room lifecycle | `POST /app-room-api/room/com/v1/enterRoom`; `POST /app-room-api/room/com/v1/reConnectRoomInfo`; `POST /app-room-api/room/com/v1/exitRoom` |
| Room moderation / seat compensation | `POST /app-api/roomUsers/setMuted`; `POST /app-api/micUserBase/userInitiativeUpMic`; `POST /app-api/micUserBase/leaveMic` |
| PK recovery | `POST /app-api/activityPk/inviteRoomPk`; `POST /app-api/activityPk/acceptRoomPkInvitation`; `POST /app-api/activityPk/rejectRoomPkInvitation`; `POST /app-api/activityPk/surrenderRoomPk` |
| Approval microphone queue | `GET/POST /app-mini-api/mini/v1/rooms/mic-requests`; `POST /app-mini-api/mini/v1/rooms/mic-requests/cancel` |
| Private message / history | `POST /app-mini-api/mini/v1/message/send`; `GET /app-api/user/imMessage/queryChat` |
| Notification read / clear | `POST /app-mini-api/mini/v1/notifications/read`; `POST /app-api/dynamic/emptyUserDynamicNotify` |

The first-party adapter layer also has social profile/relation/privacy/friend-
request writes and dynamic publish/like/comment/delete contracts. Their exact
request and idempotency contracts are covered by
`test/backend_social_repository_contract_test.dart` and
`test/backend_dynamic_repository_contract_test.dart`; those local contract
tests are not AVD evidence. The live AVD flow records dynamic feed and social
profile/homepage reads as required capabilities and must not claim a social or
dynamic mutation without a discovered authoritative target and a safe recovery
path.

Dynamic feed (`dynamic.feed`), social profile/homepage, search, community
reads, room snapshots, commerce reads, compliance, support, and their real UI
entry points are also required first-party live coverage. The test does not
invent dynamic publish/like/comment or social-provider success when no safe
first-party write contract is present. The route-capability catalog and
`requiredMutationCapabilities` in the integration test are authoritative; a
raw route-count threshold is only a minimum evidence check.

### Deterministic room fixture and authority rules

The development fixture must expose two distinct rooms owned by the currently
authenticated user:

1. one `OPEN` direct-access room (the accepted direct access modes are
   `DIRECT`, `PUBLIC`, or `PASSWORD`); and
2. one `APPROVAL` room for the microphone queue.

The test obtains the rooms from the first-party owned-room collection, keeps
only canonical UUID IDs, and enters each candidate to prove the authoritative
`roomId`, current-user `ownerId`, `OWNER` role, and access mode. It rejects a
non-canonical ID, an unknown mode, a missing mode, a non-owned room, a reused
room ID, or a fixture with only one usable room. No fixed room ID is passed in
the command line or embedded in the live test.

The direct path proves enter/reconnect authority before moderation, seat,
gift, or PK writes and ends with `exitRoom`. The approval path proves
enter/reconnect authority, reads the queue, cancels any own stale pending
request, selects an available authoritative seat, submits a new request, GETs
the queue to verify that request, cancels it, and exits. The invariant marker
for the compensated queue flow is
`M4_AUTHORITY_INVARIANT::approval_mic_queue_action_compensated`.

## Formal vendor boundary

The live integration expects the first-party readiness document to report
`integrationStatus=READY_FOR_PROVIDER_INTEGRATION` and
`runtimeStatus=VENDOR_BLOCKED`, with all six formal capabilities present. Each
capability must have `boundaryStatus=READY`, `boundaryReady=true`,
`runtimeStatus=VENDOR_BLOCKED`, and `runtimeReady=false`; the client-side
runtime adapters remain disabled or unconfigured:

| Capability | Runtime rule |
| --- | --- |
| SMS | Development `sendSmsCode` may return an in-memory OTP for this controlled test; no formal SMS vendor is called. |
| RTC | Snapshot-only/unavailable transport; no provider media join or publication. |
| IM | No provider realtime session or delivery. |
| PAYMENT | Payment-channel invocation is unsupported; no order creation, SDK launch, callback, or success. |
| PUSH | No push registration or delivery claim. |
| OBJECT_STORAGE | No provider-backed upload or media success. |

The live dependency graph must retain the first-party adapters while exposing
no OAuth client secret, development outbox key, payment invocation support,
realtime invitation support, RTC transport, IM transport, audio service, or
other formal vendor configuration. The test emits exactly one
`M4_PROVIDER_CALLS::0` marker and `providerCalls=0` in report data. The runner
and aggregate gate reject a missing marker, a nonzero marker, or any provider
call. There is no formal vendor access in this acceptance.

## Protected inputs and secret handling

Keep all values in the protected process environment. Never paste an actual
value into a command, issue, log, screenshot, artifact, source file, APK, or
this document.

Required to run:

- `QA_ARTIFACT_ROOT`, `QA_RUN_ID`, `QA_FLUTTER_SHA`, `QA_BACKEND_SHA`, and
  `QA_BACKEND_REPO` identify the run and the exact checked-out commits.
- `QA_LIVE_PHONE` is the development-profile test account phone.
- `QA_OAUTH_CLIENT_ID` is the public OAuth client ID used by the development
  account.
- `QA_M4_FIXTURE_ID` identifies the newly provisioned, dedicated M4 fixture and
  must match `m4-fresh-*`; `QA_M4_FIXTURE_STATUS` must be the literal
  `fresh_dedicated`. A legacy account is not an acceptable substitute.

Required for collected DB evidence and an aggregate pass:

- `QA_DB_EVIDENCE_URL`, an operator-authenticated endpoint in the same
  authoritative development environment; and
- `QA_DB_EVIDENCE_TOKEN`, supplied only through the protected environment.

Both DB values are mandatory for a final `ANDROID_EMULATOR_PASS`; if either is
missing, the runner must fail the AVD with missing DB write evidence.

The controlled read-only endpoint implementation is tracked at
`tool/qa/m4_db_evidence_server.py`. The runner verifies that file and runs its
local self-test before touching an AVD; an untracked `/private/tmp` copy is not
an accepted substitute. Start the helper in the protected operator process
with its loopback/container settings, then point `QA_DB_EVIDENCE_URL` at the
announced ephemeral listener. The helper's self-test is safe to run without
Docker:

```bash
python3 tool/qa/m4_db_evidence_server.py --self-test
```

The runner refuses `DEVELOPMENT_OUTBOX_KEY`,
`QA_DEVELOPMENT_OUTBOX_KEY`, `QA_API_BASE_URL`, and contract-server variables.
It strips OAuth/client-secret aliases and all protected values before starting
Flutter, starts only an ephemeral loopback relay for the phone and public
client ID, and redacts Flutter/logcat/DB output before writing artifacts. The
relay requires a distinct high-entropy one-time bearer for each AVD. The bearer
is delivered through a mode-0600 file in the debug app's private cache using
`adb shell run-as`, then deleted after the test; it is never a `dart-define`,
APK value, process argument, log, or artifact. The relay's ephemeral port is
the only relay value passed as a `dart-define`; the phone, OTP, OAuth value,
and DB token do not enter the APK, test source, markers, screenshot names, or
evidence metadata.

## Invocation

Run from the Flutter checkout with the backend checkout at the exact SHA under
test. Use placeholders or protected environment values; do not replace them
with real credentials in documentation or shell history.

```bash
export ANDROID_SDK_ROOT="/Users/kongzheng/Library/Android/sdk"
export PATH="$ANDROID_SDK_ROOT/platform-tools:$ANDROID_SDK_ROOT/emulator:$PATH"
export QA_AVD_A_NAME="voice_social_m4_avd_a_api36"
export QA_AVD_B_NAME="voice_social_m4_avd_b_api35"
export QA_ARTIFACT_ROOT="$PWD/artifacts/qa/m4-authoritative-live-avd"
export QA_RUN_ID="m4-$(date +%Y%m%d%H%M%S)"
export QA_FLUTTER_SHA="$(git rev-parse HEAD)"
export QA_BACKEND_REPO="/secure/path/to/authoritative-backend"
export QA_BACKEND_SHA="$(git -C "$QA_BACKEND_REPO" rev-parse HEAD)"
export QA_M4_FIXTURE_ID="m4-fresh-YYYYMMDD"
export QA_M4_FIXTURE_STATUS="fresh_dedicated"
# QA_M4_FIXTURE_ID is passed as a non-secret dart-define only. The integration
# test derives nickname m4-<first-16-lowercase-hex-of-sha256(fixture-id)>.
# QA_LIVE_PHONE, QA_OAUTH_CLIENT_ID, QA_DB_EVIDENCE_URL, and
# QA_DB_EVIDENCE_TOKEN come from the protected runner environment.

# Start the helper in the same protected operator shell. These are the default
# Compose container names for this checkout and the local Colima socket; keep
# the token in the protected environment and never place its value in docs or
# shell history.
export M4_BACKEND_CONTAINER="voice-social-backend-backend-1"
export M4_MYSQL_CONTAINER="voice-social-backend-mysql-1"
export M4_DOCKER_SOCKET="unix://${HOME}/.colima/default/docker.sock"
: "${QA_DB_EVIDENCE_TOKEN:?set QA_DB_EVIDENCE_TOKEN in the protected runner environment}"
export M4_DB_EVIDENCE_TOKEN="$QA_DB_EVIDENCE_TOKEN"

python3 tool/qa/m4_db_evidence_server.py --self-test
M4_DB_EVIDENCE_LOG="$(mktemp "${TMPDIR:-/tmp}/m4-db-evidence.XXXXXX")"
python3 tool/qa/m4_db_evidence_server.py >"$M4_DB_EVIDENCE_LOG" 2>&1 &
M4_DB_EVIDENCE_PID=$!
for _ in $(seq 1 50); do
  if grep -q '^M4_DB_EVIDENCE_LISTENING=' "$M4_DB_EVIDENCE_LOG"; then break; fi
  sleep 0.1
done
M4_DB_EVIDENCE_LISTENING="$(sed -n 's/^M4_DB_EVIDENCE_LISTENING=//p' "$M4_DB_EVIDENCE_LOG")"
[[ -n "$M4_DB_EVIDENCE_LISTENING" ]] || { kill "$M4_DB_EVIDENCE_PID"; exit 1; }
export QA_DB_EVIDENCE_URL="http://$M4_DB_EVIDENCE_LISTENING/m4/db-evidence"

./tool/qa/run_m4_authoritative_live_avd.sh

QA_ARTIFACT_ROOT="$QA_ARTIFACT_ROOT" \
QA_RUN_ID="$QA_RUN_ID" \
QA_FLUTTER_SHA="$QA_FLUTTER_SHA" \
QA_BACKEND_SHA="$QA_BACKEND_SHA" \
  ./tool/qa/aggregate_m4_authoritative_live_avd.sh

kill "$M4_DB_EVIDENCE_PID" 2>/dev/null || true
wait "$M4_DB_EVIDENCE_PID" 2>/dev/null || true
rm -f "$M4_DB_EVIDENCE_LOG"
```

`QA_FLUTTER_SHA` and `QA_BACKEND_SHA` are mandatory and are compared with the
checked-out commits before the run. The helper independently checks that
`QA_BACKEND_REPO` is clean and at `QA_BACKEND_SHA`, runs the tracked
`scripts/compute-backend-source-digest.sh`, and compares that digest in
constant time with `/app/backend-source.sha256` from the named backend
container. An OCI revision label can only corroborate this check; it can never
replace the checkout and file digest. The API base URL is not an input: it is
the fixed `10.0.2.2:18080` value in both the runner and test. The runner
requires Flutter, Android `adb`/emulator tooling, Python 3, `curl`, and the
standard file/scan utilities; its timeout is implemented through Python.

The AVDs use one dedicated QA phone, so the runner treats the development SMS
challenge limit as an explicit 60-second cooldown. It records the AVD-A
challenge window, waits only the residual window before AVD-B in bounded short
sleeps, and records the wait in `sms-cooldown.txt`. A rerun should use a new
`QA_RUN_ID` and fresh fixture attestation; it never reuses a legacy account or
bypasses the cooldown with a second phone value.

## Current-run DB evidence contract

`QA_DB_EVIDENCE_URL` must return redacted aggregate JSON from the authoritative
backend, not rows, credentials, Flutter, port `8765`, or a contract server.
The accepted shape is exactly:

```json
{
  "status": "OK",
  "writeCounters": {
    "auth_sessions": 1,
    "room_activity": 0,
    "commerce_activity": 0,
    "social_community_messages": 0,
    "social_user_reports": 1,
    "idempotency_audit": 1
  },
  "scopedCounters": {
    "refresh_session_user": 1,
    "user_report_reporter": 1,
    "operation_idempotency_actor": 1
  },
  "authorityInvariants": {
    "core_schema_present": true,
    "provider_outbox_allowed_states": true,
    "provider_outbox_attempts_zero": true,
    "private_message_delivery_blocked": true,
    "adapter_status_projection_blocked": true,
    "backend_environment_development": true,
    "backend_profile_development": true,
    "development_outbox_or_blocked_sms": true,
    "formal_vendor_adapters_blocked": true,
    "provider_invocation_rows_zero": true,
    "first_party_writes_observed_since_start": true,
    "expected_backend_sha_matches": true
  },
  "providerCalls": 0,
  "secrets": false,
  "evidenceBinding": {
    "runId": "m4-YYYYMMDDHHMMSS",
    "avd": "AVD-A",
    "startNonce": "opaque-per-AVD-start-nonce",
    "fixtureId": "m4-fresh-YYYYMMDD",
    "fixtureAccountState": "created_during_run",
    "mutationKeys": [
      "auth_sessions",
      "room_activity",
      "commerce_activity",
      "social_community_messages",
      "social_user_reports",
      "idempotency_audit"
    ]
  }
}
```

The helper configuration requires the exact expected backend checkout SHA and
repo; a missing, dirty, mismatched, or non-attested checkout/content digest is
a hard failure. The runner first sends an
authenticated `GET` with `X-M4-Evidence-Phase: start`, `X-M4-Run-ID`,
`X-M4-AVD`, and `X-M4-Fixture-ID`. The helper independently derives the
fixture nickname, joins `m4_development_fixture_user` to `app_user`, and
requires AVD-A to have zero matching accounts at start while AVD-B has exactly
one. It takes a read-only snapshot and returns a one-shot opaque `startNonce`.
After that AVD's Flutter run, the runner sends the nonce back with
`X-M4-Evidence-Phase: collect`; the helper computes the delta from that exact
start snapshot, requires exactly one matching account, and echoes
`evidenceBinding`. A nonce can be collected only once for its exact run/AVD
pair. Missing, duplicate, stale, cross-AVD, or cross-run contexts return
unavailable and cannot produce a pass.

The names and counts in the example are illustrative only; the endpoint must
return current-run counters. The runner and aggregate gate require exactly the
six fixed `writeCounters` keys above, non-negative integer deltas with a
positive total, and a positive `social_user_reports` delta for the required
current-run room-report mutation. They also require exactly the three fixed
fixture-scoped counters above, each positive for the same account (so global
unrelated writes cannot satisfy the gate), the fixed invariant set including
`expected_backend_sha_matches`, the exact binding fields and mutation-key list,
`status=OK`,
`providerCalls=0`, and `secrets=false`. A missing URL/token pair, failed
endpoint, invalid response, or `NOT_CONFIGURED` file is a failed AVD, never a
passing substitute. The token is sent through an in-memory Python request and
never appears in an argument.

## Evidence layout and strict aggregate gate

`tool/qa/run_m4_authoritative_live_avd.sh` writes independent evidence under
`$QA_ARTIFACT_ROOT`:

```text
$QA_ARTIFACT_ROOT/
  AVD-A/
    environment.txt
    result.txt
    screenshots/*.png
    logs/flutter-drive.log
    logs/logcat-full.txt
    logs/flutter-errors.txt
    logs/crash-anr.txt
    http-route-coverage.csv
    authority-invariants.txt
    db-write-counters.txt
    db-evidence.json
    db-evidence-status.txt        # COLLECTED on a valid DB response
    secret-scan.txt
    apk-secret-scan.txt
  AVD-B/                         # same layout
  config-relay/relay.log
  sms-cooldown.txt
  summary.txt
  evidence-manifest.sha256
```

Failure diagnostics may additionally include `db-evidence-error.txt`,
`db-evidence-curl.stderr`, `db-evidence-validation.stderr`,
`logs/logcat-sanitizer.stderr`, or an `emulator.log` when the runner starts an
AVD. These files are also subject to the final artifact scan.

`http-route-coverage.csv` is generated from unique
`M4_ROUTE_STATUS::capability::method::route::status::state` markers and has
the header `capability,method,route,status,state`. The route status must be a
2xx–4xx status; unsafe/unknown outcomes fail required probes.
`authority-invariants.txt` is the unique sorted list of
`M4_AUTHORITY_INVARIANT::...` markers. `db-write-counters.txt` records the
client-observed write marker count and points to `db-evidence.json`; it is not
a substitute for the operator DB response.

Each `result.txt` must report `result=PASS`, `acceptance_status=PASS`, matching
`run_id`, fresh `fixture_id`/`fixture_status`, a per-AVD `db_start_nonce`, tested
Flutter SHA, backend SHA, `provider_calls_made=false`,
`db_evidence=COLLECTED`, passing secret/APK scans, zero hard findings and
crash/ANR findings, at least four non-empty screenshots, at least ten unique
route markers, and at least five authority-invariant markers. Its log must
contain exactly one `M4_ACCEPTANCE::PASS`, exactly one
`M4_PROVIDER_CALLS::0`, no nonzero provider marker, no failed acceptance
marker, and no invalid route status. Flutter error and crash/ANR files must be
present and empty.

`tool/qa/aggregate_m4_authoritative_live_avd.sh` is the only command allowed
to emit `ANDROID_EMULATOR_PASS`. It requires both AVD result files to pass,
the same `QA_RUN_ID`, matching fresh fixture attestation, exact matching
Flutter and backend SHAs, valid route and authority evidence, current-run
run/AVD/nonce-bound DB evidence for both AVDs, zero provider calls, clean
hard-error/crash/secret scans, and the exact AVD matrix evidence.
It writes `aggregate-verdict.txt` and `aggregate-verdict.json`; any missing,
stale, partial, provider-tainted, secret-tainted, or non-current-run evidence
emits `ANDROID_EMULATOR_FAIL` and exits nonzero. The runner's final
`summary.txt` and hash-only `evidence-manifest.sha256` are produced after the
complete artifact-root secret scan.

Until a real protected run produces both independent AVD artifacts and the
aggregate verdict accepts them, the authoritative conclusion remains
`LIVE_DUAL_AVD_ACCEPTANCE=PENDING`.
