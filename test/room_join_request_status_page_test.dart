import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/features/account/domain/auth_models.dart';
import 'package:voice_social_app/features/room/application/room_controller.dart';
import 'package:voice_social_app/features/room/data/mock_room_repository.dart';
import 'package:voice_social_app/features/room/data/mock_room_operations_repository.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/domain/room_repository.dart';
import 'package:voice_social_app/features/room/infrastructure/room_realtime_gateway.dart';
import 'package:voice_social_app/features/room/infrastructure/rtc_adapter.dart';
import 'package:voice_social_app/features/room/presentation/video_runtime_room_page.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/room/domain/room_operations_models.dart';
import 'package:voice_social_app/features/room/domain/room_operations_repository.dart';
import 'package:voice_social_app/features/room/presentation/room_join_request_status_page.dart';

void main() {
  for (final change in ['none', 'account', 'pending']) {
    testWidgets(
      'continue retries normal join only for original identity ($change); refusal never paints joined',
      (tester) async {
        final dependencies = AppDependencies.mock();
        await dependencies.sessionManager.save(_session(10));
        final operations =
            dependencies.roomOperationsRepository
                as MockRoomOperationsRepository;
        operations.seedApplicantStatusForQa(
          _status(RoomJoinRequestStatus.pending),
        );
        final repository = _RefusingEntryRepository();
        final realtime = MockRoomRealtimeGateway();
        final controller = RoomController(
          roomId: 'room-9527',
          title: '审批房',
          currentUserId: 10,
          accessToken: 'test',
          repository: repository,
          rtcAdapter: const SnapshotOnlyRtcAdapter(),
          realtimeGateway: realtime,
        );
        addTearDown(() async {
          controller.dispose();
          await realtime.dispose();
          dependencies.dispose();
        });
        await tester.pumpWidget(
          AppDependencyScope(
            dependencies: dependencies,
            child: MaterialApp(
              home: VideoRuntimeRoomPage(controller: controller),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(repository.calls, 1);
        await tester.tap(find.text('查看申请状态'));
        await tester.pumpAndSettle();
        expect(find.text('继续进入'), findsNothing);
        operations.seedApplicantStatusForQa(
          _status(RoomJoinRequestStatus.approved),
        );
        await tester.pump(const Duration(seconds: 2));
        await tester.pump();
        expect(repository.calls, 1);
        if (change == 'account') {
          await dependencies.sessionManager.save(_session(11));
          await tester.pumpAndSettle();
        } else if (change == 'pending') {
          await controller.join();
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text('继续进入'));
        await tester.pumpAndSettle();
        expect(repository.calls, change == 'account' ? 1 : 2);
        expect(controller.status, RoomSessionStatus.failed);
        expect(controller.snapshot, isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'cancel response cannot imply cancelled when authoritative GET says approved',
    (tester) async {
      final repository = _ApplicantRepository(
        _status(RoomJoinRequestStatus.pending),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: RoomJoinRequestStatusPage(
            roomId: 'room-9527',
            repositoryOverride: repository,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('撤回申请'));
      await tester.pump();
      repository.completeCancel();
      repository.status = _status(RoomJoinRequestStatus.approved);
      await tester.pumpAndSettle();
      expect(find.text('已同意'), findsNWidgets(2));
      expect(find.text('已撤回'), findsNothing);
      expect(find.text('继续进入'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final roomState in ['CLOSED', 'OPEN']) {
    testWidgets('approved cannot continue for unavailable room ($roomState)', (
      tester,
    ) async {
      final repository = _ApplicantRepository(
        RoomJoinRequestApplicantStatus(
          roomId: 'room-9527',
          joinRequestId: 'join-request-1',
          status: RoomJoinRequestStatus.approved,
          roomState: roomState,
          banned: roomState == 'OPEN',
          canCancel: false,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: RoomJoinRequestStatusPage(
            roomId: 'room-9527',
            repositoryOverride: repository,
            allowContinue: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('继续进入'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('account switch clears state and rejects late old account GET', (
    tester,
  ) async {
    final dependencies = AppDependencies.mock();
    await dependencies.sessionManager.save(_session(10));
    addTearDown(dependencies.dispose);
    final repository = _ApplicantRepository(
      _status(RoomJoinRequestStatus.pending),
    );
    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: dependencies,
        child: MaterialApp(
          home: RoomJoinRequestStatusPage(
            roomId: 'room-9527',
            repositoryOverride: repository,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    repository.delayNextStatusFetch();
    await tester.pump(const Duration(seconds: 2));
    await dependencies.sessionManager.save(_session(11));
    await tester.pump();
    expect(find.text('待审核'), findsNothing);
    repository.status = _status(RoomJoinRequestStatus.approved);
    repository.completeDelayedStatusFetch();
    repository.status = _status(RoomJoinRequestStatus.rejected);
    await tester.pumpAndSettle();
    expect(find.text('已同意'), findsNothing);
    expect(repository.statusCalls, 3);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'background and covering route pause; returning reads immediately',
    (tester) async {
      final repository = _ApplicantRepository(
        _status(RoomJoinRequestStatus.pending),
      );
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: RoomJoinRequestStatusPage(
            roomId: 'room-9527',
            repositoryOverride: repository,
          ),
        ),
      );
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      final before = repository.statusCalls;
      await tester.pump(const Duration(seconds: 10));
      expect(repository.statusCalls, before);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(repository.statusCalls, before + 1);
      navigator.currentState!.push<void>(
        MaterialPageRoute(builder: (_) => const Scaffold()),
      );
      await tester.pumpAndSettle();
      final covered = repository.statusCalls;
      await tester.pump(const Duration(seconds: 10));
      expect(repository.statusCalls, covered);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(repository.statusCalls, covered + 1);
      await tester.pumpWidget(const SizedBox());
      final disposed = repository.statusCalls;
      await tester.pump(const Duration(seconds: 10));
      expect(repository.statusCalls, disposed);
    },
  );

  testWidgets(
    'slow polling is single flight and room change discards old response',
    (tester) async {
      final repository = _ApplicantRepository(
        _status(RoomJoinRequestStatus.pending),
      );
      Widget page(String room) => MaterialApp(
        home: RoomJoinRequestStatusPage(
          roomId: room,
          repositoryOverride: repository,
        ),
      );
      await tester.pumpWidget(page('room-9527'));
      await tester.pumpAndSettle();
      repository.delayNextStatusFetch();
      await tester.pump(const Duration(seconds: 2));
      final calls = repository.statusCalls;
      await tester.pump(const Duration(seconds: 10));
      expect(repository.statusCalls, calls);
      await tester.pumpWidget(page('next-room'));
      expect(find.text('待审核'), findsNothing);
      repository.completeDelayedStatusFetch();
      repository.status = RoomJoinRequestApplicantStatus(
        roomId: 'next-room',
        joinRequestId: 'next-request',
        status: RoomJoinRequestStatus.rejected,
        roomState: 'OPEN',
        banned: false,
        canCancel: false,
      );
      await tester.pumpAndSettle();
      expect(find.text('待审核'), findsNothing);
      expect(repository.statusCalls, calls + 1);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('disposing during cancel never starts follow-up GET', (
    tester,
  ) async {
    final repository = _ApplicantRepository(
      _status(RoomJoinRequestStatus.pending),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: RoomJoinRequestStatusPage(
          roomId: 'room-9527',
          repositoryOverride: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('撤回申请'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    repository.completeCancel();
    await tester.pump();
    expect(repository.statusCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('approved requires explicit continue and pending has no entry', (
    tester,
  ) async {
    final repository = _ApplicantRepository(
      _status(RoomJoinRequestStatus.pending),
    );
    final navigator = GlobalKey<NavigatorState>();
    Object? result;
    await tester.pumpWidget(
      MaterialApp(navigatorKey: navigator, home: const SizedBox()),
    );
    navigator.currentState!
        .push<Object>(
          MaterialPageRoute(
            builder: (_) => RoomJoinRequestStatusPage(
              roomId: 'room-9527',
              repositoryOverride: repository,
              allowContinue: true,
            ),
          ),
        )
        .then((value) => result = value);
    await tester.pumpAndSettle();
    expect(find.text('继续进入'), findsNothing);
    repository.status = _status(RoomJoinRequestStatus.approved);
    await tester.tap(find.byTooltip('刷新权威状态'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(find.text('继续进入'), findsOneWidget);
    await tester.tap(find.text('继续进入'));
    await tester.pumpAndSettle();
    expect(result, isNotNull);
  });

  testWidgets('visible applicant reads approval within five seconds', (
    tester,
  ) async {
    final repository = _ApplicantRepository(
      _status(RoomJoinRequestStatus.pending),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: RoomJoinRequestStatusPage(
          roomId: 'room-9527',
          repositoryOverride: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();
    repository.status = _status(RoomJoinRequestStatus.approved);
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(repository.statusCalls, greaterThan(1));
    expect(find.text('已同意'), findsNWidgets(2));
    expect(find.byType(RoomJoinRequestStatusPage), findsOneWidget);
    expect(repository.cancelCalls, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'RM-007 applicant can inspect and cancel only a pending request',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final _ApplicantRepository repository = _ApplicantRepository(
        RoomJoinRequestApplicantStatus(
          roomId: 'room-9527',
          joinRequestId: 'join-request-1',
          status: RoomJoinRequestStatus.pending,
          roomState: 'OPEN',
          banned: false,
          canCancel: true,
          message: '想和大家一起聊天',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: RoomJoinRequestStatusPage(
            roomId: 'room-9527',
            repositoryOverride: repository,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('入房申请状态'), findsOneWidget);
      expect(find.text('待审核'), findsNWidgets(2));
      expect(find.text('想和大家一起聊天'), findsOneWidget);
      expect(find.text('撤回申请'), findsOneWidget);

      await tester.tap(find.text('撤回申请'));
      await tester.pump();
      expect(repository.cancelCalls, 1);
      expect(find.text('正在撤回…'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '正在撤回…'))
            .onPressed,
        isNull,
      );

      repository.completeCancel();
      await tester.pumpAndSettle();
      expect(find.text('已撤回'), findsNWidgets(2));
      expect(find.text('撤回申请'), findsNothing);
      expect(repository.statusCalls, 2);
    },
  );

  testWidgets(
    'RM-007 applicant errors remain retryable and never fake success',
    (WidgetTester tester) async {
      final _ApplicantRepository repository = _ApplicantRepository.failure(
        const ApiException(kind: ApiFailureKind.business, message: '入房申请不存在'),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: RoomJoinRequestStatusPage(
            roomId: 'room-9527',
            repositoryOverride: repository,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('入房申请不存在'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      expect(find.text('已撤回'), findsNothing);
    },
  );

  testWidgets(
    'RM-007 refresh and cancel are serialized against stale authority',
    (WidgetTester tester) async {
      final _ApplicantRepository repository = _ApplicantRepository(
        RoomJoinRequestApplicantStatus(
          roomId: 'room-9527',
          joinRequestId: 'join-request-1',
          status: RoomJoinRequestStatus.pending,
          roomState: 'OPEN',
          banned: false,
          canCancel: true,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: RoomJoinRequestStatusPage(
            roomId: 'room-9527',
            repositoryOverride: repository,
          ),
        ),
      );
      await tester.pumpAndSettle();

      repository.delayNextStatusFetch();
      await tester.tap(find.byTooltip('刷新权威状态'));
      await tester.pump();

      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '撤回申请'))
            .onPressed,
        isNull,
      );
      expect(repository.cancelCalls, 0);

      repository.completeDelayedStatusFetch();
      await tester.pumpAndSettle();
      await tester.tap(find.text('撤回申请'));
      await tester.pump();
      expect(repository.cancelCalls, 1);
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.refresh_rounded),
            )
            .onPressed,
        isNull,
      );

      repository.completeCancel();
      await tester.pumpAndSettle();
      expect(find.text('已撤回'), findsNWidgets(2));
      expect(find.text('撤回申请'), findsNothing);
    },
  );
}

RoomJoinRequestApplicantStatus _status(RoomJoinRequestStatus status) =>
    RoomJoinRequestApplicantStatus(
      roomId: 'room-9527',
      joinRequestId: 'join-request-1',
      status: status,
      roomState: 'OPEN',
      banned: false,
      canCancel: status == RoomJoinRequestStatus.pending,
    );

AuthSession _session(int userId) => AuthSession(
  accessToken: 'test',
  tokenType: 'Bearer',
  expiresAt: DateTime(2030),
  userId: userId,
  mobile: '',
  roles: 'USER',
);

class _RefusingEntryRepository extends MockRoomRepository {
  int calls = 0;
  @override
  Future<RoomSnapshot> enterRoom({
    required String roomId,
    required String? password,
    required RoomEntrySource source,
    required int currentUserId,
  }) async {
    calls++;
    if (calls == 1)
      throw RoomJoinRequestPendingException(
        roomId: roomId,
        joinRequestId: 'join-request-1',
      );
    throw const ApiException(kind: ApiFailureKind.business, message: '服务端拒绝入房');
  }
}

class _ApplicantRepository implements RoomJoinRequestRepository {
  _ApplicantRepository(this.status) : failure = null;

  _ApplicantRepository.failure(this.failure) : status = null;

  RoomJoinRequestApplicantStatus? status;
  final Object? failure;
  int statusCalls = 0;
  int cancelCalls = 0;
  Completer<RoomJoinRequestCancellation>? cancelCompleter;
  Completer<RoomJoinRequestApplicantStatus>? delayedStatusCompleter;

  void delayNextStatusFetch() {
    delayedStatusCompleter = Completer<RoomJoinRequestApplicantStatus>();
  }

  void completeDelayedStatusFetch() {
    final Completer<RoomJoinRequestApplicantStatus>? completer =
        delayedStatusCompleter;
    delayedStatusCompleter = null;
    if (completer == null || completer.isCompleted || status == null) {
      return;
    }
    completer.complete(status!);
  }

  void completeCancel() {
    final Completer<RoomJoinRequestCancellation>? completer = cancelCompleter;
    if (completer == null || completer.isCompleted) {
      return;
    }
    status = RoomJoinRequestApplicantStatus(
      roomId: 'room-9527',
      joinRequestId: 'join-request-1',
      status: RoomJoinRequestStatus.cancelled,
      roomState: 'OPEN',
      banned: false,
      canCancel: false,
    );
    completer.complete(
      const RoomJoinRequestCancellation(
        roomId: 'room-9527',
        joinRequestId: 'join-request-1',
        status: RoomJoinRequestStatus.cancelled,
        cancelled: true,
        alreadyCancelled: false,
      ),
    );
  }

  @override
  Future<RoomJoinRequestApplicantStatus> fetchJoinRequestStatus({
    String? roomId,
    String? joinRequestId,
  }) async {
    statusCalls += 1;
    if (failure != null) {
      throw failure!;
    }
    final Completer<RoomJoinRequestApplicantStatus>? delayed =
        delayedStatusCompleter;
    if (delayed != null) {
      return delayed.future;
    }
    return status!;
  }

  @override
  Future<RoomJoinRequestCancellation> cancelJoinRequest({
    required String roomId,
    required String joinRequestId,
    String? requestId,
  }) {
    cancelCalls += 1;
    cancelCompleter = Completer<RoomJoinRequestCancellation>();
    return cancelCompleter!.future;
  }

  @override
  Future<RoomJoinRequestPage> fetchJoinRequests({
    required String roomId,
    int page = 1,
    int pageSize = 20,
  }) async => throw UnimplementedError();

  @override
  Future<void> resolveJoinRequest({
    required String joinRequestId,
    required bool approved,
    String? requestId,
  }) async => throw UnimplementedError();
}
