# Golden CJK 字体子集补全

独立追加于 `332e09db626a6ad00b97e471a0c98306e227f946`，仅测试字体、生成脚本和字体合同。未重做 DS-001 或页面逐图审查，未改应用字体样式、golden PNG、容差或异常过滤。

## 来源与许可证

沿用 `tool/qa/build_m33_golden_fonts.py` 和原 Noto Sans SC Regular/Bold：

- upstream commit：`f8d157532fbfaeda587e826d4cd5b21a49186f7c`；路径为 `Sans/SubsetOTF/SC/NotoSansSC-{Regular,Bold}.otf`。
- 固定 FontTools `4.63.0`、原全部 subset 参数和 `SOURCE_DATE_EPOCH=0` 不变，没有替换字体或改字重。
- Regular 原文件 SHA-256：`faa6c9df652116dde789d351359f3d7e5d2285a2b2a1f04a2d7244df706d5ea9`。
- Bold 原文件 SHA-256：`c6cb5a93abaa9edc8ee7463b7ebb7f42d618d40e6ed2f7a5371c97b0b64767c0`。
- `test/fonts/OFL.txt` 为原 SIL Open Font License 1.1，字节未改；SHA-256 `6a73f9541c2de74158c0e7cf6b0a58ef774f5a780bf191f2d7ec9cc53efe2bf2`。

Downloads 无匹配源字体，使用现有脚本固定的官方源 URL，下载时逐文件验证上述原 hash；没有广搜磁盘。源文件/FontTools venv 由脚本的 TemporaryDirectory 自动清理，完成后实际核验目录已不存在；本次 Python import 生成的单个 pyc 也已清理，无临时工具提交。

## 覆盖范围与输出

原两个 cmap 均缺 `拍 U+62CD`、`摄 U+6444`、`殊 U+6B8A`、`特 U+7279`。固定源码覆盖检查保守收集全部 `lib/**/*.dart` 中文字符及中文/全角标点（包含注释和 Mock 文案，而不只选少数页面）：本树共 935 个，原缺 59 个，修复后两个字重均缺 0 个。另只读比对主树 `69485170ed33a3ba37f87a6630b01a337ad094a5` 的当前 `lib`，同为 935 个且无新增遗漏；当前源码无中文 Unicode escape 文案遗漏。

生成沿用原 `lib/**/*.dart` + `test/**/*.dart` 采集，同时保留旧 charset，避免退役文案导致历史字形被删。两个 cmap 均由 1014 增至 1088 个有效非 `.notdef` 映射，各新增 74、删除 0；字形增量为：

```text
≤≥临九予介估倒候兔冬副午卖却右叶各售啦四媒尾岁左弃律忘拍摄故斥既旺易替李材桥殊毁民气沿滚漂熊父牢特狐盖盾矛租窗筛精素缩覆责跨跳踢轨转途遍邮释野障雨
```

这是固定中文源码覆盖，不声称该有限测试字体覆盖任意用户/服务端文本或所有 emoji。原头像补充字体、加载方式和其图像基线保持不动；主字体现也具备 `兔狐叶熊`。

| 输出 | 字节 | SHA-256 |
| --- | ---: | --- |
| `M3GoldenCjkRegular.otf` | 257288 | `c12e9daaa1de89cc085dc6d58e8588862fb56984df6bf0365e3d9d70e05fa0c3` |
| `M3GoldenCjkBold.otf` | 258096 | `9e9782ee90d8c02594345b5e983f600089785a226cc9e6d0ae7607a76ab79750` |

## RED / GREEN 证据

新增纯 Dart OpenType cmap 格式 4/12 读取合同，不依赖本机字体、FontTools 或外部 Python 运行环境。Regular/Bold 的四字检查、全部固定中文覆盖和 charset 检查首次 **5 FAIL / 4 PASS**；原来源/hash 合同未削弱。

```sh
PYTHONDONTWRITEBYTECODE=1 python3 tool/qa/build_m33_golden_fonts.py
/Users/kongzheng/fvm/versions/3.44.7/bin/flutter test --no-pub test/golden_font_contract_test.dart --reporter expanded
# 9 PASS，exit 0，含原 4 + 新 5；不重复累计 RED。
/Users/kongzheng/fvm/versions/3.44.7/bin/flutter analyze --no-pub test/golden_font_contract_test.dart test/support/opentype_cmap.dart
# No issues found，exit 0。
```

固定 Flutter 3.44.7 / Dart 3.12.2 已先核验；2 个变更 Dart 文件 format 0 changed，diffcheck 无错误；Python AST 与当前 charset 再采集一致性通过。独立 Python stdlib 二进制 cmap 读取与 Dart 结果一致，确认新增 74/旧字形无移除/当前中文缺 0；没有将 cmap 检查冒充图像验收。

本地 ignored 日志为 `artifacts/qa/golden-font-coverage-20260910/{red,generate,green}.log`。未跑 golden、21 页图审、全量、设备、DB 或 provider，未 push。增加字形会修正旧图中的方框，后续 PNG 审核/更新仍由主安排，不在本提交中伪造图像 PASS。
