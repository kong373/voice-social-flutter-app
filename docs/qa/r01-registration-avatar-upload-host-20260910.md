# R01 注册头像上传 host / anonymous transport

基线 `2f9b911321e76cb34df29941149c3df97c4a693a`，独立分支 `codex/registration-avatar-upload-20260910`。本批不包含 AuthController、AuthRepo、RegistrationPage、AppDependencies 或最终注册提交接线。

合同来源：`backend-registration-avatar-20260910/docs/product-r01-registration-avatar-20260910.md` 与根 artifacts 下 `registration-avatar-integration-plan-20260910.md`。同时核对了实际 `RegistrationAvatarController` / `RegistrationAvatarRegistry` / `RegistrationAvatarUploadService`：QUARANTINED 已有 bytes，但 MIME/duration 仍可为 null；ALLOCATED 的 complete 返回 40983，不能当作 READY。

## 主流程接线 API

生产文件 `lib/features/account/registration_avatar/registration_avatar_host.dart`：

```dart
final host = RegistrationAvatarHost(
  context: context,
  transport: ApiRegistrationAvatarTransport(apiClient),
  store: secureKeyValueStore,
  picker: imageSelection,
  temporaryParent: temporaryParent,
);
```

`RegistrationAvatarUploadHost` 是同一类型的别名。主 AuthController factory 持有 host 到该注册流程退出；页面只订阅 ChangeNotifier，不在页面卸载时 dispose 注册流程的 host。复用现有 `ImageSelection` / `NativeImageSelection`，要求单图选择，无新插件。

`RegistrationAvatarContext` 必填 `phone/smsCode/challengeId/deviceId/clientId/expiresAt/requireCurrent/changes`。expiry 必须 UTC；主 callback 需同时验证捕获的 session generation、同一个 pending challenge 对象、registrationRequired。`changes` 使用同一身份源 Listenable。手机号相同不能代替 generation，失效的 context 不复活；不得伪造 App userId / MediaIdentityScope。

| 方法或 getter | 冻结含义 |
| --- | --- |
| `choose()` | Future<void>，选择一图、实际长度校验、复制到本 App 独有临时子目录、持久化命令；不发 HTTP。已有 allocationAttempted 禁止替换文件 |
| `restore()` | 只读并校验 secure journal；不发 HTTP，不把缓存 READY 导出为当前 proof |
| `upload()` | 显式首次 allocate → 至多一次 PUT → complete；已有尝试先核对原状态，冷恢复没有原副本不能 PUT |
| `recover()` / `complete()` | 显式恢复：未知 allocation 重放原 key/body/cap，再 GET 同 UUID，按当前状态 complete；从不 PUT，也不换 key/资产 |
| `discard()` | 使此 context/host 失效，停止旧操作、清自有临时文件和内存预览；保留 journal，不 DELETE 后端、不清未知命令。选 preset 不应调用；主在退出注册/重新获取验证码时使用 |
| `busy` / `error` | 单 flight 与当前 context 的友好错误；调用方仍需 await/catch 方法异常。没有自动重试或后台 runner |
| `hasSelection` | 当前 context 存在已选/已恢复命令，即使 status 为 null 也为 true |
| `hasPendingUpload` | 当前已有命令但尚无权威 READY，且不是已拒绝/已绑定终态；缓存 READY 未 GET 核验时仍待恢复 |
| `status` / `sourceUnavailable` | 当前九字段状态 / 原文件已不可恢复。ALLOCATED 且冷恢复无源时提示重新获取验证码，不以新文件续传旧资产 |
| `previewBytes` | ≤10,000,000 bytes 的只读 Uint8List 内存预览；上传清理文件后仍可显示，context 失效或 dispose 清引用。绝不持久化；冷恢复为 null，页面提示核验上传状态 |
| `ready` | 仅同 context、未过期、当前服务端确认 READY、持久化成功且不 busy 时返回 `RegistrationAvatarReady(assetId,version,requestId,capability)` |
| `cleanup` | 等待本 host 自有文件回收。dispose 不删除系统 picker 原文件 |

主将 ready 映射 `RegistrationAvatarChoice.uploaded` 和最终注册 Proof；沿用同 requestId/capability，不输出实际 capability，不用于日志、URL、Widget key 或诊断。最终注册失败/未知结果的原 intent 归 Auth 层，本 host 不发注册请求或全权 Token。

## 持久化、恢复与安全边界

- **必须注入真实 secure KeyValueStore**；该接口本身不能判断存储实现是否安全。本批不接普通 preferences，也不修改 AppDependencies。存储记录有 cap、key、challenge/device/client、原 UTC expiry、size、allocationAttempted、putAttempted、原 UUID/version/status；不存 Token、明文短信码、文件路径或图片内容。context 绑定摘要包含原手机号/短信码/expiry，不能移给另一挑战。
- capability 来自 Random.secure 的 32 字节，编码 canonical 43 位 base64url；header/UUID/phone/code 有明确长度和字符检查。后端响应错误脱敏，不回显其 message 中可能出现的 capability。
- selection / allocation / PUT 前逐次 await 持久化，写失败不发送对应动作。按同 store 串行 IO，新 host 的 restore 等待旧写落盘；旧 context 写等待后失效不会进入网络。
- `putAttempted` 必须先落盘。即使进程在落盘后、真正发送前死亡，也保守禁止重 PUT；GET 仍 ALLOCATED 或 complete 冲突时保留记录，不伪造成功。
- 分配响应丢失时可恢复同 key 的 allocation；PUT/complete 响应丢失时 GET 原 UUID。服务端返回的 UUID、bytes、状态顺序、version、原 expiry 必须一致/单调，不能延长原 TTL。
- 冷恢复只持久化意图，不保存或自动接管 picker 文件。若旧 PUT 已完成可 GET/complete 原资产；若没有上传且原副本已丢失，须退出该注册流程并重新获取验证码后选图。不会偷偷重分配来绕过未知结果。
- 每个异步阶段检查注册 context；openUrl 等待、body 流等待、响应等待、picker 和存储写等待的失效均拒绝旧结果。销毁/失效只回收本 App 新建临时子目录，系统 picker 文件始终保留。

## HTTP 边界

ApiClient 仅新增一行 part 注册，既有 JSON/登录/401 行为不变。专用 transport 使用配置 Backend 固定 `/app-register-api/media/v1/avatar-uploads` 路径；POST allocate、GET UUID、PUT UUID/content?expectedVersion、POST UUID/complete。不会接受响应 URL。

全部请求不读 App authorizationProvider / requestHeadersProvider，不带 Authorization 或 Content-Encoding，不做 401 refresh，不跟随重定向。四个注册 header 来源于不可变 context/原命令。PUT 分块检查实际长度和十进制 10MB 限制；JSON/错误响应仍使用 ApiClient 原 maximumResponseBytes（默认 2MB），不因图片上限而放宽。

状态严格九字段、AVATAR、图片 MIME、精确整数 bytes/version/duration；不提交客户端 URL、SHA、MIME 声明。预览不是服务端格式或扫描通过证明。

## 文件与实际验证

新增生产：

- `lib/features/account/registration_avatar/registration_avatar_models.dart`
- `lib/features/account/registration_avatar/registration_avatar_host.dart`
- `lib/features/account/registration_avatar/registration_avatar_transport_adapter.dart`
- `lib/core/media/registration_avatar_transport.dart`

既有生产仅 `lib/core/network/api_client.dart` 新增一行 part。新增测试为 `test/registration_avatar_host_test.dart`、`test/registration_avatar_transport_test.dart`、`test/support/registration_avatar_fakes.dart`。没有修改旧测试、pubspec/lockfile、既有媒体 purpose 或身份模型。

实际 Flutter **3.44.7**：

- `r01-avatar-quarantine-red.log`：handle 47284 exit 1，2 个真实失败证明旧草稿拒绝实际 QUARANTINED 部分元数据，修正后 host 22/22 PASS（56037 exit 0）。
- `r01-avatar-host-transport-tests.log`：86180 exit 1，1 个真实失败为非 canonical cap 的解码异常未统一脱敏；另外 2 个失败是 fake stream teardown 超时，不当作产品 RED。修正及 fixture 修正后 82257 exit 0，48/48 PASS。
- 最终 `r01-avatar-host-associated-regression.log`：**29078 terminal exit 0，104/104 PASS，0 失败/跳过**；本批 host 26 + transport 24 = 50，既有 ApiClient / identity / media transport / upload coordinator / image host 54。新增 durable-write 失效/冷重建原命令、实际 10MB 预览边界；body/picker 竞态用明确进入信号，不靠 sleep 声称已开始。
- 全仓 `flutter analyze --no-pub`：No issues found。仅修改 Dart 文件 format 检查 0 changed；`git diff --check` 通过。`pub get --enforce-lockfile` 成功，pubspec/lockfile 未变。

日志均在根 `/Users/kongzheng/Documents/ny/artifacts/product/filled-decisions-20260909/`，保留 RED，未纳入源码提交。命令：

```sh
/Users/kongzheng/Documents/ny/.tooling/flutter-3.44.7/bin/flutter test --no-pub \
  test/registration_avatar_host_test.dart test/registration_avatar_transport_test.dart \
  test/api_client_test.dart test/api_client_identity_bound_test.dart \
  test/media_transport_test.dart test/media_upload_coordinator_test.dart test/s13_image_host_test.dart
/Users/kongzheng/Documents/ny/.tooling/flutter-3.44.7/bin/flutter analyze --no-pub
```

**NOT_RUN / 主接线验收**：主 Auth/UI 组合编译与注册交互、真实 secure store 冷进程重建、Android/iOS 原生 build/系统 picker 权限和 Activity 回收、真实 Backend allocate→PUT→complete→最终注册归属→正式头像 controlled read。本批已有真实本机 HttpServer wire 检查和 fake HTTP 状态/身份/恢复测试，不等价于真实 Backend 或整条注册流程验收。未运行全量 Flutter tests、设备、DB、厂商或部署。
