# M5 Tencent IM + Alipay sandbox live acceptance

M5 is a two-AVD, provider-live acceptance harness. It is separate from the
M4 first-party workflow and uses only `M5_*` markers. A provider-blocked,
mock, or dry-run result is never a provider PASS.

## Safety boundary

The default run is zero-payment and zero-financial-side-effect:

* the client may read the Alipay catalog;
* it does not create an Alipay order, invoke `AlipaySDK`, or reconcile an
  order;
* no refund or other financial mutation is attempted.

The opt-in cancel lane is allowed only when all of these are supplied outside
the app process:

```text
QA_M5_ALLOW_EXTERNAL_PAYMENT=true
QA_M5_PAYMENT_CONFIRMATION=I_UNDERSTAND_SANDBOX_PAYMENT
QA_M5_ALIPAY_SCENARIO=cancel
QA_M5_ENABLE_ALIPAY_APP_PAY=true
```

The runner passes `M5_ALLOW_EXTERNAL_PAYMENT=true` only after validating this
exact opt-in. A missing or partial opt-in fails closed. The default scenario is
`none`; it never creates an order. `cancel` remains a non-successful,
non-zero PARTIAL lane. A native SDK result, including 9000, is provisional and
the authenticated backend order status remains authoritative.

The separately confirmed sandbox-success lane additionally requires the
following independent confirmation and is the only lane that may create a
successful payment assertion:

```text
QA_M5_ALLOW_EXTERNAL_PAYMENT=true
QA_M5_PAYMENT_CONFIRMATION=I_UNDERSTAND_SANDBOX_PAYMENT
QA_M5_ALIPAY_SCENARIO=success
QA_M5_SUCCESS_CONFIRMATION=I_UNDERSTAND_SANDBOX_SUCCESS_PAYMENT
QA_M5_ENABLE_ALIPAY_APP_PAY=true
```

Only AVD-A may create the order and invoke `AlipaySDK`; AVD-B is a receiver
and all payment lanes must be `NOT_RUN`. The success lane records the native
9000/result as provisional, then requires an authenticated POST reconcile plus
GET status and a second explicit POST reconcile plus GET status for the same
order to return `SUCCEEDED`. It does not trust the native result as settlement.

## Required operator inputs

The runner requires the following values for a live run. Secrets are consumed
through process environment or the one-shot runtime relay and are never put in
Flutter arguments, logs, screenshots, or evidence files:

```text
QA_ARTIFACT_ROOT=/absolute/new/directory
QA_FLUTTER_SHA=<40 lowercase hex characters>
QA_BACKEND_SHA=<40 lowercase hex characters>
QA_BACKEND_REPO=/absolute/backend/checkout
QA_BACKEND_DIGEST=<64 lowercase hex characters>
QA_BACKEND_CONTAINER=<running healthy serving backend container>
QA_M5_RUN_ID=m5-<operator-run-id>
QA_M5_FIXTURE_ID=m5-fresh-<dedicated-fixture>
QA_LIVE_PHONE=<development phone>
QA_M5_RECEIVER_PHONE=<second development phone for AVD-B C2C receiver>
QA_OAUTH_CLIENT_ID=<public OAuth client id>
# Optional external endpoint. Supply both or neither. If omitted, the runner
# starts the tracked helper on loopback after APK attestation.
QA_DB_EVIDENCE_URL=https://<operator-evidence-endpoint>
QA_DB_EVIDENCE_TOKEN=<operator evidence bearer>
QA_M5_MYSQL_CONTAINER=<serving MySQL container, for the built-in helper>
# For a success run, the helper must be started with the same scenario:
M5_ALIPAY_SCENARIO=success
```

The runner requires Docker access to the serving backend, not only a local
checkout. It fails closed unless `QA_BACKEND_CONTAINER` is running and
healthy, Docker publishes its `18080/tcp` on host port `18080`, and the
container's one-line `/app/backend-source.sha256` exactly matches both
`QA_BACKEND_DIGEST` and the digest computed in `QA_BACKEND_REPO`. The tracked
`tool/prepare_android_audio_manifest.py` helper is run after Android host
generation and before host/APK attestation; its audio-only packaging overlay
is therefore included in the host digest and build.

`QA_M5_DRY_RUN=true` is available for CI contract checks and needs only a new
absolute artifact directory. It writes `conclusion=DRY_RUN` and exits without
contacting a vendor, backend, database, or emulator.

AVD-A targets API 36 / `pixel_7_pro` at 390x844 logical pixels and acts as the
C2C sender. AVD-B targets API 35 / `pixel_2` at 360x800 and acts as the C2C
receiver. Both runs are started in parallel so B is listening before A sends;
the sender does not pass until the receiver reports a real SDK hint followed by
an HTTP history refresh. `QA_AVD_A_SERIAL` and `QA_AVD_B_SERIAL` can select
already running devices; otherwise the runner starts the named profiles.

After Tencent login is READY, AVD-A looks only for this run's exact
fixture-scoped room title. If no matching room already has an authoritative
`realtimeGroup.status=READY` projection, AVD-A creates a fresh PUBLIC room via
the room lifecycle API. The runner never promotes an unrelated or historical
`VENDOR_BLOCKED` room. It polls the first-party readiness projection for up to
75 seconds (covering two 30-second worker cycles), shares the resulting room ID
with AVD-B, and both AVDs enter that same room. AVD-A then sends one
fixture-derived public message through HTTP; AVD-B must observe the real
Tencent room custom hint, verify its message ID, and refresh authoritative HTTP
public history before the room hint lane can pass. AVD-A waits for that
receiver proof, and both sides leave through the provider and HTTP paths.
All sender/receiver coordination and provider-hint waits are bounded at 75
seconds so the fixed 30-second backend worker delay gets two opportunities;
timeouts remain BLOCKED/PARTIAL rather than fabricated provider success.

The runner builds the integration-test APK once with the attested source and
public run metadata, then uses that immutable binary on both AVDs. Sender /
receiver role and the corresponding viewport are supplied by the one-shot
relay config at runtime. This keeps the APK SHA in the single DB evidence
binding stable while still coordinating two distinct accounts.

## Provider lanes

The integration test records these lanes independently:

* `tencent.credential` — server-issued UserSig and strict account mapping;
* `tencent.login` — real Tencent SDK initialize/login and READY state;
* `tencent.c2c.http-authority` — A sends through first-party HTTP, B must
  observe the trusted Tencent C2C custom hint in the SDK and then refresh
  history through first-party HTTP; either side alone is not a PASS;
* `tencent.avchatroom.hint` — real AVChatRoom join and a trusted metadata hint
  followed by an authoritative HTTP refresh;
* `tencent.avchatroom.leave` — bounded provider leave plus HTTP room exit;
* `tencent.outage.fallback` — only a real adapter offline event can pass this
  lane;
* `alipay.catalog` — authenticated Android catalog projection;
* `alipay.order` — server-created Alipay sandbox order (opt-in only);
* `alipay.native.launch-cancel` — native launch, SDK cancellation callback,
  explicit authenticated `POST /app-economy-api/pay/ali/order/cancel`, and
  operator cancellation (cancel opt-in only);
* `alipay.native.launch-success` — native launch result marked provisional;
* `alipay.query-reconcile` — success uses reconcile POST followed by a
  mandatory DB status GET; cancel uses the explicit cancel POST followed by a
  mandatory DB-only status GET (opt-in only).
* `alipay.settlement` — success-only DB proof of one verified provider event,
  one succeeded order, one wallet credit, and one balanced two-posting ledger;
* `alipay.reconcile-idempotency` — success-only second reconcile of the same
  order, with no second credit in the DB delta.

`BLOCKED`, `NOT_OPTED_IN`, and `NOT_RUN` remain visible in evidence and none is
converted to PASS. With payment opt-in absent, the aggregate may conclude
`ANDROID_EMULATOR_NO_PAY` (core provider evidence complete) or
`ANDROID_EMULATOR_PARTIAL` (live credentials/evidence incomplete); these are
explicit safety verdicts, not product/provider PASS. Full Alipay lanes are
required only after the exact external opt-in. The cancel opt-in proves order
creation, native SDK callback, and authoritative canceled query state, but
deliberately does not claim a successful payment; it requires no asynchronous
Alipay notify event, reports `ANDROID_EMULATOR_PARTIAL`, and exits nonzero.
The separately confirmed success opt-in may use
`ANDROID_EMULATOR_PASS` only when the success lanes and DB settlement proof
below pass. Only `ANDROID_EMULATOR_PASS` and
`ANDROID_EMULATOR_NO_PAY` are successful aggregate exits; `PARTIAL` and
`FAIL` exit nonzero.

## Evidence contract

Each AVD writes `result.txt`, route CSV, lane verdicts, provider events,
provider-callback markers, logcat, crash/ANR scan, screenshots, APK and APK
SHA, DB write counters, outbox evidence, callback evidence, a resilience
verdict, and a secret scan.
The runner and aggregate attest:

* Flutter source SHA, backend Git SHA, backend source digest, Android host
  source digest, and the built APK SHA-256;
* `M5_PROVIDER_CALLS::<tencentIm>::<alipay>` counting only observed SDK
  callbacks (not client intents), with positive Tencent callbacks required for
  every provider-live verdict and a positive Alipay order/native callback
  required for the cancel-only opt-in lane;
* `M5_ROUTE_STATUS` and `M5_LANE` markers with no legacy provider namespace;
* the exact DB evidence object below, bound to run, AVD, fixture, and nonce.

APK inspection allows the base Agora SDK strings but rejects the optional
`libagora_face_capture_extension.so` and
`libagora_lip_sync_extension.so` JNI entries, plus all private-key PEM
markers. Those libraries are excluded by the Android host overlay for the
audio-only M5 build.

```json
{
  "status": "OK",
  "evidenceBinding": {
    "runId": "m5-run",
    "avd": "AVD-A",
    "fixtureId": "m5-fresh-fixture",
    "startNonce": "operator-issued-nonce",
    "backendSha": "<40 lowercase hex characters>",
    "flutterSha": "<40 lowercase hex characters>",
    "apkSha": "<64 lowercase hex characters>",
    "backendSourceDigest": "<64 lowercase hex characters>"
  },
  "writeCounters": {
    "auth_sessions": 1,
    "im_credentials": 1,
    "c2c_messages": 1,
    "avchatroom_sessions": 1,
    "alipay_orders": 1,
    "payment_provider_events": 1,
    "wallet_transactions": 1,
    "ledger_journals": 1,
    "ledger_entries": 2
  },
  "vendorOutbox": {
    "tencentIm": {"state": "SENT", "attempts": 1},
    "alipay": {"state": "SENT", "attempts": 1}
  },
  "callbackEvents": {
    "tencentIm": {"verified": true, "eventCount": 1},
    "alipay": {"verified": true, "eventCount": 1}
  },
  "paymentSettlement": {
    "providerEventVerified": true,
    "providerEventProcessedCount": 1,
    "succeededOrderCount": 1,
    "walletTransactionCount": 1,
    "walletCreditCount": 1,
    "ledgerJournalCount": 1,
    "ledgerEntryCount": 2,
    "balancedJournalCount": 1,
    "ledgerImbalanceCount": 0
  },
  "outboxAttempts": {"tencentIm": 1, "alipay": 1},
  "secrets": false,
  "backendSourceDigest": "<64 lowercase hex characters>"
}
```

The four payment safety counters are baseline deltas: provider-event rows,
wallet transactions, ledger journals, and ledger entries. A cancel-only run
must report all four as zero. A success run must report exactly one verified
provider event, one succeeded order, one wallet credit transaction, one
balanced journal, and exactly two balanced ledger postings. The
`paymentSettlement` object carries those row-count-only assertions and never
contains amounts, order identifiers, provider payloads, or user identifiers.

The database endpoint must return this fixed schema for the
`X-M5-Evidence-Phase: start` and `collect` protocol. `start` snapshots the
baseline and returns a one-shot nonce, the exact `paymentScenario`, and
`paymentSettlementPoll=internal-bounded-90s`; `collect` reports only the delta for
that exact `(runId, fixtureId, avd, startNonce, backendSha, flutterSha,
apkSha, backendSourceDigest)` binding. A historical full-table provider row
cannot satisfy this contract. The aggregate rejects stale binding, unknown
keys, negative counters, missing outbox/callback evidence, a digest mismatch,
secret material, or zero Tencent callbacks. For the cancel-only opt-in, it
instead requires a positive Alipay order/native SDK callback, `alipay_orders >=
1`, and zero asynchronous Alipay callback events; a successful-order or
wallet/ledger mutation is not accepted as cancel-only evidence. Incomplete
AVD evidence remains fail-closed.

The Tencent `callbackEvents.tencentIm` count is accepted only when the
database callback ingest links each counted `Group.CallbackAfterSendMsg` row
to this fixture's `tencent_im_room_group_outbox.public_id`; the helper then
joins that outbox row to its matching `room_public_message` and fixture-owned
room. A `received_at` window alone is not ownership evidence. Backend migration
V32 adds this link, and callback ingest writes it only after validating the
group/message hint. Older schemas remain fail-closed as `SCHEMA_MISSING`.

## Commands

```bash
bash tool/qa/run_m5_vendor_live_avd.sh
bash tool/qa/aggregate_m5_vendor_live_avd.sh
```

Before a full run, verify the dedicated fixture, backend SHA/digest, real
Tencent credentials issued by the backend, and the operator database evidence
endpoint. The current backend may report `VENDOR_BLOCKED` for Alipay until its
real sandbox order/callback integration is enabled; that is an expected
fail-closed outcome, not a successful provider lane.
