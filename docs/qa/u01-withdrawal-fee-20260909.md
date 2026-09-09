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

## P1 账号隔离追加修复

### 发送身份与401恢复补丁（87466ed之后）

87466ed仅限制仓储/页面异步交付，普通ApiClient.post仍可能在openUrl之后读取B token；因此该提交不能独立视作P1完整修复。本补丁新增窄用途 `ApiClient.postBoundToIdentity` 并仅接入提现apply。原 `postWithoutUnauthorizedRecovery` 虽提前捕获token，但完全关闭401恢复，不能满足同身份正常刷新重试，因此不直接复用。

绑定调用在任何await前检查调用方身份代际并捕获Authorization；openUrl完成后再次校验，身份变化则abort尚未发送的request；写body前再检查。401恢复前、恢复await后、每次递归重试前及重试openUrl后均检查原代际。同身份允许采用刷新后的token，原request id/body不变；跨身份抛protocol错误，仓储原账号未知key/payload不删除。普通get/post和其他请求的策略未更改。

新增 `test/api_client_identity_bound_test.dart` 用可变化的真实Authorization和委托HttpClient延迟openUrl，而非仅延迟响应：初次连接切B零请求；401响应前切B不调用恢复；恢复期间切B不重试；同身份A-old→A-new刷新两次请求key/body严格相同；刷新成功后重试连接期间切B不发送第二次请求。

最终 `flutter analyze --no-pub` handle33695 exit0，No issues found；此前52201有一个测试空Map类型推断warning，已显式类型修正。

固定Flutter3.44.7。RED handle3075 exit1：上述前三项真实失败（原post错误返回成功），同身份刷新对照1PASS；51495是缺少clientType夹具参数导致的编译失败，不算产品RED。GREEN handle20905 exit0：`flutter test --no-pub test/api_client_identity_bound_test.dart test/api_client_test.dart test/backend_commerce_repository_contract_test.dart test/commerce_live_ui_contract_test.dart --reporter expanded`，77PASS（含A返回原key/raw body及页面隔离回归）。补充重试连接切身份后，专属测试handle2539 exit0，5PASS。最终analyze及git diff --check通过。未执行DB、设备、部署或主树操作。

AppDependencies 将现有 AuthSessionManager 的 userId、identityGeneration 和通知接入 commerce；不改变认证与刷新语义。未决申请及原 key 按账号保存，in-flight Future 按账号和代际隔离。退出后不可见，B 不能获取 A 的内容或 Future；A 回来复用原 key 和逐字相同的 HTTP payload，不因旧请求晚到成功或错误清掉 A 的未知状态。恢复仍只覆盖同一 repository 生命周期，不增加磁盘持久化。

提现页面在身份切换时清理可见金额、账户、报价及历史并关闭确认弹窗；各异步完成点核对代际，旧成功不能显示为 B 成功。同代际通知不清理正在填写的内容。账户预检 Future 与可用标识同样按身份代际隔离。

TDD：backend_commerce_repository_contract_test 的 `U01 identity switch isolates pending futures and restores A exact retry` 在 handle84419 exit1 真实复现退出后 pending 非空；实现后21117 exit0，1PASS。测试断言 A/B 请求不同 key、A 恢复原 key/raw body、旧 A Future 返回身份失效而非成功。新增 UI `U01 account switch hides A intent and ignores late A success` 独立模拟晚到成功，断言 B 页面空金额且无成功提示、回 A 恢复101及禁编辑，并验证同代际通知保留输入。

固定 Flutter3.44.7，沿用上方五文件命令：handle58945 exit0，81PASS。最后同代际通知边界补充后，单独 `flutter test --no-pub test/commerce_live_ui_contract_test.dart --reporter expanded` handle93301 exit0，9PASS。过程中7228/1439因新增断言误放到旧 spy 导致编译/分析失败，已移到正确身份 spy；不计为产品 RED。此前86607仅两个 mounted lint，已显式守卫。最终 `flutter analyze --no-pub` handle17400 exit0，No issues found。未运行 DB、设备、Backend/Admin 或部署。
