# 第二批：房间分享与 App 退款退役（2026-09-09）

## 结论和基线

Q10-04、Q15-06 已落实；Q19-04 核验无私信撤回实现，不改其它业务。有效页面 61，累计 8 个原 ID 为 REMOVED_BY_PRODUCT。不是旧 69/64 页验收通过。

独立树 `/Users/kongzheng/Documents/ny/.worktrees/flutter-product-exclusions-20260909`，分支 `codex/flutter-product-exclusions-20260909`。第一批 `4e6608b` 未改写。按主任务指令依次 cherry-pick：
- `c1fb96fd573f283ece839319cdc91c8eeb05c6e1` → 本地 `9b0473e`。
- `a8035905a373eeb1be666b1a8c1de80d56345e42` → 本地 `074bf4b`。

本批 diff 基线是 `074bf4b`。未读取或改写主树源码；未同步主任务随后 e4f0659 Mic / Q04-05 discovery 并行改动，集成由主任务处理，不覆盖它们。

## 已读取的权威答案与实际 inventory

来源：主项目 `artifacts/product/filled-decisions-20260909/answers.json`，只提取相关答案，不读取其它 secret。

| 决策 | 用户原答案 | 原实际入口/依赖 | 处理 |
| --- | --- | --- | --- |
| Q10-04 | 无 | 房间更多→分享；直接复制房间号；RoomSharePage 复制房间邀请；QA RM-009 | 删除页面、import、Navigator builder、share/copy action 与按钮；移除房间配置说明中的分享字样 |
| Q15-06 | 不用管，用户自己去支付宝申请退款，平台不提供退款入口 | 商城→退款列表/选订单；订单详情→申请；申请/结果→提交/重试；QA CM-007/008；Backend/Mock repository 写方法 | 删除 App 页面和入口；旧 submitRefund/resubmitRefund 本地抛 UnsupportedError('REMOVED_BY_PRODUCT')，无 HTTP、无 Mock 状态修改 |
| Q19-04 | 不能撤回 | MessageRepository、消息页面、Backend/Mock 消息仓库、IM 适配、BackendRouteCatalog 均无 recall/revoke/retract/unsend/delete-message/撤回/撤销接口或入口 | 仅核验，不凭空增加代码或更改上麦申请撤回 |

分享页未发现独立站内邀请请求；原“复制房间邀请”属于该页已删除。管理者上麦安排、Mic 邀请、PK 邀请不属于房间分享，保留。动态“分享”、AC-004 账号绑定授权非本决策范围，未改。

通知目标只有 user、room、dynamicPost、order、none，没有退款/分享页目标。订单通知仍进 OrdersPage 并定位原订单详情；新增断言确认到达后无退款入口，刷新补单仍可用。App 无这三页的命名路由注册，新增原 App Navigator 拒绝旧页 ID/路径/deep link 的断言。RM-003 房间直达/深链解析与普通房间通知保留；它们不能打开已删除的 RM-009 页面，入房仍走原权限校验。

## 页面与源码范围

新增退役页：
- RM-009 房间分享：REMOVED_BY_PRODUCT。
- CM-007 退款申请列表：REMOVED_BY_PRODUCT。
- CM-008 退款申请与结果：REMOVED_BY_PRODUCT。

原 US-005、SC-004/005/006/007 保持退役。区域计数：AC 12、DS 8、US 9、RM 13、MS 6、CM 10、SC 3，总计 61。manifest、QA builders、QA Console 断言、M24 截图/交互计数使用同范围；M24-EMU-009 只移除 CM-008 子场景，保留工单、支付结果、订单、PK 子场景。

生产变更（相对本树根目录）：
- `lib/app/page_manifest.dart`、`lib/debug/qa_console/qa_page_catalog.dart`：退役注册。
- `lib/features/room/presentation/room_share_page.dart`：删除。
- `lib/features/room/presentation/video_runtime_room_page.dart`：仅删除 29 行分享相关代码，6 个局部 hunk；不涉及 Mic 提示、leaveMic、PK 或离房提示。
- `lib/features/room/presentation/room_configuration_form.dart`：只去掉“和分享”描述，不更改可见性/权限规则。
- `lib/features/commerce/presentation/commerce_refund_pages.dart`：删除。
- 同目录 `commerce_pages.dart`、`commerce_wallet_pages.dart`、`commerce_order_pages.dart`、`commerce_widgets.dart`：移除退款 part/CTA/导航和失去调用的 UI helper。
- `lib/features/commerce/data/backend_commerce_repository.dart`、`mock_commerce_repository.dart`：退役 App 申请/重试写，删除仅服务这些写的幂等缓存/helper/序号。

保留生产订单详情、复制订单号、支付结果、queryOrderStatus/reconcile、钱包流水、历史退款 result/history DTO 和读取、提现、礼物、装扮。refund_request_id 工具仍被提现使用，未删除。未更改任何后端服务、数据库、财务记录、支付数据、厂商或设备；退款后台由主任务/Ampere 负责。

## 测试与 QA 证据

TDD 初次运行 `product_share_refund_exclusions_test.dart`：4 项按预期失败（注册未退役、Backend 尝试 GET、Mock 仍执行申请校验、钱包仍显示退款）。实现后转绿。新的房间工具测试覆盖听众与房主，断言无分享/复制、零 Clipboard 写，并保留成员/公告及按角色出现的房管/PK 入口。

工具链 Flutter 3.44.7 / Dart 3.12.2，使用 `--no-pub`，没有 golden 更新。以下是独立运行结果，不把重复运行相加为独立用例数量：

运行 A：123 项通过（11 文件）。
```text
test/product_share_refund_exclusions_test.dart
test/room_share_page_test.dart
test/page_manifest_test.dart
test/m4_refund_scope_contract_test.dart
test/message_order_deep_link_test.dart
test/backend_commerce_repository_contract_test.dart
test/first_party_live_mutation_coverage_test.dart
test/commerce_live_ui_contract_test.dart
test/commerce_repository_test.dart
test/m22_pages_test.dart
test/commerce_visual_responsiveness_test.dart
```

运行 B：补充最终断言及受影响保留行为，162 项通过（10 文件，部分重复 A）。
```text
test/product_share_refund_exclusions_test.dart
test/m4_refund_scope_contract_test.dart
test/product_exclusions_test.dart
test/room_configuration_form_test.dart
test/room_leave_mic_feedback_test.dart
test/room_mic_queue_ui_test.dart
test/room_lifecycle_repository_test.dart
test/backend_room_lifecycle_repository_contract_test.dart
test/backend_message_repository_contract_test.dart
test/refund_request_id_test.dart
```

运行 C：`flutter test --no-pub --dart-define=ENABLE_QA_CONSOLE=true test/qa_console_app_test.dart`，4 项通过，实际进入 QA Console，验证 61 总页和筛选/返回/重置。
`flutter analyze --no-pub`：No issues found。各变更 shell 脚本单独 `bash -n`；`git diff --check` 通过。

## QA 退役映射与 M4 注意事项

逐项旧 positive 映射见 [退役测试清单](product-share-refund-retired-tests-20260909.md)。删除的是已取消业务的测试，不使用 skip，不计 PASS；混合用例保留提现、历史读取和其它有效断言。

M4 只删除退款申请/结果/重试流程及退款页面探针；历史退款记录读取仍保留。旧 strict/deferred 参数仅兼容旧调用配置，任何值都不能重启退款。报告明确输出 M4_REMOVED_BY_PRODUCT 与 REMOVED_BY_PRODUCT 数组；保留范围通过状态为 PASS_WITH_PRODUCT_REMOVALS，而不是把退款计 PASS/临时豁免。run/aggregate 两份脚本同步识别，并拒绝退款成功 route 冒充本轮结果；纯本地合成日志验证了缺失退役证据、错误旧 PASS、缺失无入口 invariant、非法退款成功 route 均失败。其它 capability/route/invariant 门禁保留。

**未执行**：完整 M24/M4 runner、全部 golden、APK build、AVD/模拟器、真机、Linux 容器、在线后端/厂商/支付流程。本轮测试不代表这些通过。
**明确剩余项**：本树 M4 旧 PK 收尾仍有两处 `roomPkRepository.surrender`（函数片段未动），已由主任务承接自然结束路径；现有 runner 不能算 PASS。主任务 e4 Mic 一分钟提示和后续 discovery 改动需主树集成验证。本批明确产品项未发现其它遗漏或待猜测业务规则。
