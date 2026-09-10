# Q03 App 私信注销可见性

基线：`1bbf77be5e8c3ee0fb791beafbd08c14a8e9ffd2`。
独立树：`flutter-account-visibility-20260910`；分支：`codex/flutter-account-visibility-20260910`。

## 依据与边界

`artifacts/product/filled-decisions-20260909/answers.json` 的 Q03-04 明确注销后他人看到的聊天、动态、昵称“删除”。本批仅修 Flutter 私信页面/会话列表可见性，不操作后端历史记录，不修改动态、注销状态机、Auth、AppDependencies、共享 ApiClient、M4、原生签名或房间图片。

已读取 Backend `message/FirstPartyMessageService.java` 的 `history`、`requireActiveUser`、`rejectBlockedPair`、`conversations`、`markRead`，及 `security/AccountAccessGuard.java`、S13 domain media contract。Curie 的 Q03 独立树当前使用 `AccountVisibilitySql.notErased` 同步过滤会话 list/count；未新增 Flutter DTO 字段或推测 `deleted` 标志。

| 收到的事实 | 当前 UI 行为 |
| --- | --- |
| HTTP404 + 40402，用户不存在或不可用 | 清当前对象的正文、昵称、头像描述符、预览及输入，停止自动同步/发送，撤销旧异步受理；不推断具体注销/封禁原因 |
| 历史/受控媒体读取 HTTP403 | 同样清理当前无读取权限的会话 |
| 最终认证失败，或 HTTP403 + 40332/40322 | 清当前账号代际的消息视图；不调用全局 logout，不清其他账号存储 |
| 发送 HTTP403 + 40381 + 精确 BLOCKED_RELATION | 当前会话不可读；其他同码仅发送限制不抹掉可读历史 |
| 网络、超时、5xx、无关404（例如40481）、协议错误 | 不作为注销证据；保留上次已接受快照及原暂时失败恢复方式 |

分类依据是已有状态码/HTTP语义，不把未知错误当删除成功。真实 Repository 已保留 HTTP status/code，因此未修改 parser、HTTP 路由或 Repository 生产源码；新增用例通过真实 ApiClient + BackendMessageRepository + 字节流 HttpClient fake 验证传播和列表替换。

## 实现文件

- `lib/features/message/presentation/message_visibility.dart`：仅进程内、按 Repository 对象及 `(userId, identityGeneration)` 隔离的不可访问状态；只存目标 ID/通用提示，不存消息/昵称/媒体/Token。记录用于阻止旧列表或页面重建把失效会话放回 UI。
- `message_pages.dart`：注册上述 part。
- `private_chat_page.dart`：清理与会话代际控制；明确拒绝不会被成功发送推进的加载序号吞掉；后台到达的同主体、同会话拒绝也生效。旧主体/旧会话的成功和拒绝都不接受。
- `message_center_page.dart`：权威列表整体替换；已知不可访问项过滤；搜索订阅当前列表，不再保存打开时的冻结副本；当前账号读取权限丧失时清列表。
- `private_media_widgets.dart`：当前有效的受控读取/媒体发送拒绝通知聊天页。原 visit、播放器、自有下载文件销毁机制复用，不删除 app-level 未知发送 journal，不重新发送或重新分配 asset。
- `test/q03_message_visibility_test.dart`：23项新增行为/HTTP/身份/播放清理测试。

### 显式恢复

失效后不自动“重新加载”旧数据。用户点击“检查会话状态”时，必须在同一有效账号及会话代际下重新 GET 会话列表，再读取当前会话历史；两项均成功才使用新的名称、正文及媒体，绝不合并已清掉的旧数据。列表缺该对象、权限仍拒绝、网络失败、切页或 ABA 均保持清空；不自动发送消息。账号级失效的列表可显式“检查账号状态”，也只能接受新权威列表，不解除已单独确认的其他对象拒绝。

## 测试证据（Flutter 3.44.7 / Dart 3.12.2）

日志均保留在根目录 `artifacts/product/filled-decisions-20260909/`。

RED 过程不合并为“通过”：

- `q03-flutter-red-r2.log`：旧轮询已失败后，晚到发送成功仍显示 `late-success`，真实断言失败；其余早期 HTTP 夹具还缺字段。
- `q03-flutter-red-r3.log`：完整媒体字段后，40402、读取40381、401三项均证实旧正文未清；网络负例3项通过。随后搜索等待未终态，结束本次进程，未称整批完成。
- `q03-flutter-media-race-red.log`：成功发送先返回，再收到已在途的40402，仍保留旧正文，真实失败；媒体断言的等待/清理夹具另有问题，后修为可观察按钮状态及有界清理，未将其初次失败称为有效权限证据。
- `q03-flutter-recheck-red.log`：显式重新核验用例先失败，再实现双重权威读取。
- `q03-flutter-background-red-r3.log`：恢复原 `_active` 拒绝条件重现首个前台帧仍有旧正文，exit1。前两轮后台测试存在生命周期顺序/未绘制帧问题，日志保留、不计作产品 RED。

GREEN：

1. `q03-flutter-regression.log`，handle90111，exit0：9文件 **252 PASS**，无失败/跳过（当时包含22项 Q03）。覆盖分页追赶/已读、发送恢复、会话搜索/返回、媒体未知 key/body、身份 ABA、受控本地播放及通知竞态。
2. 最终后台小修后 `q03-flutter-final-targeted-r2.log`，handle1122，**45 PASS / exit0**：最终23项 Q03 + 原22项自动同步回归。上一 `q03-flutter-final-targeted.log` 的44PASS/1FAIL来自后台帧断言位置，保留日志。
3. `q03-flutter-final-analyze-r2.log`：定向 analyze 0 issue / exit0。局部 format、`git diff --check` 通过。`pub get --enforce-lockfile` exit0，未修改 lockfile。

复现命令（从本树运行）：

```sh
/Users/kongzheng/Documents/ny/.tooling/flutter-3.44.7/bin/flutter test --no-pub test/q03_message_visibility_test.dart test/private_chat_automatic_sync_test.dart --concurrency=2 --reporter expanded
/Users/kongzheng/Documents/ny/.tooling/flutter-3.44.7/bin/flutter test --no-pub test/q03_message_visibility_test.dart test/private_chat_automatic_sync_test.dart test/backend_message_repository_contract_test.dart test/message_center_search_test.dart test/message_navigation_return_test.dart test/message_first_party_boundary_ui_test.dart test/private_media_message_contract_test.dart test/s13_private_media_ui_test.dart test/message_notification_race_ui_test.dart --concurrency=2 --reporter expanded
/Users/kongzheng/Documents/ny/.tooling/flutter-3.44.7/bin/flutter analyze --no-pub lib/features/message test/q03_message_visibility_test.dart
git diff --check
```

测试不执行真实API：HTTP 使用真实解析器和可控字节流 fake；媒体使用自有临时目录和 fake native player，验证实际文件删除，不等于真实设备播放证据。未运行全仓测试、设备、Apple、厂商、Backend/DB、部署或推送。后端 Curie 合并后的真实注销联调与设备验收仍为 **NOT_RUN**；本批不宣称完整 Q03 跨栈上线完成。
