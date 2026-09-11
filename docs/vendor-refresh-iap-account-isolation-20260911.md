# 消息补读与 IAP 待单账号隔离

基线：Flutter `150473fd9d2beacf18884d1df3bd7a7cfb3220ad`。只修改消息中心刷新协调和 Apple IAP 建单前的未决订单判断，没有修改 SDK、价格、支付交付/finish、Backend、设备或运行环境。

## F-IM-03

消息中心已有真实 refresh bus 订阅。原问题是 HTTP 刷新尚未完成时的新提示只等待旧 Future，导致较新消息没有被再次读取。

当前将重叠提示合并为一次尾随读取。任一时刻仍只有一个该提示流的 HTTP 请求；退出、身份失效、读取权限失效和卸载会使旧刷新代际失效，旧结果不能继续补读或清除新 flight。失败读取不会丢掉已经收到的新提示。

Widget 回归通过真实页面和 bus 驱动：第一份 HTTP 快照挂起，连续两个新提示到达，释放后最终显示新快照。成功和失败首读均补一次；退出和卸载均不补读。重复提示由现有 bus 去重。

## F-IAP-01

原未决订单集合跨账号保存；原实现却以整个集合非空阻止新账号下单。当前仅用当前账号的未决项决定复用或拒绝，保留其他账号的 journal、订单归属与恢复能力。

新增防御：Backend 若返回一个本机已知属于另一账号的订单号，仍拒绝，不改变原 owner。原负例的拒绝断言保留，只有 POST 次数由 1 改 2：B 现在可以请求自己的新单，但该旧替身故意返回 A 的订单号，结果必须被拒绝。

回归先让 A 的原生调用完成并返回 pending，再切换 B。B 可以建自己的订单；不能购买 A 的订单；B 的待单不能重复建单；切回 A 保留并恢复原订单而不再次调用 purchase。两份 journal 各自保留，没有调用 deliver 或 finish。原生设备级在途锁未修改，相关 native adapter 测试另行通过。

## 本机验证

- 先行测试有一次 fixture 编译错误（const 对象 getter 不能用于 const 初始化），已修正为 final；该次不计业务 RED。
- 真正 RED：5 项新回归中 3 失败、2 通过。两项消息补读实际 calls=2、expected=3；IAP 在 B 建单前抛未决购买错误。
- GREEN：`test/tencent_im_stage2_ui_test.dart` 与 `test/apple_iap_purchase_coordinator_test.dart` 合计 32 PASS。
- 相关回归：`q03_message_visibility_test`、`q19_private_history_ui_test`、`message_center_search_test`、`apple_iap_storekit2_adapter_test`、`apple_iap_purchase_journal_test`、`apple_iap_commerce_repository_test` 合计 50 PASS。
- Flutter 3.44.7；format、4 项 analyze、diff-check 通过。未修改依赖。
- 日志：`/Users/kongzheng/Documents/ny/artifacts/release/flutter-refresh-iap-isolation-20260911/` 的 `fixture-compile-attempt.log`、`red.log`、`green.log`、`related.log`、`analyze.log`。

上述为本地测试替身/Widget 证据，不是腾讯 ≤2 秒实测，也不是 StoreKit 实际购买。未覆盖、替换正在验收的 `150473f` 普通 App；新候选整体验收另行绑定 SHA。
