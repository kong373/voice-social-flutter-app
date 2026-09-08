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

SupportTicket _ticket({
  SupportTicketStatus status = SupportTicketStatus.waitingUser,
  bool replied = false,
}) => SupportTicket(
  id: 'ticket-1',
  subject: '页面反馈',
  content: '遇到了显示问题',
  status: status,
  statusText: status == SupportTicketStatus.waitingUser ? '等待补充信息' : '客服处理中',
  createdAt: DateTime.utc(2026, 9, 9),
  progressAvailable: true,
  version: replied ? 2 : 1,
  events: <SupportTicketEvent>[
    SupportTicketEvent(
      actorType: 'AGENT',
      eventType: 'MESSAGE',
      message: '请补充发生时间',
      createdAt: DateTime.utc(2026, 9, 9),
    ),
    if (replied)
      SupportTicketEvent(
        actorType: 'USER',
        eventType: 'MESSAGE',
        message: '九点发生',
        createdAt: DateTime.utc(2026, 9, 9, 1),
      ),
  ],
);

void main() {
  const input = ValueKey<String>('support-reply-input');
  const submit = ValueKey<String>('support-reply-submit');

  Future<void> mount(
    WidgetTester tester,
    _Repository repo, {
    bool settle = true,
  }) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: _Dependencies(repo),
        child: MaterialApp(
          theme: AppTheme.social(),
          home: SupportTicketPage(initialTicket: _ticket()),
        ),
      ),
    );
    if (settle) await tester.pumpAndSettle();
  }

  Future<void> reach(WidgetTester tester, Finder target) async {
    await tester.scrollUntilVisible(
      target,
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'staff timeline is visible and small-screen keyboard submission returns authority',
    (tester) async {
      final repo = _Repository();
      await mount(tester, repo);
      await reach(tester, find.text('请补充发生时间'));
      expect(find.text('客服回复'), findsOneWidget);
      await reach(tester, find.byKey(input));
      expect(tester.widget<FilledButton>(find.byKey(submit)).onPressed, isNull);
      await tester.enterText(find.byKey(input), '九点发生');
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      await tester.pumpAndSettle();
      await reach(tester, find.byKey(submit));
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(submit));
      await tester.pumpAndSettle();
      expect(repo.messages, <String>['九点发生']);
      expect(
        tester.widget<TextField>(find.byKey(input)).controller!.text,
        isEmpty,
      );
      expect(find.text('我的补充'), findsOneWidget);
      expect(find.text('九点发生'), findsOneWidget);
      expect(find.text('补充内容已提交'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed reply preserves draft and explicit retry does not fake a timeline event',
    (tester) async {
      bool fail = true;
      final repo = _Repository()
        ..onReply = () async {
          if (fail)
            throw const ApiException(
              kind: ApiFailureKind.network,
              message: '网络中断，请重试',
            );
          return _ticket(status: SupportTicketStatus.processing, replied: true);
        };
      await mount(tester, repo);
      await reach(tester, find.byKey(input));
      await tester.enterText(find.byKey(input), '九点发生');
      tester.testTextInput.hide();
      await reach(tester, find.byKey(submit));
      await tester.tap(find.byKey(submit));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byKey(input)).controller!.text,
        '九点发生',
      );
      expect(find.text('我的补充'), findsNothing);
      expect(find.text('网络中断，请重试'), findsOneWidget);
      fail = false;
      await tester.tap(find.byKey(submit));
      await tester.pumpAndSettle();
      expect(repo.messages, <String>['九点发生', '九点发生']);
      expect(find.text('我的补充'), findsOneWidget);
    },
  );

  testWidgets(
    'initial refresh disables reply and in-flight reply excludes stale refresh',
    (tester) async {
      final initial = Completer<SupportTicket>();
      final send = Completer<SupportTicket>();
      final repo = _Repository();
      repo.onRead = () => initial.future;
      repo.onReply = () => send.future;
      await mount(tester, repo, settle: false);
      await tester.pump();
      expect(find.byKey(input), findsNothing);
      initial.complete(_ticket());
      await tester.pumpAndSettle();
      await reach(tester, find.byKey(input));
      await tester.enterText(find.byKey(input), '九点发生');
      tester.testTextInput.hide();
      await reach(tester, find.byKey(submit));
      await tester.tap(find.byKey(submit));
      await tester.pump();
      expect(tester.widget<FilledButton>(find.byKey(submit)).onPressed, isNull);
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) => widget is IconButton && widget.tooltip == '刷新工单进度',
              ),
            )
            .onPressed,
        isNull,
      );
      expect(repo.reads, 1);
      expect(repo.messages.length, 1);
      send.complete(
        _ticket(status: SupportTicketStatus.processing, replied: true),
      );
      await tester.pumpAndSettle();
      expect(find.text('我的补充'), findsOneWidget);
      expect(repo.reads, 1);
    },
  );

  for (final status in <SupportTicketStatus>[
    SupportTicketStatus.resolved,
    SupportTicketStatus.closed,
    SupportTicketStatus.unavailable,
  ]) {
    testWidgets('$status never offers a reply', (tester) async {
      final repo = _Repository()..onRead = () async => _ticket(status: status);
      await mount(tester, repo);
      await tester.drag(find.byType(ListView), const Offset(0, -1400));
      await tester.pumpAndSettle();
      expect(find.byKey(input), findsNothing);
      expect(find.byKey(submit), findsNothing);
      expect(repo.messages, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('conflict reloads terminal authority without submitting twice', (
    tester,
  ) async {
    final repo = _Repository();
    repo.onReply = () async {
      repo.onRead = () async => _ticket(status: SupportTicketStatus.closed);
      throw const ApiException(
        kind: ApiFailureKind.conflict,
        httpStatus: 409,
        message: '工单已关闭',
      );
    };
    await mount(tester, repo);
    await reach(tester, find.byKey(input));
    await tester.enterText(find.byKey(input), '九点发生');
    tester.testTextInput.hide();
    await reach(tester, find.byKey(submit));
    await tester.tap(find.byKey(submit));
    await tester.pumpAndSettle();
    expect(repo.reads, 2);
    expect(repo.messages.length, 1);
    expect(find.byKey(input), findsNothing);
    expect(find.byKey(submit), findsNothing);
    expect(find.text('工单已关闭'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'initial detail failure does not enable reply from a stale history summary',
    (tester) async {
      final repo = _Repository()
        ..onRead = () async => throw const ApiException(
          kind: ApiFailureKind.network,
          message: '详情暂不可用',
        );
      await mount(tester, repo);
      expect(find.byKey(input), findsNothing);
      expect(find.text('详情暂不可用'), findsOneWidget);
      repo.onRead = () async => _ticket();
      await tester.tap(find.byTooltip('刷新工单进度'));
      await tester.pumpAndSettle();
      await reach(tester, find.byKey(input));
      expect(repo.reads, 2);
      expect(find.byKey(input), findsOneWidget);
    },
  );

  testWidgets(
    'emoji length matches backend limit with visible error and disabled submit',
    (tester) async {
      final repo = _Repository();
      await mount(tester, repo);
      await reach(tester, find.byKey(input));
      await tester.enterText(find.byKey(input), '😀' * 501);
      tester.testTextInput.hide();
      await reach(tester, find.byKey(submit));
      expect(find.text('1002/1000'), findsOneWidget);
      expect(find.text('补充说明超过1000字符，请缩短内容'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(submit)).onPressed, isNull);
      expect(repo.messages, isEmpty);
      await tester.enterText(find.byKey(input), '😀' * 500);
      await tester.pumpAndSettle();
      expect(find.text('1000/1000'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byKey(submit)).onPressed,
        isNotNull,
      );
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
  int reads = 0;
  final List<String> messages = <String>[];
  Future<SupportTicket> Function()? onRead;
  Future<SupportTicket> Function()? onReply;

  @override
  Future<SupportTicket> fetchSupportTicket(String ticketId) {
    reads++;
    return onRead?.call() ?? Future.value(_ticket());
  }

  @override
  Future<SupportTicket> replyToSupportTicket({
    required String ticketId,
    required String message,
  }) {
    messages.add(message);
    return onReply?.call() ??
        Future.value(
          _ticket(status: SupportTicketStatus.processing, replied: true),
        );
  }
}
