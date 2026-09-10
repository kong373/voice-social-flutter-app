# CM-002 大字体卡片高度修复

基线 `8fc6cd5344a97d3d7a8697f8cc74f8d0352a9bdf`；独立分支 `codex/flutter-commerce-responsive-20260910`。

原 `CM-002 fits 360x800 at 1.3x` 真实 RED：固定 138 高卡片扣除 padding 后仅有 `135×118` 内容区域，礼物币数量换行，Column 底部溢出 2px。新增金额可见/选择回归在原实现也因相同 overflow 失败。

仅将充值商品固定高度 GridView 改为两列 Wrap：列宽与 10px 间距不变，138 为最小高度，内容可以撑高。字号、TextScaler、价格/礼物币/赠币/推荐字段、商品启用与选择逻辑均未改；没有裁掉内容或吞掉异常。原 40 个响应式用例及视口不变。

固定 `/Users/kongzheng/fvm/versions/3.44.7/bin/flutter --version` 核验为 Flutter 3.44.7 / Dart 3.12.2。新树仅 `pub get --offline`，未修改 SDK/fvm 或依赖锁文件。

实际 GREEN，共 **43 个不同测试**（早期 CM-002 子集 5 项不重复相加）：

```sh
/Users/kongzheng/fvm/versions/3.44.7/bin/flutter test --no-pub test/commerce_visual_responsiveness_test.dart --reporter expanded
# 41 PASS（原 40 + 新 1），exit 0。
/Users/kongzheng/fvm/versions/3.44.7/bin/flutter test --no-pub test/m24_pages_test.dart test/m33_deep_interactions_test.dart --name '^(CM-002 through CM-004 enforce platform channels and authority|recharge selection reaches a server-authoritative result)$' --reporter expanded
# 2 PASS，仅所列用例，不声称两文件全过。
/Users/kongzheng/fvm/versions/3.44.7/bin/flutter analyze --no-pub lib/features/commerce/presentation/commerce_pages.dart lib/features/commerce/presentation/commerce_catalog_pages.dart test/commerce_visual_responsiveness_test.dart
# No issues found，exit 0。
```

新增用例在 360×800 / 1.3x 下逐项验证 5 档币数/金额完整处于卡片内、可滚动选择，最终支付页接收所选 648 元/6480 币商品。2 个改动 Dart 文件格式检查 0 changed，`git diff --check` 无错误。日志位于本树 ignored `artifacts/qa/cm002-responsive-20260910/`，含 `red.log`、`interaction-red.log`、`cm002-green.log`、`responsiveness-green.log`、`recharge-flows-green.log`。

未跑全量、golden、设备、DB 或 provider；未改主树、图片、金额合同或支付写逻辑。既有 CM-002 golden 位于 `test/goldens/m3_3_all/` 及 `test/goldens/linux/m3_3_all/`，本次不更新、不宣称图像门禁通过。主合并态全量由主另行验证。
