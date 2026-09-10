# Q06/Q07/Q08 Flutter microphone policy

Base: `dd66c076263f10f860225ac4b794dfcd84f559b1`.
Backend contract: `backend-room-mic-policy-20260909/docs/product-room-mic-policy-20260909.md` (`595112a`, reviewed independently by main).

## Batch 1: REQUEST wire protocol and INVITE retirement

- `resolveMicRequest` requires the REQUEST `expectedVersion` and supports optional `targetSeatNumber`. Rejecting with a target fails locally.
- DTOs strictly parse nonnegative integer `version` and nullable `assignedSeatNumber`. Original `seatNumber` is not overwritten by the assigned destination.
- An unknown resolve retains its original key and exact decision/version/destination; switching any of them fails locally. The session generation remains part of the binding.
- INVITE creation and acceptance are retired locally, without HTTP dispatch, RTC reconciliation or compensating rejection. Historical INVITE records remain readable and have no target action. Existing direct `hugUserUpMic` management is preserved.
- RED: existing HTTP contract test failed compilation because `expectedVersion` was absent. Tests now exercise alternate assignment, reject omission, malformed versions, unchanged-key retry and retired invitation behavior.
- Final focused checks: 83 distinct tests across 8 files pass in batches; full `flutter analyze --no-pub` reports no issues. The retired occupied-muted INVITE assertion was migrated to no occupancy/no RTC dispatch, not a successful invitation. SDK remains Flutter 3.44.7.

This batch does not yet complete the alternate-seat UI, independent audio mute causes or fresh-grant RTC publication. No device, vendor, Backend, DB or Android plugin work is performed.

## Batch 2: alternative-seat UI and current-occupancy moves

- Approval re-reads the room authority before choosing. An unavailable requested seat opens an explicit eligible-empty-seat picker; it never selects an alternative automatically. The original request version and destination survive an unknown write result via the `重试原处理` action.
- Live management authority comes from the backend snapshot rather than route role. Account generation and lease generation fence pending reads, dialogs and writes; the existing room/viewer widget key remains in place.
- Already-occupied ordinary members can choose `更换麦位` in room tools. Moving uses the existing self-up route and preserves local publication intent and effective mute. After down-mic, an ordinary user again submits REQUEST rather than directly self-granting.
- RED: occupied-seat approval lacked the picker; ordinary occupied move returned false. GREEN: 53 focused tests across 6 files in batches, including queue races, exact-intent unknown retry, seat layout and leave feedback. Full analyze: no issues. Existing sync-test fixtures now explicitly provide the free target seat; the race and error assertions remain.

Independent audio-reason parsing and Q07-02 publication are still the next batch.

## Batch 3: audio authority wire model

- `b96b05c` confirmed enter snapshots expose three strict Boolean reasons and `joinedAt`, but no seat version. Mutation receipts strictly require a nonnegative seat version. Missing legacy reasons are represented as unknown; partial or contradictory occupied-seat causes fail parsing. Empty-seat stale compatibility mute is not copied to a member.
- Self-mute receipts validate `selfMuted`; management receipts validate `forcedMuted` and explicit legacy-hold release. Effective mute may remain true after removing a forced mute when self mute remains true. Public-text `muted` is untouched.
- Assignment, self-up/move and audio-mute unknown intents bind destination/decision via a stable subject-scoped intent. Mic POSTs additionally check the captured identity/lease before dispatch and same-identity recovery; non-mic writes retain their existing path.
- Focused wire/model/seat-adapter tests: 109 PASS across 4 files. Includes independent cause combinations, malformed authority, real HTTP parser and receipt preservation; old receipt fixtures gained the new explicit fields without changing their expected request bodies or business assertions.

Q07-02 RTC controller and audio-control UI integration remain pending after this wire-model batch.

## Batch 4: Q07-02 publication and personal audio control

- A newly observed off-mic → occupied transition with `joinedAt` gets at most one foreground automatic attempt. The controller fetches fresh publisher credentials, checks the same room/member/lease/grant, and relies on the existing Agora permission adapter and SDK acknowledgement before showing the microphone as enabled. Initial joins, reconnects, token renewal, ordinary authority reads and releasing a management hold do not create an unmute intent.
- Missing audio causes, forced/legacy holds, stale/expired leases, audience or expired credentials, denied permission and failed/unconfirmed SDK enable remain unpublished. Failed publication retains the confirmed first-party seat; it does not invent a compensating down-mic action. The next attempt requires an explicit personal mic action.
- Personal close disables native publication before the server round trip. Unknown personal toggles/placements retain their original boolean/seat; a known placement receipt followed by a failed read is re-read without another placement write. Account ABA, leave, background transition and audio-authority generation changes fence late work. Failed SDK reconciliation explicitly clears publication, with transport ownership checked so an old controller cannot leave a newer controller's channel.
- Public-text mute is independent of audio. The legacy tests that used text-mute events to assert audio shutdown were migrated to `closeMic`/forced audio authority. Existing first-join double toggles became one explicit open because local audio initially remains off. The stale-completion assertion now requires the previous muted snapshot to remain, rather than accepting stale open state.
- Genuine RED: the new reconnect-SDK-failure test observed native audio still enabled after local connection flags had been cleared; cleanup now uses a forced, ownership-bound disable. The first new publication test run had a fixture compilation error (`giftBalance` absent), so that run is not claimed as a behavioral RED.
- Latest focused controller/publication/race/background batch: **55 PASS** across `room_mic_publication_policy_test.dart` (16), `room_controller_race_test.dart`, `room_controller_test.dart`, `room_background_lease_controller_test.dart`. Authority/race/lease/background batch: **78 PASS**. Existing Agora adapter tests also passed, including real adapter code with fake engine/permission ports. Final transition/role/layout batch: **27 PASS**. Batches overlap and are not summed as distinct tests.
- Full `flutter analyze --no-pub`: **0 issues**. Flutter/Dart use `/Users/kongzheng/fvm/versions/3.44.7/bin/`. No device, real permission prompt, vendor call, Backend or database run; these results are not real-device publication evidence.

## Batch 5: reason-specific management controls and original-target retries

- Seat cards show personal, management and historical audio holds separately. `强制静音` / `解除管理静音` change management authority only. Empty seats, missing reason authority and ungovernable targets are disabled. Live cards are updated from a fresh authority read; clearing management mute never claims that the other person's device is now publishing.
- Direct arrangement and management mute retain the original member/seat/decision after unknown results and expose explicit retry buttons. A new optional `targetUserId` on the internal `setSeatMuted` Dart method lets the UI bind its observed occupant; the HTTP body remains the existing `userId`/`seatNumber` contract. A subsequent member-list read cannot retarget the original retry to a replacement occupant. Old callers without the optional target retain the existing loaded-projection lookup.
- Account/lease generation fencing remains on reads, dialogs and all mic POSTs. The submitted REQUEST intent is subject-scoped so changing requested seat while its result is unknown cannot mint an unrelated second operation.
- RED: management audio changed Mock public-text mute; the UI lacked independent reason labels and an explicit original-audio retry. GREEN: **46 PASS** (`room_management_audio_policy_test.dart`: 6, `backend_room_operations_repository_contract_test.dart`: 40), including actual HTTP parser/body/key checks after occupant replacement. An initial arrangement-widget fixture required scrolling to the member; that setup failure is not a business RED.
- Related UI/queue/management regression batch: **30 PASS** across `room_management_review_fixes_test.dart`, `room_operations_pages_test.dart`, `room_mic_queue_ui_test.dart`. Eight small-screen/text-scale seat-layout cases passed in the final 27-test transition/role/layout batch. No skipped or weakened historical authority assertions. Final full analyze: **0 issues**; format and `git diff --check` clean.

## Handoff scope

Implementation worktree: `/Users/kongzheng/Documents/ny/.worktrees/flutter-room-mic-policy-20260909`.
Branch: `codex/room-mic-policy-ui-20260909`, base `dd66c076263f10f860225ac4b794dfcd84f559b1`.

Production changes are restricted to mic DTOs/repositories/seat adapter, room permission/controller mic paths, Dart RTC publication acknowledgement, management mic controls and the room mic picker/tools entry. No gift/entry/manager-profile/media logic, native plugin, Backend or dependency changes. Retained `APPROVAL` compatibility fixtures only test that entry mode does not grant mic authority; no retired entry approval UI is restored.

The five implementation batches complete this local Flutter scope. Main review/cherry-pick and device/vendor acceptance are not claimed complete. No push performed.

## Independent-review follow-up: permission-await P1

Hubble rejected `e1202a1`: controller generation checks after an awaited adapter call were too late. While real `AgoraRtcAdapter` awaited OS permission, controller teardown queued behind its audio mutex. A later permission grant could issue `publishMicrophoneTrack=true` before controller cleanup ran. The previous Mock-adapter tests did not establish this boundary.

Test-first reproduction on unchanged `e1202a1` production: actual `RoomController` + `AgoraRtcAdapter`, injected fake engine, pending permission Completer and an already-fetched publisher token. Account ABA, leave and expired lease all failed with a recorded SDK publish=true; valid authority control passed (**3 RED / 1 PASS**). Raw output: [permission-fence RED](evidence/room-mic-permission-fence-red.txt). Lease expiry advances the monotonic clock without first notifying the controller, so a cancellation flag alone cannot pass it.

Repair is limited to the two production files `room_controller.dart` and `rtc_adapter.dart`:

- The controller passes a live publication predicate binding session/identity generation, lease validity/session, audio-authority generation, RTC transport ownership and eligible snapshot/token. The adapter rechecks it after permission status/request, after background-runtime startup, immediately before SDK publication, and between SDK media-options update and stream unmute.
- Controller revocation/disable/disposal and transport replacement synchronously invalidate an adapter publication generation before waiting for any controller/adapter mutex. This invalidates pending enables without superseding a queued disable. It does not pretend already-active publication was stopped synchronously.
- Native background startup uses the same controller-revocation predicate; a plain adapter disable retains the existing playback downgrade behavior. The old `disable during pending native upgrade wins without SDK publish` assertion remains unchanged. If authority is lost while an already-issued SDK call awaits, the next enable step is suppressed and existing safe rollback is used.

Final focused verification on Flutter 3.44.7: **103 PASS** in two disjoint batches: new `room_mic_permission_fence_test.dart` (16) plus `rtc_background_audio_adapter_test.dart` (20); and `rtc_agora_adapter_test.dart`, `room_controller_rtc_transition_test.dart`, `room_mic_publication_policy_test.dart`, `room_controller_race_test.dart` (67 combined). New coverage includes permission-query/request and native-start waits, ABA/leave/expiry, forced mute, dispose, synchronous adapter cancellation, SDK-options/unmute boundary, transport replacement, and valid controls with/without native background capability. Assertions record every enable call, not merely final local state. Full analyze: **0 issues**; format/diff checks clean.

An additional boundary-test fixture initially included the legitimate initial audience disable in an expected `[true]` list; it now counts all publish=true calls and forbids all unmute=false calls after invalidation. No production behavior or prior assertion was relaxed for this fixture. The old playback-downgrade regression was fixed in production, not by editing its test.

This is an appended repair, with the original five commits preserved. **Awaiting Hubble's independent re-review; not APPROVE and not merged/pushed.** No device, vendor, database, Backend or other Flutter-module changes.
