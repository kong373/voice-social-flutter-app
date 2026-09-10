# DS-001 九麦摘要小屏大字适配

追加基线 `6f912328060ab234af5ddf8404d0e37338dcc1a5`；同隔离树 `flutter-commerce-responsive-20260910`，与 CM-002 分开提交，不改主树。

## 复现与最小修复

原 `test/visual/m2_4_text_scale_1_3_test.dart` 第一用例真实失败：`DS-001 must render at 360.0×800.0, 1.3× text`，右侧 RenderFlex overflow 12px。首页 hero 的 `_SeatSummary` 有九个固定 22px 圆点，大字体计数占宽后剩余宽度不足；390×844 不溢出。

仅为这九个圆点容器各增加 `Flexible`，按剩余宽度弹性收窄；原最大宽度/高度 22、图标大小 12、九个位置、占用状态和完整计数不变。没有缩小文字/字体比例、隐藏字段、修改页面入口或忽略异常。其他首页/图片/业务逻辑不变。

## 验证

固定绝对 SDK 已先核验为 Flutter 3.44.7 / Dart 3.12.2。

```sh
/Users/kongzheng/fvm/versions/3.44.7/bin/flutter test --no-pub test/visual/m2_4_text_scale_1_3_test.dart --plain-name 'all 60 active pages render at 360x800 and 1.3x text' --reporter expanded
# 原 case RED 1 FAIL，exit 1。
/Users/kongzheng/fvm/versions/3.44.7/bin/flutter test --no-pub test/discovery_home_responsiveness_test.dart --reporter expanded
# 修复前新增回归：360 FAIL（同一 overflow），390 PASS。
/Users/kongzheng/fvm/versions/3.44.7/bin/flutter test --no-pub test/discovery_home_responsiveness_test.dart test/visual/m2_4_text_scale_1_3_test.dart --reporter expanded
# GREEN 4 PASS，exit 0：新增 2 + 原 text_scale 文件完整 2 case。
/Users/kongzheng/fvm/versions/3.44.7/bin/flutter analyze --no-pub lib/features/discovery/home_page.dart test/discovery_home_responsiveness_test.dart
# No issues found，exit 0。
```

原 text_scale 文件及 support 未改：每 case 遍历当前 catalog 60 页，两种视口共 120 次页面布局检查，不将其误记为 120 个测试。未发现其他 overflow。新增两项检查九个图标、完整 `3/9 麦` 计数、不重叠、标题/主题/进入按钮保留，以及收藏入口导航可用。2 个改动 Dart 文件格式检查 0 changed，`git diff --check` 无错误。

本地 ignored 日志：`artifacts/qa/ds001-responsive-20260910/{red,seats-red,green}.log`。未重跑已交付的 CM-002 43 项，不重复相加；未改其生产/测试文件。未跑全仓、golden、DB、设备或 provider，未改测试视口/字体比例/异常处理，未 push。
