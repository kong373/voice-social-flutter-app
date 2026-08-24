# M4 原生权限与运营前端范围审计

## 当前边界状态

`UI_SCOPE=COMPLETE_69_PAGE_C_END` 仅表示 69 个 C-end Page ID 的 UI 实现
已完成；`LIVE_DUAL_AVD_ACCEPTANCE=PENDING` 仍表示真实 first-party live
双 AVD 尚未验收。本审计不把页面实现、后端能力和 live AVD 证据混写。

Backend ops/B7 能力已由后端提供，但不属于 Flutter 的 69 页 C-end 导航。
因此 `C_END_B7_SCOPE=INTENTIONALLY_OUT_OF_SCOPE`，本边界的 canonical
审核状态为 `VERIFIED`。Flutter 不新增 B7 路由，也不把普通用户入口冒充
operator 工作台。

## 原生权限

`AC-005` 系统权限中心现在只管理第一方操作系统权限：麦克风、通知、照片。Live 模式通过 `voice_social_app/system_permissions` 通道查询和请求 Android/iOS 状态；没有原生 host 或通道异常时返回 `unavailable`，不会把未知状态当作 `notDetermined` 或 `granted`。Android 权限由本地 plugin manifest 合并，iOS usage description 由 `tool/apply_native_permissions.sh` 写入生成 host 的 `ios/Runner/Info.plist`。

系统权限与厂商能力保持分离：正式 SMS、RTC、IM、PAYMENT、PUSH、
OBJECT_STORAGE 六项能力仍然分别是 `VENDOR_BLOCKED`/不可用边界。`MS-006`
只读取系统通知权限；它不会把 IM 或推送供应商状态映射成系统授权状态。

## 69 页范围内的运营/财务/公会 CPS/审核覆盖

当前 69 页只定义 C 端页面；Backend ops/B7 运营后台作为独立的后端受权限
能力存在，但没有对应的 C-end 一级、二级或三级导航，也没有平台管理角色
入口。普通 C 端因此不会看到运营权限。

| 范围 | 已有 C 端页面 | 确切缺口 | 当前处理 |
| --- | --- | --- | --- |
| 财务 | `CM-001` 钱包与流水、`CM-011` 主播收益、`CM-012` 结算与提现；退款为 `CM-007/CM-008` | 财务审核队列、提现/退款人工审批、对账差异处理、打款失败重试与运营审计日志 | 不新增页面；等待后端明确 operator 角色、路由和响应契约 |
| 公会 CPS | `SC-003` 邀请与渠道归属（C 端查看归属）；`SC-001/SC-002` 公会主页及成员/申请治理 | CPS 规则配置、渠道效果报表、佣金明细、结算审批、归属纠纷处理 | 不把 C 端归属页冒充运营后台；等待后端契约 |
| 内容/账号审核 | `AC-006` 实名提交与状态、`AC-009` 处罚申诉、`US-008` 举报、`SC-002` 入会申请审核、`CM-007/CM-008` 退款申请状态 | 实名人工审核队列、证件材料查看/脱敏、审核员决策、举报/申诉工作台、审核审计与批量操作 | C 端可提交第一方人工审核请求并只展示服务端脱敏状态；`FIRST_PARTY_MANUAL_REVIEW` 且 `providerInvocation=false`，实名业务状态仍按服务端 `PENDING/APPROVED/REJECTED` 显示 |
| Backend ops/B7 平台运营 | 后端已具备受权限保护的 ops 能力；无对应 C-end Page ID | 用户/房间巡检、封禁解封工作台、公告/活动配置、运营权限与角色管理 | `C_END_B7_SCOPE=INTENTIONALLY_OUT_OF_SCOPE`；不向 69 页普通用户导航暴露；canonical 审核状态 `VERIFIED` |

## 接口适配边界

本分支不把后端 B7/ops 能力复制成 C-end 页面，也不猜测其 operator
导航。后端提供的 B7 能力必须继续使用独立的受权限保护导航树、operator
身份和审计链路，不能复用普通用户的 69 页根导航。C-end 只保留其 69 页
范围内的服务端审核/状态展示。

公会 membership 是独立的产品能力，`SC-001`/`SC-002` 的公会加入、申请、
成员列表和成员治理保持在范围内；本审计的商业 VIP/membership 与礼物
backpack 排除不影响公会 membership。
