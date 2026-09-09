import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/app/page_manifest.dart';
import 'package:voice_social_app/debug/qa_console/qa_page_catalog.dart';
import 'package:voice_social_app/features/community/presentation/community_pages.dart';
import 'package:voice_social_app/features/social/data/mock_social_repository.dart';
import 'package:voice_social_app/features/social/presentation/social_pages.dart';

void main() {
  testWidgets(
    'old feature paths and deep links cannot construct an App route',
    (tester) async {
      await tester.pumpWidget(
        VoiceSocialApp(dependencies: AppDependencies.mock()),
      );
      await tester.pumpAndSettle();
      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      for (final path in [
        'US-005',
        'SC-004',
        'SC-005',
        'SC-006',
        'SC-007',
        'RM-009',
        'RM-012',
        '/room/diagnostics',
        'voice-social://room/diagnostics',
        'CM-007',
        'CM-008',
        '/room/share',
        '/commerce/refund',
        '/commerce/refund/application',
        '/commerce/refund/result',
        'voice-social://room/share',
        'voice-social://commerce/refund',
        '/community/tasks',
        '/community/cp',
        '/community/guardian',
        '/community/activities',
        '/social/friend-request',
        'voice-social://community/tasks',
        'voice-social://social/friend-request',
      ]) {
        expect(
          () => navigator.pushNamed<void>(path),
          throwsFlutterError,
          reason: path,
        );
        expect(navigator.canPop(), isFalse, reason: path);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'joined guild keeps management but removes sign action and status',
    (tester) async {
      await tester.pumpWidget(
        AppDependencyScope(
          dependencies: AppDependencies.mock(),
          child: const MaterialApp(home: GuildDetailPage(guildId: 'guild-1')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('签到'), findsNothing);
      expect(find.text('公会主播'), findsOneWidget);
      await tester.tap(find.text('公会主播'));
      await tester.pumpAndSettle();
      expect(find.byType(GuildMembersPage), findsOneWidget);
      expect(find.textContaining('签到'), findsNothing);
    },
  );

  test('product removed IDs cannot be constructed through the QA catalog', () {
    for (final id in ['US-005', 'SC-004', 'SC-005', 'SC-006', 'SC-007']) {
      expect(appPageManifest.where((page) => page.id == id), isEmpty);
      expect(qaPageCatalog.where((page) => page.id == id), isEmpty);
    }
  });

  testWidgets('community exposes only retained guild and attribution entries', (
    tester,
  ) async {
    final dependencies = AppDependencies.mock();
    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: dependencies,
        child: const MaterialApp(home: CommunityHubPage()),
      ),
    );
    await tester.pumpAndSettle();
    for (final label in ['CP 关系', '守护与粉团', '任务与签到', '主题活动中心']) {
      expect(find.text(label), findsNothing);
    }
    for (final label in ['公会主页', '公会加入与主播管理', '邀请与渠道归属']) {
      expect(find.text(label), findsOneWidget);
    }
    await tester.tap(find.text('公会主页'));
    await tester.pumpAndSettle();
    expect(find.text('晚风陪伴社'), findsOneWidget);
  });

  testWidgets('ordinary follow never sends an independent friend request', (
    tester,
  ) async {
    final dependencies = AppDependencies.mock();
    final repository = dependencies.socialRepository as MockSocialRepository;
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: dependencies,
        child: const MaterialApp(home: PublicProfilePage(userId: 20004)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('申请好友'), findsNothing);
    expect(find.text('私聊'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '关注'));
    await tester.pumpAndSettle();
    expect(
      (await repository.fetchPublicProfile(20004)).user.isFollowing,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });
}
