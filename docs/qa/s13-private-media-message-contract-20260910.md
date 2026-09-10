# S13 私信媒体 schema / 发送契约

基线 `4c0bd66e7a8af56099198768849ded8e437b2e29`；独立分支 `codex/private-media-contract-20260910`。本批只修改 message 三个 domain/data 文件，新增专属契约测试与本文档；没有修改 AppDependencies、pubspec、UI、media host、旧测试或 Backend。

## 契约与接线

- `ChatMessage.messageType` 为 `ChatMessageType.text/image/voice/video`，wire 为严格的 `TEXT/IMAGE/VOICE/VIDEO`；旧构造默认 TEXT。`media` 是单个 `MediaReference?`，`copyWith` 保留类型与同一附件，同时保持原已读单调语义。
- 历史 `media` 必须是 List。TEXT 接受空 List 或 legacy 缺失；显式 null、非 List、TEXT 附件均拒绝。媒体消息必须恰好一个附件，purpose 对应 PRIVATE_IMAGE / PRIVATE_VOICE / PRIVATE_VIDEO，content 必须显式 `''`，不得降级为空文本消息。
- 复用 core `MediaReference.fromJson`：严格六字段 `assetId,purpose,mediaType,bytes,durationMillis,version`，拒绝 URL/额外字段、缺字段、类型错误和产品限额错误。媒体历史额外核对当前会话参与者、第一方留存及 IM 证据，整页解析成功之后才允许沿原逻辑标已读。
- 独立 opt-in `MediaPrivateMessageRepository.sendPrivateMediaMessage` 使用 named arguments：`conversation`、`media`、`identity`、`requestId` 均 required。原 `MessageRepository`、Mock 和 text send 方法签名不变。
- 实际 POST `/app-mini-api/mini/v1/message/send`，`X-Request-Id` 沿原消息键语法规范化，空键拒绝，不自动新建。JSON **仅** `{targetUserId,messageType,mediaAssetId}`；没有 content、客户端 metadata、URL、文件路径或 body requestId。
- 采用现有 `postBoundToIdentity`，在连接完成、写入、401 refresh 重试以及返回结果/错误前校验 scope 与 repository actor。`MediaIdentityScope.wait` 使 ABA/销毁及时拒绝，晚成功与晚错误均被观察并丢弃。观察到 provider 不一致会永久失效 scope，不因 userId 恢复而复活。
- 回执显式核对整型 sender/receiver、type、content、六字段附件全等及已知 conversationId；必须 FIRST_PARTY_STORED，并有明确 deliveryStatus / imStatus / bool providerInvocation。VENDOR_BLOCKED 不允许声明 providerInvocation=true；已留存不等于实时已送达或已读。
- 并发按 **scope 对象 + requestId** 隔离。同一 scope 的同意图只发一次；改变 target 或任一附件 metadata 同 key 冲突。未知结果后只清 flight，保留指纹，允许原 key/asset/reference 重试；成功重试也访问 Backend，不用本地缓存绕过当前授权。不同 scope 或 actor 不共享 Future。
- Backend send 没有提供 conversationId 时，草稿保持 null；不编造 ID，不追加查历史或标已读。后续页面可通过有当前身份/可见性保护的正常历史同步解析会话身份。

合同对照：Backend `FirstPartyMessageService.send/messageMap`、`docs/product-s13-private-media-contract-20260909.md`、`docs/s13-media-http-contract-20260910.md`，以及基线已合入的 media core。Backend 文档早期有关 GET/部署未完成的段落不是本批对其最新上线状态的判断。

## 本机真实验证

固定 `/Users/kongzheng/fvm/versions/3.44.7/bin/flutter`，实际版本 Flutter 3.44.7 / Dart 3.12.2。没有设备、DB、真实 Backend、厂商或外部媒体操作；HTTP 行为通过现有 `test/support/media_http_fakes.dart` 接真实 ApiClient 的编码、refresh、请求绑定和响应 parser。

- 历史行为 RED：17 FAIL，非法媒体被旧实现返回为 ChatMessage。初轮夹具的 read response 字段不完整，失败体现在错误地发出了第二个请求；补成合法 read response 后重跑，17 项均明确因非法消息被接受而失败，保留两轮日志，不把夹具问题当正确行为红测。
- 新契约首批 80 PASS。安全复核追加 provider mismatch 回归，先 1 FAIL（provider 恢复后旧 scope 仍可发），修正后 1 PASS。
- 最终新契约 **88 PASS**；包括三种类型、legacy TEXT、历史拒绝、发送 exact body、六字段一致性、所有投递状态不升级、同意图单飞/变意图冲突、未知重试、401 同身份 refresh、ABA 开连接/响应/refresh、late error、不同 scope/actor 隔离。
- 旧 `backend_message_repository_contract_test`、`message_repository_test`、`message_request_id_test`、`message_first_party_boundary_ui_test`、`message_notification_race_ui_test`：**105 PASS**，文件及断言未改。
- 原 `private_chat_automatic_sync_test`：**22 PASS**，覆盖分页/poll/receipt、已读单调、隐藏/换号晚响应等；文件及断言未改。
- 合计 **7 个测试文件、215 个不重复用例 PASS**。首次 analyze 仅新测试空 List 类型推断 warning，显式类型后 full analyze **0 issue**。指定四个 Dart 文件 format 检查 0 change；git diff --check 通过。

可复现命令（在本 worktree）：

```sh
/Users/kongzheng/fvm/versions/3.44.7/bin/flutter test --no-pub test/private_media_message_contract_test.dart test/private_chat_automatic_sync_test.dart --reporter expanded
/Users/kongzheng/fvm/versions/3.44.7/bin/flutter test --no-pub test/backend_message_repository_contract_test.dart test/message_repository_test.dart test/message_request_id_test.dart test/message_first_party_boundary_ui_test.dart test/message_notification_race_ui_test.dart --reporter expanded
/Users/kongzheng/fvm/versions/3.44.7/bin/flutter analyze --no-pub
/Users/kongzheng/fvm/versions/3.44.7/bin/dart format --output=none --set-exit-if-changed lib/features/message/domain/message_models.dart lib/features/message/domain/message_repository.dart lib/features/message/data/backend_message_repository.dart test/private_media_message_contract_test.dart
git diff --check
```

日志目录 `/Users/kongzheng/Documents/ny/artifacts/product/filled-decisions-20260909/`：`s13-private-message-history-red.log`、`s13-private-message-history-behavior-red.log`、`s13-private-message-first-green.log`、`s13-private-message-provider-fence-red.log`、`s13-private-message-final-green.log`、`s13-private-message-legacy-regression.log`、`s13-private-message-analyze.log`、`s13-private-message-analyze-final.log`。

## 真实局限 / 后续 private UI 接入责任

这里只完成 schema/send/parse，不是选择、上传、受控下载、显示/播放、进程重启恢复或双端验收。没有接入新的 UI 入口，没有把媒体接入完成或 HTTP 成功当成可播放/READY。

调用方必须为一个可重试意图保留原 scope、requestId、reference（以及上传层原文件身份）；token refresh 可继续该 scope，logout/换号/ABA 后必须销毁，不用新 scope 自动续传旧意图。此处指纹为 repository 实例内的弱 scope 缓存，不是持久化 outbox，也不替代 Backend 跨进程幂等与 READY/owner/用途/引用事务校验。销毁 scope 只阻止本客户端接受旧结果；已到 Backend 的 POST 仍可能成功，不能据此声称“未发送”。

不新增支持能力 bool、不扩大 Mock，不改 JSON 2MB 限制，不改上传/流式下载或媒体临时文件清理。本批无本地文件、URL、Cookie、媒体内容日志和新增依赖。
