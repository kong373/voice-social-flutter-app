# R01 正式头像受控显示

## 基线与范围

- Worktree: `/Users/kongzheng/Documents/ny/.worktrees/flutter-user-avatar-display-20260910`
- Branch: `codex/user-avatar-display-20260910`
- Base: `e67b9bce56e26ff8b0b4591bb564e5f2d9889383`，实际主 RC `voice-social-flutter-unified-rc` 当时 HEAD，已含 strict `UserAvatarDescriptor` 和装扮覆盖层。
- Backend 合同：`backend-registration-avatar-20260910/docs/product-r01-registration-avatar-20260910.md`。
- 不改 Auth、RegistrationPage、AppDependencies、pubspec、注册上传、Backend、厂商或原生插件。`api_client.dart` 仅增加一个 part 声明。

## 受控读取与显示接口

```dart
// ApiClient extension; no MediaReference/purpose is fabricated.
Future<Uint8List> readUserAvatarContent({
  required String assetId,
  required int version,
  required MediaIdentityScope identity,
});

UserAvatarView({
  required UserAvatarDescriptor? avatar,
  required int userId,
  required Widget fallback,
  double size = 44,
  bool enabled = true,
});
```

`UserAvatarView` 从现有 `AppDependencyScope` 取得 `sessionManager`、`privateMediaHost.api`。只借用同一 App ApiClient，不调用 host 的上传、播放器、访问记录或临时文件方法，不需要新构造参数。

- PRESET 复用六个精确 ID 的 `PresetAvatarView`，不发 HTTP。
- UPLOADED 仅固定鉴权 GET `/app-api/media/v1/assets/{uuid}/content`。UUID 不作 URL；descriptor version 用于显示请求代次隔离，不添加未约定的 version query 或伪造 MIME/bytes/purpose。
- 配置地址拒绝 userInfo/query/fragment。关闭 redirect，只传 App Bearer、公开 Client 标识和随机请求 ID，不透传任意 provider headers、Cookie 或 registration capability。
- 200 响应必须 `Cache-Control: private, no-store`，不得 public；MIME 精确 JPEG/PNG/WEBP，Content-Encoding 必须不存在。Content-Length 若存在必须与实际流一致，未知长度仍按实际流限制 `0 < bytes <= 10_000_000`。
- 401 只允许同一身份代次的一次既有 refresh；403、重定向、坏协议不重放。每个异步边界检查 scope；账号变化立即 abort，晚打开的连接不写凭据。
- `ui.ImageDescriptor`/codec 实际解码，按显示大小降采样到最长边最多 512 像素；仅显示首帧。持有并显式释放本组件的 image/codec/buffer，不用 Flutter 全局 ImageCache，不落磁盘。
- mounted view 在账号/generation ABA 后永久失效；新账号必须从新授权页面创建视图。换目标/版本、禁用、离页会清旧图并取消 scope。旧 null 保持原 fallback；非空非法 descriptor 在 DTO 层拒绝，读取/解码失败只显示中性不可用，不回退外链。

## 核心证据

固定 Flutter `/Users/kongzheng/fvm/versions/3.44.7/bin/flutter`；offline pub get，无 pubspec/lock 修改。

日志目录：`/Users/kongzheng/Documents/ny/artifacts/product/filled-decisions-20260909/`。

- `r01-avatar-transport-red.log`：先缺新方法编译 RED；`r01-avatar-transport-green.log`：22 PASS。
- `r01-avatar-view-red.log`：先缺组件编译 RED。组件最终 8 项覆盖真实 PNG 解码、零 ImageCache、注销释放、ABA 晚成功/错误、版本变更及 pending read 离页。
- 这是本机 fake HTTP/unit/widget 证据，不是设备、真实注册上传、厂商或生产可见性验证。GET 的最终可见性和授权仍由服务端当前状态裁定。

## 正式读投影与实际入口

| 冻结字段 | App 读模型 | 本批实际显示入口 |
| --- | --- | --- |
| 本人/公主页 `avatar` | `LiveCurrentUser.avatar`、`SocialUser.avatar` | 主“我的”、个人中心、公主页、既有资料编辑页头像 |
| room seats/member `avatar` | `BackendMicSeat`、`MicSeat`、`RoomMember` | 房间顶部成员头像、麦位、在线成员页 |
| `conversations.list[].avatar` | `ConversationSummary.avatar` | 会话列表、搜索、聊天页对方头像；公主页打开聊天保留 descriptor |
| `history.list[].senderAvatar/receiverAvatar`、send 当前回读同名字段 | `ChatMessage.senderAvatar/receiverAvatar` | 按真实 sender 显示本人/对方气泡头像；copyWith 保留，不写入发送 intent/body |

- 本人/公主页仅 ACTIVE 投影消费正式头像。MicSeat 换 occupant、失去在线/占用状态清除旧 descriptor；普通音频状态更新保留。装扮仍由原外层 `EquippedDecorationView` 渲染，原权限/期限/lease 判断未放宽。
- `chatUserInfo.avatar` 的后端字段已由主冻结，但当前 App repository 没有独立消费 chatUserInfo 的方法；本批不添加重复请求，气泡直接用 history/send 当前读投影。历史缺字段保留原气泡；新字段不从任意 URL 推导。
- 消息列表原读仅比较 actorId，已由行为 RED 证实 A→B→A 晚成功会新建旧头像。增加页面 viewer generation、依赖实例、读取序号检查及同步清除；搜索也绑定同一 viewer。失效页面提示重新进入，不让旧 Future 成为新账号数据。不改消息发送、已读或私信媒体流程。

## 当前明确未接边界

- 主正在集成 Hubble 的消息 Backend 投影；Flutter parser/mock 通过不代表该 Backend 已部署。
- 本批检查到通知 list/detail 只有 `actorHeadImgUrl`，尚未收到通知 strict descriptor 的冻结字段名。因此系统/互动通知暂保留原类型图标，**不宣称 postComment/follow 通知已支持正式头像**，也不把该旧 URL 当作 UPLOADED reference。待主冻结字段后可追加同边界适配。
- 不扩大到关注/访客/黑名单页面、动态作者头像、Auth/注册上传；没有为这些未冻结的投影猜字段。
- 未跑 DB、device、vendor、Android/iOS build；未读 Secret/.env，未改主树或 push。

## 最终验证与修复证据

- `r01-avatar-entry-red.log`：五个真实页面原本没有 `PresetAvatarView` 的行为 RED。
- `r01-avatar-conversation-aba-red2.log`：消息列表 ABA 晚成功实际显示旧头像 RED；晚错误未泄漏。`r01-avatar-entry-identity-green.log`：9 PASS。
- `r01-avatar-message-fields-red.log`：新增 sender/receiver 严格字段先缺 getter 编译 RED；随后 14 DTO + 10 入口 24 PASS。
- 新增实际公主页 UPLOADED fake HTTP→真实解码→注销销毁，以及已打开搜索页的 ABA 测试。`r01-avatar-entry-final-green.log`：22 PASS（8 组件 + 12 入口 + 2 原房间头像）。
- `r01-avatar-targeted-final.log`：22 个相关测试文件 **504 PASS，0 fail**，涵盖头像、social/room/message 既有合同、私信媒体合同、装扮、private chat/member 自动刷新。不是项目全量测试。
- `r01-avatar-analyze-final.log`：full analyze **0 issue**。改动 Dart format、`git diff --check` 通过。
- 保留失败日志：早期分页 fixture 缺 pageNum/list、fake headers 类型及假时钟/真实流切换错误已修正；不计产品行为 RED。旧 `room_avatar_contract_test.dart` 缺现有 entry decoration 所需 AppDependencyScope，仅补 fixture/销毁，保留“空头像不伪造图片”的原断言。
- 实际图片入口测试最终按 `UserAvatarView` 子树定位 RawImage，避免把页面背景图误当头像。analyze 的异步 context 提示以显式 mounted guard 修复，未关闭 lint。

代码拆为受控 transport/widget 和读投影/实际入口两个顺序提交；仅 cherry-pick 本批提交，不 merge 整个旧基线分支。
