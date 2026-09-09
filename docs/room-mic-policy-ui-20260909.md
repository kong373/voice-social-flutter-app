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
