# 第二批旧 positive 退役清单

依据 Q10-04/Q15-06；以下条目均为 **REMOVED_BY_PRODUCT**，不是 PASS、SKIP 或临时豁免。范围基线 074bf4b，完成证据见 [交接](product-share-refund-exclusions-20260909.md)。

## 仓库测试

文件均相对 `test/`。

| 文件 | 旧 testcase | 处置 |
| --- | --- | --- |
| backend_commerce_repository_contract_test.dart | order-scoped refund uses exact check, submit, result, repeat contracts | REMOVED_BY_PRODUCT；改由零请求拒绝测试覆盖 |
| backend_commerce_repository_contract_test.dart | concurrent duplicate refund submission sends one authoritative write | REMOVED_BY_PRODUCT；改由零请求拒绝测试覆盖 |
| backend_commerce_repository_contract_test.dart | refund submit retries an ambiguous response with one bounded stable request ID | REMOVED_BY_PRODUCT；改由零请求拒绝测试覆盖 |
| backend_commerce_repository_contract_test.dart | refund submit retains 40901/40902 and rotates after definitive 40903 | REMOVED_BY_PRODUCT；改由零请求拒绝测试覆盖 |
| backend_commerce_repository_contract_test.dart | refund retry keeps one request ID across an ambiguous response and prevents duplicate economic writes | REMOVED_BY_PRODUCT；改由零请求拒绝测试覆盖 |
| backend_commerce_repository_contract_test.dart | refund retry reconciles a submitted state before applying the rejected gate | REMOVED_BY_PRODUCT；改由零请求拒绝测试覆盖 |
| backend_commerce_repository_contract_test.dart | refund retry intent is refund-scoped when expected order is optional | REMOVED_BY_PRODUCT；改由零请求拒绝测试覆盖 |
| backend_commerce_repository_contract_test.dart | refund result and retry reject mismatched refund IDs and selected orders | 仅 retry 分段 REMOVED_BY_PRODUCT；result 身份/订单错配断言原样保留并改名为历史读取 |
| first_party_live_mutation_coverage_test.dart | withdrawal, refund submit/result/retry preserve first-party authority | 仅退款写分段与专用 fixture REMOVED_BY_PRODUCT；提现账户、金额、request ID、返回值断言保留 |

所有其它订单 query/reconcile、历史 result/history 分页、币种/金额/时间/供应商状态矛盾检查、错误 envelope、提现幂等与查询测试保留。没有删除退款历史类型/记录或后台金融测试。

## 页面测试

| 文件（test/） | 旧 testcase/矩阵 | 处置 |
| --- | --- | --- |
| room_share_page_test.dart | RM-009 keeps clipboard sharing first-party and native sharing fail-closed | REMOVED_BY_PRODUCT；替换为听众/房主真实更多工具无分享/复制、零 Clipboard 写及保留管理入口 |
| commerce_live_ui_contract_test.dart | order refund form only exposes the first-party order contract | REMOVED_BY_PRODUCT |
| commerce_live_ui_contract_test.dart | order refund eligibility is bound to the selected order | REMOVED_BY_PRODUCT |
| commerce_live_ui_contract_test.dart | refund $failure preserves the draft and never shows success：403/409/422/500 四项 | REMOVED_BY_PRODUCT |
| commerce_live_ui_contract_test.dart | double tapping refund submit produces one write | REMOVED_BY_PRODUCT |
| commerce_live_ui_contract_test.dart | refund retry sends the selected refund and order identity | REMOVED_BY_PRODUCT |
| commerce_live_ui_contract_test.dart | refund result refresh is single-flight before rebuild | REMOVED_BY_PRODUCT（页面已删除；仓库历史读取回归保留） |
| commerce_live_ui_contract_test.dart | refund retry is single-flight before rebuild | REMOVED_BY_PRODUCT |
| commerce_visual_responsiveness_test.dart | CM-007/CM-008 × 390x844/360x800 × 1.0x/1.3x，共 8 个旧布局项 | REMOVED_BY_PRODUCT；其余 10 个商城页 × 4 视口/字阶 = 40 项保留并通过 |
| m22_pages_test.dart | 钱包 hub 内“退款申请”存在断言 | REMOVED_BY_PRODUCT；换为不存在断言，同测试其它入口保留 |
| m4_refund_scope_contract_test.dart | strict executes original operation; deferred performs zero writes | 旧退款可执行语义 REMOVED_BY_PRODUCT；两种兼容参数均只允许退役后的范围 |
| m4_refund_scope_contract_test.dart | scope retains every other capability and strict mutations（退款部分） | 退款正向要求 REMOVED_BY_PRODUCT；仍断言礼物/提现/私信及全局门禁存在，并新增脚本拒绝伪通过证据测试 |

## 集成注册及脚本

| 文件 | 旧项 | 处置 |
| --- | --- | --- |
| integration_test/m2_4_commerce_flow_test.dart | FLOW-012-06-refund-result / CM-007、CM-008 | REMOVED_BY_PRODUCT；前后订单补单、收益、提现流程保留 |
| integration_test/m2_4_fixture_authority_flow_test.dart | P1-M24-EMU-009-CM-008-authoritative-refund | REMOVED_BY_PRODUCT；其它权威 fixture 详情保留 |
| integration_test/m4_first_party_live_integration_test.dart | _runRefundMutation / _runStrictRefundMutation 和退款入口探针 | REMOVED_BY_PRODUCT；不执行 App 退款写，不要求旧业务成功，保留历史 records 读取 |
| tool/qa/run_m24_emulator_ci.sh | M24-EMU-009 的 CM-008 截图子项 | REMOVED_BY_PRODUCT；同用例其它子项继续要求证据，61 页计数同步 |
| tool/qa/run_m4_authoritative_live_avd.sh、aggregate_m4_authoritative_live_avd.sh | strict refund submit/result 成功或 deferred 临时豁免 | REMOVED_BY_PRODUCT；统一显式退役记录，非法旧退款成功 route 拒绝；其它门禁不变 |
| test/visual/m2_4_360x800_test.dart、m2_4_390x844_test.dart、m2_4_text_scale_1_3_test.dart | 旧 64 页标题/动态目录范围 | 新标题 61 页，实际目录来自有效 QA catalog；三页 REMOVED_BY_PRODUCT；未运行、未改 golden 文件 |

## 替代负向证据

`product_share_refund_exclusions_test.dart`：三页注册不存在、Backend/Mock 重复退款申请/重试抛本地拒绝、HTTP 次数为零、Mock 历史状态不变、钱包保留订单流水且无退款 CTA。
`product_exclusions_test.dart`：实际 App Navigator 无法通过旧页 ID、路径及 deep link 创建路由；上一批有效测试仍在。
`message_order_deep_link_test.dart`：订单通知定位目标订单、仍能补单，且不能重新出现退款入口。

私信撤回未找到实现，因此无旧 positive 要退役，不替换/删除任何消息发送、已读、历史、通知回归。上麦申请撤回/管理邀请不在本批删除范围。
