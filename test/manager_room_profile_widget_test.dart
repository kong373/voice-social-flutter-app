import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/account/domain/auth_models.dart';
import 'package:voice_social_app/features/room/data/backend_room_lifecycle_repository.dart';
import 'package:voice_social_app/features/room/presentation/edit_room_page.dart';
import 'manager_room_profile_test.dart'
    show ProfileApi, profileWire, profileRoomId;
import 'room_lease_contract_fixture.dart';

void main() {
  late ProfileApi api;
  late BackendRoomLifecycleRepository repo;
  setUp(() {
    api = ProfileApi()..wire = profileWire(owner: false);
    repo = BackendRoomLifecycleRepository(
      apiClient: api,
      leaseBinding: admittedRoomFixture(roomId: profileRoomId),
    );
  });
  Future<void> mount(WidgetTester tester) async {
    // Construct the write guard inside the widget test's async zone.
    repo = BackendRoomLifecycleRepository(
      apiClient: api,
      leaseBinding: repo.leaseBinding,
    );
    final deps = AppDependencies.mock();
    addTearDown(deps.dispose);
    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: deps,
        child: MaterialApp(
          home: EditRoomPage(roomId: profileRoomId, repositoryOverride: repo),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'mock manager edits without owner-only controls or live uploads',
    (tester) async {
      await mount(tester);
      expect(find.byKey(const Key('edit-room-save-button')), findsOneWidget);
      await tester.drag(find.byType(ListView), const Offset(0, -1800));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('edit-room-close-button')), findsNothing);
      expect(find.byKey(const Key('edit-room-reopen-button')), findsNothing);
      expect(find.text('在首页房间发现中展示'), findsNothing);
      expect(find.text('进入房间时自动锁定空麦'), findsNothing);
      expect(find.text('上传封面'), findsNothing);
      await tester.tap(find.byKey(const Key('edit-room-save-button')));
      await tester.pumpAndSettle();
      expect(api.writes.single['sessionId'], roomLeaseSessionId);
    },
  );

  testWidgets('lease change before save prevents write and clears editor', (
    tester,
  ) async {
    await mount(tester);
    repo.leaseBinding.beginEntry('new lease');
    await tester.tap(find.byKey(const Key('edit-room-save-button')));
    await tester.pumpAndSettle();
    expect(api.writes, isEmpty);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.textContaining('账号或房间会话已变化'), findsOneWidget);
  });

  testWidgets('unknown save locks draft and retries identical intent', (
    tester,
  ) async {
    await mount(tester);
    api.saveError = const ApiException(
      kind: ApiFailureKind.timeout,
      message: 'timeout',
    );
    await tester.tap(find.byKey(const Key('edit-room-save-button')));
    await tester.pumpAndSettle();
    expect(find.text('重试原保存请求'), findsOneWidget);
    for (final field in tester.widgetList<TextFormField>(
      find.byType(TextFormField),
    )) {
      expect(field.enabled, isFalse);
    }
    api.saveError = null;
    await tester.tap(find.byKey(const Key('edit-room-save-button')));
    await tester.pumpAndSettle();
    expect(api.writes[0], api.writes[1]);
    expect(api.requestIds[0], api.requestIds[1]);
  });

  testWidgets('late save after lease change cannot report success', (
    tester,
  ) async {
    await mount(tester);
    api.saveGate = Completer<void>();
    await tester.tap(find.byKey(const Key('edit-room-save-button')));
    await tester.pump();
    repo.leaseBinding.beginEntry('new lease');
    api.saveGate!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(EditRoomPage), findsOneWidget);
    expect(find.textContaining('账号或房间会话已变化'), findsOneWidget);
  });

  for (final code in [40901, 40902]) {
    testWidgets('pending idempotency $code keeps original draft', (
      tester,
    ) async {
      await mount(tester);
      api.saveError = ApiException(
        kind: ApiFailureKind.conflict,
        code: code,
        message: 'pending',
      );
      await tester.tap(find.byKey(const Key('edit-room-save-button')));
      await tester.pumpAndSettle();
      expect(find.text('重试原保存请求'), findsOneWidget);
      api.saveError = null;
      await tester.tap(find.byKey(const Key('edit-room-save-button')));
      await tester.pumpAndSettle();
      expect(api.requestIds[0], api.requestIds[1]);
      expect(api.writes[0], api.writes[1]);
    });
  }

  testWidgets('replaced room cannot receive late old-room projection', (
    tester,
  ) async {
    api.getGate = Completer<void>();
    final selected = ValueNotifier(false);
    addTearDown(selected.dispose);
    final newerApi = ProfileApi()
      ..expectedRoomId = 'new-room'
      ..wire = {...profileWire(), 'roomId': 'new-room', 'roomName': '新房间'};
    final newer = BackendRoomLifecycleRepository(apiClient: newerApi);
    final deps = AppDependencies.mock();
    addTearDown(deps.dispose);
    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: deps,
        child: MaterialApp(
          home: ValueListenableBuilder<bool>(
            valueListenable: selected,
            builder: (_, value, _) => EditRoomPage(
              roomId: value ? 'new-room' : profileRoomId,
              repositoryOverride: value ? newer : repo,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    selected.value = true;
    await tester.pumpAndSettle();
    api.getGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('新房间'), findsWidgets);
    expect(find.text('资料房间'), findsNothing);
    expect(api.writes, isEmpty);
  });

  testWidgets(
    'identity ABA invalidates editor even after returning to same account',
    (tester) async {
      final deps = AppDependencies.mock();
      addTearDown(deps.dispose);
      AuthSession account(int id) => AuthSession(
        accessToken: 'fixture',
        tokenType: 'Bearer',
        expiresAt: DateTime.utc(2030),
        userId: id,
        mobile: '',
        roles: 'USER',
      );
      await deps.sessionManager.save(account(1));
      await tester.pumpWidget(
        AppDependencyScope(
          dependencies: deps,
          child: MaterialApp(
            home: EditRoomPage(roomId: profileRoomId, repositoryOverride: repo),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await deps.sessionManager.save(account(2));
      await deps.sessionManager.save(account(1));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('edit-room-save-button')), findsNothing);
      expect(find.textContaining('账号或房间会话已变化'), findsOneWidget);
      expect(api.writes, isEmpty);
    },
  );

  testWidgets(
    'revoked manager cannot reload and replay as a version conflict',
    (tester) async {
      await mount(tester);
      api.saveError = const ApiException(
        kind: ApiFailureKind.conflict,
        code: 40937,
        message: '旧租约',
      );
      final reads = api.paths.length;
      await tester.tap(find.byKey(const Key('edit-room-save-button')));
      await tester.pumpAndSettle();
      expect(api.paths, hasLength(reads));
      expect(find.byKey(const Key('edit-room-save-button')), findsNothing);
      expect(api.writes, hasLength(1));
    },
  );
}
