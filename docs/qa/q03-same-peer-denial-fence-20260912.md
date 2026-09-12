# Q03 同 peer 权威拒绝的加载序号隔离

基线：`582bca4d006f7b793aca7a7cb58857c09298d51a`。

分支：`codex/private-chat-q03-20260912`。

## 范围与合同

仅修 `private_chat_page.dart` 的私聊历史读取错误交付。后台切换或发送成功会递增 `_loadRequestId`，但只要账号身份代次、目标 peer 和 `conversationEpoch` 仍一致，已识别的权威读取拒绝仍必须清理当前会话；该规则同时适用于 `BackendMessageRepository` 的 paged 路径，因为其 `_fetchPrivateMessages` 会将 HTTP 拒绝上抛到页面统一 catch。

只对 `!flight.abandoned` 且 identity、peer、`conversationEpoch` 精确一致的 `_MessageReadDenial` 放宽 requestId fence。成功回包仍要求原有 `requestId`、active、账号和 epoch fence；旧成功不能回填。已被实时提示废弃的 periodic head 仍因 `flight.abandoned` 不能走放宽分支，继续经过原 requestId fence，保留 paged priority 的 abandoned head 隔离。explicit recheck、history watermark、peer/identity ABA 语义不变。

## RED / GREEN

- Godel 原始 RED：`/Users/kongzheng/Documents/ny/.worktrees/q19-message-tab-activation-refresh-20260912/artifacts/qa/q03-candidate-two-failures-20260912/same-peer-confirmed-denial.log` 与同目录 `send-receipt-denial.log`，两项均因 `old-body` 残留失败；本树复核合并日志为 `/tmp/voice-social-q03-20260912-two-red.log`，tool chunk `081117`，两项 exit `1`。
- 实际 Paged RED：新增用例 `paged same-peer confirmed denial while backgrounded redacts before returning foreground` 使用真实 `BackendMessageRepository`，同 identity/peer 的未 abandoned 后台拒绝仍留下 `old-body`，exit `1`；日志 `/tmp/voice-social-q03-20260912-paged-scope-red.log`，tool chunk `c7df74`。
- 实际 Paged GREEN：同一用例 `1 PASS`、exit `0`；日志 `/tmp/voice-social-q03-20260912-paged-scope-green.log`，tool chunk `cc54cb`。
- abandoned 边界：既有 `a preempted periodic denial cannot revoke the realtime conversation` 修复后 `1 PASS`、exit `0`；日志 `/tmp/voice-social-q03-20260912-paged-abandoned-after.log`，tool chunk `11f1e6`。

## 定向回归

- 完整 Q03：`test/q03_message_visibility_test.dart`，`24 PASS`，tool chunk `ce713a`，日志 `/tmp/voice-social-q03-20260912-final-q03.log`。
- Paged 自动同步：`test/private_chat_automatic_sync_test.dart`，`28 PASS`，tool chunk `31a8ed`，日志 `/tmp/voice-social-q03-20260912-final-private-chat-automatic.log`。
- Paged priority：`test/im_correlation_trace_test.dart`，`13 PASS`，tool chunk `9582f6`，日志 `/tmp/voice-social-q03-20260912-final-im-correlation.log`。
- clear-history：`test/q19_private_history_contract_test.dart` + `test/q19_private_history_ui_test.dart`，`42 PASS`，tool chunk `edb69c`，日志 `/tmp/voice-social-q03-20260912-final-clear-history.log`。
- Analyze：Flutter `3.44.7` / Dart `3.12.2`，`No issues found!`，tool chunk `9e84ee`，日志 `/tmp/voice-social-q03-20260912-final-analyze.log`；Dart format 0 changed，tool chunk `efe515`，日志 `/tmp/voice-social-q03-20260912-final-format.log`；`git diff --check` 通过，tool chunk `d9c583`。

只使用离线 Flutter test/analyze 与本地 fake；未运行真实 HTTP、DB、provider、设备、厂商、Android/iOS 构建或 Chrome。

## 变更文件

- `lib/features/message/presentation/private_chat_page.dart`
- `test/q03_message_visibility_test.dart`
- `docs/qa/q03-same-peer-denial-fence-20260912.md`

`test/q03_message_visibility_test.dart` 的两项既有回归原样保留并通过，并新增一项真实 Paged 后台拒绝回归；未改 MessageCenter、MainShell、room 或数据层。
