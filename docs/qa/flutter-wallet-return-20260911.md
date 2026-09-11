# WALLET-01 支付宝结果返回钱包刷新验证

验证基线：`12fb52aeb62b425e7aa48523870ceebba0d91131`

验证分支：`codex/flutter-wallet-return-20260911`

验证日期：2026-09-11

## 结论

基线存在真实 Widget 导航缺陷。完整路径在支付宝结果页确认到账后，点击一次“返回钱包”不会显示最新礼物币余额：结果页通过 `pushReplacement` 替换提交页，使目录页等待的 push 提前完成，目录原有刷新发生在权威结果确认之前。

最小修复后，结果页改为普通 `push`；结果页返回后提交页自动退回充值目录，目录页原有的返回后 `_load` 才会执行。没有修改 `CommerceIdentityFence`、repository、ApiClient、adapter、AppDependencies、价格、原生 SDK、IAP coordinator 或房间代码。

## 真实 Widget 路径证据

WALLET-01 使用 `AppDependencies.mock()` 内部已经连接的 `MockCommerceRepository` 与 `MockCommerceCatalogRepository`，未替换页面导航：

```text
CommerceHubPage
  → RechargeCatalogPage
  → PaymentSubmissionPage（选支付宝）
  → PaymentResultPage
  → 点击一次“返回钱包”
  → PaymentSubmissionPage 自动退回
  → RechargeCatalogPage
```

初始 hub 和充值目录显示 `1680` 礼物币。结果页第一次自动查询仍为“服务端确认中”；点击真实“刷新订单状态”完成 fake 的第二次权威查询，fixture 余额变为 `2360`。该操作是为了产生权威订单结果，不是钱包刷新。随后只点击一次结果页的“返回钱包”，测试确认：

- 结果页和提交页均已离开，实际当前页面是 `RechargeCatalogPage`；
- 页面栈没有使用 `pushReplacement`，页面 pop 事件为结果页一次、提交页自动返回一次；
- 目录页 `_continue` 的返回后 `_load` 调用 `commerceRepository.fetchWalletSummary()`，并显示新余额 `2360`；
- 没有点击钱包顶部“刷新”，没有手动 pop 多级路由。

## 执行记录

基线业务 RED：`wallet-01-baseline.log` 中的 `retry_exit=1` 记录了完整路径在返回目录后找不到新余额 `2360` 的失败。此前的第一次失败是目录按钮未滚入测试视口的测试假红，已通过滚动到真实按钮排除。

修复后 GREEN：`wallet-01-green.log` 中的 `retry_exit=0`，WALLET-01 通过。

最终定向回归：`targeted-commerce-regressions.log` 中的 `final_exit=0`，WALLET-01、CM 页面、commerce identity 和既有充值交互共 17 项通过。`format-check.log` 的 `final_exit=0`，`analyze.log` 的 `exit=0`；没有执行全量测试。

执行边界：仅使用 Flutter 3.44.7 的 offline dependencies 和 Widget fake；未运行真实 PayTask、StoreKit、厂商 SDK、数据库、设备、APK 构建或 `28080`，未输出订单字符串或运行凭据。
