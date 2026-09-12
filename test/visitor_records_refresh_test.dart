import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/account/data/auth_session_manager.dart';
import 'package:voice_social_app/features/account/domain/auth_models.dart';
import 'package:voice_social_app/features/room/data/platform_room_repository.dart';
import 'package:voice_social_app/features/social/data/mock_social_repository.dart';
import 'package:voice_social_app/features/social/domain/social_models.dart';
import 'package:voice_social_app/features/social/presentation/social_pages.dart';

void main() {
  testWidgets('logout discards a pending visitor response', (tester) async {
    final repo = _Visitors();
    final deps = await _show(tester, repo, authenticated: true);
    await deps.sessionManager.clear();
    repo.requests.single.complete(_page(8));
    await tester.pump();
    expect(find.text('QA visitor'), findsNothing);
    expect(find.text('访问 8 次'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('visitor count refreshes after returning from the real profile', (
    tester,
  ) async {
    final repo = _Visitors();
    await _show(tester, repo);
    repo.requests.single.complete(_page(8));
    await tester.pumpAndSettle();
    expect(find.text('访问 8 次'), findsOneWidget);
    await tester.tap(find.text('QA visitor'));
    await tester.pumpAndSettle();
    expect(find.byType(PublicProfilePage), findsOneWidget);
    Navigator.of(tester.element(find.byType(PublicProfilePage))).pop();
    await tester.pump(const Duration(milliseconds: 400));
    expect(repo.requests, hasLength(2));
    repo.requests.last.complete(_page(9));
    await tester.pumpAndSettle();
    expect(find.text('访问 9 次'), findsOneWidget);
    expect(find.text('访问 8 次'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('older visitor response cannot replace the selected direction', (
    tester,
  ) async {
    final repo = _Visitors();
    await _show(tester, repo);
    await tester.tap(find.text('我看过谁'));
    await tester.pump();
    expect(repo.types, [
      VisitorRecordType.viewedMe,
      VisitorRecordType.viewedByMe,
    ]);
    repo.requests[1].complete(_page(9));
    await tester.pumpAndSettle();
    repo.requests[0].complete(_page(3));
    await tester.pumpAndSettle();
    expect(find.text('访问 9 次'), findsOneWidget);
    expect(find.text('访问 3 次'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('visitor read failure is recoverable without an uncaught error', (
    tester,
  ) async {
    final repo = _Visitors();
    await _show(tester, repo);
    repo.requests.single.completeError(
      const ApiException(kind: ApiFailureKind.server, message: '暂时无法加载'),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('重试'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pump();
    repo.requests.last.complete(_page(9));
    await tester.pumpAndSettle();
    expect(find.text('访问 9 次'), findsOneWidget);
    expect(find.text('重试'), findsNothing);
  });
}

Future<_Dependencies> _show(
  WidgetTester tester,
  _Visitors repository, {
  bool authenticated = false,
}) async {
  final deps = _Dependencies(repository);
  if (authenticated) {
    await deps.sessionManager.save(
      AuthSession(
        accessToken: 'test-visitor',
        tokenType: 'Bearer',
        expiresAt: DateTime(2099),
        userId: 1,
        mobile: '',
        roles: 'USER',
      ),
    );
  }
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    deps.backing.dispose();
  });
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    AppDependencyScope(
      dependencies: deps,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const VisitorRecordsPage(),
      ),
    ),
  );
  await tester.pump();
  return deps;
}

class _Dependencies extends Fake implements AppDependencies {
  _Dependencies(this.socialRepository);
  final backing = AppDependencies.mock();
  @override
  final _Visitors socialRepository;
  @override
  AuthSessionManager get sessionManager => backing.sessionManager;
  @override
  AppEnvironment get environment => backing.environment;
  @override
  PlatformRoomRepository get platformRoomRepository =>
      backing.platformRoomRepository;
}

SocialPage<SocialUser> _page(int visits) => SocialPage(
  items: [
    SocialUser(
      userId: 20001,
      name: 'QA visitor',
      signature: '',
      avatarUrl: '',
      isFollowing: false,
      isFollower: false,
      isFriend: false,
      isBlocked: false,
      isOnline: false,
      visitCount: visits,
    ),
  ],
  page: 1,
  pageSize: 50,
  total: 1,
  hasMore: false,
);

class _Visitors extends MockSocialRepository {
  final requests = <Completer<SocialPage<SocialUser>>>[];
  final types = <VisitorRecordType>[];

  @override
  Future<SocialPage<SocialUser>> fetchVisitors({
    required VisitorRecordType type,
    required int page,
    required int pageSize,
  }) {
    types.add(type);
    final request = Completer<SocialPage<SocialUser>>();
    requests.add(request);
    return request.future;
  }
}
