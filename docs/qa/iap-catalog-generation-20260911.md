# IAP catalog request generation

Base: `d47dd868d9b41c32fe3113a2ff03fc31667ff30f`; commerce production code
is unchanged from its parent `ff06e9a7b8bef7e3788ebf15de22683879cfcf0c`.

## Confirmed defect and fix

An old READY catalog could wait for StoreKit while a newer request completed
with VENDOR_BLOCKED. The old completion then restored shared iOS readiness.
Each catalog fetch now owns a monotonically increasing local request generation.
HTTP, unfinished recovery and product validation completions are checked before
continuing or changing readiness. Superseded completions throw the existing
`ApiFailureKind.conflict`; they do not clear a newer successful result.
No endpoint, price, product ID, payment authority, SDK or StoreKit configuration
changed. This is not evidence of a real purchase or server financial mutation.

## Actual verification

The diagnostic `IAP-CAT-P2-01 late READY must not overwrite newer blocked catalog`
was run against the baseline before the production edit: exit 1, expected false,
actual true. After the fix the same assertion passed. Two host-added regressions
also cover a late HTTP response (no subsequent StoreKit call) and an older
StoreKit failure after a newer valid catalog (new readiness retained).

Flutter 3.44.7, three actual test files:

```sh
flutter test --no-pub --concurrency=1 test/apple_iap_commerce_repository_test.dart test/apple_iap_purchase_coordinator_test.dart test/apple_iap_purchase_journal_test.dart
```

Result: 53 tests passed, exit 0. The same four changed Dart files passed
`flutter analyze --no-pub`; formatting and `git diff --check` passed.
Logs are in the host `artifacts/release/task15-unified-20260911/` directory:
`iap-catalog-red.log`, `iap-catalog-final-green.log`.

## External delivery disposition

The first GPT IAP delivery's three Flutter test changes were independently read,
applied, formatted and actually executed by the host. Its other supplemental
assertions cover mapping/price rejection and saved purchase recovery. The host
retains these verified tests together with the diagnostic rather than treating
the later GPT index as an instruction to discard useful verified coverage.
The second GPT package is a separate test proposal, not a superset or replacement.
It is not applied here and its proposed counts are not added to the 53 results.
Neither package's Backend tests nor Apple portal/real purchase/recovery are
claimed to have run by this change.
