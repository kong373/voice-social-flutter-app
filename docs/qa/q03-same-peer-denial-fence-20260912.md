# Q03 同 peer 权威拒绝的加载序号隔离

基线：`582bca4d006f7b793aca7a7cb58857c09298d51a`。

分支：`codex/private-chat-q03-20260912`。

## 范围与合同

仅修 `private_chat_page.dart` 的非 paged 私聊历史读取错误交付。后台切换或发送成功会递增 `_loadRequestId`，但只要账号身份代次、目标 peer 和 `conversationEpoch` 仍一致，已识别的权威读取拒绝仍必须清理当前会话。

成功回包仍要求原有 `requestId`、active、账号和 epoch fence；旧成功不能回填。`PagedPrivateMessageRepository` 及 `flight.abandoned` 的拒绝仍经过原 requestId fence，保留 paged priority 的 abandoned head 隔离。explicit recheck、history watermark、peer/identity ABA 语义不变。

## RED / GREEN

- Godel 原始 RED：`/Users/kongzheng/Documents/ny/.worktrees/q19-message-tab-activation-refresh-20260912/artifacts/qa/q03-candidate-two-failures-20260912/same-peer-confirmed-denial.log` 与同目录 `send-receipt-denial.log`，两项均因 `old-body` 残留失败；本树复核合并日志为 `/tmp/voice-social-q03-20260912-two-red.log`，tool chunk `081117`，两项 exit `1`。
- 两项窄 GREEN：`/tmp/voice-social-q03-20260912-two-green.log`，tool chunk `140a82`，两项各 `1 PASS`、exit `0`。

## 定向回归

- 完整 Q03：`test/q03_message_visibility_test.dart`，`23 PASS`，tool chunk `9bfdba`，日志 `/tmp/voice-social-q03-20260912-green.log`。
- paged priority：`test/im_correlation_trace_test.dart` + `test/private_chat_automatic_sync_test.dart`，`41 PASS`，tool chunk `5d04a6`，日志 `/tmp/voice-social-q03-20260912-paged-priority-green.log`。
- clear-history：`test/q19_private_history_contract_test.dart` + `test/q19_private_history_ui_test.dart`，`42 PASS`，tool chunk `fa1f99`，日志 `/tmp/voice-social-q03-20260912-clear-history-green.log`。
- Analyze：Flutter `3.44.7` / Dart `3.12.2`，`No issues found!`，tool chunk `82f0d8`，日志 `/tmp/voice-social-q03-20260912-analyze.log`。Dart format 0 changed，`git diff --check` 通过，tool chunk `110d78`。

只使用离线 Flutter test/analyze 与本地 fake；未运行真实 HTTP、DB、provider、设备、厂商、Android/iOS 构建或 Chrome。

## 变更文件

- `lib/features/message/presentation/private_chat_page.dart`
- `docs/qa/q03-same-peer-denial-fence-20260912.md`

`test/q03_message_visibility_test.dart` 的两项既有回归原样保留并通过；未改 MessageCenter、MainShell、room 或数据层。
