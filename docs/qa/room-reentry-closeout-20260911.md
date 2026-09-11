# S2 Flutter room re-entry race closeout

日期：2026-09-11

## 范围

本次只验证 room controller 的入房取消、同房重试、session lease 与迟到补偿交互。没有修改支付、IM、IAP、设备、数据库、28080 或 host/build 相关文件。

## 既有覆盖核对

- `test/room_controller_race_test.dart` 原有用例只验证旧 join 补偿不会清理新的 transport。
- `test/room_lease_controller_test.dart` 已覆盖 heartbeat、租约过期和旧 lease response，但没有覆盖取消入房后的同房重试。
- `test/backend_room_lease_repository_contract_test.dart` 已覆盖不同 entry intent 下 late enter/exit 不覆盖 newer same-user binding；本次不重复复制该 HTTP contract。

## 新增覆盖

`test/room_controller_race_test.dart` 新增两条可控异步用例：

1. 取消第一次入房后立即启动同房重试；新 session 先成功，旧 enter 回包随后到达，controller 保持新 session，且不发旧补偿 exit。
2. 取消后旧 enter 回包先触发补偿；补偿 exit 保留旧 session，期间同房新 session 成功；旧 exit 延迟完成后，新 session 和 transport 仍保持。

两条用例均使用有效 `RoomSessionLease`。第一条确认正常 cancel 返回与重试成功，第二条确认取消后的迟到补偿只清理旧 session。

## 结果

基线为 `ff06e9a7b8bef7e3788ebf15de22683879cfcf0c`，工作分支为 `codex/room-reentry-closeout-20260911`。新增用例在未修改生产实现的 base 上通过，没有发现可归因于生产代码的业务 RED，因此没有做生产修复。

最终命令与退出证据在本地交付记录中保留：

```text
Flutter 3.44.7: /Users/kongzheng/fvm/versions/3.44.7/bin/flutter
flutter pub get --enforce-lockfile: exit 0
flutter test --no-pub --concurrency=1 test/room_controller_race_test.dart: 13 passed, exit 0
flutter test --no-pub --concurrency=1 test/room_controller_race_test.dart test/room_lease_controller_test.dart test/backend_room_lease_repository_contract_test.dart: 97 passed, exit 0
flutter analyze --no-pub <7 room/controller/lease/repository files>: exit 0
dart format --output=none --set-exit-if-changed test/room_controller_race_test.dart: exit 0
git diff --check: exit 0
```

## NOT_PROVEN

- 测试替身可控地模拟了 session-bound exit，但没有执行真实 backend HTTP 并发时序；服务端在两个入房请求同时落地时的最终成员状态仍未证明。
- 没有运行 28080、数据库、设备、vendor SDK、Flutter build 或全量测试；本记录只对上述本地 controller/repository contract 范围负责。
