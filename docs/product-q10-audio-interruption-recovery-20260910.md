# Q10-03：iOS 系统音频中断后的受控恢复

基线：Flutter `db17a2461a792f6e6a63a7a5c1ca05d423346d5b`。
工作树：`flutter-ios-audio-recovery-20260910`，分支 `codex/flutter-ios-audio-recovery-20260910`。
来源：已填 `answers.json` Q10-03「自动恢复」及
`artifacts/product/filled-decisions-20260909/final-rule-gap-audit-20260910.md`。

## 行为和授权边界

系统中断与用户主动关麦分开记录。只有中断开始前 SDK 已确认发音的意图可以自动恢复；
占着麦但已关麦、听众、尚在等待首次 SDK unmute 的请求，均不产生恢复意图。
中断期间 RTC 实际发音和 native active 都为 false，不能凭保留意图继续后台房间心跳。
麦克风按钮保留原主动开关意图，用户点击关闭会立即取消恢复意图；这不是发音/在线证明，
没有修改 `isSpeaking`、麦位 presence、租期或 CPS 口径。

恢复链路：

1. Swift 观察真实 `AVAudioSession.interruptionNotification`。`began` 停止 active，保留原
   adapter-local UUID、原模式和原 monotonic deadline，不续签、不占用新后台任务。
2. 只有相同中断的 `ended` 带 `shouldResume`，原观察期限未到且系统配置/权限有效，才发
   `{sessionId, active:false, interruption:'ended'}`。通知本身不打开麦克风。
3. RoomController 对相同账号/身份代次、controller epoch、transport ownership、有效
   服务端 lease、相同房间/session/麦位/occupantJoinedAt，发起新的只读权威同步。
   同步失败、旧版本未接受、下麦/离线、换占用、换 session、管理静音或 self mute 均拒绝。
4. 当前已授予的系统麦克风权限再次查询，不自动弹授权。权限等待、native start、SDK
   options 和 unmute 各阶段都保留原意图的代次检查；SDK 已发出的 options 若随后失权，
   不执行后续 unmute，既有 rollback/leave 保障保留。
5. 只有这一次受控恢复可以在后台重启原麦克风模式；普通新开麦仍需要前台。
   成功后消费意图，重复 end 不重复发音。重连/退出/换号/过期/撤权/用户操作均使旧意图失效。

没有调用 `setCategory`、`setActive`、`setMode`，没有接管 Agora 的 AudioSession。
按照 [Apple 的 interruption 文档](https://developer.apple.com/documentation/avfaudio/handling-audio-interruptions)
区分 begin/end/shouldResume；不是根据前台变化猜测系统已允许恢复。

### 原租期不延长

native 观察 lease 原有 45 秒上限继续生效：中断等待不延长它，过期后不自动复活。
服务端 lease 仍按已有单调时钟锚点判定，中断时停止不具备 native active 的后台续签。
只有原期限内的合法恢复完成后，native 才恢复正常每 10 秒续签；没有修改服务器 TTL。
长中断、OS 不提供 shouldResume、网络/权限核验失败会保持静音，不能宣称所有来电结束都必定开麦。

## 精确写集

| 文件 | 作用 |
| --- | --- |
| `packages/first_party_room_audio/ios/Classes/FirstPartyRoomAudioPlugin.swift` | begin/end 信号、原期限 continuation、限定同 UUID/原模式后台恢复 |
| `packages/first_party_room_audio/ios/Classes/InterruptionContinuation.swift` | 无 UIKit 依赖的原期限/模式判定，可直接 Swift 编译测试 |
| `packages/first_party_room_audio/lib/first_party_room_audio.dart` | 严格 wire 扩展、停止自动续签、匹配单次结束、旧 renew 返回的 revision fence |
| `lib/features/room/domain/room_background_audio.dart` | 把系统中断与通用失活分开，保留非 active 的原 UUID |
| `lib/features/room/infrastructure/native_room_background_audio.dart` | typed 信号映射 |
| `lib/features/room/infrastructure/rtc_adapter.dart` | 捕获真实 prior publication、立即静音、限定恢复、权限/SDK await fence |
| `lib/features/room/application/room_controller.dart` | 权威回读、租约/身份/占用/手动关麦 fence；不修改 Mic 权限策略 |
| `test/room_audio_interruption_recovery_test.dart` | 32 项真实 EventChannel→bridge→Agora adapter→controller 回归，SDK/native 为明确 fake |
| `packages/first_party_room_audio/test/interruption_channel_test.dart` | 10 项 wire、取消/过期、错误、迟到续签回归 |
| `packages/first_party_room_audio/ios/Tests/InterruptionContinuationTests.swift` | 14 条可执行 Swift 边界断言 |
| package README、本文件 | 合同、证据、未运行边界 |

不修改 `room_permission_policy`、后端、Auth、账号模型、媒体页面、礼物、财务、Runner、
插件依赖或主工作树；Android native 实现及其原两字段事件兼容。

## 红绿证据

日志均在根 `artifacts/product/filled-decisions-20260909/`；不含真实 token/设备标识。

- `q10-audio-recovery-red.log`：exit 1，2 个行为 FAIL。原实现前台没有恢复所需新权威读，
  后台只出现首次 publish，未出现期望的第二次；不是编译错误，也没有改旧断言。
- `q10-audio-recovery-green-r1.log`：exit 0，2/2。
- `q10-audio-recovery-green-r2.log`：exit 0，新增 29 + 原有五类相关回归合计 114/114。
- `q10-audio-recovery-green-r3.log`：exit 0，新增最终 32/32（补离线占位、凭证到期、transport 换主）。
- `q10-audio-final-tests.log`：exit 0，九个房间/RTC 文件 **152/152**，无 skip。
- `q10-audio-bridge-green-r1.log`：未完成，不算 PASS。新增 renew 竞态的 fake/real zone
  混用挂起，仅终止该批已确认 PID 36652/36820，日志保留；没有删断言。
- `q10-audio-bridge-green-r2.log`：改为等待真实 renew 进入的 Completer（12 秒上限），
  再放回 false；三文件 **27/27**，exit 0。此前 17 个 timeout/renew/旧事件断言全部保留。
- `q10-audio-analyze-r1.log`：1 条 unnecessary null-aware warning；清理后
  `q10-audio-analyze-final.log` **No issues found，exit 0**。
- `q10-audio-swift-typecheck.log`：iOS 13 arm64 simulator target，实际 SDK + Flutter framework
  对两个生产 Swift 文件 typecheck，exit 0，非仅字符串检查。
- `q10-audio-swift-policy.log`：macOS 实际执行纯 Swift policy，14 条断言 PASS。

最终 Flutter 测试是 **179 个不同用例**（152 + 27），不是把各轮通过数累加。
新增 Dart 用例 42 个；Swift 14 是断言数量，不冒充 14 个设备用例。

### 可重复命令

工作目录为本 worktree，Flutter 固定 `/Users/kongzheng/Documents/ny/.tooling/flutter-3.44.7/bin/flutter`。

```sh
/Users/kongzheng/Documents/ny/.tooling/flutter-3.44.7/bin/flutter test --no-pub \
  test/room_audio_interruption_recovery_test.dart test/rtc_background_audio_adapter_test.dart \
  test/room_mic_permission_fence_test.dart test/native_room_background_audio_test.dart \
  test/room_background_lease_controller_test.dart test/room_lease_controller_test.dart \
  test/room_controller_test.dart test/room_audio_mute_state_test.dart \
  test/room_management_audio_policy_test.dart --reporter expanded
/Users/kongzheng/Documents/ny/.tooling/flutter-3.44.7/bin/flutter test --no-pub \
  packages/first_party_room_audio/test/first_party_room_audio_test.dart \
  packages/first_party_room_audio/test/bounded_channel_test.dart \
  packages/first_party_room_audio/test/interruption_channel_test.dart --reporter expanded
/Users/kongzheng/Documents/ny/.tooling/flutter-3.44.7/bin/flutter analyze --no-pub
xcrun swiftc packages/first_party_room_audio/ios/Classes/InterruptionContinuation.swift \
  packages/first_party_room_audio/ios/Tests/InterruptionContinuationTests.swift \
  -o /tmp/q10-interruption-continuation-test
/tmp/q10-interruption-continuation-test
xcrun swiftc -typecheck -swift-version 5 -target arm64-apple-ios13.0-simulator \
  -sdk /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator26.5.sdk \
  -F /Users/kongzheng/Documents/ny/.tooling/flutter-3.44.7/bin/cache/artifacts/engine/ios/Flutter.xcframework/ios-arm64_x86_64-simulator \
  packages/first_party_room_audio/ios/Classes/FirstPartyRoomAudioPlugin.swift \
  packages/first_party_room_audio/ios/Classes/InterruptionContinuation.swift
```

## 明确未运行 / 合并后验收

未启动模拟器、真机、DB/Docker 或厂商连接；未运行 Flutter 全仓测试或完整 iOS build。
模拟器目标 typecheck 不能证明模拟器来电或扬声器行为。真实电话、其他 App 音频抢占、
蓝牙路由、锁屏后台、系统不发 shouldResume、超过原期限的中断，需主任务统一 native build
后按设备窗口验收。检查实际发送音频而不只看 UI 开关；原手动静音不得恢复，
中断期间被下麦/禁麦/换号/离房不得恢复，合法短中断只恢复原麦位一次。
