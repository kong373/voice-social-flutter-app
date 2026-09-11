# Flutter IM session recovery — F-IM01 / F-IM02

日期：2026-09-11

## 范围

本次变更只覆盖两个 coordinator：

- `lib/features/im/application/im_session_coordinator.dart`
- `lib/features/im/application/tencent_im_avchat_room_coordinator.dart`

测试只扩展既有的 `test/tencent_im_session_test.dart` 和
`test/tencent_im_avchat_room_test.dart`。未修改 adapter 生产文件、message center、IAP、设备配置、SDK 版本、数据库或网络厂商实现。

## 根因与修复

F-IM01：`logout()` 递增 coordinator generation，但遗留了
`_ensureFlight/_ensureFlightUserId`。挂起 credential fetch 在 logout 后完成时，新的同 user ensure 会复用旧 future，导致新 generation 没有建立 IM。修复是在 native teardown 前清空这两个 flight 字段；旧 future 的 completion 继续通过既有 `identical` fence，不能清除新 flight。

F-IM02：`TencentImSessionAdapter.renew()` 的真实路径会先 quit active group，再 logout、login。AVChat coordinator 原先保留旧 `_joinedGroupId`，所以新 READY 会被认为已经入群。修复是在会替换 native session 的非 READY 状态清除本地 group claim；READY 只对当前 room binding 且 `sessionId` 仍有效的 room 串行 rejoin。本批不补证底层 `RoomLeaseBinding`/HTTP 租约截止，也不宣称能识别所有同群原始旧 SDK 事件。room generation、session identity 和 disposed fence 继续阻止旧 room、late join、leave/close 后的恢复。

没有增加 adapter session generation：现有 adapter state stream 已在 renew/logout/login 边界发出 renewing、loggingIn、loggingOut、error/ready 等状态；回归测试通过真实 `TencentImSessionAdapter` 加 fake SDK 观察 quit/logout/login/rejoin 序列，足以区分 native session replacement 与 room 本地状态。

## 验证

专用 RED 日志：

- `/Users/kongzheng/Documents/ny/artifacts/release/flutter-im-session-recovery-20260911/red-fim01.txt`
- `/Users/kongzheng/Documents/ny/artifacts/release/flutter-im-session-recovery-20260911/red-fim02.txt`

GREEN 相关测试日志：

- `/Users/kongzheng/Documents/ny/artifacts/release/flutter-im-session-recovery-20260911/related-tests-green.txt`

两文件全测结果记录在 `related-tests-green.txt`，最终 analyze 结果记录在
`final-analyze.txt`。覆盖 44 项测试，包括：

- logout 后同 user 新 flight、旧 completion 隔离；
- renew 的 quit/logout/login/rejoin 恰一次；
- renew 失败后的恢复登录；
- room switch 只恢复当前 room；
- leave/close 后晚到 READY 不复活旧 room。

验证限定在本地 Flutter 3.44.7 / Dart 3.12.2，依赖使用 `--offline`/既有 pub cache；未构建 APK。
