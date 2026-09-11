# Relation list refresh on profile return

Base57bbfe3f9a4cdca5afb86389e6b14948ef7f2f02. Native B reproduced a distinct
problem after the nested-JSON alias fix: unfollow succeeds in the public profile,
but returning to RelationsPage retains the old row until leaving/reopening the
whole page. This is not the prior parsing bug.

Cause: the relation row pushed PublicProfilePage without awaiting navigation or
refreshing on return. Minimal fix captures the selected user ID, awaits normal
navigation completion and reloads the current relation type if still mounted.
No service, repository, role, relation rule, VisitorRecordsPage or native change.

Regression uses real RelationsPage→PublicProfilePage→unfollow→ordinary back:
both following and mutual-friend cases verify the repository has changed and
the obsolete row disappears without a manual reload. Before the fix both fail
at the stale-row assertion; after the fix both pass. Unrelated following rows
remain and the empty mutual-friend list renders its legitimate empty state.

- RED: social-return-red.log,2 failed stale-row assertions.
- GREEN: social-return-green.log,61 related tests pass (new2, public-profile,
  social repository and existing Backend social contracts).
- Analyze2 files: no issues; formatting and diff-check pass.
- Logs under root artifacts/release/task15-unified-20260911/.

These are local Widget/repository checks, not a new installed-native pass.
The current B57bbfe3 still has the return-refresh defect until a reviewed,
combined candidate is built and installed. Preserve its native evidence.
