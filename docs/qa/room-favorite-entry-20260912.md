# DS-008 ordinary room favorite entry

Base Flutter `0fd9ad63801d050361dedaa34c78168074fc480b`; observed Backend
`82cd83ab283b6e7cdd90ab07d65bedea92a57709`.

## Confirmed product gap

DS-008 remains active in `docs/qa/m2.4-page-coverage.md`. The frozen business
contract `docs/m2-no-vendor-business.md` requires adding/removing favorites,
collections and room entry. The existing normal room page had no UI caller for
`setFavorite(favorite: true)`; SavedRoomsPage only removed existing favorites.
Android B observed this in the ordinary installed app, not a QA-console route.
The original screenshots remain outside Git under
`artifacts/release/vendor-android-0fd9-20260912/B/`.

## Implementation

- Room > More > 收藏房间 opens an authoritative collection-backed sheet.
- Loading/read errors cannot assume an unfavorited state. An explicit add or
  remove awaits the existing strict repository response; repeated pending taps
  do not submit another write, and failures retain the last confirmed state.
- Closing/removing the sheet or ending the room invalidates late UI results.
  The action captures the originating controller/repository before navigation.
- Returning from a room reloads SavedRoomsPage, including when no route result
  is provided.
- Existing favorite writes now capture current user and identity generation.
  The same-account refresh can retry, but queued work, 401 recovery and late
  responses from a changed account/ABA are rejected. Intent/idempotency queues
  are partitioned by that identity; already submitted server work is not
  misrepresented as cancelled. No backend route, DTO or idempotency rule changes.

## Verification actually performed

Flutter 3.44.7:

- Original UI: six new widget cases failed at the absent ordinary favorite
  entry. `room-favorite-entry-red.log` is retained outside Git.
- Identity tests before fencing: two new negative cases failed; twelve other
  favorite cases passed, including same-identity refresh. Log:
  `room-favorite-identity-red.log`.
- Final six-file combination: **54 passed**, no skipped assertions. Files:
  `room_favorite_entry_test`, `backend_discovery_repository_contract_test`,
  `saved_rooms_create_entry_test`, `manager_room_profile_entry_test`,
  `room_manager_pk_entry_test`, `video_room_session_end_test`.
- Changed Dart files passed analyze and formatting; `git diff --check` clean.

All logs above are in `artifacts/release/task15-unified-20260911/` outside Git.
The final log is `room-favorite-combined-final.log`.

## Explicit diagnostic boundary and device follow-up

A hand-assembled widget harness calling `RoomController.leaveRoom()` remained
in `leaving`, including a control run with no favorite sheet at all. Fake-clock
pumping and a real-async three-second control did not complete that call. The
original diagnostic source is retained as
`room-favorite-leave-diagnostic-source.patch`, with its trace/control logs. This
does **not** establish the cause or prove that transport teardown was fixed.
Production RoomController was not changed. The final favorite test explicitly
uses the existing room-closed event and only proves late favorite-read rejection
and no new write after session invalidation; it is not a leave-transport PASS.

After one combined APK build/install, verify normal room entry > add favorite >
explicitly leave > collection list > enter > remove > leave > refreshed empty
list. Verify actual server favorite rows, account isolation and no new Flutter
exception. Preserve the old failed evidence; current installed-device acceptance
is still pending at this commit.
