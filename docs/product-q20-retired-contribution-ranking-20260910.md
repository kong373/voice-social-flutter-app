# Q20 仅保留三类日周月榜

排行榜页只提供魅力榜、财富榜、房间榜；移除累计贡献入口/说明。Live 与 Mock repository 均在任何网络请求前拒绝旧 contribution 请求（code41001）。保留旧 enum/parser 只为旧数据兼容和明确拒绝老调用，不是仍可访问的产品入口。价格、送礼记分、后端排序和原三榜精确金额合同不改。

2026-09-10 Flutter3.44.7：页面无第四榜、旧查询不触网两个用例真实 2 RED 后修正；排行榜页面/repository/parser 三文件 94 tests PASS，相关完整目录 analyze 无问题，format/diff-check PASS。历史 parser 回归仍可解析旧快照，不据此恢复旧入口。最终设备验收仍待同候选执行。

日志：工作区 `artifacts/product/filled-decisions-20260909/q20-retired-ranking-flutter-{red,green,analyze}-20260910.log`。
