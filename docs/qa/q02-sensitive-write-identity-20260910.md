# Q02 实名与公会写入 network identity fence

独立树 `/Users/kongzheng/Documents/ny/.worktrees/flutter-sensitive-write-identity-20260910`；分支 `codex/flutter-sensitive-write-identity-20260910`；基线 `420d93c29c78ceeb919bf9ca8aaa6254efe6655c`。本地提交，不 push。

## 确定问题与修复边界

原 Q02 页面预检/返回检查无法阻断 repo 内部换号：公会 coordinator 的 queue/flight/key 未绑定身份，排队 action 可读取新 token；普通 POST 在 openUrl 延迟期间 A→B 或 A→B→A 可发送旧申请/实名资料。

生产仅两个 repo：

- `BackendCommunityRepository`：5 个 mutation（apply/quit/resolve/mute/remove）统一在 `_runCommunityWrite` 调用时冻结 actor/generation；flight、retained requestId 和 serial queue 都加该身份范围。排队执行前、网络发送前、响应/错误后以及返回调用方前检查原身份，过期队列不会进入 openUrl，新身份也不等待或共享旧 flight。读路径和已退役操作不变。
- `BackendAccountComplianceRepository`：仅 `submitRealName`，调用时冻结 actor/generation，并加入既有 one-way intent digest；仍保留姓名/证件标准化和同身份相同输入 single-flight。网络前/结果后检查，晚错误按失效身份返回，不向新身份显示旧错误；同身份未知结果继续保留原 key。其余 compliance 写路由完全未改。

以上 POST 都复用**基线已存在的** `ApiClient.postBoundToIdentity`；没有改 ApiClient、Auth 协议、refresh、请求 body、路由、Backend 或 UI。同身份 401 refresh 保持原 key/body；恢复期间 ABA 禁止重放。真实 ApiClient 在 openUrl 后调用身份回调时中止 request，不写 Authorization、X-Request-Id 或 body，也不 close 发送。

安全审查用于限制旧身份证数据的网络发送与错误归属；测试驱动先复现真实行为，未以 missing-method 编译失败冒充 RED。没有日志记录姓名/证件/token；新测试使用合成身份数据和既有 `test/support/media_http_fakes.dart`。

## Ampere 必须补的主集成接线

用户明确 AppDependencies 由 Ampere 独占，因此本树未修改它。两个构造均统一追加：

```dart
int? Function()? currentUserIdProvider,
int Function()? identityGeneration,
```

主 AppDependencies 内创建两个 Backend repo 时均传：

```dart
currentUserIdProvider: () => sessionManager.session?.userId,
identityGeneration: () => sessionManager.identityGeneration,
```

必须是读取现有 sessionManager 的实时闭包，不能捕获某次固定 userId/generation。缺失或只传一个参数时 configuration fail closed；未登录、无效 actor 或负 generation 时 unauthorized，均不创建 HTTP 请求。Mock repo 不需要这些参数，源码和接口不变；旧 Backend 测试夹具只显式注入固定测试 actor/generation，不降断言。

## 验证结果与精确证据

SDK `/Users/kongzheng/fvm/versions/3.44.7/bin/flutter`；本树 `pub get --offline` 成功，未改 pubspec/lock。日志根为 `/Users/kongzheng/Documents/ny/artifacts/product/filled-decisions-20260909/`。

| 批次 | 结果 | 日志 |
| --- | --- | --- |
| 原实现真实 RED | 13 FAIL / 0 PASS | `sensitive-write-identity-red.log` |
| 首次窄 GREEN | 同 13 项 PASS | `sensitive-write-identity-green.log` |
| 最终新增 21 + 旧合同/可靠性 48 | 69 PASS | `sensitive-write-identity-contract-green.log` |
| 既有 mock / 实名入口 / Q02 live UI | 17 PASS、3 FAIL，见下节 | `sensitive-write-identity-ui-mock-integration-gap.log` |
| full analyze | 0 issues、exit0 | `sensitive-write-identity-analyze.log` |

新增21项覆盖所有5个公会mutation和实名的 pending-open ABA、实名 A→B、旧队列成功/失败后失效、新身份 queue/flight/key 独立、同身份未知重试、401 refresh/ABA、晚 transport error、缺失/部分/无效注入零 HTTP。旧相同实名 future identity、未知幂等、错误回执、第一方手动审核、社区串行和请求原字段断言均保留。`dart format --output=none --set-exit-if-changed` 检查7个 Dart 文件，0 changed；`git diff --check` 通过。

```sh
/Users/kongzheng/fvm/versions/3.44.7/bin/flutter test --no-pub test/sensitive_write_identity_test.dart test/backend_community_repository_contract_test.dart test/community_write_reliability_test.dart test/backend_account_compliance_repository_contract_test.dart test/backend_account_compliance_write_reliability_test.dart --reporter expanded
/Users/kongzheng/fvm/versions/3.44.7/bin/flutter test --no-pub test/community_repository_test.dart test/account_compliance_repository_test.dart test/guild_join_real_name_test.dart test/real_name_vendor_gate_test.dart --reporter expanded
/Users/kongzheng/fvm/versions/3.44.7/bin/flutter analyze --no-pub
```

### 已确认但本树不越权修的集成失败

`guild_join_real_name_test.dart` 用现有 live AppDependencies 创建 BackendCommunityRepository。本树 `lib/app/app_dependencies.dart:358` 尚未注入上述两个参数，因此以下3项期望 POST=1、实际=0；这是缺失接线的 configuration 阻断，不是新的传输失败，也不是基线旧日志：

- `verified account explicitly submits once without duplicate pending taps`（断言112行）。
- `server real-name revocation after preflight guides without replay`（断言167行）。
- `known-underage denial is not success or an automatic real-name retry`（断言184行）。

不修改这些断言，不降级成旧普通 POST，不为跑绿提供生产默认身份。Ampere 接线后主需重跑该文件并完成合并态验证。最终去重86项已通过、3项待接线，不宣称本独立树全绿或 live 已接通。

## 未做

未运行设备、厂商、DB、Backend/Maven/Docker 或全量 Flutter tests；不改 Q18 视觉穿戴、其他 compliance 路由或读取权限。本批隔离已过期请求，不撤回已经发往服务器的动作；unknown key 沿用既有 repo 内存生命周期，不新增跨进程恢复或身份改绑。
