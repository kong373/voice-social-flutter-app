# Q19-05 Flutter 仅本人清空当前聊天记录

基线 `64f2701ca327857d600e62cd7ec0a859ea2cd6f0`，分支 `codex/flutter-q19-private-history-clear-20260910`。遵循 Backend `backend-q19-private-history-clear-20260910/docs/product-q19-private-history-clear-20260910.md` 冻结合同；不增加撤回、单条删除、清空对方或恢复已清记录的能力。

收尾只读核对 Backend 稳定实现 `45ac22a02cca3ed6aaed3855cf747a2eee329b1c` 与验证文档 `f105c5654ce173dc04b21164da7259efdb392fdb`：路径、新字段字符串及空摘要约定一致；后端测试数字不计入本批 Flutter 结果。

## 实现及边界

- 私信更多菜单新增“清空聊天记录”，明确仅本人、不可恢复，并先确认。已有但不可访问的会话仍可清空；未建立会话的草稿不能发送清空请求。恢复到空的已有会话保留服务端 UUID/入口，不伪造时间。
- 仅 POST `/app-mini-api/mini/v1/message/clear-history`，body 为 `{targetUserId: int}`、`X-Request-Id` 和现有 App auth。没有本地乐观成功。未知结果保留当前账号代次内的原 key/body，跨页面卸载可重试；明确失败不伪造回执，不自动生成新清空操作。
- history 根、conversations 每项、send/read/clear 的新增水位版本严格读取十进制字符串，messageSequence 为正十进制字符串，lastMessageSequence 允许 0。使用 BigInt，无浮点转换；旧版本响应不能回退已知水位，同版本水位不一致或新版本水位下降拒绝。
- 当前账号+identityGeneration 绑定私信 GET/文字 send/read/clear，覆盖 HTTP token 刷新、A→B→A、草稿 fallback。共享水位使已挂载聊天、列表和打开的搜索同步清除旧正文/摘要/未读；旧 cursor 与旧 Future 不能重新填入已清消息。
- 清空更新会话 epoch，卸载旧媒体 bubble/本地读取及 composer visit，取消旧输入/发送结果回写。已有 Q03 媒体下载/临时文件销毁机制保留。精确 `40481` 的旧媒体发送是失败终态，只退役原本地发送 intent，不伪造成功或新 key；未知网络结果仍保留原 intent。
- 清空后 sequence 高于水位的新消息正常显示；实时提示仍只触发权威 HTTP 恢复，不拿 IM payload 当消息事实。对方数据/媒体引用/通知不由客户端删除。
- 当前 Flutter 全局 `messageUnread/totalUnread` 仅在 `_syncNotifications`/`clearInteractionNotifications` 检查响应一致性，不保存/展示为全局 badge；现有 UI badge 来自 `ConversationSummary.unreadCount`，随共享水位归零并拒绝旧摘要。没有新增或伪造全局 badge。日后新增全局 badge 消费者也必须按后端合同废弃清空前请求，不能仅合并一个无版本总数。
- 同账号 token refresh 不失效；换号/登出后的旧代次不可复活。清空 pending 仅在内存、不写 storage；冷启动从服务端恢复水位，只有新的用户确认才会创建新清空操作。Mock/旧 test double 未声明此能力，不显示假清空入口。
- 不增加页面 ID、不改有效页数/runner/golden；现有 QA 页面范围不变。

## 精确验证

SDK 实际核验 `/Users/kongzheng/fvm/versions/3.44.7/bin/flutter` 为 Flutter 3.44.7 / Dart 3.12.2；没有改 SDK/fvm 目录。

RED：新增 contract 首轮 11 FAIL（其中 8 项为旧 parser 接受无效新字段，3 项为未实现清空/水位行为）；UI 2 FAIL（缺入口）；媒体恢复 1 FAIL（40481 后仍保留原 intent）。最终新增覆盖共 39 项，包含在以下去重 354 PASS 内，不重复相加工作中快照。

```sh
/Users/kongzheng/fvm/versions/3.44.7/bin/flutter test --no-pub \
  test/q19_private_history_contract_test.dart test/q19_private_history_ui_test.dart \
  test/backend_message_repository_contract_test.dart test/private_media_message_contract_test.dart \
  test/private_chat_automatic_sync_test.dart test/q03_message_visibility_test.dart \
  test/user_avatar_projection_test.dart test/tencent_im_stage2_test.dart \
  test/s13_private_media_host_test.dart test/s13_private_media_ui_test.dart \
  test/message_notification_race_ui_test.dart test/message_repository_test.dart --reporter expanded
# 336 PASS

/Users/kongzheng/fvm/versions/3.44.7/bin/flutter test --no-pub \
  test/message_first_party_boundary_ui_test.dart test/message_center_search_test.dart \
  test/message_navigation_return_test.dart test/message_order_deep_link_test.dart \
  test/message_request_id_test.dart --reporter expanded
# 17 PASS

/Users/kongzheng/fvm/versions/3.44.7/bin/flutter test --no-pub \
  test/first_party_live_mutation_coverage_test.dart \
  --plain-name 'private message and notification mutations sync first-party state only' --reporter expanded
# 1 PASS；不是该整个文件 PASS

/Users/kongzheng/fvm/versions/3.44.7/bin/flutter analyze --no-pub
git diff --check
```

本地原始日志留在本树 ignored `artifacts/qa/q19-private-history-clear-20260910/`。格式检查仅覆盖本批变更 Dart 文件。既有 Backend 消息合同大文件通过明确命名的 `_currentMessageFixture` 为旧场景补零水位/正序号，不修复其故意错误的旧字段；Q19 新负向测试直接使用原始 wire，没有该适配。其他受影响媒体/头像/同步夹具直接补精确新字段，原有效业务断言保留。

最终 `analyze`：No issues found（10.7s）；20 个变更 Dart 文件 `format --output=none --set-exit-if-changed`：0 changed；`git diff --check`：0。以上为本独立树结果，不是主合并态结果。

## 变更文件

生产：`lib/app/app_dependencies.dart`、`lib/core/network/backend_route_catalog.dart`、`lib/features/media/private_media_host.dart`；`lib/features/message/data/backend_message_repository.dart`；`lib/features/message/domain/{message_models,message_repository,private_history}.dart`；`lib/features/message/presentation/{message_pages,private_chat_page,message_center_page}.dart`。

测试：`test/{q19_private_history_contract_test,q19_private_history_ui_test,backend_message_repository_contract_test,first_party_live_mutation_coverage_test,private_chat_automatic_sync_test,private_media_message_contract_test,q03_message_visibility_test,s13_private_media_host_test,tencent_im_stage2_test,user_avatar_projection_test}.dart`。另本交接文档，共 21 文件。

## 未执行及主线接线

- 未跑全量、golden、设备、真实厂商、DB、真实两用户 HTTP/IM 或发布验收；局部门禁不代表 release PASS。需与 Backend Q19/V75 合入后由主做最终实证，本客户端不会把缺失水位的旧响应默认为成功。
- 依赖盘点曾运行整个 `first_party_live_mutation_coverage_test.dart`，其未修改的 `room moderation and seats write exact authority with idempotency` 用例在 `RoomAudioMuteState.parse` 报“麦克风静音原因或版本无效”。本批仅改该文件的私信新字段并验证私信用例，未削弱/跳过/修改该房间断言；该范围外失败交主线处理。
- 无 Backend、room/PK、payout、金额、部署改动；仅 AppDependencies 两行私信代次注入和 route catalog 新接口为共享接线点。媒体 host 仅上文 40481 终态处理。未 push。
