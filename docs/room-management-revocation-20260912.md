# 房管撤权 UI 定向修复

基线：`950d08f89ad932a2ff2ce1e64aa968ec12dac98c`

分支：`codex/room-management-revocation-20260912`

## 验证记录

- RED：基线运行 `test/room_management_revocation_test.dart`，撤权后锁定按钮仍返回可执行闭包，测试期望 `onPressed == null` 失败。
- GREEN：Flutter `3.44.7`、`--no-pub` 运行撤权定向用例，4 个用例通过。
- 兼容回归：撤权用例及此前受影响的 `room_management_review_fixes_test.dart` 共 14 个用例通过。
- 定向检查：受影响页面、撤权测试和 review-fixes 测试 `dart analyze` 通过；`dart format --set-exit-if-changed` 与 `git diff --check` 通过。

本次只修改房管页面、撤权回归测试和本记录；未改 Backend、厂商、支付、RoomController 或数据层。未执行移动端构建、设备、Chrome、HTTP、DB、provider 验证。
