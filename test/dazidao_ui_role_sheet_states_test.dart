import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/features/room/domain/room_permission_policy.dart';
import 'package:voice_social_app/features/room/application/room_controller.dart';
import 'package:voice_social_app/features/room/data/mock_room_operations_repository.dart';
import 'package:voice_social_app/features/room/data/mock_room_repository.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/domain/room_operations_models.dart';
import 'package:voice_social_app/features/room/infrastructure/room_realtime_gateway.dart';
import 'package:voice_social_app/features/room/infrastructure/rtc_adapter.dart';
import 'package:voice_social_app/features/room/presentation/video_runtime_room_page.dart';
import 'dazidao_ui_render_matrix_test.dart' show renderDazidaoScenario;
import 'support/golden_font_gate.dart';

// Actual production sheets opened from the room, with synthetic repositories.
// Never invoke device, live account, gift, payment, or governance commands.
const _matrix = bool.fromEnvironment('UI_MATRIX');
const _only = String.fromEnvironment('UI_CASE');
const _roomId = '880217';
const _viewerId = 10001;

enum _Panel { mic, interactions, tools }

class _Scenario {
  const _Scenario(this.id, this.role, this.panel, {this.requestStatus});
  final String id;
  final RoomRole role;
  final _Panel panel;
  final MicRequestStatus? requestStatus;
}

void main() {
  setUpAll(loadGoldenFonts);
  final cases = <_Scenario>[
    const _Scenario('RM-005-listener-available', RoomRole.listener, _Panel.mic),
    for (final state in [
      MicRequestStatus.pending,
      MicRequestStatus.approved,
      MicRequestStatus.rejected,
    ])
      _Scenario(
        'RM-005-listener-${state.name}',
        RoomRole.listener,
        _Panel.mic,
        requestStatus: state,
      ),
    for (final role in [RoomRole.owner, RoomRole.moderator])
      _Scenario('RM-005-${role.name}-direct', role, _Panel.mic),
    for (final role in [
      RoomRole.owner,
      RoomRole.moderator,
      RoomRole.listener,
      RoomRole.platformModerator,
    ]) ...[
      _Scenario('RM-004-${role.name}-interactions', role, _Panel.interactions),
      _Scenario('RM-004-${role.name}-tools', role, _Panel.tools),
    ],
  ];
  final variants = _matrix
      ? <(Size, double)>[
          for (final size in const [
            Size(375, 667),
            Size(390, 844),
            Size(402, 874),
          ])
            for (final scale in [1.0, 1.3]) (size, scale),
        ]
      : <(Size, double)>[(const Size(390, 844), 1.0)];
  for (final scenario in cases) {
    if (_only.isNotEmpty && !_only.split(',').contains(scenario.id)) continue;
    for (final variant in variants) {
      testWidgets('sheet ${scenario.id} ${variant.$1} text=${variant.$2}', (
        tester,
      ) async {
        RoomController? controller;
        final operations = MockRoomOperationsRepository();
        await renderDazidaoScenario(
          tester,
          id: scenario.id,
          size: variant.$1,
          scale: variant.$2,
          prepare: (dependencies) async {
            if (scenario.requestStatus case final status?) {
              operations.seedMicRequestForQa(_request(status));
            }
            controller = RoomController(
              roomId: _roomId,
              title: '界面测试房间',
              currentUserId: _viewerId,
              accessToken: 'synthetic-widget-fixture',
              repository: _EmptySeatsRepository(scenario.role),
              rtcAdapter: const SnapshotOnlyRtcAdapter(),
              realtimeGateway: const SnapshotOnlyRoomRealtimeGateway(),
              roomOperationsRepository: operations,
            );
            await controller!.join();
            expect(controller!.status, RoomSessionStatus.joined);
            expect(controller!.role, scenario.role);
            expect(controller!.isOnMic, isFalse);
          },
          builder: (_) => Theme(
            data: AppTheme.room(fontFamily: kGoldenFontFamily),
            child: VideoRuntimeRoomPage(controller: controller!),
          ),
          exercise: (tester, dependencies) =>
              _openAndVerify(tester, dependencies, scenario, controller!),
          release: () => controller?.dispose(),
          annotations: {
            'manifestId': scenario.panel == _Panel.mic ? 'RM-005' : 'RM-004',
            'roomRole': scenario.role.name,
            'state': scenario.requestStatus?.name ?? 'normal',
            'surface': scenario.panel.name,
            'actualPanelOpened': true,
          },
        );
      });
    }
  }
}

Future<void> _openAndVerify(
  WidgetTester tester,
  AppDependencies dependencies,
  _Scenario scenario,
  RoomController controller,
) async {
  final mic = scenario.panel == _Panel.mic;
  final trigger = mic
      ? find.text('上麦').hitTestable()
      : find.byTooltip('更多').hitTestable();
  await _waitFor(tester, trigger);
  expect(controller.isOnMic, isFalse);
  await tester.tap(trigger);
  await _waitFor(tester, find.byType(BottomSheet));
  if (mic) {
    final direct =
        scenario.role == RoomRole.owner || scenario.role == RoomRole.moderator;
    await _waitFor(tester, find.text(direct ? '选择麦位' : '审批上麦'));
    if (direct) {
      // The route can be mounted before its entry transition becomes tappable.
      await _waitFor(tester, find.text('1 号麦').hitTestable());
      for (var number = 1; number <= 9; number++) {
        await _waitFor(tester, find.text('$number 号麦').hitTestable());
        expect(find.text('$number 号麦').hitTestable(), findsOneWidget);
      }
    } else if (scenario.requestStatus == MicRequestStatus.pending) {
      expect(find.text('你正在等待 5 号麦审批'), findsOneWidget);
      expect(
        find.byKey(const Key('approval-mic-request-cancel')),
        findsOneWidget,
      );
    } else {
      expect(find.byKey(const Key('approval-mic-seat-1')), findsNothing);
      expect(find.byKey(const Key('approval-mic-seat-9')), findsOneWidget);
      if (scenario.requestStatus != null) {
        expect(
          find.text(
            scenario.requestStatus == MicRequestStatus.approved
                ? '最近状态：已同意'
                : '最近状态：已拒绝',
          ),
          findsOneWidget,
        );
      }
    }
    expect(
      controller.isOnMic,
      isFalse,
      reason: 'Opening a visual panel never grants microphone publication',
    );
  } else {
    await _waitFor(tester, find.text('互动玩法').hitTestable());
    if (scenario.panel == _Panel.tools) {
      await tester.tap(find.text('工具').hitTestable());
      await _waitFor(tester, find.text('音频').hitTestable());
      expect(find.text('重新连接'), findsOneWidget);
      expect(find.text('离开房间'), findsOneWidget);
      expect(find.text('主动下麦'), findsNothing);
    } else {
      final mayPk =
          scenario.role == RoomRole.owner ||
          scenario.role == RoomRole.moderator;
      expect(find.text('房间 PK'), mayPk ? findsOneWidget : findsNothing);
      expect(controller.allows(RoomCapability.editRoom), mayPk);
      expect(find.text('房间资料'), mayPk ? findsOneWidget : findsNothing);
    }
  }
  expect(dependencies.environment.isLive, isFalse);
  expect(tester.takeException(), isNull);
}

Future<void> _waitFor(WidgetTester tester, Finder target) async {
  for (var attempt = 0; attempt < 80; attempt++) {
    if (target.evaluate().length == 1) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 3)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    expect(
      tester.takeException(),
      isNull,
      reason: 'A failed fixture/render must not be counted as business RED',
    );
  }
  expect(
    target,
    findsOneWidget,
    reason: 'Actual production panel readiness barrier timed out',
  );
}

MicAccessRequest _request(MicRequestStatus status) => MicAccessRequest(
  id: 'synthetic-ui-request',
  roomId: _roomId,
  member: const RoomMember(
    userId: _viewerId,
    name: '测试申请人',
    role: RoomRole.listener,
    presence: RoomMemberPresence.listener,
  ),
  seatNumber: 5,
  version: 1,
  status: status,
  createdAt: DateTime.utc(2026, 9, 21),
  type: MicRequestType.request,
  requestedByUserId: _viewerId,
  subjectUserId: _viewerId,
  targetAction: MicRequestTargetAction.cancel,
);

class _EmptySeatsRepository extends MockRoomRepository {
  _EmptySeatsRepository(RoomRole role) {
    seedEntryRoleForQa(role);
  }

  @override
  Future<RoomSnapshot> enterRoom({
    required String roomId,
    required String? password,
    required RoomEntrySource source,
    required int currentUserId,
  }) async {
    final original = await super.enterRoom(
      roomId: roomId,
      password: password,
      source: source,
      currentUserId: currentUserId,
    );
    return original.copyWith(
      transportMode: RoomTransportMode.snapshotOnly,
      accessMode: 'APPROVAL',
      seats: [
        for (var number = 1; number <= 9; number++)
          MicSeat(
            number: number,
            backendIndex: number,
            state: MicSeatState.available,
          ),
      ],
      rtc: RtcCredentials(
        solution: RtcSolution.unknown,
        token: '',
        channelId: roomId,
        userId: currentUserId,
      ),
    );
  }
}
