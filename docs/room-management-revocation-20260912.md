# 房管撤权 UI 定向修复

基线：`950d08f89ad932a2ff2ce1e64aa968ec12dac98c`

分支：`codex/room-management-revocation-20260912`

## 验证记录

- RED：基线运行 `test/room_management_revocation_test.dart`，撤权后锁定按钮仍返回可执行闭包，测试期望 `onPressed == null` 失败。
- 边界 RED：基线真实打开 `安排 阿岚 上麦` 选麦 overlay 后等待 3 秒，撤权 authority read 已返回但 overlay 仍在（tool chunk `6fbe82`）；延期 authority future 在身份变化后会重新发起第 2 次读取（tool chunk `9c8773`）。
- GREEN：Flutter `3.44.7`、`--no-pub` 运行撤权定向用例，7 个用例通过（tool chunk `112f81`）。选麦 overlay 在 authority 降级后关闭，`assignWrites == 0`；延期 future 不再重启旧 identity 请求。
- 兼容回归：撤权用例及此前受影响的 `room_management_review_fixes_test.dart` 共 14 个用例通过。
- 指定回归集：`room_management_automatic_sync_test.dart`、`room_management_join_queue_sync_test.dart`、`room_management_audio_policy_test.dart`、`room_management_seat_layout_test.dart`、`room_management_review_fixes_test.dart`、`room_mic_queue_ui_test.dart`、`room_management_revocation_test.dart` 共 59 个用例通过（tool chunk `53f306`；日志 `/tmp/voice-social-room-management-20260912-green-final.log`）。
- 定向检查：受影响页面与撤权测试 `flutter analyze --no-pub` 通过（tool chunk `978d37`；日志 `/tmp/voice-social-room-management-20260912-analyze-final.log`）；`dart format --set-exit-if-changed` 与 `git diff --check` 通过（tool chunk `6dc0ce`）。

本次只修改房管页面、撤权回归测试和本记录；未改 Backend、厂商、支付、RoomController 或数据层。未执行移动端构建、设备、Chrome、HTTP、DB、provider 验证。
