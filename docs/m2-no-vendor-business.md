# M2.1 — 不依赖第三方 SDK 的业务核心

本阶段在声网、支付渠道与腾讯 IM 申请期间继续开发平台业务代码。第三方能力统一保留在既有端口层，不阻塞页面、状态机、接口契约和自动测试。

## 本阶段页面

- DS-001 首页房间发现：由 Repository 提供推荐房间，不再硬编码在页面。
- DS-002 全局搜索：搜索房间、用户或房间号，数字房间号可进入 RM-003 校验。
- DS-003 搜索结果：房间与用户分组，房间结果直接进入 RM-004。
- DS-008 收藏与我的房间：收藏、取消收藏、我的房间、进入与管理。
- RM-001 创建房间：兼容后端“注册时自动创建个人房”的事实模型，防止重复建房。
- RM-002 编辑与关闭房间：保存后复核权威状态；关闭房间与普通离房严格区分。
- RM-003 房间直达：有效目标直接替换为 RM-004，只有无效、关闭或不可用时展示恢复界面。

## 已确认后端契约

- `/app-api/rooms/v1/getRecommendRooms`
- `/app-api/es/getSearchESResult`
- `/app-api/user/favorite/getFvoriteRooms`
- `/app-api/user/favorite/starRoom`
- `/app-api/rooms/getRoomSelectByUserId`
- `/app-api/rooms/getRoomById`
- `/app-api/rooms/updateRoomInformation`
- `/app-api/rooms/getRoomTopics`
- `/app-api/rooms/setRoomTopics`

## 主动阻断的错误映射

- 未确认普通房新增接口时，不伪造“创建成功”。已有个人房按配置与重新开放处理。
- 未确认服务端关闭房间接口时，不使用 `exitRoom` 冒充关闭房间。
- 有效深链不展示普通“正在进入房间”中间页。
- 搜索结果中已失效或无权限房间不伪装为可进入。

## 第三方边界

本阶段不新增声网、腾讯 IM、支付 SDK 或相关依赖。RTC、实时消息、支付均继续通过端口层 fail-closed；Mock 仅用于业务流程和自动测试。
