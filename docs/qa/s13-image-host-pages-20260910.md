# S13 App 图片 host、动态与工单接线

基线：`2b334c718393dabdcc0f30d275d2ca29624c9d69`；分支 `codex/flutter-media-core-20260910`。本批仅在原独立树追加，既有 `core/media/*`、`core/network/api_client.dart` 没有修改。

## 合同与实现边界

域合同以 `/Users/kongzheng/Documents/ny/.worktrees/backend-media-domain-bindings-20260910/docs/product-s13-domain-bindings-20260910.md` 为准。

- 动态 `publish`：文字最多 1000，可纯图，图片最多 9。附件请求仅 `mediaAssetIds`，由当前账号 READY 资产产生；旧 URL/images 写仍拒绝。读模型 `media` 严格解析六字段；缺字段仅兼容无附件历史，显式 null/错误 purpose/额外 URL/非整数 bytes/重复 ID/超量失败关闭。
- 工单创建 `saveSugggestion`、补充 `/{id}/replies`：文字仍必填，图片每次最多 3；创建文字 UI 沿用原 200 上限，仓库及服务端最大 1000，补充 UI 最大 1000。创建图片属于 CREATED event，补充属于相应 MESSAGE event。历史 `eventId:null` 仅允许无图片，不伪造历史 ID。
- 上传 status 仍使用 core 九字段；域模型仍使用六字段。应用不提交 URL、SHA、MIME、bytes 或 duration 作为域绑定依据。
- 动态/工单 POST 使用现有 `postBoundToIdentity`，发送前、401 恢复及响应后检查同一个 userId/generation；原 text-only 调用兼容。图片能力不依赖旧 `objectStorageStatus`。
- Mock 保持文字行为，明确不上传图片，不返回伪造 READY/媒体发布成功。

## App 级 host 与恢复

`AppDependencies.imageMediaHost` 由当前 `sessionManager.session.userId`、`identityGeneration` 和同一 Listenable 构造；token/refresh 仍由已有 ApiClient 负责。真实 picker 为 `NativeImageSelection`，临时父目录来自 `getTemporaryDirectory()`。

| 接口 | 契约 |
| --- | --- |
| `AppImageMediaHost.identity / scope` | 当前账号与代际；refresh 不改变身份，退出/ABA 永久失效旧 scope |
| `draft(key, purpose)` | App 生命周期内按账号 + 功能 key 保留草稿；本批只接受 DYNAMIC_IMAGE/SUPPORT_IMAGE |
| `pick(draft)` | 系统多图选择；再次验证实际数量和每文件 10,000,000 bytes；只复制到本 App 新建临时子目录 |
| `upload(draft, image)` | 用户显式首次推进 allocate→PUT→complete；单文件单 key、单次 PUT；固定 ID/版本/大小/expiry 校验 |
| `upload(..., recover:true)` | 已知 ID 只 GET 原 ID；分配响应丢失则显式重放原 allocate key/purpose，随后停止，不盲 PUT |
| `ImageDraft.retainedUploads` | 用户取消未知上传后清本机副本，保留原 key/ID 的只读恢复区；不 DELETE、不自动重分配、不进入新内容附件 |
| `submit / acknowledge` | 固定域请求 key + 内容/有序 IDs；未决/409 保留原命令，明确 400 校验拒绝才解除；回执消费后清正常草稿，不清未知取消记录 |
| `download(reference, scope)` | 配置 Backend 固定 UUID content 路径，复用受控流式 transport 和 app-owned 临时文件；不读取响应外链 |
| `cleanup` | 可等待本 host 发起的文件清理完成，用于宿主收尾/测试，不吞掉清理失败证据 |

关闭页面只移除 `ImagePageBinding` 监听，不销毁 App 草稿/未知命令。退出/换号立即失效旧 scope、清理本机副本；原账号重新进入使用新代际、新 Future，保留原非 secret key/资产 ID/域命令。旧代际的晚响应不能成为当前 receipt。若原文件已清理，恢复只查询原资产，不能替换新文件续传。

原 core `MediaUploadCoordinator` 与 scope 绑定，不能复活已失效 scope。本 host 用现有 core transport/models/files 保留独立的账号命令检查点，没有放宽原 core，也不把旧文件搬给新 scope。QUARANTINED/UPLOADING 仅由用户显式“重新检查就绪”推进，没有自动 runner。

**持久化边界：本批是 App 进程内 journal，不是进程重启恢复。** 不写 token 或 picker 源文件路径。Android Activity/进程丢失结果会读取 `retrieveLostData`，但没有可信原 actor 归属时要求重新选择，不自动上传。进程被杀后的原命令 journal/临时孤儿回收尚未实现，不声称通过。

## 页面与权限

- `PublishDynamicPage`、`HelpCenterPage`、`SupportTicketPage` 使用 App 草稿；锁住未知提交的字段/附件，显式同 key/body 恢复。纯图必须全部 READY 才能提交，工单图片不能代替必填文字。
- `ControlledImages` 仅显示服务端六字段引用；点击后受控 GET，校验类型/精确字节数后用 app-owned 文件解码。403、协议错误、格式不可解码均可见；身份变化清除文件与解码缓存，不显示晚结果。工单详情回读失败隐藏旧详情/图片并提供重试。
- 动态 feed/detail 新读请求有代际 fence，换号清当前列表，旧响应不再写缓存/页面。
- 不涉及私信、麦位、房管、礼物、充值、Backend 或 Admin。`scope/download` 可给后续私信复用；图片 draft/picker 不能直接用于语音/视频。本批没有录制/视频选择/音视频播放器。

## 官方插件与平台配置

锁定 `image_picker: 1.2.3`、`path_provider: 2.1.6`，并提交 lockfile。官方文档：[image_picker](https://pub.dev/packages/image_picker)、[pickMultiImage](https://pub.dev/documentation/image_picker/latest/image_picker/ImagePicker/pickMultiImage.html)、[path_provider 2.1.6](https://pub.dev/packages/path_provider/versions/2.1.6)。

使用系统 gallery selector，`requestFullMetadata:false`，不缩放/伪造 MIME；实际数量/大小由 host 再验证。Android 24+/iOS 13+ 满足当前项目最低版本。Android 不添加全相册访问权限，并在 app manifest 移除旧权限插件贡献的 READ_MEDIA_IMAGES/READ_MEDIA_VISUAL_USER_SELECTED/READ_EXTERNAL_STORAGE；不改变麦克风等权限。iOS 保留 NSPhotoLibraryUsageDescription 并说明动态/工单选图用途；不增加拍摄/录音入口。插件失活恢复只在 Android 调用；照片拒绝/受限有明确提示。

## 文件范围

新增生产：

- `lib/features/media/app_image_media_host.dart`
- `lib/features/media/native_image_selection.dart`
- `lib/features/media/image_domain_contract.dart`
- `lib/features/media/image_widgets.dart`

接线/模型/仓库：

- `lib/app/app_dependencies.dart`
- `lib/features/discovery/dynamic/domain/dynamic_models.dart`
- `lib/features/discovery/dynamic/data/backend_dynamic_repository.dart`
- `lib/features/discovery/dynamic/data/mock_dynamic_repository.dart`
- `lib/features/discovery/dynamic/presentation/dynamic_pages.dart`
- `lib/features/social/domain/social_models.dart`
- `lib/features/social/data/backend_social_repository.dart`
- `lib/features/social/data/mock_social_repository.dart`
- `lib/features/social/presentation/social_pages.dart`（part 文件 import）
- `lib/features/social/presentation/social_support_pages.dart`
- `pubspec.yaml`、`pubspec.lock`、`ios/Runner/Info.plist`、`android/app/src/main/AndroidManifest.xml`

新增测试：`test/s13_image_domain_contract_test.dart`（真实本机 HttpServer + 发送/401 fake transport）、`test/s13_image_host_test.dart`（状态/文件/ABA）、`test/s13_image_pages_test.dart`（真实仓库接线的 widget 行为，含真实 PNG 解码）。

旧用例映射：`backend_dynamic_repository_contract_test` 只把“全部图片能力关闭”改为 asset 能力开放，原 local:// URL 禁止断言保留；`m23_pages_test` 仅更新演示环境文案/空内容校验文案。两工单页面测试 fake 签名增加可选 media/requestId 与 nullable host，原权限、失败、键盘、分页、补充和状态断言保留。没有 Disabled、跳过或降低覆盖率。

## 验证证据

- RED handle `12271` exit 1：合法纯图 content 为空被旧 parser 拒绝。
- RED handle `14740` exit 1：不同内容在 in-flight/receipt 分支错误获得原 Future/receipt；修复为先核对 fingerprint 再取缓存。
- RED handle `26347` exit 1：取消未知上传原实现直接拒绝；修复为只清本机副本、保留只读原资产记录。
- 中间 widget 调试 `7172`、`47639` 在 FakeAsync 文件清理阶段被人工中止，**不是 PASS**（工具返回退出码 0 也不计）。最终测试在 widget scope 内实际等待原生文件清理并断言完成。
- 最终 handle `45809` 终态 **exit 0，184 PASS / 0 FAIL / 0 SKIP**。其中新增 domain 15、host 12、widget 8，共 **35**；既有定向回归 149。JSON 报告：`build/s13-image-host-final-results.json`（本地构建产物，未纳入源码提交）。
- `flutter analyze --no-pub` handle `58528` 终态 exit 0，No issues found；21 个修改相关 Dart 文件 format 检查 exit 0、0 changed；`git diff --check` exit 0。
- 没有运行全仓测试、设备、模拟器、DB 或厂商调用。

```sh
/Users/kongzheng/Documents/ny/.tooling/flutter-3.44.7/bin/flutter test --no-pub --concurrency=4 --file-reporter=json:build/s13-image-host-final-results.json \
  test/s13_image_domain_contract_test.dart test/s13_image_host_test.dart test/s13_image_pages_test.dart \
  test/backend_dynamic_repository_contract_test.dart test/backend_social_repository_contract_test.dart \
  test/backend_dynamic_repository_test.dart test/dynamic_repository_test.dart test/dynamic_presentation_reliability_test.dart \
  test/dynamic_detail_short_refresh_test.dart test/dynamic_time_format_test.dart test/dynamic_request_id_test.dart \
  test/support_ticket_reply_page_test.dart test/support_ticket_history_page_test.dart test/m23_pages_test.dart \
  test/media_transport_test.dart test/media_files_test.dart test/media_identity_test.dart test/api_client_identity_bound_test.dart
/Users/kongzheng/Documents/ny/.tooling/flutter-3.44.7/bin/flutter analyze --no-pub
```

## 仍需主流程证据

Android/iOS 主 App 原生编译、插件注册/manifest 合并检查、模拟器系统选图（含权限拒绝/取消/Activity 回收）均 NOT_RUN；没有真实 Backend allocate→PUT→complete→domain→GET 联调。主已报告 Backend GET 可用，不替代本批 App 联调证据。正式验收还需确认原生 HEIC 选择/服务端格式拒绝提示、边界数量/大小、后台恢复及图片权限撤销后读取。尚未进行普通设备/厂商验收，也未扩建 runner。
