# Q14-02 新充值不赠币

依据用户已填决策“没有赠币”，仅把演示商品里的赠币移除；价格、基础币数和渠道不变。正式 Backend 对应 V74 及新订单路径约束，历史订单、余额和赠币消费权益不重新计算。客户端既有历史/契约解析不擅自扣减服务端旧订单快照。

2026-09-10：新增两平台无赠币用例先 RED（期望 0，实际 20），修正后 `commerce_catalog_repository_test.dart` 与 `backend_commerce_catalog_repository_contract_test.dart` 共 32 tests PASS；两项文件 analyze 无问题、format 与 diff-check 通过。此证据为本地商品/支付合同回归，不代表厂商付款或设备验收。

原始日志位于工作区 `artifacts/product/filled-decisions-20260909/q14-no-bonus-flutter-{red,green}-20260910.log`，不包含支付凭据或订单串。价格与渠道的原暂缓决策保持不变。
