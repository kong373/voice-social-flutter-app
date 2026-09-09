# Flutter 房间规则检查点 · 2026-09-09

基线：`e443e796bb78debd3355a09e042b1b8a21290e34`。
分支：`codex/flutter-room-rules-20260909`。
本检查点仅落实已确认规则；主任务转入产品业务核对后不扩展业务范围。

## 已落实

- 创建和保存仅 PUBLIC/PASSWORD。旧 APPROVAL 保留为未选择状态，房主明确选择后才能保存，不自动公开。
- 实际房间失败页、管理页不再提供入房申请入口或发起入房审批读取。历史独立页面/接口类型保留为旧代码，不接入当前导航。
- 普通成员上麦必须申请；OWNER/MANAGER 自由上麦，与 accessMode 无关。管理页上麦申请自动刷新，支持同意和拒绝。
- 仅房主任免管理员。保留管理员不能治理房主或其他管理员的边界。支持安排普通成员到空闲未锁麦位、强制下麦、踢出。
- `hugUserUpMic` 使用 actor sessionId 和 X-Request-Id。setRole/kick/unban 同样要求当前租约。
- 踢出响应严格确认 `kicked=true,banned=true,banMinutes=10,expiresAt`；页面明确显示 10 分钟禁入，40949 不能提前解除。没有永久封禁或不禁入选项。
- CLOSED 房主进入实际房间管理视图，不自动开放，不创建成员身份、租约、RTC/IM 或心跳；退出不发 session POST。
- CLOSED 只允许设置和显式重新开放。保存保持 CLOSED；重新开放后的新 RoomPage 正常 enter 获取新租约。
- CLOSED context 持续只读校验，房主或开放状态变化结束旧视图。OPEN 的租约解析、绑定和续期检查保持原有约束。
- Mock 自由上麦保留 OWNER/MANAGER 角色；Mock 我的房间与配置共用状态，关闭后再次进入为房主管理视图。

## 验证与边界

Flutter 3.44.7，仅定向 test/analyze/format。包括 CLOSED 字段矩阵、零离房 POST、角色与入房模式矩阵、原 OPEN lease/authority/race/RTC 权限回归、配置和管理页面。

已通过的定向批次（有重叠，不汇总为唯一用例数）：

- CLOSED/角色、lease repository、operations contract、管理队列及布局：133 项。
- controller、race、RTC transition、authority sync、lease/background lease：94 项。
- 最终入口与页面检查：video runtime、session end、普通创建入口、CLOSED 管理视图、入房审批导航替换测试：40 项。
- 配置表单与生命周期定向测试：44 项。
- room repository contract 与首轮 CLOSED/角色测试：75 项。
- 修改源码和新增测试定向 analyze、format、`git diff --check` 通过。

未运行全量约 2000 测试；没有设备、build、CI、部署、vendor 配置或生产数据操作。Mock 和单元测试不代替 Backend 联调或系统麦克风授权验收。

## 提交产品核对的现有行为

这些不是本轮新增规则，也不阻碍本轮已确认行为；本轮保持原状，不擅自扩展：

1. `platformModerator` 仍保留原有管理页面权限，但不纳入 OWNER/MANAGER 自由上麦规则；其正式产品角色范围需在完整流程稿中明确。
2. 旧麦位 INVITE 接受/拒绝能力仍存在；新“安排上麦”使用直接座位授权。是否继续对外保留邀请流程，需与产品统一。两者均不能替代设备麦克风授权。
3. 历史独立入房申请页面和接口代码暂留，当前入口已移除；是否另开清理任务删除这些历史兼容代码，未在本轮扩大处理。
4. 上麦申请有效期、重复申请和关房后的旧队列处理遵循现有 Backend 权威状态，本轮未新增客户端自定超时或重试业务规则。

已明确的 10 分钟踢出冷却不属于待决项，不能由产品入口或客户端参数绕过。
