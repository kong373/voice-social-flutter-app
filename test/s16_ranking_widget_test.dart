import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/discovery/dynamic/data/mock_dynamic_repository.dart';
import 'package:voice_social_app/features/discovery/dynamic/data/ranking_contract.dart';
import 'package:voice_social_app/features/discovery/dynamic/domain/dynamic_models.dart';
import 'package:voice_social_app/features/discovery/dynamic/presentation/dynamic_pages.dart';
import 's16_ranking_fixtures.dart';

void main() {
  Future<void> mount(
    WidgetTester tester,
    MockDynamicRepository repository,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.social(),
        home: RankingPage(repository: repository),
      ),
    );
    await tester.pump();
  }

  Future<void> choose(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.tap(find.text(label));
    await tester.pump();
  }

  testWidgets(
    '65-digit fen is fully displayed exactly at phone width with server window',
    (tester) async {
      final repo = ControlledRankings();
      await mount(tester, repo);
      repo.calls.single.succeed(score: '9' * 65);
      await tester.pumpAndSettle();
      expect(find.text('${'9' * 63}.99 元'), findsOneWidget);
      expect(
        find.textContaining('2026-09-09 00:00 至 2026-09-10 00:00（不含）'),
        findsOneWidget,
      );
      expect(find.textContaining('同分先达到者优先'), findsOneWidget);
      expect(find.textContaining('本期剩余'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'rapid day/week/month and board changes never accept old success or errors',
    (tester) async {
      final repo = ControlledRankings();
      await mount(tester, repo);
      await choose(tester, '周榜');
      await choose(tester, '月榜');
      expect(repo.calls.map((r) => r.period), [
        RankingPeriod.day,
        RankingPeriod.week,
        RankingPeriod.month,
      ]);
      repo.calls[2].succeed(name: '月新结果');
      await tester.pumpAndSettle();
      repo.calls[0].succeed(name: '日旧结果');
      repo.calls[1].fail('周旧错误');
      await tester.pumpAndSettle();
      expect(find.text('月新结果'), findsOneWidget);
      expect(find.text('日旧结果'), findsNothing);
      expect(find.text('周旧错误'), findsNothing);
      await choose(tester, '财富榜');
      expect(find.text('月新结果'), findsNothing);
      expect(repo.calls.last.board, RankingBoard.wealth);
      expect(repo.calls.last.period, RankingPeriod.month);
      repo.calls.last.succeed(name: '财富当前');
      await tester.pumpAndSettle();
      expect(find.text('财富当前'), findsOneWidget);
    },
  );
  testWidgets(
    'only charm wealth and room boards are available with gift periods',
    (tester) async {
      final repo = ControlledRankings();
      await mount(tester, repo);
      expect(find.text('贡献榜'), findsNothing);
      expect(find.textContaining('累计贡献'), findsNothing);
      expect(find.text('魅力榜'), findsOneWidget);
      expect(find.text('财富榜'), findsOneWidget);
      await choose(tester, '房间榜');
      repo.calls.last.succeed();
      await tester.pumpAndSettle();
      expect(find.text('日榜'), findsOneWidget);
      expect(find.text('101.00 元'), findsOneWidget);
      repo.calls.first.succeed(name: '旧魅力');
      await tester.pumpAndSettle();
      expect(find.text('旧魅力'), findsNothing);
    },
  );
  testWidgets(
    'server pagination replaces page, honors totals and resets on period change',
    (tester) async {
      final repo = ControlledRankings();
      await mount(tester, repo);
      repo.calls.last.succeed(total: 21, name: '第一页');
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('ranking-next')),
        500,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const ValueKey('ranking-next')));
      await tester.pump();
      expect(repo.calls.last.page, 2);
      final page2 = repo.calls.last;
      page2.succeed(total: 21, name: '第二页');
      await tester.pumpAndSettle();
      expect(find.text('第二页'), findsOneWidget);
      expect(find.text('第一页'), findsNothing);
      expect(find.text('第 2 页 / 共 2 页 · 21 项'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(find.byKey(const ValueKey('ranking-next')))
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(find.text('周榜'));
      await choose(tester, '周榜');
      expect(repo.calls.last.page, 1);
      expect(repo.calls.last.period, RankingPeriod.week);
      repo.calls.last.succeed(total: 0);
      await tester.pumpAndSettle();
      expect(find.text('当前榜单暂无有效数据。'), findsOneWidget);
      expect(find.text('第 1 页 / 共 0 页 · 0 项'), findsOneWidget);
      expect(find.byKey(const ValueKey('ranking-window')), findsOneWidget);
    },
  );
  testWidgets('late page2 is ignored after switching boards and new page1', (
    tester,
  ) async {
    final repo = ControlledRankings();
    await mount(tester, repo);
    repo.calls.last.succeed(total: 21);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('ranking-next')),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const ValueKey('ranking-next')));
    await tester.pump();
    final old = repo.calls.last;
    await choose(tester, '财富榜');
    expect(repo.calls.last.page, 1);
    repo.calls.last.succeed(name: '新财富');
    await tester.pumpAndSettle();
    old.succeed(total: 21, name: '旧第二页');
    await tester.pumpAndSettle();
    expect(find.text('新财富'), findsOneWidget);
    expect(find.text('旧第二页'), findsNothing);
  });
  testWidgets(
    'A→B→A and logout clear rows and fence stale requests across generations',
    (tester) async {
      final repo = ControlledRankings();
      await mount(tester, repo);
      final oldA = repo.calls.single;
      repo.identity.value = (20002, 2);
      await tester.pump();
      repo.calls.last.succeed(name: 'B当前');
      await tester.pumpAndSettle();
      expect(find.text('B当前'), findsOneWidget);
      repo.identity.value = (10001, 3);
      await tester.pump();
      expect(find.text('B当前'), findsNothing);
      oldA.succeed(name: 'A旧结果');
      await tester.pump();
      expect(find.text('A旧结果'), findsNothing);
      repo.calls.last.succeed(name: 'A新结果');
      await tester.pumpAndSettle();
      expect(find.text('A新结果'), findsOneWidget);
      repo.identity.value = (0, 4);
      await tester.pumpAndSettle();
      expect(repo.calls, hasLength(3));
      expect(find.text('A新结果'), findsNothing);
      expect(find.text('请登录后查看排行榜'), findsOneWidget);
    },
  );
  testWidgets('late 401 from A cannot display reauthentication for B', (
    tester,
  ) async {
    final repo = ControlledRankings();
    await mount(tester, repo);
    final old = repo.calls.single;
    repo.identity.value = (20002, 2);
    await tester.pump();
    repo.calls.last.succeed(name: 'B结果');
    await tester.pumpAndSettle();
    old.completer.completeError(
      const ApiException(kind: ApiFailureKind.unauthorized, message: 'A已过期'),
    );
    await tester.pumpAndSettle();
    expect(find.text('B结果'), findsOneWidget);
    expect(find.text('A已过期'), findsNothing);
  });
  testWidgets(
    'current failure clears data and manual retry keeps selected period/page',
    (tester) async {
      final repo = ControlledRankings();
      await mount(tester, repo);
      await choose(tester, '月榜');
      repo.calls.last.fail('错单位，拒绝显示');
      await tester.pumpAndSettle();
      expect(find.text('错单位，拒绝显示'), findsOneWidget);
      expect(find.byKey(const ValueKey('ranking-pagination')), findsNothing);
      await tester.tap(find.text('重新加载'));
      await tester.pump();
      expect(repo.calls.last.period, RankingPeriod.month);
      expect(repo.calls.last.page, 1);
      repo.calls.last.succeed(name: '重读成功');
      await tester.pumpAndSettle();
      repo.calls.first.fail('旧日错误');
      await tester.pumpAndSettle();
      expect(find.text('重读成功'), findsOneWidget);
    },
  );
  testWidgets('dispose and remount does not consume the prior Future', (
    tester,
  ) async {
    final repo = ControlledRankings();
    await mount(tester, repo);
    final old = repo.calls.single;
    await tester.pumpWidget(const SizedBox());
    await mount(tester, repo);
    repo.calls.last.succeed(name: '新页面');
    old.succeed(name: '已销毁页面');
    await tester.pumpAndSettle();
    expect(find.text('新页面'), findsOneWidget);
    expect(find.text('已销毁页面'), findsNothing);
  });
  testWidgets('Mock is explicitly sample data, not live or a server window', (
    tester,
  ) async {
    await mount(tester, MockDynamicRepository());
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ranking-demo')), findsOneWidget);
    expect(find.byKey(const ValueKey('ranking-window')), findsNothing);
    expect(find.text('1289.00 元'), findsOneWidget);
  });
}

class ControlledRankings extends MockDynamicRepository {
  final identity = ValueNotifier<(int, int)>((10001, 1));
  final calls = <RankingCall>[];
  @override
  (int, int) get rankingIdentity => identity.value;
  @override
  Listenable get rankingIdentityChanges => identity;
  @override
  Future<RankingSnapshot> fetchRanking({
    required RankingBoard board,
    required RankingPeriod period,
    int page = 1,
    int pageSize = 20,
  }) {
    final call = RankingCall(board, period, page, pageSize);
    calls.add(call);
    return call.completer.future;
  }
}

class RankingCall {
  RankingCall(this.board, this.period, this.page, this.size);
  final RankingBoard board;
  final RankingPeriod period;
  final int page, size;
  final completer = Completer<RankingSnapshot>();
  void succeed({String name = '当前榜单', String score = '10100', int total = 1}) =>
      completer.complete(
        parseRanking(
          rankingWire(
            board: board,
            period: period,
            page: page,
            size: size,
            total: total,
            name: name,
            score: score,
          ),
          board: board,
          period: period,
          page: page,
          pageSize: size,
          viewerUserId: 10001,
        ),
      );
  void fail(String message) => completer.completeError(
    ApiException(kind: ApiFailureKind.protocol, message: message),
  );
}
