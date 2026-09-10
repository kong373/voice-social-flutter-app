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
