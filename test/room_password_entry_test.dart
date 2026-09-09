import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/room/application/room_controller.dart';
import 'package:voice_social_app/features/room/data/mock_room_repository.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/infrastructure/room_realtime_gateway.dart';
import 'package:voice_social_app/features/room/infrastructure/rtc_adapter.dart';
import 'package:voice_social_app/features/room/presentation/video_runtime_room_page.dart';

class _Repository extends MockRoomRepository {
  final List<String?> passwords = [];
  int? rejection = 40332;
  Completer<void>? gate;

  @override
  Future<RoomSnapshot> enterRoom({
    required String roomId,
    required String? password,
    required RoomEntrySource source,
    required int currentUserId,
  }) async {
    passwords.add(password);
    await gate?.future;
    if (rejection != null && password != '1234') {
      throw ApiException(
        kind: ApiFailureKind.forbidden,
        code: rejection,
        message: '房间密码错误', // Non-password codes must not match this text.
      );
    }
    return super.enterRoom(
      roomId: roomId,
      password: password,
      source: source,
      currentUserId: currentUserId,
    );
  }
}

void main() {
  late _Repository repository;
  late RoomController controller;
  late MockRoomRealtimeGateway realtime;
  late ValueNotifier<int> identity;

  setUp(() {
    repository = _Repository();
    realtime = MockRoomRealtimeGateway();
    identity = ValueNotifier(0);
    controller = RoomController(
      roomId: '880217',
      title: '密码房',
      currentUserId: 10001,
      accessToken: 'test-token',
      repository: repository,
      rtcAdapter: MockRtcAdapter(),
      realtimeGateway: realtime,
      sessionChanges: identity,
      identityGeneration: () => identity.value,
    );
  });
  tearDown(() async {
    controller.dispose();
    identity.dispose();
    await realtime.dispose();
  });

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: AppDependencies.mock(),
        child: MaterialApp(home: VideoRuntimeRoomPage(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'password challenge submits and wrong password requires explicit retry',
    (tester) async {
      await mount(tester);
      expect(repository.passwords, [null]);
      final input = find.byKey(const Key('room-entry-password'));
      expect(input, findsOneWidget);
      final field = tester.widget<TextField>(input);
      expect(field.obscureText, isTrue);
      expect(field.enableSuggestions, isFalse);
      expect(field.autocorrect, isFalse);
      await tester.enterText(input, '9999');
      await tester.tap(find.text('确认进入'));
      await tester.pumpAndSettle();
      expect(repository.passwords, [null, '9999']);
      expect(input, findsNothing);
      await tester.tap(find.text('重新进入'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(input).controller!.text, isEmpty);
      await tester.enterText(input, '1234');
      await tester.tap(find.text('确认进入'));
      await tester.pumpAndSettle();
      expect(repository.passwords, [null, '9999', '1234']);
      expect(controller.status, RoomSessionStatus.joined);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('cancel never loops or sends a password', (tester) async {
    await mount(tester);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    expect(find.byKey(const Key('room-entry-password')), findsNothing);
    expect(repository.passwords, [null]);
  });

  for (final code in [40331, 40939, 40431]) {
    testWidgets('non-password rejection $code never prompts', (tester) async {
      repository.rejection = code;
      await mount(tester);
      expect(find.byKey(const Key('room-entry-password')), findsNothing);
      expect(repository.passwords, [null]);
    });
  }

  testWidgets('backend admission without password never prompts', (
    tester,
  ) async {
    repository.rejection = null;
    await mount(tester);
    expect(controller.status, RoomSessionStatus.joined);
    expect(repository.passwords, [null]);
    expect(find.byKey(const Key('room-entry-password')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('identity change closes input and prevents submission', (
    tester,
  ) async {
    await mount(tester);
    await tester.enterText(
      find.byKey(const Key('room-entry-password')),
      '1234',
    );
    identity.value++;
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('room-entry-password')), findsNothing);
    expect(repository.passwords, [null]);
  });

  testWidgets('late challenge after identity change does not open dialog', (
    tester,
  ) async {
    repository.gate = Completer<void>();
    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: AppDependencies.mock(),
        child: MaterialApp(home: VideoRuntimeRoomPage(controller: controller)),
      ),
    );
    await tester.pump();
    identity.value++;
    repository.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('room-entry-password')), findsNothing);
    expect(repository.passwords, [null]);
  });

  testWidgets('empty input makes no request', (tester) async {
    await mount(tester);
    await tester.tap(find.text('确认进入'));
    await tester.pumpAndSettle();
    expect(find.text('请输入不超过32个字符的房间密码'), findsOneWidget);
    expect(repository.passwords, [null]);
  });

  testWidgets('valid joined session is not re-entered on page rebuild', (
    tester,
  ) async {
    repository.rejection = null;
    await mount(tester);
    expect(controller.status, RoomSessionStatus.joined);
    repository.rejection = 40332;
    await mount(tester);
    expect(repository.passwords, [null]);
    expect(find.byKey(const Key('room-entry-password')), findsNothing);
    expect(controller.status, RoomSessionStatus.joined);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('moderator still follows server password challenge', (
    tester,
  ) async {
    repository.seedEntryRoleForQa(RoomRole.moderator);
    await mount(tester);
    expect(repository.passwords, [null]);
    await tester.enterText(
      find.byKey(const Key('room-entry-password')),
      '1234',
    );
    await tester.tap(find.text('确认进入'));
    await tester.pumpAndSettle();
    expect(controller.status, RoomSessionStatus.joined);
    expect(controller.role, RoomRole.moderator);
    expect(repository.passwords, [null, '1234']);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'removing room page removes its dialog from surviving navigator',
    (tester) async {
      final visible = ValueNotifier(true);
      addTearDown(visible.dispose);
      await tester.pumpWidget(
        AppDependencyScope(
          dependencies: AppDependencies.mock(),
          child: MaterialApp(
            home: ValueListenableBuilder<bool>(
              valueListenable: visible,
              builder: (_, shown, _) => shown
                  ? VideoRuntimeRoomPage(controller: controller)
                  : const Text('已离页'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('room-entry-password')), findsOneWidget);
      visible.value = false;
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('room-entry-password')), findsNothing);
      expect(find.text('已离页'), findsOneWidget);
      expect(repository.passwords, [null]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('late submitted success cannot join after identity ABA', (
    tester,
  ) async {
    await mount(tester);
    repository.gate = Completer<void>();
    await tester.enterText(
      find.byKey(const Key('room-entry-password')),
      '1234',
    );
    await tester.tap(find.text('确认进入'));
    await tester.pump();
    identity.value++;
    identity.value++;
    repository.gate!.complete();
    await tester.pumpAndSettle();
    expect(controller.status, isNot(RoomSessionStatus.joined));
    expect(find.byKey(const Key('room-entry-password')), findsNothing);
    expect(repository.passwords, [null, '1234']);
  });

  testWidgets('leave while challenge pending never opens input', (
    tester,
  ) async {
    repository.gate = Completer<void>();
    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: AppDependencies.mock(),
        child: MaterialApp(home: VideoRuntimeRoomPage(controller: controller)),
      ),
    );
    await tester.pump();
    await controller.leaveRoom();
    repository.gate!.complete();
    await tester.pumpAndSettle();
    expect(controller.status, RoomSessionStatus.left);
    expect(find.byKey(const Key('room-entry-password')), findsNothing);
  });
}
