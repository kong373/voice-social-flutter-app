# M5 vendor database evidence

`tool/qa/m5_vendor_db_evidence.py` is a read-only evidence helper for the
vendor-bound database contract. Its live interface is a protected HTTP
`start` -> `collect` session: `start` stores a fixture-scoped aggregate
baseline and returns a signed one-shot nonce; `collect` computes only the
baseline delta and returns a fixed redacted JSON schema. The SQL contains no
data-mutating statement and the output never contains a database diagnostic.

The module also retains `build_payload`/`payload_to_csv` for offline marker
contract tests and controlled CSV projections. They must not be used as a
replacement for the protected live session, because a standalone full-table
snapshot cannot establish current-run ownership.

## Evidence binding

Every successful report carries all four values below. They are mandatory even
when a report is `FAIL` because the schema or an invariant is not satisfied.

| Environment | Meaning | Validation |
| --- | --- | --- |
| `M5_RUN_ID` | protected run identifier | ASCII `[A-Za-z0-9_.:-]`, max 96 characters |
| `M5_BACKEND_SHA` | backend commit under test | exact 40-hex `HEAD` of `M5_BACKEND_REPO` |
| `M5_FLUTTER_SHA` | Flutter commit under test | exact 40-hex `HEAD` of `M5_FLUTTER_REPO`, or this checkout when omitted |
| `M5_APK_SHA` | APK artifact digest | exact 64-hex SHA-256; must match `M5_APK_PATH` when supplied |

The `QA_*` aliases are accepted for the same values. Conflicting aliases are
rejected. `M5_BACKEND_REPO` is required and must be clean, at the requested
commit, and contain the tracked V29/V30/V31 migration files. If
`M5_FLUTTER_REPO` is not set, the helper uses the Flutter checkout containing
the helper; a dirty or mismatched checkout is rejected. This prevents an
operator from attaching a database snapshot to a different source or APK.

The protected live response extends this binding with `fixtureId`, `avd`,
`startNonce`, and `backendSourceDigest`. The backend source digest must match
the output of the attested checkout's
`scripts/compute-backend-source-digest.sh`. The runner sends and validates
these values on both phases using `X-M5-Backend-SHA`, `X-M5-Flutter-SHA`,
`X-M5-APK-SHA`, and `X-M5-Backend-Digest` headers.

## Database configuration

`M5_MYSQL_CONTAINER` is a Docker container name, and `M5_DOCKER_SOCKET` may
only be a local Unix socket (`unix://...` or `/...`). The helper passes only a
minimal `PATH`/Docker socket environment to Docker. MySQL credentials are read
from the container environment (`MYSQL_DATABASE` and one of
`MYSQL_PASSWORD`, `MYSQL_APP_PASSWORD`, or `MYSQL_ROOT_PASSWORD`) and are
expanded only inside the container shell. Do not put credentials in command
arguments, output paths, logs, or this document.

The SQL reads only table existence, column existence, counts, controlled
status counts, valid UUID public IDs, and SHA-256 fields. It deliberately does
not select provider credentials, signed requests, provider order/refund
identifiers, message/body content, user/room numeric identifiers, phone
values, or JSON payload columns. Public IDs and hashes are bounded to 32 rows
per field in the offline projection. The live session sets
`M5_INCLUDE_PUBLIC_IDS=0`, strips IDs/hashes from its persisted baseline, and
never returns those row lists. Any malformed marker or unexpected output is
rejected rather than echoed.

The live endpoint additionally requires:

| Environment | Meaning |
| --- | --- |
| `M5_DB_EVIDENCE_TOKEN` | operator-provided bearer secret, at least 32 ASCII characters |
| `M5_DB_EVIDENCE_STATE_DIR` | pre-created private directory (mode `0700` or narrower) for nonce state |
| `M5_BACKEND_DIGEST` | expected 64-hex backend source digest |
| `M5_DB_EVIDENCE_HOST` / `M5_DB_EVIDENCE_PORT` | loopback bind address and port (`127.0.0.1` is the default host) |

The state file is mode `0600`, contains only the SHA-256 of the signed nonce,
and is atomically marked consumed after a successful collect. Raw nonce,
provider fields, IDs, hashes, and MySQL/Docker diagnostics are never written
to state or error responses.

## V29–V31 coverage

The report requires and projects the following tables:

- Auth attribution: `app_user` and `refresh_session` (used only for the
  fixture-scoped `auth_sessions` delta).
- Tencent delivery: `provider_delivery_outbox`, `private_message`,
  `tencent_im_account`, `tencent_im_callback_event`,
  `tencent_im_room_group`, `tencent_im_room_group_outbox`, and
  `room_public_message`.
- Alipay/payment: `payment_provider_event` and `recharge_order`.
- First-party authority/ledger: `wallet`, `wallet_transaction`,
  `ledger_account`, `ledger_journal`, `ledger_posting`, and
  `wallet_reconciliation`.
- Refund/ops: `refund_application`, `wallet_adjustment_request`,
  `operations_moderation_case`, `operations_export_job`,
  `operation_idempotency`, and `operations_audit_log`.

The checks are aggregate-only:

- private-message and Tencent outbox status pairing, missing pair, and the
  eight-attempt ceiling;
- callback event/body hash shape, room-group/outbox generation mapping, and
  positive public-message event versions;
- payment event order linkage/fingerprint, and Alipay succeeded-order
  provider status;
- non-negative wallet amounts, positive transaction amounts, balanced ledger
  journals, and reconciliation status;
- refund four-eyes and provider outcome consistency, operations four-eyes,
  audit row count, and idempotency fingerprint shape.

`auth_sessions` in the live `writeCounters` is the observed delta of
fixture-attributed `app_user` and `refresh_session` rows. It is never a
synthetic success bit; SMS challenge rows are not counted because their
phone-hash-only schema cannot be fixture-attributed without exposing or
recomputing private input.

The live `writeCounters` contract also contains the payment/accounting deltas:

- `payment_provider_events`: fixture-owned `payment_provider_event` rows whose
  `received_at` is after `start` (provider event fields remain redacted).
- `wallet_transactions`: fixture wallet `wallet_transaction` rows whose
  `created_at` is after `start`.
- `ledger_journals`: fixture-actor `ledger_journal` rows whose `created_at` is
  after `start`.
- `ledger_entries`: `ledger_posting` rows joined to those fixture journals and
  created after `start`. The public counter uses “entries” while the V4/V11
  storage table is named `ledger_posting`.

These are non-negative, current-session deltas, not all-time totals. The
cancel-only acceptance gate can therefore require `alipay_orders >= 1` while
requiring `payment_provider_events == 0`, `wallet_transactions == 0`,
`ledger_journals == 0`, and `ledger_entries == 0`. A future sandbox-success
scenario can require positive payment/accounting counters and reconcile them
without exposing amount, provider, or ledger values.

`VENDOR_BLOCKED`, `PENDING`, `PROCESSING`, `RETRY`, `UNKNOWN`, `DELIVERED`,
and `FAILED` remain visible as controlled status counts. A non-zero invariant
check produces `status: "FAIL"` and `INVARIANT_VIOLATION`; missing V29–V31
tables/columns produces `SCHEMA_MISSING`. No uncontrolled error text is
returned.

## Invocation

Run from the attested Flutter checkout with protected environment values. The
example intentionally uses placeholders and does not show a password or a
provider value:

```bash
export M5_RUN_ID="m5-YYYYMMDDHHMMSS"
export M5_BACKEND_REPO="/secure/path/to/authoritative-backend"
export M5_BACKEND_SHA="$(git -C "$M5_BACKEND_REPO" rev-parse HEAD)"
export M5_FLUTTER_REPO="$PWD"
export M5_FLUTTER_SHA="$(git rev-parse HEAD)"
export M5_APK_PATH="/secure/path/to/app-release.apk"
export M5_APK_SHA="$(shasum -a 256 "$M5_APK_PATH" | awk '{print $1}')"
export M5_MYSQL_CONTAINER="authoritative-mysql"
export M5_DOCKER_SOCKET="unix:///secure/path/to/docker.sock"
export M5_DB_EVIDENCE_TOKEN="provided-by-the-protected-runner"
export M5_DB_EVIDENCE_STATE_DIR="/secure/private/m5-evidence-state"
mkdir -m 700 -p "$M5_DB_EVIDENCE_STATE_DIR"
export M5_BACKEND_DIGEST="$(bash "$M5_BACKEND_REPO/scripts/compute-backend-source-digest.sh")"

python3 tool/qa/m5_vendor_db_evidence.py --self-test
python3 tool/qa/m5_vendor_db_evidence.py --serve
```

The process prints `M5_DB_EVIDENCE_LISTENING=host:port/m5/db-evidence`. The
runner must call `GET /m5/db-evidence` with `Authorization: Bearer ...` and
these headers:

| Phase | Required headers |
| --- | --- |
| `start` | `X-M5-Evidence-Phase`, `X-M5-Run-ID`, `X-M5-AVD`, `X-M5-Fixture-ID`, source/APK digest headers |
| `collect` | all `start` headers plus `X-M5-Start-Nonce` |

`start` returns `201` and a nonce. `collect` returns `200` with exactly these
top-level keys: `status`, `evidenceBinding`, `writeCounters`, `vendorOutbox`,
`callbackEvents`, `providerCalls`, `secrets`, and `backendSourceDigest`.
`evidenceBinding` contains the run/AVD/fixture/nonce and all source digests.
Wrong bearer, wrong AVD/fixture/run, stale state, replayed nonce, and any
baseline counter rollback fail closed with a controlled `UNAVAILABLE` category.
The same nonce cannot be collected twice.

The session's SQL predicates bind rows through the fixture nickname derived
from `fixtureId` and a `created_at`/`received_at` boundary captured at
`start`. Payment events are joined through the fixture's `recharge_order`;
Tencent room rows are joined through fixture-owned/member rooms; callback
events use the explicit received-time boundary because V30 has no
first-party-user foreign key. Consequently, pre-existing rows and unrelated
global public IDs cannot satisfy the live current-run delta.

`--json`/`--csv` are intentionally not accepted in `--serve` mode; callers
must persist the validated JSON response themselves. `payload_to_csv` remains
available for the offline, fixed-shape marker contract.

The offline contract suite is:

```bash
python3 tool/qa/m5_vendor_db_evidence_test.py
python3 -m py_compile tool/qa/m5_vendor_db_evidence.py \
  tool/qa/m5_vendor_db_evidence_test.py
```
