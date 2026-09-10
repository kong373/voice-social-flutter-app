# Q02：实名重提与入会引导

基线：`4c0bd66e7a8af56099198768849ded8e437b2e29`。仅修改实名页与公会申请入口，不改 AppDeps、pubspec、commerce、媒体或全局注册协议。

## 最小合同

- 第一方人工实名的 `REJECTED` 与未提交状态均可填写并重新提交；`PENDING` 不重复展示提交表单，结果仍以现有服务端审核为准。
- 入会按钮先读取现有账户合规状态。未实名或被拒绝引导至现有实名页；审核中、状态不可用、账号受限或青少年锁定均不发申请 POST。
- 已实名用户仍须主动点击入会。返回实名页后不自动申请；当前提交未结束时重复点击不产生第二次 POST。
- 服务端 `40368` 表示当前实名资格不满足，显示实名引导；`40369` 表示已知未满18岁，显示服务端拒绝信息，不伪装成功、不自动重试。
- 入会预检、导航与写入响应均绑定本次 session 和 identity generation；账号退出/切换/ABA 后丢弃迟到结果。实名页绑定首次加载身份代次，旧表单不能跨代次重提，异步结果不能重新装载其他账号状态。
- 已知年龄资格由 Backend 入会边界裁决。本批没有建立全局18岁准入或新的年龄采集协议，也没有完成第三方实名接入。

## 定向验证

- 新增 `test/guild_join_real_name_test.dart`：12项，覆盖拒绝后重提、三种实名不满足状态零申请、正常仅一次申请、未知/受限/青少年锁定、预检 ABA、实名表单 ABA，以及服务端撤实名/年龄拒绝。
- 行为 RED：`build/q02-flutter-red-v2.log` 11项中9失败；更早的 `q02-flutter-red.log` 混有 HTTP fixture 异步等待超时，不把这些超时算作产品 RED。
- 独立表单 ABA RED：`build/q02-form-aba-red.log`，预期提交次数0，实际1；修复后纳入最终 GREEN。
- `build/q02-final-focused-green.log`：54 PASS，包含新增12项及 `real_name_vendor_gate_test`、`community_presentation_contract_test`、`community_write_reliability_test`、`backend_community_repository_contract_test`、`community_repository_test`、`backend_account_compliance_permissions_test`。
- `build/q02-final-analyze.log`：本次4个 Dart 文件 analyze 0；`git diff --check` 通过。
- 测试使用真实 Widget 与 BackendCommunityRepository HTTP 解析路径，HTTP transport/合规状态为受控测试替身。未运行设备、SDK网络、厂商或全量回归，不将这些结果标作设备 E2E。
