# Q18 Flutter 装扮续购与只读预览

独立树 `/Users/kongzheng/Documents/ny/.worktrees/flutter-dress-renewal-20260910`，分支 `codex/flutter-dress-renewal-20260910`，基线 `4c0bd66e7a8af56099198768849ded8e437b2e29`。不 push。

## 产品与接口依据

已完整读取根 `artifacts/product/filled-decisions-20260909/answers.json` 的 Q18 问答：重复购买延长、无永久新售、同类型穿戴一个、仅预览。对照 Backend `92184b74533db5dc02e316b26398352e7c88f3da` 及独立树 `docs/product-q18-decoration-renewal-20260910.md` 后续已购列表追加合同。

交付时主同步已集成 Backend `cc884aa/e0f2397`（主 `a9ab547`），已购接口包含本人的 legacy/expired。Flutter 主 `420d93c` 含 Q02；本独立提交保持既定 `4c0bd66` 基线，交由主做合并态测试，未自行 cherry 其他域。

- `durationDays` 必须是 Backend 显式非负整数；缺失/null/string/负数不默认为 30 天。新购/续购必须有限时长且存在于在售目录。`durationDays=0` 或已拥有且 `expiresAt=null` 为历史永久，保留展示和既有穿/脱，不提供新购或续购。
- `GET /app-api/mall/index` 是在售目录；`GET /app-api/user/userDecorations/getList` 现在仅为本人的已购历史。两次读取使用同一 actor/generation，按 UUID 合并，后读已购投影提供当前状态，历史停售项不丢失。每个列表重复 ID 拒绝；其中一个读取失败时不把半张列表当成功。内部 `forSale` 来自在售列表成员关系，不增加 Backend JSON 字段。
- 购买仍使用原 `POST /app-api/mall/userBuyOrGiveGoods`、body `{decorationId}` 和 `X-Request-Id`。商品成本保持整币，不做十分之一缩放。成功后的权威状态只从已购列表回读，不把历史购买回执当当前穿戴或到期，不在 live 本地计算到期。
- 已拥有商品有独立“续购”操作，确认实际天数和整币扣费；仍有原穿/脱动作。未过期续购保留有效穿戴，过期不自动上身。Mock 使用稳定可注入时钟按 `max(now, expiresAt)+durationDays` 计算并保持同类型穿戴一个。

## 身份、未知结果与共享文件边界

页面监听已有 `sessionManager` 的 actor/generation，确认弹窗、加载、保存、离页和依赖替换都隔离晚结果/晚错误；账号 ABA 使旧确认无效，同账号 token refresh 不使有效确认失效。只关闭本页面持有的 DialogRoute。

装扮 repo 的 single-flight、串行队列和 requestId 按 actor/generation/商品绑定，绑定回调传至现有 POST 和新增 GET 薄封装。旧账号排队任务不会以新账号执行，两个 generation 不共用 flight。未知结果保持原 key/body；已拥有不能证明本次续购成功。错误回执、已接受回执后目录回读失败都不能轮换购买 key。只有确认完成后用户另发新购买才分配新 key。页面保留原操作快照；停售或列表不再返回该项时，未知购买仍显示“重试原购买”，不伪造已拥有或穿戴。

用户专门授权 `ApiClient.getBoundToIdentity`：仅新增 15 行公开薄封装，原样转交 `_request(method:'GET', authenticated:true, query, headers, requireIdentity)`；未修改 `_request`、refresh、HTTP/media 实现。安全审查重点用于这些身份和金额重试边界，TDD 与验证闭环仅运行本批相关本机测试。

### 主集成接线（Ampere 持有 AppDependencies）

本树没有修改 AppDependencies/pubspec。Backend catalog 构造增加以下两个可选参数，主已收到精确签名并协调接线；未注入时仅装扮操作 fail closed，不改变充值/礼物旧入口：

```dart
BackendCommerceCatalogRepository({
  // existing arguments unchanged
  int? Function()? currentUserIdProvider,
  int Function()? identityGeneration,
})

// AppDependencies existing catalog construction:
currentUserIdProvider: () => sessionManager.session?.userId,
identityGeneration: () => sessionManager.identityGeneration,
```

不需要新增 Listenable，也没有新角色或支付机制。Backend 已购列表拆分和上述两行须一并由主集成；本树不宣称已完成真实联调。

## 只读预览及具体素材缺项

新 `DecorationPreview` 依商品 `assetKey` 映射，只显示已明确配置的 bundled asset，不把任意字符串当 URL 或文件路径，不产生读写 API、试用、穿戴或扣币。预览弹窗和列表图片使用同一映射。

下列 Backend 内置 key 当前没有专属交付素材，live 明确显示“预览未配置”，未拿同类型通用头像/礼物图冒充商品：

- `decoration/star-ring-frame`
- `decoration/stream-entry`
- `decoration/companion-badge`

Mock 显式使用现存的 `assets/runtime/avatar-rose.png`、`avatar-silver.png`、`room-cover-festival.png`、`gift-blossom.png`；仅非 live 可选这些受限路径。两个同类型商品使用不同素材的 widget 测试验证真实 `AssetImage.assetName`，不是仅断言预览按钮存在。真实商品视觉预览仍待专属素材，不宣称这部分美术已完成。

## 验证与证据

固定 `/Users/kongzheng/fvm/versions/3.44.7/bin/flutter`，本机实测 3.44.7。已 offline pub get；pubspec/lock 未修改。所有日志位于根 `artifacts/product/filled-decisions-20260909/`，没有复制旧通过结果作为新改动证据。

真实行为 RED：

- `q18-flutter-renewal-red.log`：5 FAIL（缺失/错误 duration 被接收、重复购买拒绝）。
- `q18-flutter-ui-red.log`：2 FAIL（续购、预览缺失）。
- `q18-flutter-identity-intermediate.log`：18 PASS / 1 FAIL，GET pending-open 期间 ABA 未阻断发送；新薄封装修复。
- `q18-flutter-unknown-receipt-red.log`：错误回执后 key 从 test-1 变 test-2。
- `q18-flutter-accepted-read-red.log`：购买已接受后 GET 403，重试 key 从 test-1 变 test-2。
- `q18-flutter-catalog-union-red.log`：仅读已购漏掉在售未购商品。
- `q18-flutter-retired-retry-red.log`：停售后原未知购买重试按钮消失。
- `q18-flutter-permanent-rights-red.log`：永久旧权益展示/操作未按追加合同保留；首个失败断言为旧“仅查看”文案。

最终去重 **93 PASS**（不重复计入中间轮次）：

| 检查 | 结果 | 日志 |
| --- | --- | --- |
| 新合同 24 + 旧 catalog/幂等 33 | 57 PASS | `q18-flutter-contract-delivery-green.log` |
| 新 widget 18 + CM-010 四视口 | 22 PASS | `q18-flutter-ui-delivery-green.log` |
| 既有 ApiClient 身份绑定/refresh 兼容 | 14 PASS | `q18-flutter-api-regression.log` |
| 全 analyze | 0 issues | `q18-flutter-analyze-delivery.log` |

```sh
/Users/kongzheng/fvm/versions/3.44.7/bin/flutter test --no-pub test/decoration_renewal_contract_test.dart test/backend_commerce_catalog_repository_contract_test.dart test/commerce_catalog_repository_test.dart test/decoration_purchase_request_id_test.dart --reporter expanded
/Users/kongzheng/fvm/versions/3.44.7/bin/flutter test --no-pub test/decoration_renewal_ui_test.dart test/commerce_visual_responsiveness_test.dart --name 'renewal|purchase|permanent|mock products|unavailable|ABA|token refresh|late|leaving during|owned decoration|preview action|CM-010' --reporter expanded
/Users/kongzheng/fvm/versions/3.44.7/bin/flutter test --no-pub test/api_client_identity_bound_test.dart test/api_client_test.dart --reporter expanded
/Users/kongzheng/fvm/versions/3.44.7/bin/flutter analyze --no-pub
```

原 catalog 断言保留；夹具仅补真实 duration 和身份绑定，原单 GET 断言迁移为精确商城+已购两 GET 且均无 body。没有删资金、错误回执、未知重试或同类型装备断言。格式检查和 `git diff --check` 通过。

## 未做与局限

未运行设备、厂商、DB、Backend/Maven/Docker、全量 Flutter tests；未改 media/auth/AppDeps/pubspec、分享、gift、麦位或原服务。没有试用、会员、背包。live 到期全部来自 Backend；Mock 的时钟计算不是线上权益来源。

未知请求只在现有 repo 实例按身份代次保留，页面快照仅当前页面存活期有效；不提供进程重启恢复，也不会把登出/ABA 之前的请求自动改绑到新身份发送。身份隔离阻止失效后的发送/接受结果，不能撤销已经到达服务器的购买。主仍负责跨树集成与真实 HTTP 验证。
