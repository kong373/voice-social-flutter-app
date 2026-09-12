# Message tab activation refresh（2026-09-12）

## 范围与结论

- 基线：`e89b9061708b9e27ffd671203f3db6a154ce6487`
- 提交：`d78da900bfd3d950e54b4381141bce96832d8ba7`
- 范围：`MainShell` 将消息 tab 的激活态传给 keep-alive 的 `MessageCenterPage`；从非激活变为激活时复用既有 `_load(showLoading: false)` 重新读取会话列表。
- 不改 Room、RoomController、HTTP、DB、设备、SDK、支付或新的 poller；既有 identity、visibility、history 与 request fences 不变。

Q19 保留已有会话的服务端身份/入口，解绑或清空不等于删除；Q03 仍过滤已确认 blocked/erased 或无读取权限的目标，激活刷新不使用 `revalidate: true`，因此不能借刷新复活这些行。

## TDD 与定向验证

- RED：[red.log](/Users/kongzheng/Documents/ny/.worktrees/q19-message-tab-activation-refresh-20260912/artifacts/qa/q19-message-tab-activation-refresh-20260912/red.log)：`+0 -1`，断言 `Expected: <2> Actual: <1>`，exit `1`。
- GREEN：[green-regression-final.log](/Users/kongzheng/Documents/ny/.worktrees/q19-message-tab-activation-refresh-20260912/artifacts/qa/q19-message-tab-activation-refresh-20260912/green-regression-final.log)：`+1: All tests passed!`，exit `0`。
- 相关最终套件：导航 `+4`、消息搜索 `+6`、Q19 UI `+7`；4 条 Q03 消息中心用例各 `+1`，均 exit `0`。对应日志保留在同目录。
- [analyze.log](/Users/kongzheng/Documents/ny/.worktrees/q19-message-tab-activation-refresh-20260912/artifacts/qa/q19-message-tab-activation-refresh-20260912/analyze.log)：No issues found，exit `0`；format 0 changed、diff-check exit `0`。

完整 Q03 定向日志另有 2 条未改动 `PrivateChatPage` 时序失败（`21 pass / 2 fail`），不属于本次消息列表激活改动。

## Native bounded evidence

主流程于 `2026-09-12 21:06` 补充了确定性 native 证据：最小化 17Pro 宿主窗口后，CUA geometry 恢复；`950 SE3` 的 Messages 页面仍显示空列表。随后执行正常下拉刷新，立即出现：

`qa0911second / QA950 II POSTCLEAR 1932 / 19:32`

这组 bounded 证据说明历史数据并未丢失，空页面是 keep-alive 页面在 tab 激活时没有重新读取权威会话列表；手动刷新可恢复正是该缺口的可见旁证。截图：[ios-950-se3-message-list-manual-refresh-restored.jpg](/Users/kongzheng/Documents/ny/artifacts/release/task15-unified-20260911/ios-950-se3-message-list-manual-refresh-restored.jpg)。本次追加只记录证据，不重测 UI。

## Q03 两条失败的 e89 对照

同一个 Flutter 3.44.7 命令仅运行以下两个精确 test name；基线使用独立 clean tree `e89b9061708b9e27ffd671203f3db6a154ce6487`，候选使用本分支 `a5ada2e57c8d5ffbf5123162f1a3a49490638e69`：

| test name | e89 baseline | candidate | 断言结果 |
| --- | --- | --- | --- |
| `same-peer confirmed denial while backgrounded redacts before returning foreground` | `+0 -1 / exit 1` | `+0 -1 / exit 1` | `old-body` 仍存在，测试行 76 |
| `send receipt cannot suppress a same-peer authoritative denial already in flight` | `+0 -1 / exit 1` | `+0 -1 / exit 1` | `old-body` 仍存在，测试行 188 |

原始日志：[baseline same-peer](/Users/kongzheng/Documents/ny/.worktrees/voice-social-flutter-room-entry-failure-message-20260912/artifacts/qa/q03-baseline-e89-two-failures-20260912/same-peer-confirmed-denial.log)、[baseline send receipt](/Users/kongzheng/Documents/ny/.worktrees/voice-social-flutter-room-entry-failure-message-20260912/artifacts/qa/q03-baseline-e89-two-failures-20260912/send-receipt-denial.log)、[candidate same-peer](/Users/kongzheng/Documents/ny/.worktrees/q19-message-tab-activation-refresh-20260912/artifacts/qa/q03-candidate-two-failures-20260912/same-peer-confirmed-denial.log)、[candidate send receipt](/Users/kongzheng/Documents/ny/.worktrees/q19-message-tab-activation-refresh-20260912/artifacts/qa/q03-candidate-two-failures-20260912/send-receipt-denial.log)。

最小根因是 `PrivateChatPage._performLoad` 的 non-paged catch：`private_chat_page.dart:624-634` 先检查 `requestId != _loadRequestId`，再解析 `_MessageReadDenial`。后台切换在 `:360` 递增 requestId；发送成功为防旧 history 成功覆盖新回执，在 `:892` 也递增 requestId。于是同一 identity、同一 conversation epoch 的权威 denial 在两条 fixture 中都提前返回，未执行 visibility deny，旧 `old-body` 留在页面。

这不是 earlier paged IM priority 的 abandoned-head 边界：两条用例的 `_PendingRepository` 继承普通 `MockMessageRepository`，不实现 `PagedPrivateMessageRepository`；paged priority handoff 只在 `:452-464` 的 realtime/periodic head 条件下成立。不能因此放宽所有过期成功或改变本候选实现。结论是两条为 e89 已有、候选复现的确定失败；本次只做一轮树间对照，不把它们泛化标成随机 Flake，也无证据表明来自消息 tab activation。

去重 PASS 口径：此前最终导航 `+4`（已包含新增 activation 回归）、消息搜索 `+6`、Q19 UI `+7`，以及完整 Q03 的 `+21 -2`；不再重复加入单测 `+1` 或四条 Q03 单独重跑的 `+1`，合计 `38` 个不同 PASS、`2` 个 Q03 失败。此次两条 baseline/candidate 对照新增 `0` 个 PASS。
