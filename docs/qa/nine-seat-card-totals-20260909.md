# S02 remaining room-card totals

Follow-up to7bfc1df. Six production files only: discovery home, saved rooms,
search results, backend discovery count clamp, dynamic Mock live room subtitles,
and shell video home cards. Eight /8 labels now /9; count cap and home indicators
now9. No historical-list records or unrelated numeric8 replacements.

Pinned `/Users/kongzheng/fvm/versions/3.44.7/bin/flutter --version` verified3.44.7
before work. Two regressions genuinely RED: backend occupancy capped8 and shell
refresh rendered old total. After fix **47 PASS**:

```sh
/Users/kongzheng/fvm/versions/3.44.7/bin/flutter test --no-pub test/backend_discovery_repository_contract_test.dart test/video_runtime_home_race_test.dart test/business_pages_test.dart test/saved_rooms_create_entry_test.dart test/ordinary_create_room_entry_test.dart
```

Pinned full analyze: No issues. git diff --check clean. Production lib search has
no remaining /8 or fixed-eight room copy. No golden run/update, device, DB, build.

Golden impact only, not updated: video_runtime_visual_golden_test home and dynamic
room-ranking screenshots; m33_all_pages_visual_golden_test entries that render home,
search, saved-room lists or room-ranking cards. Prior S02 room stage/management
image impact remains in nine-seat-s02-flutter-20260909.md. No image marked PASS.
No page-count change. This supersedes that handoff's pending /8 room-card items.
