import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/features/account/domain/auth_models.dart';
import 'package:voice_social_app/features/account/data/auth_session_manager.dart';
import 'package:voice_social_app/features/commerce/display/domain/equipped_decoration.dart';
import 'package:voice_social_app/features/social/data/mock_social_repository.dart';
import 'package:voice_social_app/features/social/domain/social_models.dart';
import 'package:voice_social_app/features/social/presentation/social_pages.dart';
import 'package:voice_social_app/features/shell/video_runtime_pages.dart';
import 'package:voice_social_app/features/room/data/platform_room_repository.dart';

const frame = EquippedDecoration(
  decorationId: '00000000-0000-0000-0000-000000000001',
  type: 'AVATAR_FRAME',
  assetKey: 'decoration/star-ring-frame',
  expiresAt: null,
);
const badge = EquippedDecoration(
  decorationId: '00000000-0000-0000-0000-000000000002',
  type: 'PROFILE_BADGE',
  assetKey: 'decoration/companion-badge',
  expiresAt: null,
);
const frameKey = ValueKey('decoration-art-decoration/star-ring-frame');
const badgeKey = ValueKey('decoration-art-decoration/companion-badge');

void main() {
  testWidgets(
    'actual mine header uses the same frame and badge and clears both on ABA',
    (tester) async {
      final deps = _Dependencies();
      await deps.sessionManager.save(_session(1));
      deps.repo.load = (_) async => _profile(1);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        deps.backing.dispose();
      });
      await tester.pumpWidget(
        AppDependencyScope(
          dependencies: deps,
          child: MaterialApp(
            home: Scaffold(
              body: VideoRuntimeAccountPage(
                dependencies: deps,
                onOpenRoom: (_) {},
                onSignOut: () async {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(frameKey), findsOneWidget);
      expect(find.byKey(badgeKey), findsOneWidget);
      await deps.sessionManager.save(_session(2));
      await deps.sessionManager.save(_session(1));
      await tester.pump();
      expect(find.byKey(frameKey), findsNothing);
      expect(find.byKey(badgeKey), findsNothing);
    },
  );
  for (final self in [true, false]) {
    testWidgets(
      '${self ? "personal" : "public"} profile displays actual frame and badge, logout removes both',
      (tester) async {
        final deps = _Dependencies();
        await deps.sessionManager.save(_session(1));
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox());
          deps.backing.dispose();
        });
        deps.repo.load = (_) async => _profile(1);
        await _show(tester, deps, self: self);
        await tester.pumpAndSettle();
        expect(find.byKey(frameKey), findsOneWidget);
        expect(find.byKey(badgeKey), findsOneWidget);
        await deps.sessionManager.clear();
        await tester.pump();
        expect(find.byKey(frameKey), findsNothing);
        expect(find.byKey(badgeKey), findsNothing);
      },
    );
    for (final error in [false, true]) {
      testWidgets(
        '${self ? "personal" : "public"} late ${error ? "error" : "success"} across ABA cannot restore old wear',
        (tester) async {
          final deps = _Dependencies();
          await deps.sessionManager.save(_session(1));
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox());
            deps.backing.dispose();
          });
          final old = Completer<SocialProfile>();
          var calls = 0;
          deps.repo.load = (_) => ++calls == 1
              ? old.future
              : Future.value(_profile(1, decorated: false));
          await _show(tester, deps, self: self);
          await tester.pump();
          await deps.sessionManager.save(_session(2));
          await deps.sessionManager.save(_session(1));
          if (error) {
            old.completeError(StateError('OLD-ERROR'));
          } else {
            old.complete(_profile(1));
          }
          await tester.pumpAndSettle();
          expect(find.byKey(frameKey), findsNothing);
          expect(find.textContaining('OLD-ERROR'), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets('replacing public profile target ignores old target response', (
    tester,
  ) async {
    final deps = _Dependencies();
    await deps.sessionManager.save(_session(1));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      deps.backing.dispose();
    });
    final old = Completer<SocialProfile>();
    deps.repo.load = (id) =>
        id == 1 ? old.future : Future.value(_profile(id, decorated: false));
    await _show(tester, deps, self: false);
    await tester.pump();
    await _show(tester, deps, self: false, target: 2);
    await tester.pump();
    old.complete(_profile(1));
    await tester.pumpAndSettle();
    expect(find.byKey(frameKey), findsNothing);
    expect(find.text('User2'), findsOneWidget);
  });
}

class _Dependencies extends Fake implements AppDependencies {
  final backing = AppDependencies.mock();
  final repo = _Repository();
  @override
  AuthSessionManager get sessionManager => backing.sessionManager;
  @override
  SocialRepository get socialRepository => repo;
  @override
  AppEnvironment get environment => backing.environment;
  @override
  PlatformRoomRepository get platformRoomRepository =>
      backing.platformRoomRepository;
}

class _Repository extends MockSocialRepository {
  late Future<SocialProfile> Function(int) load;
  @override
  Future<SocialProfile> fetchMyProfile() => load(1);
  @override
  Future<SocialProfile> fetchPublicProfile(int userId) => load(userId);
}

Future<void> _show(
  WidgetTester tester,
  _Dependencies deps, {
  required bool self,
  int target = 1,
}) => tester.pumpWidget(
  AppDependencyScope(
    dependencies: deps,
    child: MaterialApp(
      home: self
          ? PersonalCenterPage(
              session: deps.sessionManager.session,
              onSignOut: () async {},
            )
          : PublicProfilePage(userId: target),
    ),
  ),
);
SocialProfile _profile(int id, {bool decorated = true}) => SocialProfile(
  user: SocialUser(
    userId: id,
    name: 'User$id',
    signature: '',
    avatarUrl: '',
    isFollowing: false,
    isFollower: false,
    isFriend: false,
    isBlocked: false,
    isOnline: true,
    equippedDecorations: decorated ? [frame, badge] : [],
  ),
  account: '$id',
  sex: 1,
  birthday: '',
  city: '',
  coverUrl: '',
  followingCount: 0,
  followerCount: 0,
  friendCount: 0,
  postCount: 0,
  level: null,
);
AuthSession _session(int id) => AuthSession(
  accessToken: 'test-$id',
  tokenType: 'Bearer',
  expiresAt: DateTime(2099),
  userId: id,
  mobile: '',
  roles: 'USER',
);
