# WALLET-01 支付宝结果返回充值目录与钱包 Hub 刷新验证

验证基线：`12fb52aeb62b425e7aa48523870ceebba0d91131`

验证分支：`codex/flutter-wallet-return-20260911`

验证日期：2026-09-11

## 结论

本次把“返回钱包”拆成两个实际页面分别验收：

- actual catalog route：基线中结果页通过 `pushReplacement` 替换提交页，使充值目录等待的 push 提前完成；目录原有刷新发生在权威结果确认之前。最小修复后，结果页返回的实际当前页面是 `RechargeCatalogPage`，可见余额为 `2360`。
- actual wallet Hub route：在目录已显示 `2360` 的前提下，原 `CommerceHubPage._open` 不等待子路由返回，也不触发返回后的 `_load`；再执行一次系统 `pageBack()` 回到真正的 `CommerceHubPage` 时仍显示旧余额 `1680`。新增断言先在 `wallet-01-hub-baseline.log` 中 RED，随后以最小 Hub 返回刷新修复并 GREEN 为 `2360`。

最终没有修改 `CommerceIdentityFence`、repository、ApiClient、adapter、AppDependencies、价格、原生 SDK、IAP coordinator 或房间代码。

## 真实 Widget 路径证据

WALLET-01 使用 `AppDependencies.mock()` 内部已经连接的 `MockCommerceRepository` 与 `MockCommerceCatalogRepository`，未替换页面导航：

```text
CommerceHubPage
  → RechargeCatalogPage（目录初始 1680）
  → PaymentSubmissionPage（选支付宝）
  → PaymentResultPage
  → 点击一次结果页“返回钱包”
  → RechargeCatalogPage（actual catalog，2360）
  → 一次系统 pageBack()
  → CommerceHubPage（actual wallet Hub，2360）
```

初始 hub 和充值目录显示 `1680` 礼物币。结果页第一次自动查询仍为“服务端确认中”；点击真实“刷新订单状态”完成 fake 的第二次权威查询，fixture 余额由 `1680` 变为 `2360`。该操作只产生权威订单结果，不是钱包刷新。之后只点击一次结果页“返回钱包”，再执行一次系统 `pageBack()`。

测试确认：

- 结果页“返回钱包”的实际落点是 `RechargeCatalogPage`，不是 `CommerceHubPage`；结果页和提交页离开后，目录可见 `2360`。
- 充值目录 `_continue` 在提交页返回后调用已有 `_load`，其中调用 `commerceRepository.fetchWalletSummary()`，并显示 `2360`。
- 系统 `pageBack()` 只返回一层到 `CommerceHubPage`；Hub 修复后的 `_open` 等待子路由完成，再调用同一 `_load`/`fetchWalletSummary()`，Hub 可见 `2360`。
- 没有点击钱包顶部“刷新”，没有手动 `Navigator.pop` 多级路由；身份栅栏定义及 token/退出换号隔离逻辑未改动。

## 执行记录

原基线目录业务 RED：`wallet-01-baseline.log` 的 `retry_exit=1` 记录完整路径在结果页返回目录后找不到新余额 `2360`。此前第一次失败是目录按钮未滚入测试视口的测试假红，已通过滚动到真实按钮排除。

目录修复后 Hub 业务 RED：`wallet-01-hub-baseline.log` 的 `exit=1` 记录目录 `2360` 断言通过后，系统 `pageBack()` 回到 Hub 的 `2360` 断言找不到（实际仍为旧 Hub 状态）。

Hub 修复后 GREEN：`wallet-01-hub-green.log` 的 `exit=0`，同一真实 Widget 路径与两层余额断言通过。

本次 Hub 增量只执行了定向 `test/commerce_wallet_return_test.dart` 这一项，没有重复当前 17 项回归；此前 17 项结果仍记录在 `targeted-commerce-regressions.log`。本次改动后的 format/analyze 结果分别记录在 `hub-format-check.log`、`hub-analyze.log`。

执行边界：仅使用 Flutter 3.44.7 的 offline dependencies 和 Widget fake；未运行真实 PayTask、StoreKit、厂商 SDK、数据库、设备、APK 构建或 `28080`，未输出订单字符串或运行凭据。
