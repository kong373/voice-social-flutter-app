# 房间审查 P2 修复 checkpoint · 2026-09-09

基线：`08f6f7e3b4f5bff4f5aab76e373887b280cffe1b`。
独立分支：`codex/flutter-room-review-fixes-20260909`。
仅处理主审确认的两项 P2；未修改主 Flutter worktree。

## 改动

- 管理页复用 `RoomAuthorityRepository.fetchRoomAuthority`，生产入口从现有 `AppDependencyScope.roomRepository` 取得依赖，无 Backend 接口及调用方改动。初始加载、手动刷新、治理成功后读取真实麦位；锁定/静音成功后同样刷新。成员分页不再推断占位或空位锁定状态。读取失败沿用错误页，旧响应不能覆盖后发加载。无权威读取能力的离线预览保留传入麦位，不猜测空位。
- 历史房间限制按实际 `expiresAt` 展示本地到期时间，空值展示“无期限”。踢出动作的固定 10 分钟提示及禁止提前解禁保持原状。
- 仅新增可选 `authorityRepositoryOverride` 测试注入参数，复用既有接口。

## 验证

Flutter 3.44.7。先添加测试注入参数及回归测试，未接入读取或修改显示逻辑时，4 项测试均因预期行为缺失而失败（RED）。实现后以下批次 35 项全通过：

```sh
flutter test --no-pub \
  test/room_management_review_fixes_test.dart \
  test/room_management_automatic_sync_test.dart \
  test/room_management_join_queue_sync_test.dart \
  test/room_management_seat_layout_test.dart \
  test/room_operations_pages_test.dart --reporter expanded
```

新增用例覆盖自动锁麦及下次选择器排除、手动刷新及分页外占位、权威读取失败恢复、历史有期/无期限制显示。原有固定 10 分钟踢出及提前解禁拒绝测试通过。

```sh
dart analyze lib/features/room/presentation/room_management_page.dart test/room_management_review_fixes_test.dart
dart format --output=none --set-exit-if-changed lib/features/room/presentation/room_management_page.dart test/room_management_review_fixes_test.dart
git diff --check
```

以上检查通过。未删除或削弱既有测试；未运行全量测试、设备、vendor、数据库、push 或部署。未修改 `first_party_live_mutation_coverage_test.dart`。新增公会、收益提现和平台工作人员资格/权限规则均未纳入。

## 文件

- `lib/features/room/presentation/room_management_page.dart`
- `test/room_management_review_fixes_test.dart`
- `docs/room-review-fixes-checkpoint-20260909.md`
