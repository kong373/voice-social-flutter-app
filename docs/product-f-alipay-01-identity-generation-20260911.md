# F-ALIPAY-01: initiating identity across asynchronous payment work

## Input and scope

- Web review baseline: `150473fd9d2beacf18884d1df3bd7a7cfb3220ad`.
- Local fix base: `12fb52aeb62b425e7aa48523870ceebba0d91131` (earlier IM/IAP fixes retained).
- The three affected production files were unchanged between those baselines.
- Supplement report SHA-256: `e699effc92cada2637a62dda5bdf86f467ae66b06f55484cd1ca441ab82143cf`.
- Supplement archive SHA-256: `aa73b3648164ba74d2804151d3ec6ff590de1558ad60aaede523ee19a9a47282`.
- Host verification: report/archive hashes, 10 exported file hashes, 6 complete Git blobs and 901 original lines across 4 excerpts match the exact review baseline. This is integrity verification, not a claim of runtime vendor acceptance.

## Fix

Alipay create, cancel, reconcile and status operations capture `(userId, identityGeneration)` before their first wait. Existing identity-bound HTTP methods pin authorization before opening the connection and reject identity changes before sending/401 recovery/replay. Bound POST gained only an optional query argument. Repository completion and best-effort recovery paths check the same captured identity, including error paths; they cannot replace a stale operation with a request under the current account.

Create single-flight and idempotency intent keys include both identity components. A normal token refresh with unchanged identity retains the same request ID/body; logout/relogin, even for the same user, starts a distinct intent. Returned signed orders retain local identity provenance; native invocation requires that provenance to match the active login. This does not authorize or settle an order: the backend remains the authority. Existing-order HTTP recovery starts an explicit new identity-bound read/reconcile and still relies on server ownership validation; it does not relaunch a retained signed order after relogin.

The shared MethodChannel adapter accepts a per-invocation identity guard, supplied by the production repository. It checks before starting and after the asynchronous consent check, before invoking native payment. Logout cannot retroactively cancel a payment already handed to the SDK; a late SDK result is rejected before reconciliation or result publication. Direct isolated QA adapter calls without an App session remain separate harnesses, not the production payment entry point.

No SDK, Kotlin bridge, payment amount, ledger, backend route, Apple IAP path, provider flag or running environment changed.

## Actual verification

Only loopback fixture HTTP and a fake MethodChannel were used. No AVD, phone, provider, database, signing key or real payment was accessed.

- Initial test harness attempt: failed because the standard Widget binding intercepts HTTP with 400; not counted as product RED. The test binding now permits loopback HTTP.
- Valid pre-fix RED: 12 failing identity cases, 2 normal positive cases passing; exit 1.
- Post-fix targeted: 14/14 PASS; exit 0.
- Related regression: 113/113 PASS across the new identity suite, adapter, payment flow, production-mode contract, bound HTTP, commerce catalog/decoration and IAP coordinator tests; exit 0.
- Bound-POST override sweep: two additional test doubles gained the optional query parameter and forwarding only. Their private-chat/room projection suites plus the unchanged Q19 clear-history suite passed 130/130. Total distinct tests across both groups: 243, not counting reruns.
- The 14 identity tests were rerun with exact `unauthorized` assertions and passed; arbitrary protocol/configuration exceptions cannot satisfy those negatives.
- Changed Dart files: format unchanged, analyze no issues, diff check clean.

Logs: `artifacts/release/flutter-alipay-identity-20260911/` in the main ny workspace (`red.log` is the harness failure; `red-business.log` is the valid RED; `green.log`, `green-exact-error.log`, `regression.log`, `http-override-regression.log`, `analyze.log`). Follow-up review/test results are recorded alongside these logs, not inferred from this document.

Regression cases cover open wait, 401 before/after refresh, same-identity refresh, stale success response, consent wait with another/same user relogin, old signed order before launch, pending create across relogin, late native 9000, and connection waits in cancel/reconcile/status. Existing native-cancel provenance, provisional native status, duplicate order creation and authoritative status assertions remain intact; existing test fixtures only gained explicit identity providers and the adapter guard parameter.

## Not concluded here

This local candidate is not yet installed on the four acceptance devices or deployed to port 28080. Real Alipay payment, IM latency, RTC audio, SMS and Apple IAP are NOT_RUN in this change. Wallet return refresh and canceled-entry room compensation are separate review items, not silently marked PASS. The user's deferral of SMS receipts and Alipay callback/refund work remains unchanged.
