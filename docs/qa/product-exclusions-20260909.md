# 2026-09-09 产品删除范围与交接

本轮基于 `1e58d0f787b06e77eace967b9b1d972e69420615`，独立 worktree `/Users/kongzheng/Documents/ny/.worktrees/flutter-product-exclusions-20260909`，分支 `codex/flutter-product-exclusions-20260909`。仅本地提交，不 push/merge。下面是当前产品范围；旧 69 页文档/截图不作为本轮 PASS。

## 决策与页面

| 决策 | 退役功能 | 页面/状态 | 保留边界 |
| --- | --- | --- | --- |
| Q23-01 | CP 列表、资格、邀请、接受/拒绝、解除 | SC-004 REMOVED_BY_PRODUCT | 普通关注、互关好友、公开资料 |
| Q23-02/03 | 守护查询、购买与页面 | SC-005 REMOVED_BY_PRODUCT | 普通礼物赠送、装扮 |
| Q23-04 | 免费粉丝团与任务 | 同 SC-005 REMOVED_BY_PRODUCT | 用户关系中的普通粉丝 |
| Q23-05 | 任务、连续签到、签到奖励与领取 | SC-006 REMOVED_BY_PRODUCT | 公会治理、动态、礼物 |
| Q23-06 | App 专题活动 | SC-007 REMOVED_BY_PRODUCT | 普通发现、排行榜、房间；不修改 PK |
| Q22-07 | 公会签到按钮、状态展示、请求 | SC-001/002 保留，仅签到退役 | 入会/退会、申请审核、成员禁言/移除 |
| Q16-02 | 独立好友请求及申请入口 | US-005 REMOVED_BY_PRODUCT | US-003/004、普通关注、互关=好友、私聊 |

有效 App manifest 与 QA builder 均为 64 页，旧 5 个 ID 在 `removedProductPages` 单独记为 `REMOVED_BY_PRODUCT`，不复用、不计 PASS。会员及礼物背包继续排除。

## 实际入口与依赖核对

- 社区中心删除 CP、守护/粉团、任务/签到、专题活动 4 个入口，保留公会主页、加入与成员管理、邀请归属。
- 个人中心及消息中心删除好友请求；他人主页删除申请好友及发送成功状态，关注/取消关注、私聊、拉黑与资料保留。
- 视频样式个人中心删除活动中心；通知权限说明改为私聊消息、系统通知和房间邀请。
- 删除 CP、守护/粉团、任务/签到、活动、好友请求页面实现及 QA builder；独立保留 `invite_attribution_page.dart`。
- App 原本无这些功能的命名路由注册；负向测试通过真实 `VoiceSocialApp` Navigator 验证旧 ID、路径及 URI 无法建路由。通知目标仍仅为用户、房间、动态、订单、不可用目标，无被删功能 builder。
- Backend/Mock 原有功能请求和变更实现移除，共用永久兼容拒绝方法。所有旧调用（含重复调用）直接抛 `UnsupportedError('REMOVED_BY_PRODUCT')`，无 HTTP 读取、写入或状态变更。未新增 feature flag；两个既有 capability getter 固定 false。
- 旧返回类型和路由名称保留为兼容数据定义，不存在生产出站调用。公会历史签到元数据可以读取但不展示、不写入，且不再是详情/成员查询的必要字段。
- 未修改金融历史、数据库、Backend、18080 服务、设备、厂商、next-platform。

## 回归与范围处理

测试先于入口删除执行：新负向测试 3 项在基线按预期失败（QA builder、社区 CP 入口、资料申请好友仍存在）。实施后通过。

最终 Flutter 3.44.7 / Dart 3.12.2：以下 23 个文件共 **206 项测试通过**。包括 Backend/Mock 19 类退役调用的重复拒绝/零网络矩阵、好友状态不被旧申请改变、真实 Navigator 拒绝旧路径、64 页注册、保留公会治理/普通关系、4 组社区视口布局、消息、礼物/财务既有回归。这里的保留 PK 邀请/end 协议测试只表示基线非认输断言未被破坏，不是主任务新 PK 改动或 M4 自然结束路径的验收。

```sh
FLUTTER=/Users/kongzheng/Documents/ny/.tooling/flutter-3.44.7/bin/flutter
"$FLUTTER" test --no-pub \
  test/product_exclusions_test.dart \
  test/product_exclusions_repository_test.dart \
  test/backend_community_repository_contract_test.dart \
  test/backend_social_repository_contract_test.dart \
  test/community_repository_test.dart \
  test/social_repository_test.dart \
  test/community_write_reliability_test.dart \
  test/community_presentation_contract_test.dart \
  test/community_discovery_live_fake_cleanup_test.dart \
  test/community_visual_responsiveness_test.dart \
  test/m22_pages_test.dart \
  test/m23_pages_test.dart \
  test/m33_deep_interactions_test.dart \
  test/message_center_search_test.dart \
  test/video_runtime_shell_consistency_test.dart \
  test/social_public_profile_friend_request_test.dart \
  test/first_party_live_mutation_coverage_test.dart \
  test/page_manifest_test.dart \
  test/qa_console_app_test.dart \
  test/live_shell_gate_test.dart \
  test/m4_refund_scope_contract_test.dart \
  test/account_compliance_repository_test.dart \
  test/backend_account_compliance_permissions_test.dart
"$FLUTTER" analyze --no-pub
git diff --check
bash -n tool/qa/run_m24_emulator_ci.sh
```

仅被删除功能的正向回归退役，逐项清单见 [退役测试清单](product-exclusions-retired-tests-20260909.md)。混合测试中的公会、普通关系、隐私、举报、工单与 HTTP 错误分类断言保留。公会/社交请求可靠性仍校验幂等、冲突、重试、并发、权威字段与分页。

M24 runner 的页面数量按授权范围改为 64，M24-EMU-017 记 REMOVED_BY_PRODUCT；M4 社区任务/奖励/活动探针改为明确退役记录，不再执行请求，也不要求这些能力成功。未降低其他业务门禁。

## 合并边界及确切未执行项

- `lib/features/room/pk/**` 与 `lib/features/shell/video_runtime_room_page.dart` 零 diff；保留主任务 PK 认输退役、对战主题、离房提示改动。
- `video_runtime_pages.dart` 仅删除活动快捷入口与无用社区 import。
- `integration_test/m4_first_party_live_integration_test.dart` 仅社区探针/文案/能力范围局部 diff。该文件的两处旧 `surrender` 收尾仍由主任务改为 PK 自然结束；本轮未修改、未执行，**不记 PASS**。主任务需与其最新提交合并后验证。
- 未运行完整 golden、AVD/模拟器、设备验收、Linux 容器或在线 M4 runner。已有 69 页/14 状态 golden 文件完全未修改；当前 64 页新版视觉基线验收尚未执行，不从本地 Widget 测试推导通过。
- 本轮明确删除功能未发现剩余可见入口或可执行请求。兼容签名、数据类型和历史资料保留不等于功能重新开放。
- 所有 6 个 `tool/product_exclusions_*.cjs` 临时机械编辑脚本已删除，不提交。

## 变更文件

以下包含删除文件；新增独立归属页替代原 CP/归属合并文件。本交接记录也属于新增文件。

```text
README.md
docs/m2.3-no-vendor-discovery-community.md
docs/qa/m2.4-android-emulator-test-plan.md
docs/qa/m2.4-page-coverage.md
docs/qa/m3.3-all-pages-ui-interaction-closure.md
docs/qa/product-exclusions-retired-tests-20260909.md
integration_test/m2_4_community_flow_test.dart
integration_test/m2_4_qa_console_flow_test.dart
integration_test/m4_first_party_live_integration_test.dart
lib/app/page_manifest.dart
lib/debug/qa_console/qa_console_page.dart
lib/debug/qa_console/qa_page_catalog.dart
lib/features/account/compliance/data/backend_account_compliance_repository.dart
lib/features/account/compliance/data/mock_account_compliance_repository.dart
lib/features/community/data/backend_community_repository.dart
lib/features/community/data/mock_community_repository.dart
lib/features/community/domain/community_repository.dart
lib/features/community/presentation/activity_center_page.dart
lib/features/community/presentation/community_hub_page.dart
lib/features/community/presentation/community_pages.dart
lib/features/community/presentation/community_widgets.dart
lib/features/community/presentation/guardian_fan_page.dart
lib/features/community/presentation/guild_home_pages.dart
lib/features/community/presentation/guild_members_pages.dart
lib/features/community/presentation/invite_attribution_page.dart
lib/features/community/presentation/invite_cp_pages.dart
lib/features/community/presentation/task_check_in_page.dart
lib/features/message/presentation/message_center_page.dart
lib/features/shell/video_runtime_pages.dart
lib/features/social/data/backend_social_repository.dart
lib/features/social/data/mock_social_repository.dart
lib/features/social/domain/social_models.dart
lib/features/social/presentation/social_profile_pages.dart
lib/features/social/presentation/social_relation_pages.dart
lib/features/social/presentation/social_widgets.dart
test/backend_community_repository_contract_test.dart
test/backend_social_repository_contract_test.dart
test/community_discovery_live_fake_cleanup_test.dart
test/community_presentation_contract_test.dart
test/community_repository_test.dart
test/community_visual_responsiveness_test.dart
test/community_write_reliability_test.dart
test/first_party_live_mutation_coverage_test.dart
test/live_shell_gate_test.dart
test/m22_pages_test.dart
test/m23_pages_test.dart
test/m33_deep_interactions_test.dart
test/message_center_search_test.dart
test/page_manifest_test.dart
test/product_exclusions_repository_test.dart
test/product_exclusions_test.dart
test/qa_console_app_test.dart
test/social_public_profile_friend_request_test.dart
test/social_repository_test.dart
test/video_runtime_shell_consistency_test.dart
test/visual/m2_4_360x800_test.dart
test/visual/m2_4_390x844_test.dart
test/visual/m2_4_text_scale_1_3_test.dart
tool/qa/run_m24_emulator_ci.sh
docs/qa/product-exclusions-20260909.md
```
