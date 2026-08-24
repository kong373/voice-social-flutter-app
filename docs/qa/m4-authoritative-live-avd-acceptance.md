# M4 authoritative live AVD acceptance

This acceptance runner exercises the Flutter client against the real first-party
development backend at `http://10.0.2.2:18080/`. It does not start the
deterministic contract server, and it does not start SMS, RTC, IM, payment,
push, or storage vendors. Port `8765` and any `contract-server` target are
rejected before an emulator is launched.

## Current status

`LIVE_DUAL_AVD_ACCEPTANCE=PENDING`. This file specifies the authoritative
runner and its evidence contract; it is not evidence that the runner has
passed. No live AVD `PASS` may be recorded until both AVD-A and AVD-B produce
protected evidence on the same candidate SHA and the aggregate gate accepts.

## Matrix and execution order

The script runs the two devices serially:

| ID | Android | profile | physical override | density | Flutter logical viewport | DPR |
| --- | ---: | --- | --- | ---: | --- | ---: |
| AVD-A | API 36 | `pixel_7_pro` | `1170x2532` | `480` | `390x844` | `3.00` |
| AVD-B | API 35 | `pixel_2` | `864x1920` | `384` | `360x800` | `2.40` |

An already-running emulator may be supplied with `QA_AVD_A_SERIAL` or
`QA_AVD_B_SERIAL`; otherwise the script starts the configured AVD by name.
The script validates the Android API level, applies the physical size/density,
and the Flutter test asserts the resulting logical viewport and DPR.

## Protected inputs

The following values are required in the protected process environment. Their
actual values must never be pasted into a command, issue, log, screenshot,
artifact, source file, or APK:

* `QA_LIVE_PHONE`: the development-profile test account phone.
* `QA_OAUTH_CLIENT_ID`: the OAuth public client ID.
* `QA_DB_EVIDENCE_TOKEN`: an operator-only token for the redacted DB evidence
  endpoint (see below).

The exact source of those values is an operator/CI secret store. The runner
refuses `DEVELOPMENT_OUTBOX_KEY`, `QA_DEVELOPMENT_OUTBOX_KEY`,
`QA_API_BASE_URL`, and contract-server variables. The development outbox key
is never passed to Flutter. The app obtains the development OTP only from the
in-memory `sendSmsCode` response.

The runner starts a short-lived loopback configuration relay. The relay sends
the phone and public client ID only to the emulator request at `10.0.2.2` and
does not log requests; only its ephemeral port is supplied as a
`dart-define` value. The actual phone/client ID therefore do not enter the
APK, test source, Flutter debug markers, or evidence metadata. Flutter and
logcat output pass through a redactor before being written to disk.

## Invocation

Run from the Flutter checkout, with the backend checkout at the exact SHA being
tested. Keep the protected values in the environment rather than replacing the
placeholders in this example:

```bash
export QA_ARTIFACT_ROOT="$PWD/artifacts/qa/m4-authoritative-live-avd"
export QA_RUN_ID="m4-$(date +%Y%m%d%H%M%S)"
export QA_FLUTTER_SHA="$(git rev-parse HEAD)"
export QA_BACKEND_REPO="/secure/path/to/authoritative-backend"
export QA_BACKEND_SHA="$(git -C "$QA_BACKEND_REPO" rev-parse HEAD)"
# QA_LIVE_PHONE, QA_OAUTH_CLIENT_ID, QA_DB_EVIDENCE_URL and
# QA_DB_EVIDENCE_TOKEN come from the protected runner environment.
./tool/qa/run_m4_authoritative_live_avd.sh
QA_FLUTTER_SHA="$QA_FLUTTER_SHA" \
QA_BACKEND_SHA="$QA_BACKEND_SHA" \
QA_ARTIFACT_ROOT="$QA_ARTIFACT_ROOT" \
  ./tool/qa/aggregate_m4_authoritative_live_avd.sh
```

`QA_FLUTTER_SHA` and `QA_BACKEND_SHA` are mandatory and are compared with the
checked-out commits before the run. The API base URL is intentionally not an
input: it is the fixed authoritative `10.0.2.2:18080` value in the runner and
test. Domain states such as an absent guild or an ineligible operation may be
recorded as explicit redacted states. Network, timeout, server, protocol,
configuration, authorization, unknown-exception, and required-route failures
fail the run instead of being counted as optional coverage.
The host must provide Flutter, Android `adb`/emulator tooling, Python 3, and
`curl`. The runner enforces its process timeout through Python, so a separate
GNU `timeout` installation is not required on macOS.

## Strict aggregate gate

`run_m4_authoritative_live_avd.sh` writes independent `AVD-A/result.txt` and
`AVD-B/result.txt` files. The second command above is mandatory: it is the only
place that may emit `ANDROID_EMULATOR_PASS`. It requires both AVD results to be
`PASS`, both `acceptance_status=PASS`, the same exact Flutter
`tested_git_sha`, the exact Backend SHA, successful route and authority
evidence, collected DB evidence, zero provider calls, and clean hard-error and
secret scans. Missing evidence, a stale SHA, nonzero provider calls, or a
single-AVD/partial run produces `ANDROID_EMULATOR_FAIL` and a nonzero exit.
There is no fallback to a previous artifact or run. The script writes
`aggregate-verdict.txt` and the machine-readable `aggregate-verdict.json`.

The Flutter integration test receives the candidate SHAs as non-secret
`dart-define` values and emits `M4_ACCEPTANCE::PASS` only after its required
route outcomes and authority invariants are present. Composite repository reads
are labelled `composite_success`; they are not presented as separately
observed HTTP calls. A missing or failed required outcome raises a test failure
and cannot be converted to PASS by the shell runner.

The required route-capability catalog is maintained in the integration test and
is intentionally grouped by first-party boundary: auth/session, vendor
readiness, home/search/discovery, social, guild/task/activity, room lifecycle
and read-only moderation/PK, messages, wallet/ledger/orders/refund/withdrawal
and catalog, account compliance, and support. The generated
`http-route-coverage.csv` is the evidence instance of that catalog; a raw
route-count threshold alone is not sufficient.

## DB evidence contract

To claim acceptance, the protected `QA_DB_EVIDENCE_URL` must point to an
operator-authenticated endpoint in the authoritative development environment,
not to Flutter, port `8765`, or a contract server. The endpoint must return
redacted JSON counters rather than rows or credentials, for example:

```json
{
  "status": "OK",
  "writeCounters": {
    "auth_session": 1,
    "room_enter_exit": 1
  },
  "authorityInvariants": {
    "session_owner_matches_account": true,
    "room_exit_compensates_enter": true
  },
  "providerCalls": 0,
  "secrets": false
}
```

The runner sends the token from an environment variable through an in-memory
Python request, redacts the response, and never places the token in a command
argument. If the URL/token pair is absent or the endpoint fails, each AVD is
marked `db_write_evidence_missing_or_failed`; a `NOT_CONFIGURED` file is not a
passing substitute. The returned `writeCounters` and `authorityInvariants`
objects must both be non-empty, `providerCalls` must be exactly zero, and
`secrets` must be explicitly false. The endpoint must itself omit phone
numbers, tokens, passwords, OAuth values, and row-level PII.

## Flow and evidence

The single integration test uses the real `AppDependencies` live graph and
covers consent, SMS login/registration, refresh and process-restart recovery,
home and search, dynamic/social/community/task reads, authoritative room enter
and compensating exit with seats/moderation/PK/message reads, message records,
wallet/ledger/orders/gift catalog/withdraw/refund reads, support/compliance,
vendor-boundary UI, and final product logout. Gift sending, payment launch,
withdrawal/refund writes, task claims, moderation writes, seat changes, PK
start, media upload, and every provider invocation are intentionally not
attempted. Logout requires both a confirmed backend response and successful
local credential deletion. If the backend response is not confirmed, local
credentials are still cleared for safety, but the controller exposes that
outcome and M4 fails instead of inventing a `200`. Each high-risk room write is scoped to a discovered
authoritative room and compensated by exit; no fixed fixture ID is used.

Each AVD directory contains:

* `environment.txt` with tested commits, viewport, live target, and provider
  boundary flags;
* `logs/flutter-drive.log`, full redacted `logs/logcat-full.txt`,
  `logs/flutter-errors.txt`, and `logs/crash-anr.txt`;
* Flutter screenshots, `http-route-coverage.csv`,
  `authority-invariants.txt`, and `db-write-counters.txt`;
* `db-evidence.json` plus its collection status;
* `secret-scan.txt`, `apk-secret-scan.txt`, and `result.txt`.

The final `summary.txt` and `evidence-manifest.sha256` are generated after both
serial runs. The strict scan rejects `.env.local`, contract-server/8765 names,
Chinese mobile-number-shaped values, OAuth/client values, bearer/access or
refresh tokens, and the protected DB token. It scans each AVD directory and the
complete artifact root (including the relay log and final summary) before the
hash-only manifest is generated. A run is PASS only when both AVDs
produce the viewport marker, screenshots, route markers, authority invariants,
provider-call marker `0`, DB evidence, clean Flutter/Android findings, and a
zero secret scan. The aggregate gate additionally requires the two AVD results
and tested commit identities to agree.
