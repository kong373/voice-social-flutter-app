# Q21 房管 PK 入口

依据已填 Q21-01：房主和房间管理员可发起、接受 PK；认输入口仍按后续决定退役。

`RoomPermissionPolicy` 在 interactive 和 snapshot-only 两种传输下都允许当前 owner/moderator 使用 PK。普通用户、平台工作人员身份本身不获得这项权限；关闭房间及现有 controller 的账号、lease、joined 状态检查保持不变。后端当前 canonical owner/manager 授权未改变。

主候选在修改前的两项权限与两项真实更多菜单测试观察到 4 FAIL；仅改两处权限映射后，权限、更多菜单进入 PK 准备页、旧 PK repository、平台管理页面组合 27/27 PASS，定向 analyze 0，格式 0 changes。日志位于根验收目录 `q21-manager-pk-red-20260910.log` 与 `q21-manager-pk-green-20260910.log`。没有操作设备、发起真实 PK、修改后端或厂商。

最终同候选双用户设备验收仍待执行。
