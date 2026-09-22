# 搭子岛：60个有效页面交付矩阵

页面ID、名称、路由和源码沿用实际manifest；9个删除页面不恢复。默认画面与状态/角色/交互的证据分别记录，不将mock当设备通过。

| ID | 当前页面 | 工作包 | 已声明附加场景 | 直接源码 | 后续边界 |
|---|---|---|---:|---|---|
| AC-001 | 启动与会话恢复 | account | 3 | lib/app/app_gate.dart | 原生设备/未声明组合不计通过 |
| AC-002 | 协议与隐私同意 | account | 3 | lib/features/account/presentation/consent_page.dart | 原生设备/未声明组合不计通过 |
| AC-003 | 手机注册登录 | account | 2 | lib/features/account/presentation/login_page.dart, lib/features/account/presentation/registration_page.dart | 原生设备/未声明组合不计通过 |
| AC-004 | 第三方账号绑定与分享授权 | account | 0 | lib/features/account/presentation/third_party_authorization_page.dart | 原生设备/未声明组合不计通过 |
| AC-005 | 系统权限中心 | account | 8 | lib/features/account/compliance/presentation/system_permission_pages.dart | 原生设备/未声明组合不计通过 |
| AC-006 | 实名认证 | account | 7 | lib/features/account/compliance/presentation/system_permission_pages.dart | 原生设备/未声明组合不计通过 |
| AC-007 | 登录设备与会话管理 | account | 3 | lib/features/account/compliance/presentation/system_permission_pages.dart | 原生设备/未声明组合不计通过 |
| AC-008 | 账号封禁拦截 | account | 3 | lib/features/account/compliance/presentation/account_status_pages.dart | 原生设备/未声明组合不计通过 |
| AC-009 | 处罚申诉 | account | 8 | lib/features/account/compliance/presentation/account_status_pages.dart | 原生设备/未声明组合不计通过 |
| AC-010 | 账号注销申请与进度 | account | 5 | lib/features/account/compliance/presentation/account_status_pages.dart | 原生设备/未声明组合不计通过 |
| AC-011 | 版本升级 | account | 5 | lib/features/account/compliance/presentation/account_status_pages.dart | 原生设备/未声明组合不计通过 |
| AC-012 | 青少年模式 | account | 3 | lib/features/account/compliance/presentation/account_status_pages.dart | 原生设备/未声明组合不计通过 |
| DS-001 | 首页房间发现 | discovery | 3 | lib/features/discovery/home_page.dart | 原生设备/未声明组合不计通过 |
| DS-002 | 全局搜索 | discovery | 3 | lib/features/discovery/presentation/global_search_page.dart | 原生设备/未声明组合不计通过 |
| DS-003 | 搜索结果 | discovery | 3 | lib/features/discovery/presentation/search_results_page.dart | 原生设备/未声明组合不计通过 |
| DS-004 | 发现动态流 | discovery | 3 | lib/features/discovery/dynamic/presentation/dynamic_pages.dart | 原生设备/未声明组合不计通过 |
| DS-005 | 动态详情与评论 | discovery | 5 | lib/features/discovery/dynamic/presentation/dynamic_pages.dart | 原生设备/未声明组合不计通过 |
| DS-006 | 发布动态 | discovery | 1 | lib/features/discovery/dynamic/presentation/dynamic_pages.dart | 原生设备/未声明组合不计通过 |
| DS-007 | 用户与房间排行榜 | discovery | 5 | lib/features/discovery/dynamic/presentation/dynamic_pages.dart | 原生设备/未声明组合不计通过 |
| DS-008 | 收藏与我的房间 | discovery | 3 | lib/features/discovery/presentation/saved_rooms_page.dart | 原生设备/未声明组合不计通过 |
| US-001 | 个人中心 | social | 2 | lib/features/social/presentation/social_profile_pages.dart | 原生设备/未声明组合不计通过 |
| US-002 | 编辑个人资料 | social | 1 | lib/features/social/presentation/social_profile_pages.dart | 原生设备/未声明组合不计通过 |
| US-003 | 他人公开主页 | social | 3 | lib/features/social/presentation/social_profile_pages.dart | 原生设备/未声明组合不计通过 |
| US-004 | 关注、粉丝与好友列表 | social | 3 | lib/features/social/presentation/social_relation_pages.dart | 原生设备/未声明组合不计通过 |
| US-006 | 访客记录 | social | 3 | lib/features/social/presentation/social_relation_pages.dart | 原生设备/未声明组合不计通过 |
| US-007 | 隐私与黑名单 | social | 3 | lib/features/social/presentation/social_relation_pages.dart | 原生设备/未声明组合不计通过 |
| US-008 | 举报用户或房间 | social | 1 | lib/features/social/presentation/social_support_pages.dart | 原生设备/未声明组合不计通过 |
| US-009 | 帮助与客服中心 | social | 6 | lib/features/social/presentation/social_support_pages.dart | 原生设备/未声明组合不计通过 |
| US-010 | 工单详情与处理进度 | social | 5 | lib/features/social/presentation/social_support_pages.dart | 原生设备/未声明组合不计通过 |
| RM-001 | 创建房间 | room | 3 | lib/features/room/presentation/create_room_page.dart | 原生设备/未声明组合不计通过 |
| RM-002 | 编辑与关闭房间 | room | 2 | lib/features/room/presentation/edit_room_page.dart | 原生设备/未声明组合不计通过 |
| RM-003 | 房间直达与深链校验别名 | room | 2 | lib/features/room/presentation/room_deep_link_page.dart | 原生设备/未声明组合不计通过 |
| RM-004 | 语音房主界面 | room | 10 | lib/features/room/presentation/room_page.dart | 原生设备/未声明组合不计通过 |
| RM-005 | 上麦申请与麦位选择 | room | 6 | lib/features/room/presentation/room_page.dart | 原生设备/未声明组合不计通过 |
| RM-006 | 在线成员与听众席 | room | 3 | lib/features/room/presentation/room_members_page.dart | 原生设备/未声明组合不计通过 |
| RM-007 | 房主管理与处罚 | room | 3 | lib/features/room/presentation/room_management_page.dart | 原生设备/未声明组合不计通过 |
| RM-008 | 房间公告编辑 | room | 3 | lib/features/room/presentation/room_topic_page.dart | 原生设备/未声明组合不计通过 |
| RM-010 | 音频路由与麦克风控制 | room | 5 | lib/features/room/presentation/room_audio_page.dart | 原生设备/未声明组合不计通过 |
| RM-011 | 弱网重连与会话恢复 | room | 3 | lib/features/room/presentation/room_recovery_page.dart | 原生设备/未声明组合不计通过 |
| RM-013 | PK 邀请与准备 | room | 3 | lib/features/room/pk/presentation/room_pk_pages.dart | 原生设备/未声明组合不计通过 |
| RM-014 | PK 对战与结算 | room | 5 | lib/features/room/pk/presentation/room_pk_pages.dart | 原生设备/未声明组合不计通过 |
| MS-001 | 会话列表 | message | 3 | lib/features/message/presentation/message_center_page.dart | 原生设备/未声明组合不计通过 |
| MS-002 | 私聊会话 | message | 10 | lib/features/message/presentation/private_chat_page.dart | 原生设备/未声明组合不计通过 |
| MS-003 | 系统与互动通知 | message | 3 | lib/features/message/presentation/notification_pages.dart | 原生设备/未声明组合不计通过 |
| MS-004 | 通知详情 | message | 3 | lib/features/message/presentation/notification_pages.dart | 原生设备/未声明组合不计通过 |
| MS-005 | 通知目标不可用 | message | 0 | lib/features/message/presentation/notification_pages.dart | 原生设备/未声明组合不计通过 |
| MS-006 | 通知权限与消息恢复 | message | 8 | lib/features/message/presentation/message_recovery_page.dart | 原生设备/未声明组合不计通过 |
| CM-001 | 钱包与流水 | commerce | 6 | lib/features/commerce/presentation/commerce_wallet_pages.dart | 原生设备/未声明组合不计通过 |
| CM-002 | 充值商品目录 | commerce | 3 | lib/features/commerce/presentation/commerce_catalog_pages.dart | 原生设备/未声明组合不计通过 |
| CM-003 | 支付方式与提交中 | commerce | 3 | lib/features/commerce/presentation/commerce_catalog_pages.dart | 原生设备/未声明组合不计通过 |
| CM-004 | 支付返回与结果 | commerce | 7 | lib/features/commerce/presentation/commerce_catalog_pages.dart | 原生设备/未声明组合不计通过 |
| CM-005 | 订单列表 | commerce | 3 | lib/features/commerce/presentation/commerce_order_pages.dart | 原生设备/未声明组合不计通过 |
| CM-006 | 订单详情与补单 | commerce | 3 | lib/features/commerce/presentation/commerce_order_pages.dart | 原生设备/未声明组合不计通过 |
| CM-009 | 礼物目录与赠送面板 | commerce | 3 | lib/features/commerce/presentation/commerce_catalog_pages.dart, lib/features/room/presentation/gift_sheet.dart | 原生设备/未声明组合不计通过 |
| CM-010 | 装扮中心 | commerce | 5 | lib/features/commerce/presentation/commerce_catalog_pages.dart | 原生设备/未声明组合不计通过 |
| CM-011 | 主播收益 | commerce | 3 | lib/features/commerce/presentation/commerce_earnings_pages.dart | 原生设备/未声明组合不计通过 |
| CM-012 | 结算与提现 | commerce | 12 | lib/features/commerce/presentation/commerce_earnings_pages.dart | 原生设备/未声明组合不计通过 |
| SC-001 | 公会主页 | community | 14 | lib/features/community/presentation/guild_home_pages.dart | 原生设备/未声明组合不计通过 |
| SC-002 | 公会加入与成员管理 | community | 5 | lib/features/community/presentation/guild_members_pages.dart | 原生设备/未声明组合不计通过 |
| SC-003 | 邀请与渠道归属 | community | 3 | lib/features/community/presentation/invite_attribution_page.dart | 原生设备/未声明组合不计通过 |

完整角色、适用性、源码和逐场景路径见 page-matrix.json / STATE_MATRIX_FINAL.json。
AC-004与MS-005的固定不可用页面有明确N/A说明；其余未声明组合不以N/A代替未验证。
本地证据：/Users/kongzheng/Documents/ny/artifacts/ui-audit-20260921/gpt-takeover-20260921
