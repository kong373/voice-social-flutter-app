# Automatic mic cancellation history compatibility

Base: Flutter `42a8a8409256d59b647900c66f194a48593e8fee`; observed Backend `1dbf2bac0a3f2ed0f96e71c83df2991500ae029d`.

The ordinary two-device RTC preparation reached the owner's mic-request page. A historical lifecycle cancellation had `status=CANCELLED`, `version=0`, a non-null `resolved_at`, and SQL NULL `resolved_by_user_id` (serialized as 0). The client rejected the whole list, hiding a newer pending request. No history rows were deleted or rewritten.

## Contract

- `CANCELLED` must retain a valid authoritative resolution time. Legacy automatic cancellation may have no resolver (0 or null), represented as null in the domain model. This does not claim a human actor or authorize approval.
- `APPROVED` and `REJECTED` still require a resolution time and positive resolver. Negative resolvers remain invalid for every status. Existing pending, member identity, assigned-seat, room binding and provider-invocation checks are unchanged.
- Future Backend cancellation metadata is a separate fix. It cannot remove the need to read already persisted history.

## Verification

The same two resolver-0/null mixed-history tests first failed with the exact production parsing exception (exit 1). After the minimal parser fix, the five relevant test files passed **69 tests** (exit 0): `backend_room_operations_repository_contract_test.dart`, `room_mic_queue_controller_test.dart`, `room_mic_queue_ui_test.dart`, `room_mic_approval_auto_sync_regression_test.dart`, `room_operations_pages_test.dart`.

New negative cases retain rejection of approval/rejection without an actor, cancelled records with a negative actor, and cancelled records without a resolution time. Fetching mixed history performs one GET and does not create or resolve an application.

Local evidence: `artifacts/release/task15-unified-20260911/mic-cancel-parser-{red,green,analyze}-20260912.log` under the parent ny workspace. Native approval and RTC bidirectional audio remain pending a new candidate build and normal-device retest; these tests do not prove audio acceptance.
