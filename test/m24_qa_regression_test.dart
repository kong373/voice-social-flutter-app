import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/debug/qa_console/qa_console_page.dart';
import 'package:voice_social_app/debug/qa_console/qa_gate.dart';
import 'package:voice_social_app/debug/qa_console/qa_fixtures.dart';
import 'package:voice_social_app/debug/qa_console/qa_models.dart';
import 'package:voice_social_app/features/account/compliance/presentation/account_compliance_pages.dart';
import 'package:voice_social_app/features/account/presentation/third_party_authorization_page.dart';
import 'package:voice_social_app/features/discovery/presentation/search_results_page.dart';
import 'package:voice_social_app/features/message/presentation/message_pages.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/presentation/room_members_page.dart';
import 'package:voice_social_app/features/room/presentation/room_page.dart';
import 'package:voice_social_app/features/social/presentation/social_pages.dart';

void main() {
  test('QA console is disabled unless the compile-time flag is present', () {
    expect(qaConsoleEnabled, isFalse);
  });

  testWidgets('AC-004 is a real fail-closed vendor boundary page', (
    WidgetTester tester,
  ) async {
    await _pumpScoped(tester, const ThirdPartyAuthorizationPage());

    expect(find.text('第三方账号绑定与分享授权'), findsWidgets);
    expect(find.text('VENDOR_BLOCKED'), findsNWidgets(3));
    expect(find.textContaining('不会伪造绑定成功'), findsOneWidget);
  });

  testWidgets('QA page frame reflects the selected role and scenario', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const QaPageFrame(
          pageId: 'DS-001',
          scenario: QaScenario(
            role: QaRole.guest,
            state: QaPageState.offline,
            mockScenario: QaMockScenario.errorResponse,
            network: QaNetworkScenario.packetLoss,
          ),
          stateSupported: true,
          child: Scaffold(body: SizedBox.expand()),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('qa-active-scenario-DS-001')),
      findsOneWidget,
    );
    expect(find.textContaining('游客 · offline'), findsOneWidget);
    expect(find.textContaining('error · packetLoss'), findsOneWidget);
  });

  testWidgets('account hub exposes AC-004 through an ordinary user entry', (
    WidgetTester tester,
  ) async {
    await _pumpScoped(
      tester,
      const AccountComplianceHubPage(
        account: '13800138000',
        currentVersion: 5,
        platformType: 1,
      ),
    );

    expect(find.text('第三方账号绑定与分享授权'), findsOneWidget);
    await tester.tap(find.text('第三方账号绑定与分享授权'));
    await tester.pumpAndSettle();
    expect(find.byType(ThirdPartyAuthorizationPage), findsOneWidget);
  });

  testWidgets('search user result opens the real US-003 page', (
    WidgetTester tester,
  ) async {
    await _pumpScoped(tester, const SearchResultsPage(keyword: '鹿屿'));

    await tester.tap(find.text('鹿屿'));
    await tester.pumpAndSettle();
    expect(find.byType(PublicProfilePage), findsOneWidget);
    expect(find.text('个人主页'), findsOneWidget);
  });

  testWidgets('room member profile action opens the real US-003 page', (
    WidgetTester tester,
  ) async {
    await _pumpScoped(tester, _roomMembersPage());

    await tester.tap(find.text('房主 · 鹿屿'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('查看主页'));
    await tester.pumpAndSettle();
    expect(find.byType(PublicProfilePage), findsOneWidget);
  });

  testWidgets('room member private chat action opens the real MS-002 page', (
    WidgetTester tester,
  ) async {
    await _pumpScoped(tester, _roomMembersPage());

    await tester.tap(find.text('房主 · 鹿屿'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('发起私聊'));
    await tester.pumpAndSettle();
    expect(find.byType(PrivateChatPage), findsOneWidget);
  });

  testWidgets('room member report action opens the real US-008 page', (
    WidgetTester tester,
  ) async {
    await _pumpScoped(tester, _roomMembersPage());

    await tester.tap(find.text('房主 · 鹿屿'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('举报用户'));
    await tester.pumpAndSettle();
    expect(find.byType(ReportPage), findsOneWidget);
    expect(find.text('举报房主 · 鹿屿'), findsOneWidget);
  });

  testWidgets('room more action opens the real room report page', (
    WidgetTester tester,
  ) async {
    await _pumpScoped(
      tester,
      const RoomPage(roomId: '880217', title: '深夜温柔陪伴'),
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    expect(find.byTooltip('更多'), findsOneWidget);
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('举报房间'));
    await tester.pumpAndSettle();

    expect(find.byType(ReportPage), findsOneWidget);
    expect(find.text('举报深夜温柔陪伴'), findsOneWidget);
  });
}

Future<void> _pumpScoped(WidgetTester tester, Widget page) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final AppDependencies dependencies = await createQaDependencies();
  await tester.pumpWidget(
    AppDependencyScope(
      dependencies: dependencies,
      child: MaterialApp(theme: AppTheme.dark(), home: page),
    ),
  );
  await tester.pumpAndSettle();
}

RoomMembersPage _roomMembersPage() => const RoomMembersPage(
  roomId: '880217',
  currentUserId: 10001,
  currentRole: RoomRole.listener,
  seats: <MicSeat>[
    MicSeat(
      number: 1,
      backendIndex: 1,
      state: MicSeatState.occupied,
      userId: 20001,
      userName: '房主 · 鹿屿',
      userRole: RoomRole.owner,
    ),
  ],
);
