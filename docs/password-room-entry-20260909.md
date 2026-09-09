# Q05 密码房入房补丁

Base: `c7814475d7ffe7d662462df94e3eea5a0dd8f13c`
Branch: `codex/password-room-entry-20260909`

## 行为和范围

- 初始入房先不带密码请求后端，只有入房阶段的 `ApiException.code == 40332` 才打开一次密码输入框。房主、独立 staff、已有有效 lease 的免密资格完全由后端决定，不从房间名或 moderator 角色推断。
- 房管和普通用户遇到密码拒绝后填写密码；仅沿既有 `RoomController.join(password:)` → `BackendRoomRepository.enterRoom` POST body 发送。repository 已具备参数，无需修改。没有新增 URL 参数、日志、持久化、自动填充或输入法学习。
- 输入为空或超过后端 32 字符上限不能提交。输入框提交、取消、销毁时清理；不保存上次密码。Dart 字符串不可原地擦除，清理含义是解除 UI 引用，不声称内存零化。
- 取消或错误密码不会循环弹窗；错误仍保留失败页和显式“重新进入”。`40431` closed、`40331` ban、`40939` retired approval 不转密码弹窗，不恢复旧审批流程。
- page entry epoch、controller 身份 generation 和路由有效性共同隔离晚响应。离页或身份失效移除该页的密码 dialog；JOIN transport cleanup 后再次校验 epoch，防止 cleanup 等待期间换号或离房又写回失败状态。
- 有效 joined 会话不重新 join；没有修改密码配置、lease 更新或 reconnect 行为。更改密码不踢有效 lease 的规则仍由后端执行。

生产仅三个文件：`room_password_dialog.dart`、`video_runtime_room_page.dart` 的入房交互及生命周期隔离、`room_controller.dart` 的 JOIN 错误分类和 cleanup 后校验。未改 `_openGift`、`sendGift`、礼物/余额显示、RoomPage、repository、导航或依赖配置。

## 本机证据

SDK: `/Users/kongzheng/fvm/versions/3.44.7/bin/flutter`，实测 Flutter 3.44.7 / Dart 3.12.2。

- 实现前：新增 8 项 widget 测试，5 PASS / 3 FAIL，失败为找不到密码输入交互，非编译失败。
- 最终：以下 5 文件共 120 PASS（其中密码 widget 14 项，repository 新增 POST body/40332 契约 1 项）。

```sh
flutter test --no-pub test/room_password_entry_test.dart test/backend_room_repository_contract_test.dart test/room_controller_race_test.dart test/room_lease_controller_test.dart test/room_controller_test.dart
flutter analyze --no-pub
```

- 全量 analyze 0；初次 4 个 async context lint 已通过显式 mounted guard 修复，不关闭检查。
- 另跑 `video_runtime_ui_test.dart` 与 controller：22 PASS / 2 FAIL。两项失败在临时、未修改的同 base checkout 定点复跑原样复现：
  - `home enters room, opens gift sheet and minimizes the session`：line 166，缺少 `video-room-mood-stage-standard`。
  - `room gift to tools remains stable at cloud-constrained 360 width and 1.3x text`：line 386，面板期望 `340x395`，实际 `340x283`。
- 保留这两个基线断言，不扩改送礼；临时 baseline worktree 验证后移除。
- 未运行设备、DB、vendor，不 push。测试中的 repository admission stub 不是后端角色鉴权证据；角色豁免规则核对了后端 `FirstPartyRoomLifecycleService.joinRoomOnce/requireAdmissionPolicy`，客户端不自行放行。

## 合并提示

主线对 `video_runtime_room_page.dart` 做逐 hunk 合并：本补丁仅新增入房包装函数、密码 dialog 清理、替换三个 join 调用及失败页密码提示；Ampere 的 gift 函数改动不应被覆盖。
