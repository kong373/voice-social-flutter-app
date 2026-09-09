# 提现金额与日限额交接（2026-09-09）

## 已确认规则

来源：主工作区 `artifacts/product/filled-decisions-20260909/answers.json`
Q15-01，`supplement-answers.json` S10/S11，`final-details-answers.json` T01-T04。

- 最低 100 元，仅整元申请；101.12 元余额可申请 101 元，0.12 元保留。
- 手续费由申请人承担，从申请额中扣；Mock 默认 0%。Live 使用原 fee-rate
  返回的费率、feeMinor、netAmountMinor，不在客户端推导或重算手续费。
- 北京时间自然日每天成功提交一次；驳回后次日新申请，不复活原单。
- 非零后台费率配置及不足 1 分取整尚未完成/未定，本批没有实现新舍入规则。

## 实现与边界

`WithdrawalAmountPolicy` 在 UI、Mock 和 Backend repository 统一拦截低于100、
非整元、NaN/Infinity、溢出值。输入先验证十进制文本，避免极长小数被 double
舍成整数而放行；允许 `100` / `100.00`。金额转分前限制在跨客户端精确整数范围，
这是表示精度保护，不是新产品额度上限。

提现页保留报价步骤和二次确认，明确展示申请金额、实际报价费率、手续费及到账数。
余额不足100禁用提交；超余额或低于服务端最低额不能提交。原页没有全部提现按钮，
本批没有新增按钮或自动处理零头。成功后清除旧报价；HTTP409中文失败保留，不报成功。

Mock 增加可注入 clock 和初始余额用于定向回归；按 `toUtc()+8h` 的日期记录成功提交。
提交日检查与插入/扣减之间没有 await，避免并发占两个名额；客户端校验失败、无效
账户错误不占次数。记录状态更新和导入历史不回算计数，不改变原历史费率/金额。
QA 的历史 seed 只替换记录快照，不实现审核退款/返还流程。Mock 计数是当前仓库实例
内存状态，不宣称持久化或服务端授权；生产日限额仍由 Backend 权威执行。

保留原 fee-rate/apply/history 路由、quote字段、payoutAccountId 校验、人工审核与
providerInvocation=false 边界，以及现有幂等请求ID/在途合并逻辑。未改退款逻辑、
AppGate/Dependencies、青少年、昵称、room/PK，也未改变角色收益入口或收款渠道绑定。

## 测试与范围更新

TDD：初始 4 个用例真实 RED（Mock 3、Backend 1）；极长小数字符串补充回归也先 RED，
修复文本解析后通过。旧1/10/12.34元提现正向样例换为100/101元，不删除权限、分页、
缺失字段、HTTP错误或幂等回归；历史小额/非整元流水保持读取。CM-012保留，页面数不变。

Flutter 3.44.7，最终 74 PASS：

```sh
flutter test --no-pub test/withdrawal_product_policy_test.dart test/backend_commerce_repository_contract_test.dart test/commerce_repository_test.dart test/commerce_live_ui_contract_test.dart test/m22_pages_test.dart test/m4_commerce_ui_support_test.dart
```

另 1 PASS：

```sh
flutter test --no-pub test/first_party_live_mutation_coverage_test.dart --plain-name 'withdrawal preserves first-party authority'
```

覆盖北京时间23:59:59到00:00、驳回仍占日次数、历史不回算、并发一次、失败不占、
101.12/101/.12余款、非法金额无HTTP、服务端非零5%报价确认、HTTP409中文显示。
完整 `flutter analyze --no-pub`：0 issues；`git diff --check`：通过。

仅更新、未执行：M2 FLOW-012 提现部分与 M4 runner 两处100元报价。
未执行设备、DB、Backend测试、golden、构建、完整集成流程；不计未执行项为PASS。
未新增厂商调用、secret、自动打款。渠道绑定、角色入口、后台非零费率和手续费舍入
另批处理；不能据此宣称“全部提现完成”。

## 文件

- `lib/features/commerce/domain/commerce_models.dart`
- `lib/features/commerce/data/mock_commerce_repository.dart`
- `lib/features/commerce/data/backend_commerce_repository.dart`
- `lib/features/commerce/presentation/commerce_earnings_pages.dart`
- `test/withdrawal_product_policy_test.dart`
- `test/backend_commerce_repository_contract_test.dart`
- `test/commerce_live_ui_contract_test.dart`
- `test/commerce_repository_test.dart`
- `test/first_party_live_mutation_coverage_test.dart`（仅提现段）
- `integration_test/m2_4_commerce_flow_test.dart`（仅提现段）
- `integration_test/m4_first_party_live_integration_test.dart`（仅两处报价金额）
- `docs/qa/m2.4-page-coverage.md`（仅CM-012）
- 本交接文档
