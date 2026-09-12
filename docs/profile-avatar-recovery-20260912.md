# 头像超时后的原资产恢复

基线 `1bc3c8deb7ea9cba77940913dc91c75a3f0fa5cd`。

## 真实问题与最小修复

SE3 普通 UI 选择仓库公开图标并保存后，客户端提示媒体请求超时；隔离 Backend `1dbf2ba` 的对应 AVATAR 资产实际已在约 22.64 秒后达到 READY/version3，原头像仍为 moon/revision2。没有把 READY 当作头像绑定成功。

原按钮“重新读取头像设置”调用 `load()`，已加载编辑器直接返回，实际不查询。编辑器关闭重入又把待恢复图片选择覆盖成旧预设。修复：

- `reload()` 显式重读本人头像和原 asset status；只 GET，不新建资产、不重传内容、不自动 complete/bind。
- 页面重入保留同 App 生命周期、同账号草稿中的待恢复图片和错误，不把旧预设当新选择。
- 状态 READY 后仍需用户点击保存才绑定；如果本人投影已确认同一 READY asset/version，清除待提交草稿，避免再次绑定。
- 重读结果通知外层资料页更新显示；身份变化时旧查询仍失效。

没有增加全局请求超时，没有改媒体处理/安全校验/数据库。草稿仍是原有 App 生命周期内存日志，不新增跨进程持久化；新 APK 安装或进程结束后的旧未绑定测试资产不能据此宣称已恢复。

## 验证

固定 Flutter 3.44.7。新增 `profile_avatar_recovery_test.dart` 六个用例，含实际 Panel 按钮、原 asset GET、无写重放、关闭重入、身份丢失迟到查询、已绑定清理和父页回调。

- 原实现真实 2 RED：按钮应 GET1 实际0；重入应无预设选择，实际 moon。
- 补充已绑定清理、父页回调、重入清理各自先 RED，再最小修复。
- 最终 recovery/editor/panel/transport 四文件合计 **17 tests PASS**；scoped analyze 3 targets clean；format/diff-check PASS。
- 独立 Locke 只读审查指出重入已绑定清理需不依赖显式 reload，修复并补行为回归后 APPROVE。

主任务日志在 `/Users/kongzheng/Documents/ny/.m5-private-state/task15-rc-20260911/avatar-recovery-*-20260912.log`，包括 `red`、`saved-red`、`parent-red`、`reopen-bound-red`、`final17-green`。这些是本机行为测试，不冒称新候选已在原生设备通过。原生复测另由设备 owner 记录。

```sh
flutter test --no-pub test/profile_avatar_recovery_test.dart test/profile_avatar_editor_test.dart test/profile_avatar_edit_panel_test.dart test/profile_avatar_transport_test.dart --reporter expanded
flutter analyze --no-pub lib/features/account/profile_avatar/profile_avatar_editor.dart lib/features/account/presentation/profile_avatar_edit_panel.dart test/profile_avatar_recovery_test.dart
git diff --check
```
