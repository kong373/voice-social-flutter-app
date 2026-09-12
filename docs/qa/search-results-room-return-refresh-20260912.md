# SearchResults 房间返回刷新

基线为 `baca98cdb516efe71988a9a0d5a214aae5ade577`，候选分支为
`codex/search-results-room-return-refresh-20260912`。本次范围仅覆盖
`SearchResultsPage` 的房间入口及最小 Widget 回归。

Native P2 已由主流程确认：SE3 user214 搜索 `999547` 时结果卡显示「已关闭」，
房间 164 随后被房主重新开放为 PUBLIC；原失败页重试入房并正常离开后，返回搜索结果仍
显示「已关闭」。对应证据为
`ios-baca98c-room-revocation-db.json` 与
`ios-baca98c-se3-search-stale-closed-after-reopen.jpg`，均位于
`/Users/kongzheng/Documents/ny/artifacts/release/task15-unified-20260911/`。

根因是搜索结果入口 fire-and-forget 推入 `RoomPage`，返回时没有重新读取当前搜索，因而
保留旧的 `DiscoveryRoom.isClosed`。修复等待正常房间路由返回，再复用现有 `_load()`；
没有新增 poller 或全局状态，现有请求代次、搜索类型、关键词、取消和分页 fence 仍由
`_load()` / `_loadMore()` 管理。房间结果卡和用户当前房间入口共用该返回刷新路径；未改
message、room、Backend、DB、设备或 vendor。

## 验证

- RED：
  `/Users/kongzheng/Documents/ny/artifacts/release/task15-unified-20260911/search-results-room-return-refresh-red.log`，
  `reloads the active search after returning from a room route` 在基线中只记录 1 次请求而非
  预期的 2 次，`TEST_EXIT=1`；同文件其余 4 条既有测试通过。
- GREEN：
  `/Users/kongzheng/Documents/ny/artifacts/release/task15-unified-20260911/search-results-room-return-refresh-green.log`，
  该文件 5/5 通过，`TEST_EXIT=0`。
- 相关 race 回归：
  `/Users/kongzheng/Documents/ny/artifacts/release/task15-unified-20260911/search-results-room-return-refresh-related-tests.log`，
  `search_results_pagination_test.dart` 与 `discovery_presentation_race_test.dart` 共 8/8，
  `TEST_EXIT=0`。
- Analyze：
  `/Users/kongzheng/Documents/ny/artifacts/release/task15-unified-20260911/search-results-room-return-refresh-analyze.log`，
  `ANALYZE_EXIT=0`。
- Format：
  `/Users/kongzheng/Documents/ny/artifacts/release/task15-unified-20260911/search-results-room-return-refresh-format.log`，
  `FORMAT_EXIT=0`；`git diff --check` 通过。

本次只读/自动化候选验证未额外运行 native、DB、HTTP 或重建/重装；主流程使用当前 source
SHA 另行安装并复测。
