# Social pagination JSON alias regression

Base Flutter: `0fd9ad63801d050361dedaa34c78168074fc480b`.
Observed Backend: `82cd83ab283b6e7cdd90ab07d65bedea92a57709`.

## Reproduction and cause

On the ordinary Android B app, the test user followed the existing QA A user,
then opened My > Following and followers > Following. At 2026-09-12 03:58:27
Asia/Shanghai the page displayed `社交分页 list 与 records 内容不一致`.
The owner subsequently unfollowed through the peer profile and restored the
relationship. The screenshot is retained outside Git at
`artifacts/release/vendor-android-0fd9-20260912/B/native-relations-follow-list.png`.

The backend attaches an `avatar` object before putting the same item list into
the `list` and `records` response aliases. HTTP JSON decoding creates separate
nested map instances. The client's shallow map comparison incorrectly rejected
these equivalent values. This is a client parser defect, not evidence that the
backend sent different relationships.

The fix recursively compares JSON map values and ordered arrays. Map key order
does not matter; exact key sets, missing versus null, scalar values and array
order still matter. Pagination, authentication, routes and write behavior are
unchanged. The common social page parser also serves other social lists.

## Actual local verification

- Tests first, original production code: seven new cases executed, three
  equivalent-object cases failed and four genuine-drift cases passed.
- Production fix: the full `backend_social_repository_contract_test.dart`
  suite passed **54/54**. Tests use a real local HTTP server and JSON decoding,
  not the same in-memory map instance on both sides.
- `flutter analyze --no-pub` on the two changed Dart files: no issues.
- Existing assertions were retained. New negative cases cover reference,
  version, missing-key/null and ordered-array drift.

Commands used Flutter 3.44.7. Red/green logs are retained outside Git under
`artifacts/release/task15-unified-20260911/social-page-alias-{red,green}.log`.

## Remaining acceptance

This local change does not establish a new installed-device PASS. After the
candidate is integrated and a single replacement APK is built, repeat ordinary
follow > following list > peer profile > unfollow, verify backend persistence,
and check the shared list entry points. Keep the original failed screenshot.
No device, provider, payment or shared database operation was performed by these
unit tests.
