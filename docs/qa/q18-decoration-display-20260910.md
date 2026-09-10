# Q18 实际装扮：分批交付

基线 `66dd17fe63aa73a49e28cb8ee8dcb47ab6b3f791`；独立分支 `codex/flutter-decoration-display-20260910`。

## 第一批：模型、绘制、读取与预览

`EquippedDecoration.parseList` 只接受四字段 `decorationId/type/assetKey/expiresAt`，与 Backend 实际 schema 的 `AVATAR_FRAME/ROOM_ENTRY/PROFILE_BADGE` 对齐。缺失旧字段返回空；格式错误不展示装扮、不让可选装扮字段阻断其他资料；重复同 type 整组不选赢家；重复 id/外链/错误期限拒绝。期限只读，不从商城时长合成到期时间。

注册三种专属 `DecorationProduct`，`DecorationArtwork/DecorationProductPainter` 同时供预览和后续穿戴使用：星环头像框透明中间、流光入场可按 progress 揭示、陪伴徽章独立结形绘制。未知 key/type 不画；没有网络或文件加载；未引入依赖。历史永久徽章仍可预览/穿戴，不能新购/续购。原 mock 显式素材路径仅保留在 mock 预览，不映射到 live 产品。

读取接线：`BackendSocialRepository._profileFromMaps`（本人和公主页、404个人资料回退），`LiveReadOnlyRepository.fetchCurrentUser`，`BackendRoomRepository` 的座位快照，`BackendRoomOperationsRepository._memberFromOnline`。个人状态非 ACTIVE 不保留装扮；offline member/seat 不保留装扮。`SocialUser/RoomMember` copy 保留 metadata，`MicSeat` 换人/清空/离线清旧装扮。

## 后续 UI 接线合同（第一批尚未宣称完成）

- `social_profile_pages.dart` / `social_widgets.dart`：个人资料和公主页头像框、徽章；资料读取按 viewer actor/generation/read epoch/target fence；商城返回重读，不本地穿戴。
- `video_runtime_room_page.dart`：只展示接线，头像框不改变 mic/entry/gift 操作。`room_members_page.dart` 复用现有身份/lease读隔离。
- 独立展示组件管理到期清除；disabled、缺字段和未知 key 不显示，登出/换号清除旧展示。
- 入场按当前 viewer room/session + member userId/joinedAt 去重；member `joinedAt` 是真实入房时间，seat `joinedAt` 是上麦时间，不能替代。不得因 reconnect、切房、旧 lease 回调或 token 刷新重放。

无 AppDeps、pubspec、Auth、私信媒体、Backend、设备、DB、厂商操作。

## Backend 只读协议复核

对主 `backend-decoration-display-20260910` 当前8文件复核：APPROVE，未见确定 P0/P1。此前 `members/seatState` 缺字段已修；成员按页批量、seat只在线occupant，原访问校验保留，ACTIVE/EQUIPPED/expiry、retired permanent符合合同，旧mic测试仅补schema fixture，未弱化断言。主报告32/32 PASS含realMySQL、Spot0；本任务未执行Backend验证。

## 第一批验证

日志目录：`/Users/kongzheng/Documents/ny/artifacts/product/filled-decisions-20260909/`。

- `q18-display-renderer-red.log`：三款旧预览确实未配置，3 FAIL。
- `q18-display-dto-red.log`：读取缺metadata RED；成员fixture首次缺list非行为RED，补齐后 `q18-display-member-red.log` 确认真正缺metadata失败。
- `q18-display-empty-seat-red.log`：clear到空麦仍留装扮，1 FAIL；随后修复copy。
- `q18-display-core-ui-green.log`：10新DTO + 3新预览 + 19续购/永久/身份/预览测试，32 PASS。
- `q18-display-core-regression.log`：补实际像素绘制后，14新合同/绘制 + 原 seat/social/room/member/current-user 合同共161 PASS。
- 上述新合同14 + 19续购UI + 原合同147 = 180项不重复 PASS。未运行全量/设备测试。

渲染通过实际像素非空/三款不同/头像中心透明/入场零或非有限progress不绘制检查；预览确认零购买/穿戴调用。复杂实际页面身份/期限/入场测试待后续批，不能将第一批当全链路完成。

## 第二批：实际静态穿戴

`EquippedDecorationView` 与商城预览共用同一个 `DecorationArtwork`。头像框只叠加透明绘制，不替换头像；徽章只在资料中出现。可选 metadata 缺失、未知产品、离线/非 ACTIVE 的服务器投影、到期或 UI 身份失效时不绘制。有限期限有本地定时器，后台恢复重新检查；历史永久无到期定时器。期限只是客户端展示裁剪，真实权益仍由 Backend 判断。

已接 `PersonalCenterPage`、`PublicProfilePage`、实际主“我的”入口 `VideoRuntimeAccountPage`、room mic/header avatar、member list。后者只加头像展示，不改 member/mic/gift 操作。个人资料及公主页增加 actor/generation/read epoch/target 读隔离；主“我的”只补 profile read 身份校验与 header 的身份监听，不改资金/权限/媒体/Auth。商城返回重读 profile，不从商城模型伪造当前穿戴。

覆盖真实页面出现/登出消失、ABA晚成功/晚错误、公主页换target、空麦/离线、controller身份/离房/lease失效、精确期限后无需HTTP移除。旧响应、旧账户或路由参数都不能授予效果。

静态资料/麦位新增14项 PASS；相关旧profile/member/响应式36项 PASS。初次 entry fixture 在test body之后才销毁自持有controller导致4项pending timer，已补显式close，未改production lease/controller；新增mine fixture补真实Shell的Scaffold。旧断言未降低。

成员 `offMic/managers/muted` 三个读取变体有真实 repository 合同测试。其中 muted 独立构造原先遗漏 metadata，先确认 `q18-display-muted-red.log` 行为失败，再补 joinedAt/online/equippedDecorations；不改禁言规则。第二批新静态测试14项，加这3个合同变体，分别覆盖展示与实际解析。

绘制检查输出：`/Users/kongzheng/Documents/ny/artifacts/product/filled-decisions-20260909/q18-product-art-review.png`（专属三款实际CustomPainter栅格结果，不是设备截图）。一次性生成test已删除。

只包裹现有头像组件，不实现注册的六款 `avatarPresetId` 或修改头像素材映射；后续头像接线可保留这一透明装扮层。
