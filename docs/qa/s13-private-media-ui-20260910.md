# S13 私信媒体 UI / 本地受控播放

独立树 `flutter-media-core-20260910`，图片提交 `e22b640` 不 amend。
先接回私信协议 `cb2013f` 为 `5296c2c`、主图片等待夹具 `82e2d88` 为
`de660e9`、Curie Q18 `4d4c9fd` 为 `9b13fb3`。本批代码不修改 Backend、
core/media、shared ApiClient、房间、财务、头像或厂商。

## 用户行为与边界

- 私信图片单张 ≤10,000,000 bytes；录制语音 ≤60,000ms/10,000,000 bytes；
  图库视频 ≤30,000ms/100,000,000 bytes。所有实际长度与本地时长先校验，
  本地探测不是 READY 证明，只有 Backend READY 九字段解析成功后取六字段发消息。
- 图片/视频调用真实系统图库；语音调用真实 AAC-LC/m4a 录音。选完/录完只成为
  草稿，用户先上传，安全检查通过后再明确确认发送。60 秒计时器只停止录音并
  创建待上传草稿，绝不自动上传或发送。取消录音、离开页面、进入后台均停止并清理。
- 媒体消息发送只调用现有 `MediaPrivateMessageRepository.sendPrivateMediaMessage`，
  JSON仍仅 targetUserId/messageType/mediaAssetId；无URL、客户端MIME/SHA或内容声明。
  HTTP留存回执不升级为实时送达/已读，原文本同步、分页与已读单调逻辑保留。
- 私信历史按类型显示图片/语音/视频。点击后仅走配置 Backend 的 UUID 受控 GET，
  binary 流按六字段大小/MIME验证后写自有临时文件，再交给本地播放器。
  没有 networkUrl/setUrl、公开下载链接、播放器 Bearer 或本地HTTP代理。
  音视频仅对自有文件按已核验MIME添加本地扩展名，供系统解码器识别。
- 每次页面访问创建独立 `MediaIdentityScope`；身份代际、收件人或可见性变化撤销
  旧结果受理，停止原生输入/播放并删除自有文件。旧HTTP可能已到服务器，不能声称
  “未发送”。图库覆盖App的系统生命周期只允许完成选择，不触发上传/发送；离页或
  身份变化仍拒绝其迟到结果。普通后台切换取消录音/上传/发送的本次scope。
- 同一 PrivateChatPage 被复用给另一收件人时重置会话视图/输入与读取游标，新增
  conversation epoch 阻止旧文字/媒体异步结果进入新会话。没有重写文本 HTTP 协议。
- 小屏键盘弹出时，媒体面板使用消息区扣除既有说明/输入栏后的实际可用空间，
  最多占其中60%且不超过240px；内部滚动，保留消息区和可操作的确认/上传按钮。
- 动态/工单原权限、数量与恢复行为不变，仅统一“安全检查中/已上传/检查上传状态”
  文案；原测试只将一处 READY 显示断言改为“已上传”，保留主完善的403/ABA真实等待。

## 冷启动恢复小合同（已实现，不是后台outbox）

复用现有 `KeyValueStore`：生产为 `SecureKeyValueStore`，测试使用内存实现。
键为 `s13.private-media.v1.<actor>.<receiver>`。每对账号/收件人最多一个待处理媒体意图；
文字仍可正常使用。未解决的发送不通过“取消”丢弃后换键重发。

保存字段严格白名单：schema、actor、receiver、purpose、实际bytes、本地durationMillis、
allocationKey、requestId、allocationAttempted、putAttempted、sendAttempted、status九字段、
commandMedia六字段。没有Token、设备凭据、文件路径、昵称、文本或媒体原始内容。
schema/类型/身份/用途/状态和引用矛盾均拒绝，读取失败不覆盖旧记录。写入按顺序串行，
每次网络写之前先等待对应“已尝试”标记持久化；存储失败时零网络写。

| 恢复位置 | 明确用户动作与结果 |
| --- | --- |
| allocate响应丢失、尚无ID | 只用原 allocationKey/purpose恢复分配；冷恢复不继续PUT |
| 已有ID、PUT结果未知 | GET原ID；putAttempted永久保留，即使仍ALLOCATED也不再PUT或换文件 |
| UPLOADING / QUARANTINED | 检查状态只GET；用户另点“继续安全检查”才按原ID/current version complete |
| READY、尚未发消息 | 由当前原账号重新确认；仅发送该ID的服务端六字段 |
| 消息发送结果未知 | 显示恢复入口；重新确认后用原 receiver/requestId/commandMedia重放，原账号新scope，不复用旧Future |
| 严格匹配的成功回执 | 删除该意图记录，更新当前会话；失败/409/403/未知不伪成功或清key |
| 换号 / 注销 / ABA | 旧scope永久失效，原账号记录保留但不自动发；其他账号看不到或复用它 |

已选文件只在本次访问内使用。冷启动无法从任意旧picker路径恢复文件，要求重新选择，
不能把新文件塞入旧ID。未知上传记录继续保留供检查，不自动DELETE/reallocate。
没有自动轮询、续传runner、网络恢复监听器或定时发送。

私信字节全部放在 `getTemporaryDirectory()/s13-private-media-v1` 专用根；首次媒体I/O
初始化该根时，只清理先前以 s13-media-/s13-private-record- 命名的自有子目录，不跟随
symlink、不读取/删除图库原件或其他模块目录。journal不保存路径，清理后的旧字节不可
重用。图片批动态/工单RAM journal不在本批改为持久化，不能据此宣称这两个域已冷恢复。

## 公共接口与文件范围

- `PrivateMediaHost.visit(conversation)` → `PrivateMediaVisit`：loaded、intent、pick、
  startRecording/finishRecording、upload(readOnly)、send、discard、dispose/cleanup。
- `PrivateMediaHost.download(reference,scope)` 与 playerFactory：仅受控本地媒体预览。
- `private_media_native.dart`：独立输入/本地播放器接口，生产系统插件适配；假原生实现
  仅在test，不把演示环境标为可发送媒体。
- `private_media_temporary_root.dart`：专用冷启动临时文件回收。
- `private_media_widgets.dart`：媒体工具/状态/明确确认与受控媒体bubble。
- `private_chat_page.dart` / `message_pages.dart`：真实聊天页接线、收件人代际、小屏布局。
- `app_dependencies.dart`：同一 AuthSessionManager 的 userId/generation/Listenable，
  同一个现有 ApiClient、安全store、原生适配factory；不创建新token模型。
- `media_labels.dart` / image_widgets / app_image_media_host：友好文案，无图片业务放宽。
- pubspec及lock、AndroidManifest、Info.plist：插件与权限用途。
- 新测试3文件：s13_private_media_host / native / ui；旧图片测试仅一处文字断言。

## 插件与平台接线

固定 `image_picker 1.2.3`（图片批已加）、`record 7.1.1`、`just_audio 0.10.6`、
`video_player 2.14.0`。已使用维护方/官方文档核对，而非伪选择器：
[image_picker](https://pub.dev/packages/image_picker)、
[图库视频 maxDuration 不生效](https://pub.dev/documentation/image_picker/latest/image_picker/ImagePicker/pickVideo.html)、
[record录音/权限](https://pub.dev/packages/record)、
[just_audio本地文件](https://pub.dev/documentation/just_audio/latest/just_audio/AudioPlayer/setFilePath.html)、
[Flutter video_player](https://pub.dev/packages/video_player)。

iOS扩充已有麦克风/照片用途文案，不增加后台录音或相机能力。Android显式RECORD_AUDIO，
移除继承的READ_MEDIA_VIDEO，继续系统photo picker；无广泛图库访问、前台后台录音服务、
网络明文例外或新摄像头权限。现有Android24/iOS13最低版本不因本批提升。

## 验证证据

固定 `/Users/kongzheng/Documents/ny/.tooling/flutter-3.44.7/bin/flutter`。

最终 `66015` **exit0：17文件316PASS / 0FAIL / 0SKIP**；其中本批40项：
host21、native7、UI12；既有276项为私信协议/文本同步215、图片域/host/page35、
media transport/files/identity与绑定发送26。不是把重跑次数累计为测试数。
随后强化后台清理断言：不仅关闭播放器，还确认实际受控下载文件已删除；并让发送方
媒体气泡沿用原白色文字/按钮，避免紫色气泡内按钮对比不足。最终 UI 单文件 `70475`
**exit0 / 12PASS**（仍属上述40项，不累计），`39636` 最终 analyze exit0 / 0 issue；
14个相关Dart文件format检查0 change；
git diff --check通过。机器结果保留在本树 `build/s13-private-media-final-green-results.json`。
先前失败轮结果为 `build/s13-private-media-final-results.json`，未覆盖伪装为成功。

```sh
/Users/kongzheng/Documents/ny/.tooling/flutter-3.44.7/bin/flutter test --no-pub --concurrency=2 --reporter json test/s13_private_media_host_test.dart test/s13_private_media_native_test.dart test/s13_private_media_ui_test.dart test/private_media_message_contract_test.dart test/private_chat_automatic_sync_test.dart test/backend_message_repository_contract_test.dart test/message_repository_test.dart test/message_request_id_test.dart test/message_first_party_boundary_ui_test.dart test/message_notification_race_ui_test.dart test/s13_image_host_test.dart test/s13_image_domain_contract_test.dart test/s13_image_pages_test.dart test/media_transport_test.dart test/media_files_test.dart test/media_identity_test.dart test/api_client_identity_bound_test.dart
/Users/kongzheng/Documents/ny/.tooling/flutter-3.44.7/bin/flutter analyze --no-pub
git diff --check
```

真实ApiClient/BackendMessageRepository fake HTTP覆盖POST每人单次、持久化先于网络、
未知发送冷host恢复原key/body、未知PUT只GET、分配丢响应原key恢复、401同身份轮换与
换身份拒绝、延迟openUrl ABA零body/零close、延迟成功不清journal、不同收件人隔离、
持久化写失败零POST、损坏journal拒绝覆盖。原生边界测试替换插件平台或系统picker
返回，不使用设备；host重建使用同一序列化store模拟冷恢复，不宣称实际OS进程杀死验证。

- 实际RED `4301` exit1：媒体历史被显示为空文本。
- 实际RED `90197` exit1：复用聊天页仍保留旧收件人/输入；修后同用例与22项原自动同步绿。
- 小屏键盘真实溢出：`60571` exit1，49px overflow；修为按实际剩余空间滚动。
  `35440`后续失败是测试仍点击已进入滚动区的按钮；补真实滚动定位后 `91794` exit0。
- 首次夹具缺必需构造参数、初版真实App测试未覆盖queryChat路由和不恰当pumpAndSettle、
  paused状态下直接断言画面更新均为测试设置问题，不计产品RED或额外通过。
- 17文件首轮 `73556` exit1：316项中315PASS/1小屏FAIL，没有假报全绿。
- 当前没有运行设备、AVD、iOS完整构建、Backend/DB、厂商或全量Flutter测试。

## 尚需主集成后的证据

原生Android/iOS编译、插件注册/Manifest合并、系统权限弹窗/图库进程回收、真实AAC/MP4
解码与音频焦点、真实Backend五段读写链路均NOT_RUN。单元中的文件流与fake原生边界
不是设备录音/播放或正式上线证据。首发仍需主的原生/模拟器窗口及统一验收。

Q18构造已随独立parent接回；Q18与Q02三个repository的AppDependencies身份getter
由主统一树独立wiring后对齐，不混入本媒体提交。Q02 `ab2c005` 已由主接收审查，
本树尚未接回；不预写其参数或自行改ApiClient、commerce/community/account实现。
