# Flutter S16：礼物价值自然周期排行榜

## 基线与边界

- 独立树 `flutter-s16-rankings-20260909`，分支 `codex/flutter-s16-rankings-20260909`。
- 精确基线 `3c216fc7632494103e17ef9c1de820b9e09bed25`。
- 读取并遵从 Backend `backend-s16-local-review-20260909` 的
  `docs/product-s16-rankings-20260909.md`、`GiftValueRankingRules.java`、
  `GiftValueRankingService.java`。不将其旧执行记录当成本次 Flutter 验证。
- 只改 dynamic 的榜单部分。未改 Backend、shared ApiClient、路由、AppDependencies、
  社区公会、钱包、评论业务、房间权限或厂商配置。无设备/DB/部署/push。

## 实现合同

三条礼物榜继续 POST 原 charmrank / wealthrank / queryRoomDfRank 路径，body 为
`{pageNum,pageSize,period:DAY|WEEK|MONTH}`，不再发送 theType/rankType。
贡献榜仍用 contribuitonrank，body 仅 pageNum/pageSize；页面显示累计贡献、不显示周期。

新增严格 ranking_contract：验证 metric、serverAuthoritative、period、timezone、
valueBasis、scoreUnit=CNY_FEN、scoreEncoding=DECIMAL_STRING、服务端窗口及全部分页字段。
list/records 须一致；当前页条数、rank 和 ID 唯一性校验，不客户端重排/估算榜分。
窗口只用返回的 serverNow 验证北京时间自然日、周一、月初，不读取设备当前时间。
UI 展示服务端起止（结束不含）、更新时间、排除的不可估值记录数；不伪造倒计时。

score 只接受规范非负十进制字符串（0 或最多65位），解析成 BigInt 整分；使用整除及
余数显示完整人民币元和两位分，不经过 num/double/int，不压缩成“万”、不省略超大金额。
例：`184467440737095516150` → `1844674407370955161.50 元`。
贡献榜保持原 numeric 口径，单独存储，拒绝与礼物金额元数据混用。
分页/数值ID若超过跨平台精确整数范围则拒绝，不静默舍入。
正值保留服务端 firstReachedAt/TransferId（字符串），零值要求两者 null；不本地算同分名次。

房间 public_id 保持不透明非空字符串：真实 V1000 历史种子为 `100001`，并非全是 UUID。
NULL/空 roomCode 不造成整页失败，不用其替代 roomId。未增加房间准入权限。

复用已注入的 session userId/identityGeneration/Listenable，通过独立 RankingIdentity
暴露给榜单页；无需更改 AppDependencies。仓库用现有 postBoundToIdentity，在连接建立、
发送及401恢复时保持原身份，返回后再次检查。页面按请求代次和身份 tuple 拒绝旧响应，
切换/登出立即清数据；分页按页替换，不把不同服务端读视图追加混为一个快照。
网络/协议错误显示错误并允许手动重新读取，不降级成 Mock 或空榜成功。

Mock 返回有限、明确的演示数据和分页，`serverAuthoritative=false`；UI 持续标注
“演示数据 · 非实时榜单”，不制造服务端时间窗口、在线人数、奖励或我的虚构名次。

## 精确文件

生产：

- `lib/features/discovery/dynamic/domain/dynamic_models.dart`
- `lib/features/discovery/dynamic/domain/dynamic_repository.dart`
- `lib/features/discovery/dynamic/data/ranking_contract.dart`（新增）
- `lib/features/discovery/dynamic/data/backend_dynamic_repository.dart`
- `lib/features/discovery/dynamic/data/mock_dynamic_repository.dart`
- `lib/features/discovery/dynamic/presentation/dynamic_pages.dart`（只榜单页/卡片及旧榜单专用 helper）

测试：

- `test/s16_ranking_fixtures.dart`（新增冻结 wire fixture）
- `test/s16_ranking_parser_test.dart`（新增精确值、坏合同、窗口、分页、历史ID）
- `test/s16_ranking_repository_test.dart`（新增 loopback HTTP、真 Authorization 切换与401）
- `test/s16_ranking_widget_test.dart`（新增10项页面行为/竞态/窄屏大数/Mock边界）
- `test/backend_dynamic_repository_contract_test.dart`（仅替换旧榜单 alias/numeric 成功 fixture；
  原榜单负例加合法S16元数据，保留其实际失败字段；动态/评论其他断言不改）
- `test/dynamic_presentation_reliability_test.dart`（只补 fetchRanking 新分页可选参数）

## 实际执行证据

固定 `/Users/kongzheng/Documents/ny/.tooling/flutter-3.44.7/bin/flutter`，Flutter3.44.7 / Dart3.12.2。
独立树已执行 `flutter pub get --offline`，exit0。

- RED `49471` exit1：真实旧 HTTP body 为 `{theType:2}`，不是冻结 period 合同。
- 初步 GREEN `66029` exit0：上述单项通过。
- `31050` exit1：10 widget 中6PASS/4FAIL；一项真实65位金额 RenderFlex 溢出，
  三项为测试定位器（多个 Scrollable/按钮实际名）问题。均未跳过；金额改为完整换行。
- `54818` exit1：111PASS/1FAIL，fixture 修改误匹配动态分页负例；已恢复该负例原貌。
- `54748` exit1：121PASS/1FAIL，翻页清列表时旧滚动位置导致切榜不可见；新增榜单独立
  ScrollController 在开始新读取时回到顶部，保留请求/身份 fence。
- RED `98782` exit1：真实历史 room.public_id=`100001` 被额外 UUID 限制拒绝；已去掉
  非合同限制，保留必需字段、金额和分页严格校验。
- `83372` exit1：165PASS，另有一个不存在的测试文件名加载失败；正确名称为
  `s14_comment_contract_test.dart`。不将该命令记为全绿。
- 最终 `9299` **exit0，182PASS，无失败/跳过**：下面14文件定向门禁。
- analyze `88404` exit1 为新增测试两处空 List 类型推断 warning；已明确类型。
  最终 analyze `31224` **exit0，No issues found**。
- 最终12个修改/新增Dart文件 `dart format --output=none --set-exit-if-changed`：
  **exit0，0 changed**；`git diff --check` exit0。

最终命令（本树 `build/s16-evidence/targeted.log` 为未入库运行日志）：

```sh
/Users/kongzheng/Documents/ny/.tooling/flutter-3.44.7/bin/flutter test --no-pub --reporter expanded \
  test/s16_ranking_parser_test.dart test/s16_ranking_repository_test.dart \
  test/s16_ranking_widget_test.dart test/backend_dynamic_repository_contract_test.dart \
  test/backend_dynamic_repository_test.dart test/dynamic_repository_test.dart \
  test/dynamic_presentation_reliability_test.dart test/dynamic_detail_short_refresh_test.dart \
  test/m23_pages_test.dart test/s14_comment_contract_test.dart test/s14_comment_widget_test.dart \
  test/api_client_identity_bound_test.dart test/discovery_comment_lifecycle_test.dart \
  test/dynamic_request_id_test.dart
/Users/kongzheng/Documents/ny/.tooling/flutter-3.44.7/bin/flutter analyze --no-pub
```

测试覆盖快速切榜/周期/翻页、旧成功与401/错误、A→B→A、登出清除、页面销毁重建；
HTTP测试实际改变 Authorization 并延迟 openUrl，验证跨身份零发送及401不跨账号重试，
同身份正常 refresh 保留。原动态/评论/入口生命周期与贡献榜继续回归，未禁用/降低覆盖。

## 剩余验收

真实 Backend 联调、普通设备交互、厂商和全仓测试 **NOT_RUN**。本次182PASS只代表上述
本地 Flutter/loopback/mock 门禁；不等于三端部署或正式上线。跨页不承诺冻结快照；
昵称/金额/名次均以当前响应为准，不做本地汇总或奖励。主任务复核集成后安排设备验收。
