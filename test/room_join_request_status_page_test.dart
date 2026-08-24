import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/room/domain/room_operations_models.dart';
import 'package:voice_social_app/features/room/domain/room_operations_repository.dart';
import 'package:voice_social_app/features/room/presentation/room_join_request_status_page.dart';

void main() {
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
}

class _ApplicantRepository implements RoomJoinRequestRepository {
  _ApplicantRepository(this.status) : failure = null;

  _ApplicantRepository.failure(this.failure) : status = null;

  RoomJoinRequestApplicantStatus? status;
  final Object? failure;
  int statusCalls = 0;
  int cancelCalls = 0;
  Completer<RoomJoinRequestCancellation>? cancelCompleter;

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
