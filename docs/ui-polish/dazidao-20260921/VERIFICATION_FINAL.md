# 最终检查结果

测试源码：`2ea29985c75a2247aee80d1fad7c40381d4e9da9`。Flutter3.44.7/Dart3.12.2，并发2，检查串行；没有设备、数据库、真实资金或厂商调用。

| 检查 | 通过 | 失败 | 退出码 | 日志 |
|---|---:|---:|---:|---|
| sealed123-final-related | 482 | 0 | 0 | sealed123-final-related.log |
| sealed123-final-supplement | 132 | 0 | 0 | sealed123-final-supplement.log |
| sealed123-final-interactions | 90 | 0 | 0 | sealed123-final-interactions.log |
| sealed123-final-states | 1074 | 0 | 0 | sealed123-final-states.log |
| sealed123-final-default | 64 | 0 | 0 | sealed123-final-default.log |
| sealed123-final-layout | 384 | 0 | 0 | sealed123-final-layout.log |
| sealed123-final-sheets | 192 | 0 | 0 | sealed123-final-sheets.log |
| sealed123-reviewed-macos-golden | 65 | 0 | 0 | sealed123-reviewed-macos-golden.log |
| sealed123-keyboard-field-0 | 66 | 0 | 0 | sealed123-keyboard-field-0.log |
| sealed123-keyboard-field-1 | 24 | 0 | 0 | sealed123-keyboard-field-1.log |
| sealed123-keyboard-field-2 | 12 | 0 | 0 | sealed123-keyboard-field-2.log |
| sealed123-keyboard-field-3 | 6 | 0 | 0 | sealed123-keyboard-field-3.log |
| sealed123-final-analyze | N/A | N/A | 0 | sealed123-final-analyze.log |
| sealed123-final-format-check | N/A | N/A | 0 | sealed123-final-format-check.log |

上述结果存在重叠，不相加作为独立业务PASS总数。默认64为60页面+4实际主入口；1074为179场景×6配置；补充132为22×6；交互90为15×6；面板资产192为32×6。
键盘66+24+12+6共108项对应明确列出的输入位置与尺寸字号；不覆盖所有条件字段。12项举报/反馈草稿保留包含在482项相关回归中。
Mac golden65通过使用本机74张已审更新图片。远端PR未包含这些PNG，不能据此认定远端golden或CI通过；Linux像素门禁未跑。
旧Mac基准2通过63失败是实际视觉差异；字体、表单和权限夹具早期失败记录保留，不混作业务RED。
完整命令、退出码与绝对证据路径见VERIFICATION_FINAL.json。
标准Git diff-check的最终结果在本文件及JSON末尾单独记录。

最终标准 `git diff --check`：exit0，无空白错误；包含显式新测试和文档。CSV的CRLF导致过一次exit2，已转LF并复验；旧记录保留，未计作业务RED。
