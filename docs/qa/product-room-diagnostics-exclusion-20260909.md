# Q10-05 App 质量诊断入口退役

## 结论与基线

已读取主项目 `artifacts/product/filled-decisions-20260909/answers.json` 的实际 Q10-05：问题“房间质量诊断入口向谁展示？”，原答案“**不展示质量诊断**”。本批只退役 App 的 RM-012 页面，不关闭质量处理、后台监控或系统日志。

独立树 `/Users/kongzheng/Documents/ny/.worktrees/flutter-product-exclusions-20260909`，分支 `codex/flutter-product-exclusions-20260909`。开始时 clean HEAD d4dd1e3；先按授权 cherry-pick e4f06597b02c36c2f112faae007630397a6986fb，得到 b578e5a，无冲突。本批提交 diff 的基线为 b578e5a。保留主 Mic 一分钟提示和 Mock 过期策略；不修改主树。

## 实际入口盘点与实现

| 入口/依赖 | 实际情况 | 本批处理 |
| --- | --- | --- |
| RM-004 更多→工具→质量诊断 | diagnostics action→_openDiagnostics→RoomDiagnosticsPage | 删除按钮、分支、方法与 import，共 16 行、4 个局部 hunk |
| RM-012 QA 直达 | qaPageCatalog 注册真实 RoomDiagnosticsPage | 删除 builder/import；manifest 移至 removedProductPages，值 REMOVED_BY_PRODUCT |
| RoomRecoveryPage 恢复页 | 没有质量诊断入口；只有状态与重连操作 | 原源码保留；新增实际进入/重连成功断言 |
| 命名路由/deep link | 没有独立诊断命名路由 | 扩展真实 App Navigator 测试：RM-012、/room/diagnostics、voice-social://room/diagnostics 均不能创建路由 |
| RoomDiagnosticsPage | inspect() 后展示延迟、丢包、RTC、权限及重新采样按钮 | 删除整页 |
| RoomAudioService.inspect / RTC/实时质量状态 | 音频页仍使用 inspect；质量处理与日志在运行层 | 全部保留，没有删除服务/类型、处理回调、日志或监控 |

后台/开发者 vendor diagnostics、系统技术日志不属于 RM-012，本批未扩张。音频、弱网重连、上麦申请与撤回、Mic/PK、discovery、金融和后端源码未更改。

## 页面与旧 positive 映射

有效 manifest/catalog 从 61 改为 **60**，room 区域从 13 改为 12；累计 9 个退役 ID。RM-012 为 REMOVED_BY_PRODUCT，不计 PASS，不复用页号，不 skip。README、manifest/catalog 断言、QA Console 数字、M24 截图及交互计数、动态 visual 测试标题同步到 60；golden 文件未修改。

| 旧项 | 处置 |
| --- | --- |
| QA RM-012 loading/normal/unavailable 页面场景 | REMOVED_BY_PRODUCT Q10-05；不再构造诊断页，不算通过 |
| m33_room_subpages_responsive_test.dart 的 RM-012 × 1.0/1.3 字阶布局子项 | REMOVED_BY_PRODUCT Q10-05；其余有效子页断言保留 |
| 同一布局清单仍残留上一批已删除的 RM-009 | 修正上一批遗漏，明确 REMOVED_BY_PRODUCT Q10-04；不属于本批新增产品删除 |
| room_operations_pages_test.dart 原标题“RM-012 room save conflict…” | 实际测试 EditRoomPage 的版本冲突，并非诊断；仅将页号更正为 RM-002，原测试断言全部保留 |
| test/visual 三个文件中的旧 61 页矩阵标题 | 改 60；实际迭代有效 QA catalog，诊断页退役而非 PASS；本批未运行这些 golden 测试 |

## 测试证据

Flutter 3.44.7，Dart 3.12.2。最小 TDD 红：manifest 缺少 RM-012 退役标记、听众和房主仍显示质量诊断，共 3 项预期失败。实现后：

- 26 项通过：page_manifest_test、room_share_page_test、product_exclusions_test、room_operations_pages_test、m33_room_subpages_responsive_test、mock_mic_request_policy_test。
- 4 项通过：启用 ENABLE_QA_CONSOLE=true 的 qa_console_app_test，实际目录总数 60、筛选/返回/重置通过。
- 1 项通过：first_party_live_mutation_coverage_test 只选择 “all 60 manifest entries build through the QA wiring catalog”，未执行该文件其它业务写用例。
- flutter analyze --no-pub：No issues found。
- git diff --check、bash -n tool/qa/run_m24_emulator_ci.sh：通过。

合计 31 项定向测试，不包括任何退役正向项。测试使用 Mock/本地测试桩；没有连接生产服务、DB 或设备。布局测试是 Widget 溢出检查，不是 golden 生成或视觉验收。

## 精确变更文件

生产：
- lib/app/page_manifest.dart
- lib/debug/qa_console/qa_page_catalog.dart
- lib/features/room/presentation/video_runtime_room_page.dart（仅诊断局部）
- lib/features/room/presentation/room_diagnostics_page.dart（删除）

范围/验证：
- README.md
- 本文档
- integration_test/m2_4_qa_console_flow_test.dart
- test/first_party_live_mutation_coverage_test.dart
- test/m33_room_subpages_responsive_test.dart
- test/page_manifest_test.dart
- test/product_exclusions_test.dart
- test/qa_console_app_test.dart
- test/room_operations_pages_test.dart
- test/room_share_page_test.dart
- test/visual/m2_4_360x800_test.dart
- test/visual/m2_4_390x844_test.dart
- test/visual/m2_4_text_scale_1_3_test.dart
- tool/qa/run_m24_emulator_ci.sh

未执行：全量 tests、全部 golden、APK build、完整 M24/M4、AVD/模拟器/真机、DB/Linux/后端或金融验证。没有 push；没有本次临时编辑脚本。Q10-05 明确范围未发现其它遗漏；后台实际监控/日志运行状态未验证，不推导为通过。
