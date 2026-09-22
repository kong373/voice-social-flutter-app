import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/debug/qa_console/qa_fixtures.dart';
import 'package:voice_social_app/features/commerce/catalog/domain/commerce_catalog_models.dart';
import 'package:voice_social_app/features/commerce/presentation/commerce_pages.dart';
import 'package:voice_social_app/features/room/application/room_controller.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/domain/room_operations_models.dart';
import 'package:voice_social_app/features/room/infrastructure/room_audio_service.dart';
import 'package:voice_social_app/features/room/pk/data/mock_room_pk_repository.dart';
import 'package:voice_social_app/features/room/pk/domain/room_pk_models.dart';
import 'package:voice_social_app/features/room/pk/presentation/room_pk_pages.dart';
import 'package:voice_social_app/features/room/presentation/room_audio_page.dart';
import 'package:voice_social_app/features/room/presentation/room_recovery_page.dart';
import 'dazidao_ui_render_matrix_test.dart' show renderDazidaoScenario;
import 'support/dazidao_ui_state_authorities.dart';
import 'support/golden_font_gate.dart';

const _matrix = bool.fromEnvironment('UI_MATRIX');
const _cases = <(String, String)>[
  ('RM-010', 'unavailable'),
  ('RM-010', 'listener'),
  ('RM-010', 'denied'),
  ('RM-010', 'speaker'),
  ('RM-010', 'loading'),
  ('RM-011', 'snapshot'),
  ('RM-011', 'reconnecting'),
  ('RM-011', 'degraded'),
  ('RM-013', 'loading'),
  ('RM-013', 'error'),
  ('RM-013', 'empty'),
  ('RM-014', 'fighting'),
  ('RM-014', 'settling'),
  ('RM-014', 'win'),
  ('RM-014', 'lose'),
  ('RM-014', 'draw'),
  ('CM-003', 'android'),
  ('CM-003', 'ios'),
  ('CM-003', 'unavailable'),
  ('CM-006', 'normal'),
  ('CM-006', 'loading'),
  ('CM-006', 'error'),
];
void main() {
  setUpAll(loadGoldenFonts);
  for (final item in _cases) {
    final variants = _matrix
        ? [
            for (final size in const [
              Size(375, 667),
              Size(390, 844),
              Size(402, 874),
            ])
              for (final scale in [1.0, 1.3]) (size, scale),
          ]
        : [(const Size(390, 844), 1.0)];
    for (final viewport in variants) {
      testWidgets('surface ${item.$1}-${item.$2} $viewport', (tester) async {
        final mode =
            UiReadMode.values
                .where((value) => value.name == item.$2)
                .firstOrNull ??
            UiReadMode.normal;
        final target = switch (item.$1) {
          'RM-010' => 'audio',
          'RM-013' => 'pk.hot',
          'CM-006' => 'commerce.order',
          _ => '',
        };
        final probe = UiReadProbe(target, mode, variant: item.$2);
        late _Scope scope;
        final recovery = _Recovery(item.$2);
        await renderDazidaoScenario(
          tester,
          id: '${item.$1}-extra-${item.$2}',
          size: viewport.$1,
          scale: viewport.$2,
          transformDependencies: (base) => scope = _Scope(base, probe),
          prepare: (_) => scope.initialize(),
          useProductionHostTheme: true,
          builder: (dependencies) => _page(item, scope, recovery),
          release: recovery.dispose,
          exercise: (tester, _) => _verify(tester, item, probe),
          annotations: {
            'manifestId': item.$1,
            'state': item.$2,
            'evidenceType': 'SYNTHETIC_PRODUCTION_WIDGET',
            'deviceValidated': false,
          },
        );
        expect(probe.writes, isEmpty);
      });
    }
  }
}

class _Scope extends UiScenarioScope {
  _Scope(super.base, super.probe);
  @override
  late final roomAudioService = _Audio(probe);
  @override
  late final _Pk roomPkRepository = _Pk(probe);
  @override
  late final commerceCatalogRepository = _Catalog(probe);
}

class _Audio implements RoomAudioService {
  _Audio(this.probe);
  final UiReadProbe probe;
  @override
  Future<RoomAudioSnapshot> inspect() => probe.read(
    'audio',
    () async => RoomAudioSnapshot(
      configured: probe.variant != 'unavailable',
      route: RoomAudioRoute.speaker,
      availableRoutes: const {RoomAudioRoute.speaker, RoomAudioRoute.earpiece},
      microphonePermissionGranted:
          probe.variant != 'denied' && probe.variant != 'unavailable',
      microphoneEnabled: false,
      rtcConnected: false,
      realtimeConnected: false,
      grade: RoomConnectionGrade.unknown,
      latencyMs: null,
      packetLossPercent: null,
      updatedAt: qaReferenceTime,
    ),
  );
  @override
  Future<RoomAudioSnapshot> selectRoute(RoomAudioRoute route) async =>
      probe.forbidWrite('audio-route');
  @override
  Future<RoomAudioSnapshot> setMicrophoneEnabled(bool enabled) async =>
      probe.forbidWrite('microphone');
}

class _Pk extends MockRoomPkRepository {
  _Pk(this.probe);
  final UiReadProbe probe;
  @override
  Future<List<RoomPkOpponent>> fetchHotOpponents({
    required String roomId,
    void Function()? requireCurrent,
  }) => probe.read(
    'pk.hot',
    () =>
        super.fetchHotOpponents(roomId: roomId, requireCurrent: requireCurrent),
    empty: () => [],
  );
}

class _Catalog extends UiCatalogRepository {
  _Catalog(super.probe);
  @override
  bool get supportsPaymentChannelInvocation => probe.variant != 'unavailable';
}

// Read-only projection for recovery UI; real controller behavior is covered by existing tests.
class _Recovery extends ChangeNotifier implements RoomController {
  _Recovery(this.variant);
  final String variant;
  @override
  String get roomId => '880217';
  @override
  RoomSnapshot? get snapshot => null;
  @override
  RoomSessionStatus get status => variant == 'reconnecting'
      ? RoomSessionStatus.reconnecting
      : RoomSessionStatus.joined;
  @override
  bool get isSnapshotOnly => variant == 'snapshot';
  @override
  bool get realtimeDegraded => variant == 'degraded';
  @override
  bool get isOnMic => false;
  @override
  Future<void> reconnect() async =>
      throw StateError('No recovery command in visual test');
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Unexpected recovery dependency: ${invocation.memberName}',
  );
}

Widget _page((String, String) item, _Scope scope, _Recovery recovery) {
  switch (item.$1) {
    case 'RM-010':
      return RoomAudioPage(
        isOnMic: item.$2 == 'speaker' || item.$2 == 'denied',
        roomTitle: '测试语音房',
      );
    case 'RM-011':
      return RoomRecoveryPage(controller: recovery, roomTitle: '测试语音房');
    case 'RM-013':
      return const RoomPkPreparationPage(roomId: '880217', roomTitle: '测试语音房');
    case 'RM-014':
      final completed = ['win', 'lose', 'draw'].contains(item.$2);
      final result = completed
          ? RoomPkResult.values.singleWhere((value) => value.name == item.$2)
          : null;
      final score = item.$2 == 'draw'
          ? 2940
          : item.$2 == 'lose'
          ? 2000
          : 3680;
      final battle = qaRoomPkBattle(scope, completed: false).copyWith(
        sender: const RoomPkSide(
          roomId: '880217',
          roomCode: '880217',
          roomName: '测试语音房',
          score: 0,
        ).copyWith(score: score),
        stage: completed
            ? RoomPkBattleStage.completed
            : item.$2 == 'settling'
            ? RoomPkBattleStage.settling
            : RoomPkBattleStage.fighting,
        result: result,
        remainingSeconds: completed || item.$2 == 'settling' ? 0 : 95,
      );
      scope.roomPkRepository.seedBattleForQa(battle);
      return RoomPkBattlePage(roomId: '880217', initialBattle: battle);
    case 'CM-003':
      return PaymentSubmissionPage(
        product: qaRechargeProduct,
        platform: item.$2 == 'ios'
            ? ClientStorePlatform.ios
            : ClientStorePlatform.android,
        youthModeEnabled: false,
      );
    case 'CM-006':
      return OrderDetailPage(order: qaPaymentOrder(scope));
    default:
      throw StateError('Unknown page');
  }
}

Future<void> _wait(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 80 && !ready(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 3)),
    );
    await tester.pump(const Duration(milliseconds: 25));
  }
  expect(ready(), isTrue, reason: 'Actual UI readiness required');
}

Future<void> _verify(
  WidgetTester tester,
  (String, String) item,
  UiReadProbe probe,
) async {
  if (item.$1 == 'CM-006') {
    final control = find.text('刷新并补单核验');
    await tester.ensureVisible(control);
    await tester.pump();
    await tester.tap(control);
    await tester.pump();
  }
  if (probe.target.isNotEmpty) {
    await _wait(tester, () => probe.intercepted > 0);
    expect(probe.intercepted, greaterThan(0));
  }
  if (item.$2 == 'error') {
    await _wait(
      tester,
      () => find.textContaining(uiReadFailure).evaluate().isNotEmpty,
    );
    expect(find.textContaining(uiReadFailure), findsWidgets);
  }
  if (item.$1 == 'RM-010' && item.$2 != 'loading') {
    if (item.$2 == 'unavailable') expect(find.text('音频能力未配置'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byType(SwitchListTile),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
      item.$2 == 'speaker' ? isNotNull : isNull,
    );
  }
  if (item.$1 == 'RM-011') {
    final label = switch (item.$2) {
      'snapshot' => '刷新房间快照',
      'reconnecting' => '正在恢复',
      _ => '重新连接房间',
    };
    expect(find.text(label), findsOneWidget);
    final button = find.ancestor(
      of: find.text(label),
      matching: find.byWidgetPredicate((widget) => widget is FilledButton),
    );
    expect(
      tester.widget<FilledButton>(button).onPressed,
      item.$2 == 'reconnecting' ? isNull : isNotNull,
    );
  }
  if (item.$1 == 'RM-014') {
    final label = {'win': '本房获胜', 'lose': '本房落败', 'draw': '本场平局'}[item.$2];
    if (label != null) {
      await tester.scrollUntilVisible(
        find.text(label),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(label), findsOneWidget);
    } else {
      expect(find.text('本房获胜'), findsNothing);
      expect(find.text('本场平局'), findsNothing);
    }
    expect(find.textContaining('主动认输'), findsNothing);
  }
  if (item.$1 == 'CM-003') {
    if (item.$2 == 'unavailable') {
      expect(find.text('提交充值订单'), findsNothing);
      expect(find.textContaining('当前支付暂不可用'), findsOneWidget);
    } else {
      expect(find.text('提交充值订单'), findsOneWidget);
      if (item.$2 == 'ios') {
        expect(find.text('支付宝'), findsNothing);
        expect(find.text('微信支付'), findsNothing);
        expect(find.textContaining('Apple IAP'), findsWidgets);
      } else {
        expect(find.text('支付宝'), findsOneWidget);
        expect(find.text('微信支付'), findsOneWidget);
      }
    }
  }
  if (item.$2 == 'loading') {
    expect(
      find.byWidgetPredicate(
        (w) => w is CircularProgressIndicator || w is LinearProgressIndicator,
      ),
      findsWidgets,
    );
  }
  expect(tester.takeException(), isNull);
}
