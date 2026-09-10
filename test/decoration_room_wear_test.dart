import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/features/account/domain/auth_models.dart';
import 'package:voice_social_app/features/account/data/auth_session_manager.dart';
import 'package:voice_social_app/features/room/application/room_controller.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/domain/room_operations_models.dart';
import 'package:voice_social_app/features/room/data/mock_room_operations_repository.dart';
import 'package:voice_social_app/features/room/presentation/room_members_page.dart';
import 'package:voice_social_app/features/room/infrastructure/room_realtime_gateway.dart';
import 'package:voice_social_app/features/room/infrastructure/rtc_adapter.dart';
import 'package:voice_social_app/features/room/presentation/video_runtime_room_page.dart';
import 'room_lease_controller_test.dart' as lease;
import 'decoration_profile_display_test.dart' show frame, frameKey;

void main() {
  testWidgets(
    'member list displays authoritative frame, removes offline wear and clears on logout',
    (tester) async {
      final deps = _MemberDependencies();
      await deps.sessionManager.save(_session(1));
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        deps.backing.dispose();
      });
      await tester.pumpWidget(
        AppDependencyScope(
          dependencies: deps,
          child: const MaterialApp(
            home: RoomMembersPage(
              roomId: 'r',
              currentUserId: 1,
              currentRole: RoomRole.listener,
              seats: [],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(frameKey), findsOneWidget);
      deps.roomOperationsRepository.online = false;
      await tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh();
      await tester.pumpAndSettle();
      expect(find.byKey(frameKey), findsNothing);
      deps.roomOperationsRepository.online = true;
      await tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh();
      await tester.pumpAndSettle();
      expect(find.byKey(frameKey), findsOneWidget);
      await deps.sessionManager.clear();
      await tester.pump();
      expect(find.byKey(frameKey), findsNothing);
    },
  );
  for (final exit in ['ABA', 'leave', 'lease']) {
    testWidgets('real room mic avatar frame disappears after $exit', (
      tester,
    ) async {
      final deps = AppDependencies.mock();
      await deps.sessionManager.save(_session(1));
      var elapsed = Duration.zero;
      final repo = _Repo();
      final controller = RoomController(
        roomId: 'r',
        title: '',
        currentUserId: 1,
        accessToken: '',
        repository: repo,
        rtcAdapter: MockRtcAdapter(),
        realtimeGateway: SnapshotOnlyRoomRealtimeGateway(),
        sessionChanges: deps.sessionManager,
        activeUserId: () => deps.sessionManager.session?.userId,
        identityGeneration: () => deps.sessionManager.identityGeneration,
        leaseElapsed: () => elapsed,
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        deps.dispose();
      });
      await controller.join();
      await tester.pumpWidget(
        AppDependencyScope(
          dependencies: deps,
          child: MaterialApp(
            home: VideoRuntimeRoomPage(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const Key('video-room-seat-grid')),
          matching: find.byKey(frameKey),
        ),
        findsOneWidget,
      );
      if (exit == 'ABA') {
        await deps.sessionManager.save(_session(2));
        await deps.sessionManager.save(_session(1));
      } else if (exit == 'leave') {
        await controller.leaveRoom();
      } else {
        elapsed = const Duration(seconds: 90);
        controller.setForeground(false);
        controller.setForeground(true);
      }
      await tester.pumpAndSettle();
      expect(find.byKey(frameKey), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}

class _MemberDependencies extends Fake implements AppDependencies {
  final backing = AppDependencies.mock();
  @override
  final _Members roomOperationsRepository = _Members();
  @override
  AuthSessionManager get sessionManager => backing.sessionManager;
  @override
  AppEnvironment get environment => backing.environment;
}

class _Members extends MockRoomOperationsRepository {
  bool online = true;
  @override
  Future<RoomMemberPage> fetchOnlineMembers({
    required String roomId,
    int page = 1,
    int pageSize = 20,
  }) async => RoomMemberPage(
    items: [
      RoomMember(
        userId: 2,
        name: 'wearer',
        role: RoomRole.listener,
        presence: RoomMemberPresence.listener,
        online: online,
        equippedDecorations: [frame],
      ),
    ],
    page: 1,
    total: 1,
    pages: 1,
  );
}

class _Repo extends lease.Repo {
  @override
  Future<RoomSnapshot> enterRoom({
    required String roomId,
    required String? password,
    required RoomEntrySource source,
    required int currentUserId,
  }) async =>
      (await super.enterRoom(
        roomId: roomId,
        password: password,
        source: source,
        currentUserId: currentUserId,
      )).copyWith(
        seats: [
          const MicSeat(
            number: 1,
            backendIndex: 1,
            state: MicSeatState.occupied,
            userId: 2,
            userName: 'wearer',
            equippedDecorations: [frame],
          ),
        ],
      );
}

AuthSession _session(int id) => AuthSession(
  accessToken: 'test-$id',
  tokenType: 'Bearer',
  expiresAt: DateTime(2099),
  userId: id,
  mobile: '',
  roles: 'USER',
);
