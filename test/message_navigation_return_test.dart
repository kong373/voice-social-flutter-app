import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/features/message/data/mock_message_repository.dart';
import 'package:voice_social_app/features/message/domain/message_models.dart';
import 'package:voice_social_app/features/message/presentation/message_pages.dart';
import 'package:voice_social_app/features/shell/main_shell.dart';

void main() {
  Future<void> pumpHarness(
    WidgetTester tester, {
    ThemeData? parentTheme,
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final AppDependencies dependencies = AppDependencies.mock(
      mockNow: DateTime(2026, 8, 21, 10, 30),
    );
    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: dependencies,
        child: MaterialApp(
          theme: parentTheme ?? AppTheme.social(),
          home: const _MessageNavigationHarness(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpRuntimeMessages(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final AppDependencies dependencies = AppDependencies.mock(
      mockNow: DateTime(2026, 8, 21, 10, 30),
    );
    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: dependencies,
        child: MaterialApp(
          theme: AppTheme.social(),
          home: MainShell(dependencies: dependencies, onSignOut: () async {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('消息').hitTestable());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('video-runtime-messages')), findsOneWidget);
  }

  testWidgets(
    'chat return keeps the message center interactive during refresh and '
    'allows the next back navigation',
    (WidgetTester tester) async {
      await pumpHarness(tester);

      for (int cycle = 0; cycle < 2; cycle += 1) {
        await tester.tap(find.byKey(const Key('open-message-center')));
        await tester.pumpAndSettle();
        expect(find.byType(MessageCenterPage), findsOneWidget);
        await tester.tap(find.byTooltip('搜索消息').hitTestable());
        await tester.pumpAndSettle();
        await tester.tap(find.text('晚星').last);
        await tester.pumpAndSettle();
        expect(find.byType(PrivateChatPage), findsOneWidget);

        Navigator.of(tester.element(find.byType(PrivateChatPage))).pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));

        expect(find.byType(MessageCenterPage), findsOneWidget);
        expect(find.text('消息'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);

        if (cycle == 0) {
          await tester.tap(find.byTooltip('返回上一页'));
        } else {
          await tester.binding.handlePopRoute();
        }
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('message-navigation-host')),
          findsOneWidget,
        );
        expect(find.byType(MessageCenterPage), findsNothing);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('runtime messages root survives search and private-chat return', (
    WidgetTester tester,
  ) async {
    await pumpRuntimeMessages(tester);

    expect(find.byType(MessageCenterPage), findsOneWidget);
    await tester.tap(find.byTooltip('搜索消息').hitTestable());
    await tester.pumpAndSettle();
    await tester.tap(find.text('晚星').last);
    await tester.pumpAndSettle();
    expect(find.byType(PrivateChatPage), findsOneWidget);

    Navigator.of(tester.element(find.byType(PrivateChatPage))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byKey(const Key('video-runtime-messages')), findsOneWidget);
    expect(find.byType(MessageCenterPage), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'message tab reloads its conversation list when activated after keep-alive',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final _ActivationMessageRepository repository =
          _ActivationMessageRepository();
      final AppDependencies dependencies = AppDependencies.forTestEnvironment(
        environment: AppEnvironment.mock(),
        messageRepository: repository,
      );
      addTearDown(dependencies.dispose);

      await tester.pumpWidget(
        AppDependencyScope(
          dependencies: dependencies,
          child: MaterialApp(
            theme: AppTheme.social(),
            home: MainShell(dependencies: dependencies, onSignOut: () async {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(repository.conversationFetches, 1);

      await tester.tap(find.text('消息').hitTestable());
      await tester.pumpAndSettle();
      expect(find.text('暂无可展示会话'), findsOneWidget);
      final int firstActivationFetches = repository.conversationFetches;

      await tester.tap(find.text('首页').hitTestable());
      await tester.pumpAndSettle();

      repository.conversations = const <ConversationSummary>[
        ConversationSummary(
          id: 'conversation-189',
          kind: ConversationKind.privateChat,
          title: '189',
          lastMessage: '新消息',
          updatedAt: null,
          unreadCount: 0,
          targetUserId: 189,
        ),
      ];
      await tester.tap(find.text('消息').hitTestable());
      await tester.pumpAndSettle();

      expect(repository.conversationFetches, firstActivationFetches + 1);
      expect(find.text('189'), findsOneWidget);
      expect(find.text('新消息'), findsOneWidget);
    },
  );

  testWidgets(
    'message center headings keep social contrast under a dark parent theme',
    (WidgetTester tester) async {
      await pumpHarness(tester, parentTheme: ThemeData.dark());

      await tester.tap(find.byKey(const Key('open-message-center')));
      await tester.pumpAndSettle();

      final Text heading = tester.widget<Text>(find.text('消息'));
      final Text sectionHeading = tester.widget<Text>(find.text('最近消息'));
      expect(heading.style?.color, SocialColors.textPrimary);
      expect(sectionHeading.style?.color, SocialColors.textPrimary);
      expect(tester.takeException(), isNull);
    },
  );
}

class _MessageNavigationHarness extends StatelessWidget {
  const _MessageNavigationHarness();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('message-navigation-host'),
      body: Center(
        child: FilledButton(
          key: const Key('open-message-center'),
          onPressed: () => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (BuildContext context) => const MessageCenterPage(),
            ),
          ),
          child: const Text('打开消息中心'),
        ),
      ),
    );
  }
}

class _ActivationMessageRepository extends MockMessageRepository {
  List<ConversationSummary> conversations = const <ConversationSummary>[];
  int conversationFetches = 0;

  @override
  Future<List<ConversationSummary>> fetchConversations() async {
    conversationFetches += 1;
    return List<ConversationSummary>.unmodifiable(conversations);
  }
}
