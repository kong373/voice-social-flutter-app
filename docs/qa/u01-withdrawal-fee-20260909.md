# U01/Q15 Flutter 提现手续费

基线 `2e5685d401905e1ad81c8e896a6a92d79a7dac6c`，独立分支 `codex/flutter-withdrawal-fee-20260909`。完整依据 artifacts/product/filled-decisions-20260909/withdrawal-fee-implementation-contract.md。未修改Backend/Admin、未使用DB/设备/厂商、未push或merge。

## 变更契约

- `commerce_models.dart`：WithdrawalQuote必填整数feePolicyVersion及feeRateBasisPoints，费率范围0..9999；BigInt计算CEILING_FEN，校验金额、费、到账关系。`applyWithdrawal`必填confirmedQuote，不能隐式报价。新增ConfirmedWithdrawal供未决申请恢复。
- `backend_commerce_repository.dart`：严格解析服务端整数版本/bps/金额，校验可选rounding。apply发送用户确认的expectedFeePolicyVersion/expectedFeeMinor/expectedNetAmountMinor，三个字段连同金额/账户参与幂等intent。响应fee/net必须匹配原确认值。未知响应保留同key/同payload；未决期间禁止切成另一笔；成功重试后清理未决状态。没有新增报价GET。
- `mock_commerce_repository.dart`：默认0%，可显式更新测试政策（同值不升版本），按整数CEILING_FEN报价；旧版本或错金额拒绝且不冻结/占用当天次数。apply只使用显式确认报价，不自行重新报价。
- `commerce_earnings_pages.dart`：弹窗前捕获金额/账户/报价并禁用修改，确认后仅发该快照。确定的409清掉报价，重新计算后必须再确认，不自动提交。未知结果锁定原intent，页面重建从同一repository恢复，避免以新报价代替旧未决写；未决账户不再显示可变picker。
- 全部接口调用方、测试假对象及M4集成源码同步；未运行设备集成。报价构造器由浮点费率改为整数bps，旧`.feeRate`展示getter保持。

最低100元/整元/北京时间每日一次保留；提现历史amount/fee/net仍读旧快照。恢复范围为同一repository生命周期，未增加磁盘存储，不宣称进程终止后可恢复请求key。

## 回归与证据

- backend_commerce_repository_contract_test：10100*50=>51/net10049；缺失/字符串/浮点/负版本、浮点bps、10000bps、错误CEIL与金额/rounding拒绝。未知500重试原版本，原始HTTP body字符串逐字相等、同X-Request-Id，只一次账户查询、零报价请求；期间另一笔申请拒绝。
- withdrawal_product_policy_test：旧报价和错金额拒绝、余额/冻结不变，同值政策不升版本，成功按51分冻结101元；原最低/整元/每日/并发回归保留。
- commerce_live_ui_contract_test：确认弹窗冻结输入/账户，外部改变输入不能替换已确认101元；后台费率变化409后重新报价显示99.99，必须再次点击确认；页面重建复用原报价且只冻结一次。
- commerce_repository_test、first_party_live_mutation_coverage_test：保留原账本/历史/权限等断言，补显式报价及新POST字段；旧非零测试费率按各场景保留，不统一改零或跳过。

固定工具 `/Users/kongzheng/Documents/ny/.tooling/flutter-3.44.7/bin/flutter`，Flutter3.44.7/Dart3.12.2。

```sh
/Users/kongzheng/Documents/ny/.tooling/flutter-3.44.7/bin/flutter test --no-pub \
  test/backend_commerce_repository_contract_test.dart \
  test/withdrawal_product_policy_test.dart \
  test/commerce_repository_test.dart \
  test/commerce_live_ui_contract_test.dart \
  test/first_party_live_mutation_coverage_test.dart --reporter expanded
/Users/kongzheng/Documents/ny/.tooling/flutter-3.44.7/bin/flutter analyze --no-pub
```

最终handle59800 exit0：79/79 PASS。analyze83837 exit0：No issues found。git diff --check通过。

中间失败如实记录：10932有5个失败（旧payload断言、无效金额测试helper溢出、弹窗spinner未停止）；2045剩1个UI假对象未启用账户picker。修正后8313 UI7PASS、35510整批79PASS；后续整数bps模型收紧及未决picker提示改动以最终59800/83837重新验证。未执行全量、真实提现或Backend门禁。
