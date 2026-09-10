# Q08-02 Flutter 房间封面 / 背景

实现基线 `48e8d0a`；前置礼物四素材映射独立提交 `3286169`，本批不修改赠送、动画、房间治理或注册。对应 Backend `052f2bc` 的 `docs/product-room-profile-images-20260910.md`。

## 真实接线

- 复用已锁定 image_picker 和 AppImageMediaHost，仅新增 `ROOM_COVER` / `ROOM_BACKGROUND`。每次一个图片，10,000,000 bytes，READY 六字段只接受 JPEG/PNG/WebP、durationMillis=0；不接受 URL、额外字段、错误用途或截断后的数字。
- 房主 / 当前房管的既有编辑页增加选择、上传、检查原上传状态、保留原图、显式清除。未 READY 禁止保存。Mock 不上传、不伪造媒体绑定成功。iOS 原用途句只追加“房间封面和背景”，不改头像/私信表述、签名、插件、Pod 或权限项。
- 分配只发送 `{purpose}` 与原 key，不发送 roomId 或 session。保存只把变更项映射为 `coverAssetId` / `backgroundAssetId`：省略保留、null 清除、UUID 替换；不发送六字段、URL 或客户端 hash。房间 expectedVersion 与资产 version 独立。房管继续发送当前编辑时冻结的 exact sessionId，房主 CLOSED 编辑不虚构 lease，也不重开房。
- 首页（现行 runtime 与旧 HomePage）、搜索、收藏 / 自有列表、公会关联房间、PK 房间封面均使用同一个受控组件；背景仅在实际房间视图展示，保留原暗色遮罩。PK / 公会仅增加可选字段投影和图片，不改任何权限、请求动作或状态机。Backend 当前未在 PK battleSide 发 descriptor 时保留缺省图，不自行用 URL 补齐。
- GET 固定到配置 Backend 的 `/app-api/media/v1/assets/{UUID}/content`，沿现有鉴权、精确 MIME / 长度、bounded stream、禁止 redirect 的传输。组件持有自己的临时副本；不把受控 UUID 当公开地址，不读取旧 URL 回退。403 / 下载错误提供明确重试。背景 GET 不触发入房、续租、RTC、IM。

## 身份、租约及未知结果

- `MediaIdentityScope` 新增可选 context 校验，默认行为不变；房间编辑将其绑定到原 auth generation、room generation 和 exact lease。RoomLeaseBinding 仅增加变更通知，未改变 lease 有效性或 Mic 权限。
- 账号切换 / ABA、离房或换 lease、页面卸载立即失效旧 scope，abort 旧 I/O，清理本 App 自有文件与 FileImage 缓存。晚到响应不会重新显示图片，也不归入新身份。临时清理不删除系统 picker 文件，不 DELETE 服务端资产。
- 上传与本地图片源分开：分配丢响应只重放原分配 key；已知 UUID 查询同一资产；PUT 至多一次。失败 / 卸载后的原文件已清理时不可拿新文件续传原 UUID。可以取消本次选择并保留原 key / UUID 为只读检查项，不自动重新分配。
- 图片保存未知后，repository 在同一身份 / room generation 内保留完整原命令，页面重建显示“重试原保存请求”，冻结选择，人工重试复用原 X-Request-Id 与字节相同 body。换 lease 不用旧 key 配新 session。明确版本冲突 40945 先权威回读，再由用户确认新的版本 / key；不自动提交。
- 本批是现有 AppImageMediaHost 的 App 进程内 journal；未增加房间图片 cold-start 持久化。进程退出后重新读取当前权威房间配置，不声称可恢复已遗失的上传 source/key。该限制不等同于伪造上传失败或自动 PUT 重试。

## 回归与未运行边界

新增合同 / HTTP / widget 文件：

- `room_image_contract_test.dart`：两种 purpose、大小 / 数量规则，初始真实 2 RED。
- `room_image_repository_test.dart`：六字段、缺省 / null / 替换、错误 descriptor、exact manager lease、CLOSED owner、原 key / body / 幂等未知恢复。
- `room_image_host_test.dart`：真实字节流、丢分配 / PUT 响应、原 ID 恢复、离房 / ABA 中止及源清理。
- `room_image_pages_test.dart`：真实 picker fake + ApiClient / HTTP stream + 页面到 PATCH；未知卸载重建、40945 人工确认、权限读取失败重试、文件缓存清理、CLOSED 实际背景不建 lease / RTC。该测试真实发现装饰渐变挡住重试点击，已用 IgnorePointer 修复；未放宽成功或网络断言。
- `backend_discovery_room_media_contract_test.dart` / `discovery_room_cover_cards_test.dart`：首页 / 搜索 / 收藏 / owned，各字段独立、malformed 拒绝、refresh 替换 / 清除与身份晚结果。
- `guild_pk_room_media_contract_test.dart` / `guild_pk_room_cover_cards_test.dart`：独立公会 / PK 模型正确透传，缺字段保持旧显示。

旧测试无删除 / 跳过。`manager_room_profile_widget_test` 仅把原“无媒体 setters”用例名称明确为 Mock 场景；原权限 / lease / 幂等断言完整保留，真实媒体路径由新增 HTTP 页面回归覆盖。`ios_host_contract_test` 只增加新用途文本断言，不触签名 contract。

最终验收使用固定 Flutter 3.44.7；`pub get --enforce-lockfile` 无 lock 变化。详细命令、数量和终态见本文件追加验证节及根 artifacts 日志。早期卡片子批 101 PASS 使用 3.44.8，保留为历史诊断，不计固定版本最终门禁。

未运行：设备 / 模拟器、native build、实际 Backend 上传 / GET 联调、DB、processor / vendor。需主集成 Backend 新 purpose 与 processor 后，再安排真机照片权限、选图、房主 / 房管替换、旧引用撤销与离房清缓存验收；不将 widget fake 的受控 HTTP 成功称为线上闭环通过。

## 最终本机验证

固定二进制 `/Users/kongzheng/Documents/ny/.tooling/flutter-3.44.7/bin/flutter`，生成 package_config 同样指向该 3.44.7，不采用子批 3.44.8 配置；pub lock 未变。

38 个相关文件共 536 项首轮 **535 PASS / 1 FAIL**（handle `31955`，exit 1）；新增图片页面 7 项已全 PASS。唯一失败是原 `backend_room_authority_projection_test` 的 `_Api` 未实现既有 `postBoundToIdentity`，继而旧成功 fixture 缺少现行 `selfMuted/forcedMuted/legacyMuted/version`。本批只更新此假对象并保持旧 request body、session、IM cache、权限断言；未改麦克风生产逻辑。另在该文件增加真实 room authority descriptor 投影和错误用途两个测试。修正后该文件 **70/70 PASS**（handle `67168`，exit 0）。两轮合并覆盖 **538 个不同测试**，已无未解决失败；未把重复执行计为新增测试。

日志都在 `/Users/kongzheng/Documents/ny/artifacts/product/filled-decisions-20260909/`：`room-images-final-targeted.log` 保留首轮失败；`room-images-authority-final.log` 保留旧静音 receipt 缺字段失败；最终类回归 `room-images-authority-green.log`。页面 r1–r5 原日志均保留：有界等待/滚动修正未降低最终断言。最后全部改动的 `room-images-analyze-final.log` 为全仓 analyze 0（handle `57416`，exit 0）；38 个 changed Dart 文件 format 0 changed / exit 0（handle `1196`）、Info.plist plutil 和 diff 检查 PASS。

```sh
flutter test --no-pub --concurrency=2 --reporter expanded \
  test/room_image_contract_test.dart \
  test/room_image_repository_test.dart \
  test/room_image_host_test.dart \
  test/room_image_pages_test.dart \
  test/backend_discovery_room_media_contract_test.dart \
  test/discovery_room_cover_cards_test.dart \
  test/guild_pk_room_media_contract_test.dart \
  test/guild_pk_room_cover_cards_test.dart \
  test/discovery_presentation_race_test.dart \
  test/video_runtime_home_race_test.dart \
  test/search_results_pagination_test.dart \
  test/saved_rooms_create_entry_test.dart \
  test/community_presentation_contract_test.dart \
  test/manager_room_profile_test.dart \
  test/manager_room_profile_widget_test.dart \
  test/manager_room_profile_entry_test.dart \
  test/backend_room_repository_contract_test.dart \
  test/backend_room_authority_projection_test.dart \
  test/backend_room_lifecycle_repository_contract_test.dart \
  test/backend_room_lifecycle_repository_test.dart \
  test/room_lifecycle_closed_config_test.dart \
  test/backend_room_lease_repository_contract_test.dart \
  test/room_lease_controller_test.dart \
  test/app_dependencies_room_lease_test.dart \
  test/platform_staff_none_contract_test.dart \
  test/platform_staff_room_test.dart \
  test/platform_room_widget_test.dart \
  test/backend_room_pk_repository_contract_test.dart \
  test/backend_room_pk_f3a_contract_test.dart \
  test/room_pk_repository_test.dart \
  test/media_models_test.dart \
  test/media_identity_test.dart \
  test/media_files_test.dart \
  test/media_transport_test.dart \
  test/s13_image_host_test.dart \
  test/s13_image_pages_test.dart \
  test/video_runtime_ui_test.dart \
  test/ios_host_contract_test.dart
flutter test --no-pub --reporter expanded test/backend_room_authority_projection_test.dart
flutter analyze --no-pub
git diff --check
```
