# 客服反馈历史（US-009 / US-010）

普通入口：我的 → 帮助与客服 → 我的反馈 → 工单详情。仍属现有69页范围，历史列表是工单页面的子流程。

- `GET /app-mini-api/mini/v1/support/tickets?page=1&pageSize=20` 使用当前登录会话，不发送 userId；返回现有社交分页 envelope，严格校验元数据与 list/records。
- 默认每页20条，最新提交在前。加载更多失败保留已有条目，并重试同一页；刷新重置到第一页。并发新增导致跨页重复时按 ticketId 去重。
- 打开历史工单自动读取单工单接口，返回列表后刷新。若分页请求尚未结束，排队执行一次刷新，不丢失返回刷新请求。
- 未登录/网络/格式错误不转为空列表；真正零条数据才显示空状态。页面退出后的迟到响应不更新UI。
- 提交成功后清空草稿；返回不会再次提交。历史、详情刷新不产生业务写入。
- 支持 SUBMITTED、ACCEPTED、PROCESSING、WAITING_USER、RESOLVED/CLOSED 状态；未知值显示不可用，不伪造已处理。

本次不开放即时客服会话、不调用厂商、不变更财务。工单历史接口由 Backend 本人权限过滤，分页 count/list 在同一只读可重复读事务内。

验证：`test/support_ticket_history_page_test.dart`、`test/backend_social_repository_contract_test.dart`，以及现有社交/黑名单/fixture回归。帮助页新增入口和说明对应 US-009 截图；CM-012 仅同步已审核的手续费提示文案。macOS/Linux 基线分别生成并人工核对，容差不变。
