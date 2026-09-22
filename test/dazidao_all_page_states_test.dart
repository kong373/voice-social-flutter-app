import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/page_manifest.dart';
import 'package:voice_social_app/debug/qa_console/qa_fixtures.dart';
import 'package:voice_social_app/debug/qa_console/qa_models.dart';
import 'package:voice_social_app/debug/qa_console/qa_page_catalog.dart';
import 'package:voice_social_app/features/account/compliance/domain/account_compliance.dart';
import 'package:voice_social_app/features/commerce/catalog/domain/commerce_catalog_models.dart';
import 'package:voice_social_app/features/commerce/presentation/commerce_pages.dart';
import 'package:voice_social_app/features/community/presentation/community_pages.dart';
import 'package:voice_social_app/features/message/domain/message_models.dart';
import 'package:voice_social_app/features/social/presentation/social_pages.dart';
import 'package:voice_social_app/features/shell/main_shell.dart';
import 'package:voice_social_app/features/discovery/presentation/global_search_page.dart';
import 'package:voice_social_app/features/room/presentation/room_deep_link_page.dart';
import 'dazidao_ui_render_matrix_test.dart' show renderDazidaoScenario;
import 'support/dazidao_ui_state_authorities.dart';
import 'support/golden_font_gate.dart';

const _matrix = bool.fromEnvironment('UI_MATRIX');
const _only = String.fromEnvironment('UI_CASE');

class _Scene {
  const _Scene(
    this.page,
    this.target,
    this.mode, {
    this.variant = 'normal',
    this.role = 'ordinary',
  });
  final String page, target, variant, role;
  final UiReadMode mode;
  String get id =>
      '$page-${target.replaceAll('.', '-')}-${mode.name}-$variant-$role';
}

List<_Scene> _scenes() {
  final result = <_Scene>[];
  const reads = <(String, String, bool)>[
    ('AC-005', 'account.snapshot', false),
    ('AC-006', 'account.snapshot', false),
    ('AC-007', 'account.snapshot', true),
    ('AC-008', 'account.snapshot', false),
    ('AC-009', 'account.appeal', true),
    ('AC-010', 'account.cancel', false),
    ('AC-011', 'account.version', false),
    ('AC-012', 'account.snapshot', false),
    ('DS-001', 'discovery.home', true),
    ('DS-002', 'discovery.suggestions', true),
    ('DS-003', 'discovery.search', true),
    ('DS-004', 'dynamic.feed', true),
    ('DS-005', 'dynamic.post', false),
    ('DS-005', 'dynamic.comments', true),
    ('DS-007', 'dynamic.ranking', true),
    ('DS-008', 'discovery.collections', true),
    ('US-001', 'social.profile', false),
    ('US-003', 'social.public', false),
    ('US-004', 'social.relations', true),
    ('US-006', 'social.visitors', true),
    ('US-007', 'social.blacklist', true),
    ('US-009', 'social.service', false),
    ('US-009-history', 'social.tickets', true),
    ('US-010', 'social.ticket', false),
    ('MS-001', 'message.conversations', true),
    ('MS-002', 'message.private', true),
    ('MS-003', 'message.notifications', true),
    ('MS-004', 'message.notification', false),
    ('MS-006', 'message.recovery', false),
    ('CM-001', 'commerce.ledger', true),
    ('CM-002', 'catalog.products', true),
    ('CM-005', 'commerce.orders', true),
    ('CM-009', 'catalog.gifts', true),
    ('CM-010', 'catalog.decorations', true),
    ('SC-001', 'community.home', true),
    ('SC-002', 'community.members', true),
    ('SC-003', 'community.invite', true),
    ('RM-001', 'room.owned', true),
    ('RM-002', 'room.configuration', false),
    ('RM-003', 'room.link', false),
    ('RM-004', 'room.enter', false),
    ('RM-006', 'room.members', true),
    ('RM-007', 'room.members', true),
    ('RM-008', 'room.topic', true),
  ];
  for (final spec in reads) {
    for (final mode in [
      UiReadMode.loading,
      UiReadMode.error,
      if (spec.$3) UiReadMode.empty,
    ]) {
      result.add(
        _Scene(
          spec.$1,
          spec.$2,
          mode,
          role: spec.$1 == 'RM-007'
              ? 'roomOwner'
              : spec.$1 == 'RM-001' || spec.$1 == 'SC-002'
              ? 'chair'
              : 'ordinary',
        ),
      );
    }
  }
  for (final value in PermissionState.values) {
    result.add(
      _Scene(
        'AC-005',
        'account.snapshot',
        UiReadMode.normal,
        variant: 'permission-${value.name}',
      ),
    );
  }
  for (final value in VerificationState.values) {
    result.add(
      _Scene(
        'AC-006',
        'account.snapshot',
        UiReadMode.normal,
        variant: 'verification-${value.name}',
      ),
    );
  }
  for (final value in AppealState.values) {
    result.add(
      _Scene(
        'AC-009',
        'account.appeal',
        UiReadMode.normal,
        variant: 'appeal-${value.name}',
      ),
    );
  }
  for (final value in [
    'cancel-blocked',
    'cancel-cooling-open',
    'cancel-cooling-closed',
  ]) {
    result.add(
      _Scene('AC-010', 'account.cancel', UiReadMode.normal, variant: value),
    );
  }
  for (final value in [
    'version-current',
    'version-optional',
    'version-mandatory',
  ]) {
    result.add(
      _Scene('AC-011', 'account.version', UiReadMode.normal, variant: value),
    );
  }
  result.add(
    const _Scene(
      'AC-008',
      'account.snapshot',
      UiReadMode.normal,
      variant: 'restricted',
    ),
  );
  result.add(
    const _Scene(
      'AC-012',
      'account.snapshot',
      UiReadMode.normal,
      variant: 'youth-locked',
    ),
  );
  for (final value in MessageDeliveryStatus.values) {
    result.add(
      _Scene(
        'MS-002',
        'message.private',
        UiReadMode.normal,
        variant: 'delivery-${value.name}',
      ),
    );
  }
  result.add(
    const _Scene(
      'MS-004',
      'message.notification',
      UiReadMode.normal,
      variant: 'target-unavailable',
    ),
  );
  for (final value in NativeNotificationPermissionState.values) {
    result.add(
      _Scene(
        'MS-006',
        'message.recovery',
        UiReadMode.normal,
        variant: 'notification-${value.name}',
      ),
    );
  }
  for (final value in RechargeOrderState.values) {
    result.add(
      _Scene(
        'CM-004',
        'catalog.result',
        UiReadMode.normal,
        variant: 'payment-${value.name}',
      ),
    );
  }
  for (final value in ['decoration-expired', 'decoration-retired']) {
    result.add(
      _Scene(
        'CM-010',
        'catalog.decorations',
        UiReadMode.normal,
        variant: value,
      ),
    );
  }
  for (final role in ['ordinary', 'anchor', 'chair']) {
    result.add(
      _Scene('SC-001', 'community.home', UiReadMode.normal, role: role),
    );
    result.add(
      _Scene('SC-001-detail', 'community.guild', UiReadMode.normal, role: role),
    );
    result.add(
      _Scene(
        'SC-001-detail',
        'community.guild',
        UiReadMode.normal,
        role: role,
        variant: 'guild-closed',
      ),
    );
    if (role != 'ordinary')
      result.add(
        _Scene('SC-002', 'community.members', UiReadMode.normal, role: role),
      );
  }
  result.add(
    const _Scene(
      'SC-001-detail',
      'community.guild',
      UiReadMode.normal,
      variant: 'guild-pending',
    ),
  );
  result.add(
    const _Scene(
      'SC-001',
      'community.home',
      UiReadMode.normal,
      variant: 'guild-authority-unknown',
    ),
  );
  for (final value in [
    'ticket-closed',
    'ticket-resolved',
    'ticket-waitingUser',
  ]) {
    result.add(
      _Scene('US-010', 'social.ticket', UiReadMode.normal, variant: value),
    );
  }
  return result;
}

void main() {
  setUpAll(loadGoldenFonts);
  final scenes = _scenes();
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
  for (final scene in scenes) {
    if (_only.isNotEmpty &&
        !_only.split(',').any((part) => scene.id.startsWith(part)))
      continue;
    for (final variant in variants) {
      testWidgets('state ${scene.id} ${variant.$1} scale=${variant.$2}', (
        tester,
      ) async {
        final probe = UiReadProbe(
          scene.target,
          scene.mode,
          variant: scene.variant,
          role: scene.role,
        );
        late UiScenarioScope scope;
        final manifestId = scene.page.substring(0, 6);
        expect(appPageManifest.any((page) => page.id == manifestId), isTrue);
        await renderDazidaoScenario(
          tester,
          id: scene.id,
          size: variant.$1,
          scale: variant.$2,
          transformDependencies: (base) => scope = UiScenarioScope(base, probe),
          prepare: (_) => scope.initialize(),
          useProductionHostTheme: true,
          builder: (dependencies) => _page(scene, dependencies),
          exercise: (tester, _) => _verify(tester, scene, probe),
          annotations: {
            'manifestId': manifestId,
            'readTarget': scene.target,
            'state': scene.mode.name,
            'variant': scene.variant,
            'role': scene.role,
            'readCalls': probe.reads,
            'evidenceType': 'SYNTHETIC_PRODUCTION_WIDGET',
            'deviceValidated': false,
          },
        );
        expect(
          probe.writes,
          isEmpty,
          reason: 'No consumer or governance writes in visual capture',
        );
      });
    }
  }
}

Widget _page(_Scene scene, AppDependencies dependencies) {
  if (scene.page == 'DS-001' || scene.page == 'US-001')
    return MainShell(dependencies: dependencies, onSignOut: () async {});
  if (scene.page == 'DS-002')
    return GlobalSearchPage(repository: dependencies.discoveryRepository);
  if (scene.page == 'US-009-history') return const SupportTicketHistoryPage();
  if (scene.page == 'SC-001-detail')
    return const GuildDetailPage(guildId: 'guild-1');
  if (scene.page == 'CM-009') return const GiftCatalogPage();
  if (scene.page == 'RM-003') return const RoomDeepLinkPage(input: '880217');
  if (scene.page == 'CM-004') {
    final state = RechargeOrderState.values.singleWhere(
      (value) => scene.variant == 'payment-${value.name}',
    );
    return PaymentResultPage(
      order: RechargeOrder(
        orderNo: 'synthetic-read-only-order',
        account: '13800138000',
        product: qaRechargeProduct,
        channel: PaymentChannelType.alipay,
        state: state,
        createdAt: qaReferenceTime,
        message: '',
      ),
    );
  }
  final entry = qaPageCatalog.singleWhere((entry) => entry.id == scene.page);
  return entry.builder(
    dependencies,
    const QaScenario(
      role: QaRole.registeredUser,
      state: QaPageState.normal,
      mockScenario: QaMockScenario.defaultData,
      network: QaNetworkScenario.normal,
    ),
  );
}

Future<void> _verify(
  WidgetTester tester,
  _Scene scene,
  UiReadProbe probe,
) async {
  if (scene.page == 'US-001') {
    await tester.tap(find.text('我的').last);
    await _wait(tester, () => probe.intercepted > 0);
  }
  final terminalPayment =
      scene.page == 'CM-004' &&
      ['payment-failed', 'payment-canceled'].contains(scene.variant);
  if (!terminalPayment) await _wait(tester, () => probe.intercepted > 0);
  expect(
    probe.intercepted,
    terminalPayment ? 0 : greaterThan(0),
    reason: 'Requested state must flow through the actual page read',
  );
  if (scene.mode == UiReadMode.error &&
      scene.target != 'discovery.suggestions') {
    final errorLabel = switch (scene.page) {
      'RM-006' => '成员列表加载失败',
      'RM-001' => '名下房间加载失败，请重试',
      _ => uiReadFailure,
    };
    await _wait(
      tester,
      () => find.textContaining(errorLabel).evaluate().isNotEmpty,
    );
    expect(find.textContaining(errorLabel), findsWidgets);
  }
  if (scene.mode == UiReadMode.loading) {
    // Optional/secondary reads retain existing content rather than replace it.
    const retained = {
      'discovery.suggestions',
      'dynamic.comments',
      'social.ticket',
    };
    if (!retained.contains(scene.target)) {
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is CircularProgressIndicator ||
              widget is LinearProgressIndicator,
        ),
        findsWidgets,
        reason: 'Pending authoritative data cannot masquerade as completed',
      );
    }
  }
  if (scene.page == 'RM-006' &&
      (scene.mode == UiReadMode.loading || scene.mode == UiReadMode.error)) {
    expect(find.textContaining('0 人在线'), findsNothing);
    expect(find.text('全部 0'), findsNothing);
  }
  if (scene.variant == 'permission-permanentlyDenied') {
    final controls = find.widgetWithText(TextButton, '打开设置');
    expect(controls, findsWidgets);
    for (final element in controls.evaluate()) {
      expect(
        tester.getSize(find.byWidget(element.widget)).height,
        greaterThanOrEqualTo(44),
      );
    }
  }
  if (scene.variant.startsWith('delivery-')) {
    final status = MessageDeliveryStatus.values.singleWhere(
      (value) => scene.variant == 'delivery-${value.name}',
    );
    final label = switch (status) {
      MessageDeliveryStatus.delivered => '实时已送达',
      MessageDeliveryStatus.failed => '实时投递失败',
      MessageDeliveryStatus.vendorBlocked => '实时不可用',
      MessageDeliveryStatus.unknown => '实时投递未知',
      _ => '实时待送达',
    };
    await _wait(tester, () => find.textContaining(label).evaluate().isNotEmpty);
    expect(find.textContaining(label), findsWidgets);
  }
  if (scene.variant.startsWith('payment-')) {
    final state = RechargeOrderState.values.singleWhere(
      (value) => scene.variant == 'payment-${value.name}',
    );
    expect(find.text(state.label), findsWidgets);
    if (state != RechargeOrderState.succeeded)
      expect(find.text('充值成功'), findsNothing);
  }
  if (scene.variant == 'cancel-blocked') {
    expect(find.text('申请注销'), findsNothing);
    expect(find.text('撤销注销'), findsNothing);
  }
  if (scene.variant.startsWith('cancel-cooling')) {
    expect(find.text('申请注销'), findsNothing);
    expect(
      find.text('撤销注销'),
      scene.variant.endsWith('open') ? findsOneWidget : findsNothing,
    );
  }
  if (scene.variant == 'youth-locked')
    expect(find.textContaining('青少年模式'), findsWidgets);
  if (scene.page == 'SC-001-detail' && scene.mode == UiReadMode.normal) {
    if (scene.role == 'chair') expect(find.text('退出公会'), findsNothing);
    if (scene.variant == 'guild-closed')
      expect(find.textContaining('公会已关闭'), findsWidgets);
  }
  expect(tester.takeException(), isNull);
}

Future<void> _wait(WidgetTester tester, bool Function() ready) async {
  for (var attempt = 0; attempt < 120; attempt++) {
    if (ready()) {
      await tester.pump(const Duration(milliseconds: 80));
      return;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 3)),
    );
    await tester.pump(const Duration(milliseconds: 25));
    expect(
      tester.takeException(),
      isNull,
      reason: 'Fixture/render errors are not business RED',
    );
  }
  expect(ready(), isTrue, reason: 'Actual page readiness barrier timed out');
}
