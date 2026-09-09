# Q08-02 / Q08-03 房管资料与密码编辑

Base: `044db2fd873475d70cdd4e89d70ccda14fc91c44`
Branch: `codex/manager-profile-ui-20260909`

## 范围

房间工具菜单为后端 room snapshot 的 owner / moderator 展示“房间资料”，普通成员不展示。进入编辑页仍须重新读取后端编辑 projection，不把路由参数或菜单可见性当授权。topic 的原 canEdit 使用同一 editRoom policy；未改 topic operations repository、entry、gift、mic、资金或分享路径。

`GET /app-api/rooms/editable-profile?roomId=...` 按后端
`backend-room-manager-profile-20260909/docs/product-room-manager-profile-20260909.md`
冻结字段解析：roomId、roomCode、roomName、topic、topicTitle、welcomeText、accessMode、autoLockMic、hallVisible、status、version、passwordConfigured、canControlLifecycle。

- 必须有精确 roomId、真实 bool、非负 int version、PUBLIC/PASSWORD、OPEN/CLOSED；不按字符串或数字猜 bool，不补造 canEdit、sessionId 或 media URL。
- canonical owner 的 CLOSED 编辑允许无 lease，projection 的 canControlLifecycle=true 控制生命周期 UI；manager 必须 OPEN 且本地拥有同房间当前 lease，flag=false 时隐藏关闭、重开、hall 与 autoLock 控件，并从 PATCH body 省略后两字段。
- `fetchOwnedRoom(s)` 保持 owner-only 的分页/身份/话题检查；owner 保存后的校验仍走 owned authority。原 owned contract 测试改为直接测试 fetchOwnedRoom，保留原字段与负向断言。
- 现有本地 mock/手工 owner fixture 保持 RoomConfiguration 构造器的 owner 默认值；live parser 不使用该默认值，缺少 canControlLifecycle 必须失败。live existing-room 保存还必须有读取时捕获的 editGeneration。
- 房名、公告/话题、欢迎语可编辑。沿用现有 4 位数字密码表单；密码留空保留已有密码，选择 PUBLIC 清除密码，输入不日志/持久化/URL，关闭自动填充、建议和输入法学习。cover/background 未提供保存控件，仍依赖未完成的 media workflow。

## 身份、lease 与未知结果

- AppDependencies 仅把已存在的 roomLeaseBinding 注入 lifecycle repository。
- 读取时捕获 binding generation；manager 额外捕获 exact sessionId。旧读响应、旧草稿、旧 lease 或身份 ABA 不得在新代次下提交。sessionId 只在 PATCH body 中发送，不从 GET 响应推导。
- EditRoomPage 使用页面 epoch、session identity generation 与 repository generation 隔离换号、换房、离页、晚加载和晚保存；换号清空编辑权限与密码。保存成功也不会 pop 覆盖在编辑页之上的其他路由。
- 超时、网络/协议/服务端未知结果及 40901/40902 保留原 RoomConfiguration 和原 request-id/body，锁住输入，仅允许显式重试原请求。没有换新 session 自动重试。40936/40937/撤权直接结束当前编辑；仅 40945 进入版本冲突对照，不把一般 conflict 当作换版本重提授权。
- 新增 `ApiClient.patchBoundToIdentity`（15 行薄封装）复用现有 `_request(requireIdentity:)`，在连接等待后、写 body 前、401 恢复前后检查同一个身份/lease 断言；不修改原 patch/post 的全局行为。同身份刷新继续复用原 key/body。
- owner close/reopen 使用已存在的 postBoundToIdentity，业务 payload 和权限规则不变。

## 本机验证

SDK: `/Users/kongzheng/fvm/versions/3.44.7/bin/flutter`。

- Projection 先 RED：6 项旧实现误走 owned route，后转绿。
- PATCH 先 RED：4 FAIL / 1 PASS，复现连接等待、401 切号、刷新切号、重试连接切号错误返回成功；薄封装修复后 5 PASS。同身份刷新保持成功，原 POST 的 5 项身份绑定回归也通过。
- 最终以下 15 文件 **129 PASS**；全量 analyze **0**。

```sh
flutter test --no-pub \
  test/manager_room_profile_entry_test.dart \
  test/manager_room_profile_test.dart \
  test/manager_room_profile_widget_test.dart \
  test/backend_room_lifecycle_repository_contract_test.dart \
  test/backend_room_lifecycle_repository_test.dart \
  test/room_lifecycle_repository_test.dart \
  test/room_lifecycle_closed_config_test.dart \
  test/room_permission_policy_test.dart \
  test/room_configuration_form_test.dart \
  test/room_operations_pages_test.dart \
  test/room_closed_owner_view_test.dart \
  test/owned_room_selection_test.dart \
  test/api_client_patch_identity_test.dart \
  test/api_client_identity_bound_test.dart \
  test/api_client_test.dart
flutter analyze --no-pub
```

本批未跑设备、DB 或 vendor，不把 mock admission 当作后端 RBAC 证据；后端 MySQL/Spot 结果由主线管理。本地提交，不 push。

## 合并注意

video_runtime_room_page 仅 tools 的资料入口及其可见性接线；没有 entry/gift/mic diff。room_permission_policy 只扩大 editRoom 到 moderator，不扩大 closeRoom。AppDependencies 仅 lifecycle 的 shared binding 注入。额外网络文件只新增 PATCH 薄封装，主线按此范围审查。
