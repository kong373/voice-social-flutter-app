# Full CI recovery after core-eight UI refinement

Baseline: `40fc5716c29378eb45d7f0fd7c3c70894b7ccc7e`, PR #27. This change preserves business rules, APIs, money handling, permissions, dependencies, signing and existing visual baselines.

## Reproduced failures and changes

- The previous iOS quality run (`35769807788`) finished with 3895 passing and three failing tests. The general Flutter quality run (`35769807728`) exceeded its 30-minute job limit; neither native build was reached.
- Running the three affected files locally reproduced 41 passing / 3 failing tests. Two withdrawal recovery cases still searched for the new-application button even though the pending-intent action was already named `恢复原提现申请` in the parent UI branch. Only the test locators changed; their account, amount, quote and original-request assertions remain intact, with an additional assertion that no new-application action is offered.
- In a keyboard-reduced chat viewport, the list reached its tail but the media tools consumed enough height to obscure most of the newest message. While the keyboard is open, the tools now retain one complete action row and their existing independent scroll; the list's bottom spacing is smaller. No message, request, receipt or follow/drag state logic changed. Expanded Android/iOS tests verify the full newest text, three media controls with at least 44-pixel hit regions, and preservation of a user's manual history scroll.
- Related regression testing exposed a 111-pixel overflow in the chat error state at 390x568 with a 240-pixel keyboard. Two explicit platform cases reproduced it. The existing error content is now scrollable, preserving its message and retry button. Tests verify a reachable explicit retry and exactly one new history request, rather than hiding the error or suppressing exceptions.

## Complete test execution without the serial timeout

Both full quality workflows use Flutter's native `--total-shards=4` / `--shard-index` support. The full test discovery, coverage, per-shard concurrency of one, per-test timeout, formatting, analysis, source checks and platform preparation remain in place. Matrix fail-fast is disabled so all shards provide evidence.

The original quality check names remain as aggregate jobs. Each requires exactly one non-empty LCOV report from each of four named shard artifacts, merges all four reports, and requires the matrix result to be `success`. A missing report, failed merge or failed shard fails quality. Android and iOS native builds still depend on the respective aggregate quality job. No skip, continue-on-error, relaxed assertion, golden regeneration or blanket timeout increase is introduced.

## Local verification of this change

Flutter 3.44.7 / Dart 3.12.2, the independent refinement checkout and its own package configuration, serial command execution:

| Check | Result |
| --- | --- |
| Original three-file reproduction | 41 PASS / 3 FAIL, exit 1 |
| Stronger keyboard text visibility before layout fix | 43 PASS / 4 FAIL, exit 1 |
| First layout fix and withdrawal locators | 47 PASS, exit 0 |
| Related tests before error-state fix | 160 PASS / 1 FAIL, exit 1 |
| Explicit Android/iOS error-state regression before fix | 2 FAIL, exit 1 |
| Final affected business, message, finance and ordinary golden comparisons | 210 PASS, exit 0 |
| Existing workflow, iOS source/host and release-validator contracts | 34 PASS, exit 0 |
| `flutter analyze --no-pub` | No issues, exit 0 |
| Five changed Dart files' formatting | 0 changed, exit 0 |

Groups overlap; the table is not a sum of distinct business scenarios. Logs are preserved outside the source checkout under `artifacts/ui-audit-20260921/core8-refinement-20260923/`, with `ci-` prefixes, commands, exit codes and timestamps.

At this commit, remote full-suite shards and native build outcomes are still pending. Final results belong in the PR receipt; local targeted success must not be relabeled as full CI, device acceptance or release readiness. The previously built local debug APK predates this source change and is not a package for this new candidate. PR #27 remains a draft; no deployment or merge is performed.
