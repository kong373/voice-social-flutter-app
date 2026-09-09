# Flutter S07/S08/Q11 精确礼物币与收益入口（2026-09-09）

## 基线与范围

- 独立 worktree：`/Users/kongzheng/Documents/ny/.worktrees/flutter-precise-income-20260909`。
- 分支：`codex/flutter-precise-income-20260909`；精确基线：`c81066dd851a5ef506b2f9749d91365361dc3fce`。
- S07 对照 Backend `19b272c04334edef9e7b4252faccd2e772e7b698` 的 `docs/product-s07-coin-precision-20260909.md`、GiftCoinPrecisionService、ReadOnlyService、FirstPartyCommerceService 实际 DTO；S08 对照主任务冻结的 incomeRole/incomeEligible/canWithdraw 与 MANUAL_FINANCE 补充合同。
- 不改 Backend、分成/金融政策、shared ApiClient、房间权限/staff/PK、排行榜、社区、多收礼人、provider 或设备。仅本地追加 commit，不 push/merge/deploy。
- 本次不改变现金、提现报价既有单位与 feeVersion/CEILING_FEN 校验；十分币只用于精确读取/展示，不传回原整币商品、充值或消费参数。

## 契约与实现边界

| 入口 | 当前行为 |
| --- | --- |
| GET /app-economy-api/ncoin | 必须完整 GIFT_COIN / GIFT_COIN_TENTHS_V1 / integer scale=10 / 非负十进制字符串 availableTenths、frozenTenths。BigInt 解析与十进制展示；integer/value 不参与权威展示。缺失/未知/小数/科学计数/数值类型失败关闭。 |
| GET /app-mini-api/mini/v1/wallet/overview | 三能力字段严格交叉校验：ORDINARY=false/false，ANCHOR、GUILD_CHAIR=true/true。全缺失仅视为无能力，部分缺失/矛盾/未知角色显示错误；不从 App/JWT/guild 缓存猜身份。 |
| GET /app-mini-api/mini/v1/wallet/account-details | GIFT_COIN 顶层 coinPrecision 必检；行 GIFT_COIN 或 GIFT_COIN_TENTH + amountTenths/scale/version。礼物币金额不经过 double，cash 行仍按既有 CASH_CNY 合同。COIN_PRECISION_CARRY 不展示、不算收入。原分页、方向过滤、重复 ID、权限与异常页校验保留。 |
| 送礼/历史 giftReceipt | 解析可选 coinPrecision、creatorIncomeCurrency，仅 CASH_CNY/GIFT_COIN_TENTH 或历史 null。历史缺精确余额/币种仍未知，不补造；礼物价格/数量/原 key 不改。 |
| withdrawal quote | 新 MANUAL_FINANCE 必须明确 providerInvocation=false；兼容旧 FIRST_PARTY_REVIEW_PROVIDER_BLOCKED，只用于旧合同兼容。新界面说明财务人工审核、不自动打款。费率版本/CEILING_FEN/金额核对不放宽。 |
| withdrawal apply | 新申请在写之前重新 GET overview 查当前能力，不能靠之前成功的页面读取授权。原 unknown intent 跳过新申请预检查，用原身份绑定发送、原 key/body 交服务端核验历史；不重新报价、不换目标、不新建冻结。服务端仍作最终身份与幂等判定。 |

普通身份看不到“主播收益”“结算与提现”新业务入口；可进入“历史提现记录”。直达收益页拒绝展示；直达提现页隐藏新表单，保留历史与原未决恢复。未决恢复仍锁定原金额/报价/收款账户且需用户确认。当前能力不支持时不再为页面查询新 payout-account 选项。

Wallet/Hub/Earnings/Recharge/GiftCatalog 使用已有 commerce identity tuple/Listenable 接线与独立读请求序号：换号、登出、ABA、快速过滤切换及销毁均清除旧展示并拒绝旧异步结果。它不删除 repository 按账号保存的 pending/key/receipt。礼物面板独立读取精确余额，原整币房间快照不会覆盖小数，充值返回/送礼成功再次读取权威余额；读取失败隐藏金额、禁送并提供“刷新余额”。

例：1148 tenths 显示 114.8；92233720368547758079 显示 9223372036854775807.9；0.5 币不能购买原 1 币商品。旧 100 币充值仍是 100 币，不变成 10 或 1000 币。Mock 明确为 demo anchor，支持 ordinary 身份测试；精确余额和单位规则相同，模拟充值按 orderNo 去重保留零头，原历史提现保留，不宣称厂商调用成功。

## 精确文件

生产（13）：

- lib/features/commerce/domain/gift_coin_precision.dart
- lib/features/commerce/domain/commerce_models.dart
- lib/features/commerce/data/backend_commerce_repository.dart
- lib/features/commerce/data/mock_commerce_repository.dart
- lib/features/commerce/presentation/commerce_identity_fence.dart
- lib/features/commerce/presentation/commerce_pages.dart
- lib/features/commerce/presentation/commerce_wallet_pages.dart
- lib/features/commerce/presentation/commerce_earnings_pages.dart
- lib/features/commerce/presentation/commerce_catalog_pages.dart
- lib/features/commerce/presentation/commerce_widgets.dart
- lib/features/room/domain/room_models.dart（仅 GiftReceipt）
- lib/features/room/data/backend_room_repository.dart（仅 gift receipt 解析）
- lib/features/room/presentation/gift_sheet.dart（余额展示/恢复）

测试（7）：

- test/precise_income_contract_test.dart
- test/precise_income_widget_test.dart
- test/backend_commerce_repository_contract_test.dart
- test/backend_room_repository_contract_test.dart
- test/commerce_repository_test.dart
- test/first_party_live_mutation_coverage_test.dart
- test/gift_sheet_live_targets_test.dart

## TDD 与实际证据

- RED：handle96168，exit1，2 个确定失败：错误 scale 被旧 integer 掩盖；MANUAL_FINANCE 被旧模式校验拒绝。前两次精度测试夹具漏 agentEarnings 明确 null，误命中旧缺字段错误，不能算精度负向覆盖；补齐后才取得这次真实 RED。
- 页面 RED：handle62062，exit1。大额余额在 360px 真溢出；另两个是测试导航复用/懒列表定位问题，分别修为显式卸载与滚动定位，不放宽产品权限。
- 旧回归夹具：按冻结 S07 给整币 fixtures 补 coinPrecision/amountTenths；新增 S08 新申请 overview 的明确 ANCHOR 响应。原金额、流水方向/分页、U01 幂等/换号、收款账户权限、cash 历史断言保留。未 Disabled/跳过/降低覆盖。
- 中途 handle91083 手动中止（新合同缺失导致旧 fixtures 失败），不报通过。handle88818 测试加载失败（误将一个现金 WithdrawalRecord 断言改为 coinAmount），已恢复原 amount=2；不算 PASS。
- 关联首次批 handle34552：115 PASS/1 FAIL（first_party_live_mutation fixture 未补 income capability），仅补 overview 权威响应，保留写 body/key/receipt 金额断言。
- 最终 **handle5993，exit0，17 文件 257 PASS，0 failure/error/skip**。`build/precise-income-evidence/targeted-final.log`。
- 最终全 analyze **handle23287，exit0，No issues found**。`build/precise-income-evidence/analyze-final.log`。
- 固定 Flutter3.44.7 / Dart3.12.2，仅格式化本次20个 Dart 文件；diff check 无空白错误。

最终定向命令：

```sh
/Users/kongzheng/Documents/ny/.tooling/flutter-3.44.7/bin/flutter test --no-pub --reporter expanded \
  test/precise_income_contract_test.dart \
  test/precise_income_widget_test.dart \
  test/backend_commerce_repository_contract_test.dart \
  test/backend_room_repository_contract_test.dart \
  test/commerce_live_ui_contract_test.dart \
  test/commerce_repository_test.dart \
  test/gift_sheet_live_targets_test.dart \
  test/withdrawal_product_policy_test.dart \
  test/api_client_identity_bound_test.dart \
  test/first_party_live_mutation_coverage_test.dart \
  test/commerce_catalog_repository_test.dart \
  test/backend_commerce_catalog_repository_contract_test.dart \
  test/commerce_visual_responsiveness_test.dart \
  test/m4_commerce_ui_support_test.dart \
  test/apple_iap_commerce_repository_test.dart \
  test/apple_iap_app_dependencies_test.dart \
  test/alipay_backend_payment_flow_test.dart
/Users/kongzheng/Documents/ny/.tooling/flutter-3.44.7/bin/flutter analyze --no-pub
```

## 剩余边界 / NOT_RUN

真实 Backend S07+S08 合并后的 App 联调、真实设备、真实支付/退款/提现、厂商、DB/Docker、部署和全仓 Flutter test 均 NOT_RUN。主任务集成后仍需 ordinary/anchor/chair 账号现场验收：精确零头、历史申请恢复、角色撤销、新 MANUAL_FINANCE 回执及充值后余额刷新。本批不能代替后端权威身份/分账实现；多收礼人留下一批。
