# 私聊实时刷新优先级窄验证（2026-09-12）

## 范围

- 基线：`42a8a8409256d59b647900c66f194a48593e8fee`
- 分支：`codex/task15-im-refresh-priority-20260912`
- 目标：有效 realtime hint 在 periodic head 等待时启动一个优先 head；旧 head 最多保留一个废弃传输，不得写入新页面状态。
- 不在范围：APIClient/Backend、消息语义、发送/超时调度、RTC、设备、APK、数据库、provider、通用 runner。

## 实现边界

- 只对 `PagedPrivateMessageRepository` 的 periodic head 抢占；进入 continuation 或 `markVisiblePrivateMessagesRead` 后仍按既有 single-flight 排队。
- 抢占递增 `_loadRequestId`，不递增 `_conversationEpoch`，因此不会改变 clear、换号、会话切换的语义。
- 旧请求不可取消，`_abandonedPeriodicHead` 保证同一页面最多保留一个被废弃的 periodic head；旧 completion 通过 flight identity 不得清除新 flight。
- 若前一个被废弃的 periodic head 仍未完成，第二个 periodic head 不再抢占，新的 hint 沿既有 coalesce 队列等待，以限制废弃传输数量。
- 旧结果在 head 返回后通过 `isCurrent` 被丢弃；旧 denial 在 presentation catch 中先经过 requestId 检查，不得触发 visibility revoke。
- periodic Timer 在无 trace context 的 Zone 中执行，避免普通 HTTP/first-frame 继承旧 hint fingerprint。realtime hint 仍由现有 validated context 记录。

## TDD证据

RED：

```text
flutter test test/im_correlation_trace_test.dart --reporter expanded
exit=1
10 existing tests passed; 2 new tests failed
Expected: true / Actual: <false>
a valid hint must not wait for the periodic head
```

GREEN：

```text
flutter test test/im_correlation_trace_test.dart --reporter expanded
exit=0
00:03 +13: All tests passed!

flutter test test/private_chat_automatic_sync_test.dart --reporter expanded
exit=0
00:07 +25: All tests passed!

flutter analyze
exit=0
No issues found! (ran in 10.5s)
```

运行工具均为 pinned `/Users/kongzheng/Documents/ny/.tooling/flutter-3.44.7/bin/flutter`；未启动 APK、模拟器、设备、DB、provider 或服务。

## 端到端边界

这些测试只证明页面刷新优先级、过期回包隔离和 trace 归因，不证明“发送按钮→对端真实画面≤2秒”。该门禁仍需主方的真实 provider/SDK/画面采样裁决。
