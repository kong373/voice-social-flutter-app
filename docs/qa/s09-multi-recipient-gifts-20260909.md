# S09 / Q12-03 Flutter 多收礼人独立赠送

## 基线与范围

- 基线：`c7814475d7ffe7d662462df94e3eea5a0dd8f13c`。
- 分支：`codex/flutter-multi-recipient-gifts-20260909`。
- 决策只读来源：`/Users/kongzheng/Documents/ny/artifacts/product/filled-decisions-20260909/answers.json` Q12-02/03/04、`supplement-answers.json` S09。
- 各收礼人独立结算；一个收礼人的全部数量通过一条旧 single-recipient 请求提交，不拆成逐个礼物请求。分成、舍分、权限和实际余额由 Backend 决定。
- 没有新增批量 Backend 事务，没有修改 Backend、shared ApiClient、充值服务、财务政策或房间入房/麦位权限。
- `video_runtime_room_page.dart` 只改 `_showGiftSheet` 目标去重与 coordinator 接线；`room_controller.dart` 只加可选 coordinator 依赖。未改 Curie 的 JOIN / 密码房错误重试范围。

## 精确文件

| 文件 | 改动 |
| --- | --- |
| `lib/features/room/domain/gift_send_models.dart`（新） | 不可变单人命令、严格回执匹配、独立结果和非 secret journal 序列化；新增可选 `GiftCommandRepository` 能力，不改旧 `RoomRepository.sendGift` 签名 |
| `lib/features/room/application/gift_send_coordinator.dart`（新） | App 生命周期内按账号保存计划、持久化后发送、逐笔状态、原回执恢复、身份代际与并发去重 |
| `lib/features/room/data/backend_room_repository.dart` | 冻结当前 lease 的 sessionId；复用 `postBoundToIdentity`；恢复 GET 不依赖当前 lease |
| `lib/features/room/data/mock_room_repository.dart` | 同样的独立命令/回执规则、当前麦上目标校验；从现有 Mock 目录取价并扣同一个精确余额，不伪装 live/provider 成功 |
| `lib/app/app_dependencies.dart` | App 单例 coordinator，现有 session tuple/Listenable 和 KeyValueStore 注入；Mock 目录/精确余额必要接线 |
| `lib/features/room/application/room_controller.dart` | 共享 coordinator 传递，不把唯一未决记录放在 controller 内 |
| `lib/features/room/presentation/gift_sheet.dart` | 多选、BigInt 总预览、逐人结果、显式恢复/继续、充值返回再次确认 |
| `lib/features/room/presentation/video_runtime_room_page.dart` | 当前麦上身份去重，送礼 capability 与目标回调接线 |
| `test/gift_send_coordinator_test.dart`（新） | 9 个状态、持久化、身份、幂等及精确金额回归 |
| `test/backend_gift_command_contract_test.dart`（新） | 13 个真实 loopback HTTP / 严格回执 / Authorization / 401 测试 |
| `test/gift_sheet_independent_results_test.dart`（新） | 4 个真实 App/Mock 接线及结果页/重建/换号/重复点击回归 |
| `test/gift_sheet_live_targets_test.dart` | 补多选独立提交及含 0.1 币余额预览，保留旧目标/权限/充值相关断言 |
| 本文档 | 范围、恢复边界、验证证据和未验证项 |

## 写请求与恢复约束

继续使用既有单人 sendGift 路径。每个收礼人一个随机独立 `X-Request-Id`，body 固定为 `{roomId,giftId,receiverUserId,quantity,source:'WALLET',sessionId}`；actorId 单独绑定当前身份。整组预览先转 BigInt 再相乘，余额使用 tenths；不会把旧整币单价再次放大十倍。

首次点击赠送时冻结所有目标、数量、key、原 sessionId，并先成功保存 journal；每笔在 POST 前再次保存 unknown 状态。发请求前、`openUrl` 之后发 body 前、401 恢复前及响应后检查原身份代际、原 room lease 和当前麦上目标。沿用同账号正常 refresh，不允许 A 的 body/key 与 B 的 token 拼接。

未知项先 GET 原回执，严格验证 room/sender/receiver/gift/quantity/requestId/source、成功状态、transferId、providerInvocation，以及 GET 的 reconciled=true。现有 Backend parser 继续校验金额、币种及 delivery mode。404、字段不匹配或查询失败均不证明原请求未落账，保持 unknown。

- `succeeded`：不再 POST；后续失败不回滚其他人的成功。
- `unknown`：保留原 key/body；即使之后收到 401、403 或 40903，也不清原命令。
- `queued`：尚未 POST，可明确取消；不能因此取消/重发成功或未知项。
- `rejected`：仅首次明确 HTTP 4xx（排除所有 409）且属于既有校验/业务/鉴权拒绝才记录；不显示成功。
- 原 lease 变化或目标已下麦：未知项仍可只读查询；绝不在原 key 下重建 sessionId。尚未发送项记录 notSent，不产生经济写。
- “查询后重试未确认项 / 继续未发送项”是明确用户动作，逐项先查询，只允许仍然未知且原 lease/当前目标仍有效的同 body POST。不会整批重发。
- 一个账号有未决计划时，不开启另一计划；全部终态后用户明确“完成查看，重新选择礼物”才清 journal。没有自动换 key、自动补发或自动充值返回赠送。

旧单人 API、原 receipt GET 和 controller 的旧接口保持；生产 App 的新 GiftSheet 始终注入 coordinator。旧注入测试/单人调用方仍保留原 onSend 参数。新生产页成功后展示逐人结果，不再把一个 bool 当成整批成功并自动关闭弹层。

## 持久化和账号边界

复用生产 `SecureKeyValueStore`，key 为 `room.gift-journal.v1.<backend namespace>.<actorId>`；存储最小命令字段、计划单价、状态及成功 transferId，不存 token、密码、头像或姓名。账号 A/B 隔离，identity generation 独立 Future；A→B→A 旧 Future 的晚成功不写入新代际 UI。弹层/controller 销毁不删除 App-owned journal。

恢复读取不会自动 POST。旧计划来自其他房间时可以查询，但不能从当前房间重发。安全存储读取失败/格式错误时阻止新赠送；保存失败发生在首个 POST 前时零发送。

已实测序列化后用新的 store/coordinator 实例重建，并保留原 key/字节等价 body。**这不是实际设备杀进程/重启验收**：真实 Secure Storage 平台行为、应用被杀时的 I/O、卸载/重装不在本轮验证中。Mock 的回执服务仅内存存在；Mock 重建后没有回执时保持 unknown，不冒充已恢复成功。

## TDD 与实际结果

固定 Flutter **3.44.7** / Dart **3.12.2**；仅本地 Flutter 单元/widget/loopback HTTP，无设备、DB、厂商或真实礼物交易。

| 验证 | handle / 结果 |
| --- | --- |
| 多选旧实现 RED：选择两人仍只有单人价格，期望 `赠送 · 20` 不存在 | 26059 / exit 1 |
| 双击 RED：第二次点击提前推进 read ticket，第一次完成后仍 stuck busy | 26976 / exit 1；修正 early guard 后 26225 / exit 0，3 PASS |
| App/Mock 精确余额 RED：两人送出后余额仍 20.1；后续暴露目录 ID 与旧 Mock 价格表不一致 | 14489 / exit 1；58822 / exit 1；修复后 93794 / exit 0，4 PASS，20.1 → 0.1 |
| 早期 Mock 测试曾在 fakeAsync 中直接 await join，手动中断后改为 tester.runAsync 夹具 | 95872 / 中断，NOT_PASS |
| 最终 11 文件定向批 | **2700 / exit 0，172 PASS，0 FAIL，0 SKIP** |
| 全项目 flutter analyze | **33674 / exit 0，No issues found** |
| 收尾仅调整“可多选/未发送”文案后复验三个 GiftSheet 文件（上述 172 项的子集，不重复累加） | **53202 / exit 0，20 PASS** |
| 最终全项目 flutter analyze / 12 个变更 Dart 文件 format 检查 / git diff --check | **9761 / exit 0，No issues found**；format 0 changed / exit 0；diff check exit 0 |

最终 172 项按 runner JSON 报告汇总：

| 测试文件 | PASS |
| --- | ---: |
| `gift_send_coordinator_test.dart` | 9 |
| `backend_gift_command_contract_test.dart` | 13 |
| `gift_sheet_independent_results_test.dart` | 4 |
| `gift_sheet_live_targets_test.dart` | 10 |
| `gift_sheet_recharge_balance_test.dart` | 6 |
| `backend_room_repository_contract_test.dart` | 50 |
| `room_controller_test.dart` | 13 |
| `room_controller_race_test.dart` | 11 |
| `first_party_live_mutation_coverage_test.dart` | 7 |
| `commerce_visual_responsiveness_test.dart` | 40 |
| `commerce_live_ui_contract_test.dart` | 9 |

新增核心覆盖：一人全 quantity 单笔/多 key；success+rejected+unknown 混合结果；未知 GET 成功不再 POST；八种错回执字段；新 lease 不复用原 key 换 session；下麦仍可 GET；冷对象重建；账号和 Backend namespace 隔离；A→B→A 晚响应；真实变化的 Authorization+延迟 openUrl；401 换身份零跨号重试；同身份 refresh 同 key/body；目标在 openUrl 等待中离麦后零 body；双击去重；存储失败零发送；BigInt 大数与 0.1 币。

复现最终定向命令（在本 worktree）：

```sh
/Users/kongzheng/Documents/ny/.tooling/flutter-3.44.7/bin/flutter test --no-pub --reporter expanded --file-reporter json:.dart_tool/s09-targeted-tests.jsonl \
  test/gift_send_coordinator_test.dart \
  test/backend_gift_command_contract_test.dart \
  test/gift_sheet_independent_results_test.dart \
  test/gift_sheet_live_targets_test.dart \
  test/gift_sheet_recharge_balance_test.dart \
  test/backend_room_repository_contract_test.dart \
  test/room_controller_test.dart \
  test/room_controller_race_test.dart \
  test/first_party_live_mutation_coverage_test.dart \
  test/commerce_visual_responsiveness_test.dart \
  test/commerce_live_ui_contract_test.dart
/Users/kongzheng/Documents/ny/.tooling/flutter-3.44.7/bin/flutter analyze --no-pub
git diff --check
```

## 保留回归与已证明的基线失败

曾增加 `video_runtime_ui_test.dart` 跑更宽的 12 文件批：**68283 / exit 1，180 PASS / 2 FAIL**。两个失败均发生在送礼操作之前：

1. `video_runtime_ui_test.dart:166`，`home enters room, opens gift sheet and minimizes the session`：找不到旧 `video-room-mood-stage-standard`。
2. `video_runtime_ui_test.dart:386`，`room gift to tools remains stable at cloud-constrained 360 width and 1.3x text`：旧公屏高度期望 `(340,395)`，实际 `(340,283)`。

用临时、干净、detached 的精确 c7814475 基线单独运行这两项，**89875 / exit 1，同样两处、相同差值**；临时 worktree 已回收，主树未动。未放宽布局断言、未 Disabled/skip、未把它们计入 PASS。这两项布局夹具需要主线在九麦布局范围核对。第一个旧用例后续“单次成功自动关闭并显示单人 overlay”也不再代表本批逐人结果页，新的结果行为由 `gift_sheet_independent_results_test.dart` 覆盖；旧文件尚未修改。

已有 recharge-null/错误余额/返回不自动赠送、权限撤销、目标变化、controller lease/race、旧 Backend 严格回执和提现 UI 用例继续运行，没有为通过本批删除旧断言。未运行 Flutter 全量；Backend 联调、DB、实际设备、RTC/IM/支付厂商均 **NOT_RUN**。本批没有占用 DB slot，没有部署或 push。
