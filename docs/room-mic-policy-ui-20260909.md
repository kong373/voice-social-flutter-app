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
