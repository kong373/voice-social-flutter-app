# S20 / Q02-04 青少年全局锁定交接

## 决策与范围

已读取主工作区 `artifacts/product/filled-decisions-20260909/answers.json`
Q02-04 与 `supplement-answers.json` S20。用户确认 PIN 是用户自己设置的密码，
不是固定 `1`。开启后固定锁定页，不能操作 App 其他功能，无忘记密码。

基线为 worker `7771642`，先将主任务 `fbf3741` cherry-pick 为 `7bc3f44`。
本批不修改主任务拥有的 MockAccountComplianceRepository、
account_compliance_repository_test.dart，也不修改房间、Mic、PK、discovery、
质量诊断、Backend 或金融数据。

## 实现及保留边界

- AppGate 在启动恢复、登录、前台恢复和 compliance revision 后检查服务端状态。
  账号限制/不可用及强制更新优先；普通未启用用户可进入 MainShell。
- YouthModePage 只接受四位数字。成功开启立即通过现有 AuthNavigationBoundary
  替换 Navigator；已有业务页、根弹框和其 mounted 上下文被销毁，不做 pop 动画。
- YouthModeLockPage 不提供返回/忘记密码。错误 PIN、异常 disable 结果、状态复核失败
  不放行；正确 disable 后还须 status 确认。PIN 不缓存到依赖或日志。
- 请求以身份代际与 preflight 请求代际隔离，旧账号结果及旧未锁定状态不得复活页面。
- AppDependencies 跟踪其创建的房间控制器，锁定时调用既有 dispose，保留该实现的
  RTC/重连/租约/消息队列失效保护；阻止锁定期新建控制器。MainShell 原有 dispose 不改。
- IM coordinator 增加可恢复的访问暂停，注销 SDK、取消续期并隔离旧请求；锁定期
  AuthController 的 ensure/renew 不能重连，确认解锁后恢复。未更改消息协议或业务 API。
- Apple IAP 已结交易恢复及 query/reconcile 不变。客户端锁定不是后端所有业务 API
  的全面授权拦截；该服务端范围由主任务评估，本批未验证或声称完成。
- Debug QA/demo 专用宿主仍用于页面隔离测试，不代表生产 AppGate 授权路径。

## 页面与旧测试映射

AC-012 保留，YouthModeLockPage 是同一页面的全局锁定状态，不新增/删除 page ID。
manifest 分母仍为 60 个有效页、9 个 REMOVED_BY_PRODUCT；catalog 与范围文档同步。

| 旧范围/断言 | 本批处理 |
| --- | --- |
| commerce_repository_test：开启后非充值前台功能可用 | REMOVED_BY_PRODUCT；改为全局前台拒绝，保留未启用与充值 guard 断言 |
| m2_4_commerce_flow_test：只阻止新充值，仍可直接访问钱包 | REMOVED_BY_PRODUCT；保留独立充值 guard，不将删除断言计 PASS |
| m2_4_offline_emulator_test FLOW-011：开启后返回并操作充值/钱包 | REMOVED_BY_PRODUCT；改为锁定、错 PIN、正确 PIN，再查询钱包历史 |
| m2_4_test_support：直接 AppGate 未挂导航边界 | 改挂已有 AuthNavigationBoundary，使用稳定 gate key 和 revision；仍绕过 debug console |

设备 FLOW-011 仅更新源码及静态分析，未执行，不计 PASS，也未更新截图。

## 定向验证

Flutter 3.44.7 / Dart 3.12.2，命令均带 `--no-pub`。

TDD RED：初始两个全局锁定/旧路由移除用例在实现前均失败（缺失锁定页）。
实现后修正测试自身的 maybePop 返回值语义与完整生命周期状态序列；
保留不可返回、旧上下文销毁和 RTC/IM 退出断言。

第一组 88 PASS（当时青年锁定 9 个用例）：

```sh
flutter test --no-pub test/youth_global_lock_test.dart test/live_gate_contract_test.dart test/auth_navigation_test.dart test/tencent_im_session_test.dart test/commerce_repository_test.dart test/apple_iap_app_dependencies_test.dart test/apple_iap_purchase_coordinator_test.dart
```

补充组 44 PASS（青年锁定最终 11 个用例，包含新补乱序状态与根弹框用例）：

```sh
flutter test --no-pub test/youth_global_lock_test.dart test/tencent_im_session_test.dart test/m22_pages_test.dart test/m24_pages_test.dart test/page_manifest_test.dart
```

两组存在重复，不相加。覆盖自设/错误/固定 1 PIN、启动恢复、前台恢复、未知状态、
丢失开启响应、旧状态乱序、账号失效后的晚到解锁、导航/弹框移除、旧 async mounted
保护、房间释放、IM 暂停/恢复、原账号/强制更新门禁和支付恢复。

`flutter analyze --no-pub`：No issues found。`git diff --check`：通过。
未运行全量测试、集成设备测试、golden、构建、服务器、DB、厂商联调；未 push。

## 精确变更文件

- `lib/app/app_dependencies.dart`
- `lib/app/app_gate.dart`
- `lib/features/account/compliance/presentation/account_status_pages.dart`
- `lib/features/account/compliance/presentation/youth_mode_lock_page.dart`
- `lib/features/im/application/im_session_coordinator.dart`
- `lib/features/commerce/domain/commerce_models.dart`
- `lib/features/commerce/presentation/commerce_catalog_pages.dart`
- `lib/debug/qa_console/qa_page_catalog.dart`
- `test/youth_global_lock_test.dart`
- `test/commerce_repository_test.dart`
- `integration_test/m2_4_commerce_flow_test.dart`
- `integration_test/m2_4_offline_emulator_test.dart`
- `integration_test/m2_4_test_support.dart`
- `docs/design/m3.3-oxygen-page-blueprints-v2.md`
- `docs/m2.2-no-vendor-business.md`
- `docs/qa/m2.4-page-coverage.md`
- `docs/qa/m2.4-android-emulator-test-plan.md`
- 本交接文件
