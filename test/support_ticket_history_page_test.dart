import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/social/data/mock_social_repository.dart';
import 'package:voice_social_app/features/social/domain/social_models.dart';
import 'package:voice_social_app/features/social/presentation/social_pages.dart';

const _offline = ApiException(
  kind: ApiFailureKind.network,
  message: '连接失败，请重试',
);

SupportTicket _ticket(String id, {bool resolved = false}) => SupportTicket(
  id: id,
  subject: '问题$id',
  content: '反馈内容$id',
  status: resolved
      ? SupportTicketStatus.resolved
      : SupportTicketStatus.submitted,
  statusText: resolved ? '问题已处理' : '已提交，等待客服处理',
  createdAt: DateTime.utc(2026, 9, 9),
  progressAvailable: true,
);

SocialPage<SupportTicket> _page(
  List<SupportTicket> items, {
  int page = 1,
  bool hasMore = false,
}) => SocialPage<SupportTicket>(
  items: items,
  page: page,
  pageSize: 20,
  total: hasMore ? 21 : items.length,
  hasMore: hasMore,
);

void main() {
  Future<void> mount(
    WidgetTester tester,
    _Repository repository, {
    bool history = false,
  }) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: _Dependencies(repository),
        child: MaterialApp(
          theme: AppTheme.social(),
          home: history
              ? const SupportTicketHistoryPage()
              : const HelpCenterPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'ordinary help entry reopens history and fetches latest ticket status',
    (tester) async {
      final repo = _Repository()
        ..onPage = (p) async => _page(<SupportTicket>[_ticket('1')]);
      await mount(tester, repo);
      await tester.tap(find.text('我的反馈'));
      await tester.pumpAndSettle();
      expect(repo.pages, <int>[1]);
      await tester.tap(find.byKey(const ValueKey<String>('support-ticket-1')));
      await tester.pumpAndSettle();
      expect(find.text('工单详情与处理进度'), findsOneWidget);
      expect(find.text('问题已处理'), findsOneWidget);
      expect(repo.reads, <String>['1']);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(repo.pages, <int>[1, 1]);
      expect(repo.writes, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('history initial failure is retryable and never called empty', (
    tester,
  ) async {
    final repo = _Repository()..onPage = (_) async => throw _offline;
    await mount(tester, repo, history: true);
    expect(find.text('还没有提交过反馈'), findsNothing);
    expect(find.text('连接失败，请重试'), findsOneWidget);
    repo.onPage = (_) async => _page(<SupportTicket>[]);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('还没有提交过反馈'), findsOneWidget);
    expect(repo.pages, <int>[1, 1]);
  });

  testWidgets(
    'next page failure keeps history and retries the same page without duplicates',
    (tester) async {
      bool fail = true;
      final repo = _Repository()
        ..onPage = (p) async {
          if (p == 1)
            return _page(<SupportTicket>[_ticket('2')], hasMore: true);
          if (fail) throw _offline;
          return _page(<SupportTicket>[_ticket('2'), _ticket('1')], page: 2);
        };
      await mount(tester, repo, history: true);
      await tester.tap(find.text('加载更多'));
      await tester.pumpAndSettle();
      expect(find.text('问题2'), findsOneWidget);
      expect(find.text('已显示全部反馈'), findsNothing);
      fail = false;
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(repo.pages, <int>[1, 2, 2]);
      expect(find.text('问题2'), findsOneWidget);
      expect(find.text('问题1'), findsOneWidget);
      expect(find.text('已显示全部反馈'), findsOneWidget);
      expect(repo.writes, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'help service failure permits retry and independent history navigation',
    (tester) async {
      final repo = _Repository()..channelFails = true;
      await mount(tester, repo);
      expect(find.text('连接失败，请重试'), findsOneWidget);
      await tester.tap(find.text('我的反馈'));
      await tester.pumpAndSettle();
      expect(find.text('还没有提交过反馈'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      repo.channelFails = false;
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(find.text('提交问题'), findsOneWidget);
      expect(repo.channelCalls, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('late history completion after leaving the page is ignored', (
    tester,
  ) async {
    final pending = Completer<SocialPage<SupportTicket>>();
    final repo = _Repository()..onPage = (_) => pending.future;
    await mount(tester, repo);
    await tester.tap(find.text('我的反馈'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pageBack();
    await tester.pump(const Duration(seconds: 1));
    pending.complete(_page(<SupportTicket>[_ticket('1')]));
    await tester.pumpAndSettle();
    expect(find.text('帮助与客服'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('return from detail queues a refresh behind an in-flight page', (
    tester,
  ) async {
    final pending = Completer<SocialPage<SupportTicket>>();
    final repo = _Repository()
      ..onPage = (p) => p == 1
          ? Future.value(_page(<SupportTicket>[_ticket('2')], hasMore: true))
          : pending.future;
    await mount(tester, repo, history: true);
    await tester.tap(find.text('加载更多'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('support-ticket-2')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(SupportTicketPage), findsOneWidget);
    await tester.pageBack();
    await tester.pump(const Duration(seconds: 1));
    expect(repo.pages, <int>[1, 2]);
    pending.complete(_page(<SupportTicket>[_ticket('1')], page: 2));
    await tester.pumpAndSettle();
    expect(repo.pages, <int>[1, 2, 1]);
    expect(tester.takeException(), isNull);
    expect(repo.writes, 0);
  });

  testWidgets(
    'successful feedback clears the draft and does not resubmit on return',
    (tester) async {
      final repo = _Repository();
      await mount(tester, repo);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '提交反馈'))
            .onPressed,
        isNull,
      );
      await tester.enterText(find.widgetWithText(TextField, '问题主题'), '新的反馈');
      await tester.enterText(find.widgetWithText(TextField, '问题描述'), '请检查这个问题');
      await tester.pump();
      tester.testTextInput.hide();
      await tester.ensureVisible(find.text('提交反馈'));
      await tester.tap(find.text('提交反馈'));
      await tester.pumpAndSettle();
      expect(repo.writes, 1);
      expect(find.byType(SupportTicketPage), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '提交反馈'))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, '问题主题'))
            .controller!
            .text,
        isEmpty,
      );
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, '问题描述'))
            .controller!
            .text,
        isEmpty,
      );
      await tester.ensureVisible(find.text('提交反馈'));
      await tester.tap(find.text('提交反馈'));
      await tester.pumpAndSettle();
      expect(repo.writes, 1);
      expect(tester.takeException(), isNull);
    },
  );
}

class _Dependencies implements AppDependencies {
  _Dependencies(this.socialRepository);
  @override
  final SocialRepository socialRepository;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Repository extends MockSocialRepository {
  final List<int> pages = <int>[];
  final List<String> reads = <String>[];
  int writes = 0;
  int channelCalls = 0;
  bool channelFails = false;
  Future<SocialPage<SupportTicket>> Function(int)? onPage;

  @override
  Future<SocialPage<SupportTicket>> fetchSupportTickets({
    required int page,
    required int pageSize,
  }) async {
    expect(pageSize, 20);
    pages.add(page);
    return onPage?.call(page) ?? _page(<SupportTicket>[]);
  }

  @override
  Future<SupportChannel> fetchCustomerService() async {
    channelCalls += 1;
    if (channelFails) throw _offline;
    return super.fetchCustomerService();
  }

  @override
  Future<SupportTicket> fetchSupportTicket(String ticketId) async {
    reads.add(ticketId);
    return _ticket(ticketId, resolved: true);
  }

  @override
  Future<SupportTicket> submitFeedback({
    required String subject,
    required String content,
  }) async {
    writes += 1;
    return super.submitFeedback(subject: subject, content: content);
  }
}
