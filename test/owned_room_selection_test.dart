import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/account/domain/auth_models.dart';
import 'package:voice_social_app/features/community/data/mock_community_repository.dart';
import 'package:voice_social_app/features/community/domain/community_models.dart';
import 'package:voice_social_app/features/room/data/mock_room_lifecycle_repository.dart';
import 'package:voice_social_app/features/room/data/mock_room_repository.dart';
import 'package:voice_social_app/features/room/domain/room_lifecycle_models.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/presentation/create_room_page.dart';
import 'package:voice_social_app/features/room/presentation/edit_room_page.dart';
import 'package:voice_social_app/features/room/presentation/room_configuration_form.dart';
import 'package:voice_social_app/features/room/presentation/room_page.dart';

void main() {
  testWidgets(
    'owner explicitly creates another room and navigates to its returned ID',
    (tester) async {
      final repository = _Rooms();
      await _pump(tester, repository);
      await tester.tap(find.text('创建新房间'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('创建并进入房间'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 400));
      expect(repository.writes.single.hasExistingRoom, isFalse);
      expect(tester.widget<RoomPage>(find.byType(RoomPage)).roomId, '952703');
      await _dispose(tester);
    },
  );

  testWidgets(
    'multiple rooms stay separate; manage loads only selected room without writes',
    (tester) async {
      final repository = _Rooms();
      await _pump(tester, repository);
      expect(find.text('第一间'), findsOneWidget);
      expect(find.text('第二间'), findsOneWidget);
      expect(find.text('已关闭'), findsOneWidget);
      expect(find.byType(RoomConfigurationForm), findsNothing);
      expect(repository.configurationReads, isEmpty);
      expect(repository.writes, isEmpty);
      final second = find.byKey(const ValueKey('owned-room-952702'));
      await tester.tap(
        find.descendant(of: second, matching: find.text('管理房间')),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<EditRoomPage>(find.byType(EditRoomPage)).roomId,
        '952702',
      );
      expect(repository.configurationReads, ['952702']);
      expect(repository.writes, isEmpty);
      expect(find.text('第二间'), findsWidgets);
      await _dispose(tester);
    },
  );

  testWidgets(
    'enter selected room never saves its configuration or creates a room',
    (tester) async {
      final repository = _Rooms();
      await _pump(tester, repository);
      final second = find.byKey(const ValueKey('owned-room-952702'));
      await tester.tap(
        find.descendant(of: second, matching: find.text('进入房间')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.widget<RoomPage>(find.byType(RoomPage)).roomId, '952702');
      expect(repository.writes, isEmpty);
      expect(repository.configurationReads, isEmpty);
      await _dispose(tester);
    },
  );

  testWidgets(
    'new creation has no existing ID and reports quota conflict without navigation',
    (tester) async {
      final repository = _Rooms()..reject = true;
      await _pump(tester, repository);
      await tester.tap(find.text('创建新房间'));
      await tester.pumpAndSettle();
      expect(find.byType(RoomConfigurationForm), findsOneWidget);
      await tester.tap(find.text('创建并进入房间'));
      await tester.pumpAndSettle();
      expect(repository.writes.single.roomId, isNull);
      expect(repository.writes.single.version, isNull);
      expect(find.text('已达到公会可建房数量上限'), findsOneWidget);
      expect(find.byType(RoomPage), findsNothing);
      await _dispose(tester);
    },
  );

  for (final role in [GuildRole.member, GuildRole.manager, GuildRole.visitor]) {
    testWidgets(
      '$role cannot start new creation but owned history remains visible',
      (tester) async {
        final repository = _Rooms();
        await _pump(tester, repository, home: _Home(role: role));
        expect(find.text('创建新房间'), findsNothing);
        expect(find.byType(RoomConfigurationForm), findsNothing);
        expect(find.text('第二间'), findsOneWidget);
        expect(repository.writes, isEmpty);
        await _dispose(tester);
      },
    );
  }

  for (final home in [_Home(closed: true), _Home(unknown: true)]) {
    testWidgets(
      'closed or unknown guild authority cannot start new creation (${home.closed})',
      (tester) async {
        await _pump(tester, _Rooms(), home: home);
        expect(find.text('创建新房间'), findsNothing);
        expect(find.text('第二间'), findsOneWidget);
        await _dispose(tester);
      },
    );
  }

  for (final pendingWrite in [false, true]) {
    testWidgets(
      'account ABA invalidates old ${pendingWrite ? 'creation' : 'list'} Future',
      (tester) async {
        final dependencies = AppDependencies.mock();
        addTearDown(dependencies.dispose);
        await dependencies.sessionManager.save(_session(10001));
        final repository = _Rooms();
        if (pendingWrite) {
          repository.pendingSave = Completer<RoomLifecycleSaveResult>();
        } else {
          repository.pendingList = Completer<List<OwnedRoomSummary>>();
        }
        await _pump(
          tester,
          repository,
          dependencies: dependencies,
          settle: pendingWrite,
        );
        if (pendingWrite) {
          await tester.tap(find.text('创建新房间'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('创建并进入房间'));
          await tester.pump();
        }
        await dependencies.sessionManager.save(_session(10002));
        await dependencies.sessionManager.save(_session(10001));
        if (pendingWrite) {
          repository.pendingSave!.complete(
            const RoomLifecycleSaveResult(
              roomId: 'stale-created',
              roomCode: '900000',
              created: true,
            ),
          );
        } else {
          repository.pendingList!.complete(const [
            OwnedRoomSummary(
              roomId: 'stale-room',
              roomCode: '900000',
              title: '旧账号房间',
              availability: RoomAvailability.open,
              accessMode: RoomAccessMode.publicRoom,
            ),
          ]);
        }
        await tester.pumpAndSettle();
        expect(find.text('账号已变化，请返回后重新打开'), findsOneWidget);
        expect(find.text('旧账号房间'), findsNothing);
        expect(find.text('创建新房间'), findsNothing);
        expect(find.byType(RoomPage), findsNothing);
        expect(repository.writes.length, pendingWrite ? 1 : 0);
        await _dispose(tester);
      },
    );
  }

  test(
    'mock preserves two rooms and CLOSED owner entry uses selected configuration',
    () async {
      final repository = MockRoomLifecycleRepository(
        initialRooms: [_room('952701', '第一间')],
        roomLimit: 2,
      );
      final created = await repository.saveRoom(_newRoom());
      expect(created.roomId, isNot('952701'));
      await repository.closeRoom(created.roomId);
      expect((await repository.fetchOwnedRooms()).map((r) => r.roomId), [
        '952701',
        created.roomId,
      ]);
      final snapshot = await MockRoomRepository(lifecycleRepository: repository)
          .enterRoom(
            roomId: created.roomId,
            password: null,
            source: RoomEntrySource.home,
            currentUserId: 10001,
          );
      expect(snapshot.role, RoomRole.owner);
      expect(snapshot.ownerClosedAccess, isTrue);
      expect(snapshot.transportMode, RoomTransportMode.snapshotOnly);
      expect(snapshot.title, '新房间');
      await expectLater(
        repository.saveRoom(_newRoom()),
        throwsA(isA<ApiException>()),
      );
      expect((await repository.fetchRoom('952701')).title, '第一间');
    },
  );
}

Future<void> _pump(
  WidgetTester tester,
  _Rooms repository, {
  _Home? home,
  AppDependencies? dependencies,
  bool settle = true,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final deps = dependencies ?? AppDependencies.mock();
  if (dependencies == null) addTearDown(deps.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.social(),
      home: AppDependencyScope(
        dependencies: deps,
        child: CreateRoomPage(
          repositoryOverride: repository,
          communityRepositoryOverride: home ?? _Home(),
        ),
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
}

Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 2));
  expect(tester.takeException(), isNull);
}

class _Rooms extends MockRoomLifecycleRepository {
  _Rooms()
    : super(
        initialRooms: [
          _room('952701', '第一间'),
          _room('952702', '第二间', closed: true),
        ],
        roomLimit: 3,
      );
  final configurationReads = <String>[];
  final writes = <RoomConfiguration>[];
  bool reject = false;
  Completer<List<OwnedRoomSummary>>? pendingList;
  Completer<RoomLifecycleSaveResult>? pendingSave;
  @override
  Future<List<OwnedRoomSummary>> fetchOwnedRooms() =>
      pendingList?.future ?? super.fetchOwnedRooms();
  @override
  Future<RoomConfiguration> fetchRoom(String roomId) {
    configurationReads.add(roomId);
    return super.fetchRoom(roomId);
  }

  @override
  Future<RoomLifecycleSaveResult> saveRoom(
    RoomConfiguration configuration,
  ) async {
    writes.add(configuration);
    if (reject)
      throw const ApiException(
        kind: ApiFailureKind.conflict,
        code: 40998,
        message: '已达到公会可建房数量上限',
      );
    return pendingSave?.future ?? super.saveRoom(configuration);
  }
}

class _Home extends MockCommunityRepository {
  _Home({
    this.role = GuildRole.owner,
    this.closed = false,
    this.unknown = false,
  });
  final GuildRole role;
  final bool closed;
  final bool unknown;
  @override
  Future<GuildHomeSnapshot> fetchGuildHome() async => GuildHomeSnapshot(
    currentGuildAuthority: unknown
        ? GuildCurrentAuthority.unavailable
        : GuildCurrentAuthority.authoritative,
    currentGuild: unknown
        ? null
        : GuildSummary(
            id: 'guild',
            code: 'G10001',
            name: '测试公会',
            ownerUserId: role == GuildRole.owner ? 10001 : 20001,
            role: role,
            joined: role != GuildRole.visitor,
            status: closed ? GuildStatus.closed : GuildStatus.active,
          ),
  );
}

AuthSession _session(int id) => AuthSession(
  accessToken: 'test-$id',
  tokenType: 'Bearer',
  expiresAt: DateTime.now().add(const Duration(hours: 1)),
  userId: id,
  mobile: 'test',
  roles: 'USER',
);

RoomConfiguration _room(String id, String title, {bool closed = false}) =>
    RoomConfiguration(
      roomId: id,
      roomCode: id,
      title: title,
      topicTitle: '',
      topicContent: '',
      welcomeMessage: '',
      accessMode: RoomAccessMode.publicRoom,
      password: '',
      showInHall: true,
      autoLockMic: false,
      version: 1,
      availability: closed ? RoomAvailability.closed : RoomAvailability.open,
    );

RoomConfiguration _newRoom() => const RoomConfiguration(
  title: '新房间',
  topicTitle: '',
  topicContent: '',
  welcomeMessage: '',
  accessMode: RoomAccessMode.publicRoom,
  password: '',
  showInHall: true,
  autoLockMic: false,
  availability: RoomAvailability.open,
);
