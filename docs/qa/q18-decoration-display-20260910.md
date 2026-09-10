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
