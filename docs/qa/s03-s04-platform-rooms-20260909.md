# S03/S04 Flutter 平台房间能力

基线 `562338106178f28ead207f03bd458ffb5aef313e`，独立分支 `codex/flutter-platform-staff-20260909`。按本轮冻结 Q09/S03/S04 DTO 实现；Backend/Admin/V57 不在本提交内。

## 边界与文件

- `lib/features/room/domain/room_models.dart`、`room_permission_policy.dart`：独立 platformStaff/canControlRoomLifecycle/closedRoomAccess；真实 room role 不变。staff 只增加生命周期，不能凭平台绑定获得编辑、成员治理、PK、麦位管理。真实 owner/manager 原权限保留。
- `lib/features/room/data/backend_room_repository.dart`：严格闭房 staff 身份、状态、无 session/lease、无 vendor 能力校验；legacy ownerClosedAccess 仍限真实 owner，缺新字段旧 owner 兼容，其他人不推导平台权限。入房免密码直接不传 password，由服务端判定绑定。
- `lib/features/room/application/room_controller.dart`：所有闭房管理视图不启动 lease、RTC、IM、公屏刷新；重连仅权威 GET；离开/销毁后迟到闭房 enter 不发送普通 exit 补偿。实际入房才切换共享 IM，闭房管理不退出另一个 IM 房间。正常 RTC/IM 清理回归保留。
- `lib/features/room/data/platform_room_repository.dart`：authority/list 严格解析；只通过真实 authority 展示目录，不用 JWT role。独立 account→pending 与 identity tuple→future，close/reopen 精确 roomId/expectedVersion。使用现有 postBoundToIdentity，不修改 shared ApiClient。未知操作保留原 body/key，不允许替换目标、版本或动作。
- `lib/features/room/presentation/platform_rooms_page.dart`：私有目录、搜索分页、清数据/晚结果 fence、独立生命周期确认按钮。新动作确认期间冻结 room/version/action；未知重试亦须确认。首次明确 403/404/409 不算成功；未知后的拒绝不抹掉原 key。
- `lib/features/room/presentation/video_runtime_room_page.dart`：staff 闭房只显示平台管理说明、重新开放和退出，绝不进入 EditRoomPage。开放中的 staff 另有明确关闭按钮。成功刷新权威视图再退出，返回目录后刷新；再次入房必须用户选房，不自动连接音频。
- `lib/features/shell/video_runtime_pages.dart`：“我的”仅增加 authority-gated 入口。
- `lib/core/network/backend_route_catalog.dart`：只新增 platformRoomAuthority/platformRoomList 两条 GET 路径。
- `lib/app/app_dependencies.dart`：仅注入平台 repository、现有 session userId/identityGeneration/Listenable。Mock 默认无绑定，明确拒绝平台目录/写操作，不伪造 live 成功。

RoomWriteGuard 自身不查 owner，但既有 lifecycle.fetchRoom 依赖“我的房间”。平台写使用独立精确目标 journal，不复用 owner 配置查询；旧 owner 编辑功能未修改。未知 journal 为 repository 生命周期内内存保存，不声称跨进程/应用重启持久恢复。

## 专属测试

- `test/platform_staff_room_test.dart`：staff 密码闭房无 password 请求、无 lease/transport；17 种矛盾字段拒绝；撤销结束视图；迟到闭房 enter 无补偿 exit；staff 与真实 listener/owner/manager 权限矩阵。
- `test/platform_room_repository_test.dart`：真实 loopback HTTP authority/list、严格 DTO、close/reopen 回执、403/404/409、未知后冲突、A-B-A 原 key/字节 body、旧成功 fence、延迟 openUrl 时真实 Authorization 变化、401 换号及同身份刷新。
- `test/platform_room_widget_test.dart`：私有入口、旧页撤权清数据、晚目录结果、staff 闭房无 owner 编辑/公屏/麦位、确认期间版本冻结、未知 remount/防重点击、确认期间换号零写、迟到成功不进入 B。

未删除/禁用/降低任何旧测试断言。

## 实际验证记录

固定 `/Users/kongzheng/Documents/ny/.tooling/flutter-3.44.7/bin/flutter`；全部 `test --no-pub`。仅 loopback HTTP 与 Flutter 测试替身，无真实 Backend/设备/厂商。

- RED `74542` exit 1：首次 staff 闭房合法响应被旧 owner-only parser 拒绝。
- `94474` exit 0：staff 首条与旧 owner rules，共 19 PASS。
- 中间 `16419` exit 1：35 项中首次 403 的 pending 处理失败；生产补齐 forbidden 分类后修复。不是后端失败。
- `75884` exit 0：早期 widget 7 PASS。
- `75410` exit 0：12 类 236 PASS：platform_room_repository、platform_staff_room、room_closed_owner_rules、room_closed_owner_view、room_permission_policy、room_role_mic_policy、room_lifecycle_closed_config、room_controller_race、room_lease_controller、backend_room_authority_projection、backend_room_repository_contract、video_runtime_account_profile_race。
- `29407` exit 0：补闭房无补偿/IM 切换边界后，8 类 105 PASS：三个 platform 新测试 + room_closed_owner_rules、room_closed_owner_view、room_controller_race、tencent_im_avchat_room、room_controller_rtc_transition。
- `1097` exit 0：新增 exact close / unknown→409 后，三个专属类 49 PASS。
- 最终 `19980` exit 0：三个专属类 49 PASS；含最终回调身份 fence 与分页整数校验。
- analyze 中间 `28005` exit 1：三处新测试 dynamic lint；改为明确 Map 类型。`21737` exit 0：No issues found。
- 最终 analyze `74524` exit 0：No issues found；`git diff --check` exit 0。仅格式化本轮改动 Dart 文件。

复现专属门禁：

```sh
/Users/kongzheng/Documents/ny/.tooling/flutter-3.44.7/bin/flutter test --no-pub test/platform_room_repository_test.dart test/platform_room_widget_test.dart test/platform_staff_room_test.dart
/Users/kongzheng/Documents/ny/.tooling/flutter-3.44.7/bin/flutter analyze --no-pub
git diff --check
```

后端实际联调、DB、设备/音频/厂商验收、全仓测试、部署全部 NOT_RUN。主流程需在集成 Backend 冻结 DTO 后进行真实绑定/撤销/权限与设备验收；此提交不宣称已上线。

## 追加修复：首次 staff 闭房 memberRole=NONE

主审确认 Backend 在首次访问 CLOSED 时没有 room_member 行，因此 enter 与 roomContext 合法返回 `memberRole=NONE`。560d00d 的 MEMBER/MANAGER 白名单拒绝该真实契约，原 49 PASS 不能证明首次访问场景可用。

本次只修改 `lib/features/room/data/backend_room_repository.dart`：NONE 仅在 `_isStaffClosedAccess` 完整校验通过时可接受，保持原 viewer/owner、state/status、平台授权、无 session/lease、无 provider/公屏/礼物约束。OPEN 的平台角色白名单不增加 NONE；不改 Backend，不造 MEMBER/成员行，不改 owner 原闭房规则。

新增 `test/platform_staff_none_contract_test.dart`，通过真实 loopback HTTP JSON 覆盖首次 NONE enter+GET 刷新、无治理/lease/RTC/IM、无显式/补偿 exit，19 类矛盾字段在 enter/context 双路径拒绝，以及合法 OPEN lease 下 NONE 拒绝、MEMBER 接受。原测试不删、不替换断言。

- RED `94250` exit 1：`NONE closed staff enters and refreshes` 预期 joined 实际 failed。
- GREEN `53599` exit 0：新增专属 23 PASS。
- `68758` exit 0：下列 8 类 212 PASS；不是与前批结果累加的总数。
- analyze `75034` exit 0：No issues found。`git diff --check` exit 0。

```sh
/Users/kongzheng/Documents/ny/.tooling/flutter-3.44.7/bin/flutter test --no-pub test/platform_staff_none_contract_test.dart test/platform_staff_room_test.dart test/platform_room_repository_test.dart test/platform_room_widget_test.dart test/room_closed_owner_rules_test.dart test/room_closed_owner_view_test.dart test/backend_room_authority_projection_test.dart test/backend_room_repository_contract_test.dart
/Users/kongzheng/Documents/ny/.tooling/flutter-3.44.7/bin/flutter analyze --no-pub
```

独立追加 commit，parent560d00d，不 amend。Backend 实际联调/DB/设备/厂商/部署仍 NOT_RUN。

## 再追加：legacy NULL room_code 的空串 DTO

Backend directory 将历史 NULL room_code 安全序列化为空串。Flutter 只移除空串拒绝条件，仍要求 roomCode 是 String；模型原样保留空串，不填造 code。目录仅在展示时使用 `ID <roomId>`，请求目标仍为真实 roomId。生产修改限 `platform_room_repository.dart`、`platform_rooms_page.dart`；对应两个既有专属测试文件各加一例。

- RED `15602` exit 1：空 code 导致整页 parser 失败，页面也未显示 ID 回退标识（2 项真实失败）。
- GREEN `17189` exit 0：platform_room_repository、platform_room_widget、platform_staff_none_contract、platform_staff_room 四类 74 PASS，含 NONE 与 legacy 空 code。
- analyze `2165` exit 0：No issues found；`git diff --check` exit 0。

追加在 NONE 修复 `880b65289a16108ff5f12b13f2742db9ba015234` 之后，不 amend。仍未运行 Backend/DB/设备/厂商测试，未部署。
