# Flutter IM correlation trace（2026-09-12）

## 用途与开关

这是下一次真实 IM 样本的临时、窄范围 QA 观测，不是通用遥测，也不是消息送达或“2 秒内显示”的证明。默认关闭；只有 debug 构建并显式传入以下编译参数才会输出：

```text
/Users/kongzheng/Documents/ny/.tooling/flutter-3.44.7/bin/flutter run --debug --dart-define=QA_IM_TRACE=true
```

`QA_IM_TRACE` 是 compile-time define。实现还要求 `kDebugMode`，所以正式 release 即使误带该 define 也不会产生这些 trace 记录。没有该 define 时不会产生新记录。

## 关联规则与脱敏边界

每条记录的 `fp` 是 `SHA-256(messageId)` 的前 16 个十六进制字符；原始 `messageId` 不记录。`seq` 是进程内 trace 序号，`tUs` 是同一 trace `Stopwatch` 的单调微秒时间，可用来判断阶段先后和等待时长。

固定格式为：

```text
im.qa.trace seq=<n> tUs=<monotonic-us> stage=<stage> event=<event> fp=<16-hex> [safe-details]
```

只允许固定枚举和计数：HTTP 仅记录 method、identity-bound、状态码、结果类别和耗时；不记录 URL、query、headers、token、response/raw body 或错误文本。任何消息文本、用户/会话标识也不进入该日志。无效或未信任的 provider hint 不能创建 trace context。

## 阶段 marker

同一 `fp` 的一条链可以包含以下阶段：

```text
sdk_callback  / trusted_custom_callback
adapter_parse / accepted
bus_dispatch  / accepted | complete | rejected
page_handler  / entered | queued | dequeued | ignored
page_load     / start
http          / start | complete | auth_recovery_start | replay_start | replay_skipped
page_publish  / publish
page_frame    / first_frame
```

`page_handler queued/dequeued` 只观测现有 PrivateChat single-flight 的排队和后续加载，不改变其调度；`http` marker 只观测实际 ApiClient 请求，并保留原有 401 recovery/identity fence。`page_frame/first_frame` 表示 publish 后挂入的首个 Flutter post-frame 回调执行。

## 单次样本读取

用同一个 `fp` 按 `seq`/`tUs` 顺序读取：缺少 `sdk_callback` 表示该样本尚未被可信 SDK callback 观测；`queued` 到 `dequeued` 的间隔表示已有 flight 造成的等待；`http start` 到 `complete` 的 `durationUs` 表示实际 HTTP 等待，401 recovery/replay 单独可见；有 `page_publish` 但没有 `page_frame` 表示页面在首帧回调前已不再挂载。不要用 HTTP fallback 代替 IM 到达或渲染时间。

## 定向验证

固定使用 Flutter 3.44.7，不启动设备、DB、provider 或浏览器：

```text
/Users/kongzheng/Documents/ny/.tooling/flutter-3.44.7/bin/flutter test test/im_correlation_trace_test.dart
/Users/kongzheng/Documents/ny/.tooling/flutter-3.44.7/bin/flutter analyze lib/core/network/api_client.dart lib/features/im/domain/im_correlation_trace.dart lib/features/im/domain/im_authoritative_refresh_bus.dart lib/features/im/infrastructure/tencent_im_session_adapter.dart lib/features/message/presentation/message_pages.dart test/im_correlation_trace_test.dart
```

测试覆盖 fingerprint/固定字段与 sink 隔离、invalid/untrusted hint fail-closed、SDK/adapter/bus 关联、identity-bound HTTP 成功与一次 401 replay，以及 PrivateChat 已有 flight queue 的第二条 hint 关联。

本次交付实跑：新增定向测试 `9/9 PASS`；同一测试带
`--dart-define=QA_IM_TRACE=true` 亦为 `9/9 PASS`；scoped `flutter analyze`
为 `No issues found`。既有 adapter/session、IM stage2 UI、ApiClient、以及
PrivateChat automatic-sync 定向回归共 `83/83 PASS`。未运行设备、DB、provider、浏览器或 APK/build。
