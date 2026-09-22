import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_gate.dart';
import 'package:voice_social_app/debug/qa_console/qa_models.dart';
import 'package:voice_social_app/debug/qa_console/qa_page_catalog.dart';
import 'package:voice_social_app/features/account/presentation/consent_page.dart';
import 'package:voice_social_app/features/account/presentation/registration_page.dart';
import 'package:voice_social_app/features/social/presentation/social_pages.dart';
import 'dazidao_ui_render_matrix_test.dart' show renderDazidaoScenario;
import 'support/dazidao_ui_state_authorities.dart';
import 'support/golden_font_gate.dart';

const _matrix = bool.fromEnvironment('UI_MATRIX');
const _only = String.fromEnvironment('UI_CASE');
const _cases = <(String, String)>[
  ('AC-001', 'restore'),
  ('AC-001', 'recovery-error'),
  ('AC-001', 'recovery-busy'),
  ('AC-002', 'agreement-sheet'),
  ('AC-002', 'privacy-sheet'),
  ('AC-002', 'consent-ready'),
  ('AC-003', 'login-validation'),
  ('AC-003', 'registration-validation'),
  ('US-002', 'profile-validation'),
  ('US-003', 'block-confirmation'),
  ('US-008', 'report-validation'),
  ('US-009', 'feedback-disabled'),
  ('DS-006', 'publish-validation'),
  ('DS-007', 'ranking-wealth'),
  ('DS-007', 'ranking-room'),
];
void main() {
  setUpAll(loadGoldenFonts);
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
  for (final item in _cases) {
    final id = '${item.$1}-${item.$2}';
    if (_only.isNotEmpty && !_only.split(',').contains(id)) continue;
    for (final variant in variants) {
      testWidgets('interaction $id ${variant.$1} text=${variant.$2}', (
        tester,
      ) async {
        final probe = UiReadProbe('', UiReadMode.normal);
        late UiScenarioScope scope;
        await renderDazidaoScenario(
          tester,
          id: id,
          size: variant.$1,
          scale: variant.$2,
          transformDependencies: (base) => scope = UiScenarioScope(base, probe),
          prepare: (_) => scope.initialize(),
          useProductionHostTheme: true,
          builder: (dependencies) => _page(item, dependencies, probe),
          exercise: (tester, _) => _exercise(tester, item),
          annotations: {
            'manifestId': item.$1,
            'surface': item.$2,
            'fixture': 'synthetic',
            'writesAllowed': false,
          },
        );
        expect(probe.writes, isEmpty);
      });
    }
  }
}

Widget _page(
  (String, String) item,
  AppDependencies dependencies,
  UiReadProbe probe,
) {
  if (item.$2 == 'restore') return const SessionRestorePage();
  if (item.$2.startsWith('recovery-'))
    return SessionRecoveryPage(
      busy: item.$2.endsWith('busy'),
      message: '网络暂不可用，原会话仍保留。',
      onRetry: () async => probe.forbidWrite('retry-session'),
      onSignOut: () async => probe.forbidWrite('sign-out'),
    );
  if (item.$1 == 'AC-002')
    return ConsentPage(onAccept: () async => probe.forbidWrite('consent'));
  if (item.$2 == 'registration-validation')
    return RegistrationPage(controller: dependencies.authController);
  return qaPageCatalog
      .singleWhere((entry) => entry.id == item.$1)
      .builder(
        dependencies,
        const QaScenario(
          role: QaRole.registeredUser,
          state: QaPageState.normal,
          mockScenario: QaMockScenario.defaultData,
          network: QaNetworkScenario.normal,
        ),
      );
}

Future<void> _exercise(WidgetTester tester, (String, String) item) async {
  switch (item.$2) {
    case 'restore':
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    case 'recovery-error' || 'recovery-busy':
      final retry = find.descendant(
        of: find.byKey(const Key('retry-session-recovery')),
        matching: find.byWidgetPredicate((widget) => widget is FilledButton),
      );
      expect(retry, findsOneWidget);
      expect(
        tester.widget<FilledButton>(retry).onPressed,
        item.$2.endsWith('busy') ? isNull : isNotNull,
      );
    case 'agreement-sheet' || 'privacy-sheet':
      await _tap(
        tester,
        find.byKey(
          Key(
            item.$2 == 'agreement-sheet'
                ? 'consent-user-agreement'
                : 'consent-privacy-policy',
          ),
        ),
      );
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('用户协议与隐私政策正文'), findsWidgets);
    case 'consent-ready':
      await _scroll(tester, find.text('暂不使用'));
      await tester.pumpAndSettle();
      final check = find.byKey(const Key('consent-agreement-checkbox'));
      expect(check, findsOneWidget);
      expect(tester.widget<CheckboxListTile>(check).onChanged, isNotNull);
      await _tap(tester, check);
      expect(tester.widget<CheckboxListTile>(check).value, isTrue);
      final submit = find.ancestor(
        of: find.text('同意并继续'),
        matching: find.byType(FilledButton),
      );
      expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
    case 'login-validation':
      await _tap(tester, find.text('登录 / 注册'));
      expect(find.text('请输入正确的手机号码'), findsOneWidget);
      expect(find.text('请输入 6 位验证码'), findsOneWidget);
    case 'registration-validation':
      await _tap(tester, find.text('完成注册'));
      expect(find.text('请填写 1—24 个字符的昵称'), findsOneWidget);
    case 'profile-validation':
      expect(find.byType(EditProfilePage), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).first, '');
      await _tap(tester, find.text('保存资料'));
      expect(find.text('请输入昵称'), findsOneWidget);
    case 'block-confirmation':
      await _tap(tester, find.byIcon(Icons.block_rounded));
      expect(find.text('加入黑名单？'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
    case 'report-validation':
      await _tap(tester, find.text('提交举报'));
      expect(find.text('请填写举报说明'), findsOneWidget);
    case 'feedback-disabled':
      await _scroll(tester, find.text('提交反馈'));
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '提交反馈'))
            .onPressed,
        isNull,
      );
    case 'publish-validation':
      await _tap(tester, find.text('发布'));
      expect(find.text('请输入动态内容或选择图片'), findsOneWidget);
    case 'ranking-wealth' || 'ranking-room':
      await _tap(tester, find.text(item.$2.endsWith('room') ? '房间榜' : '财富榜'));
      expect(find.text('贡献榜'), findsNothing);
      expect(find.text('魅力榜'), findsOneWidget);
  }
  expect(tester.takeException(), isNull);
}

Future<void> _scroll(WidgetTester tester, Finder target) async {
  if (target.hitTestable().evaluate().isNotEmpty) return;
  await tester.scrollUntilVisible(
    target,
    260,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 30,
  );
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await _scroll(tester, target);
  for (var attempt = 0; attempt < 100; attempt++) {
    if (target.hitTestable().evaluate().length == 1) break;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 3)),
    );
    await tester.pump(const Duration(milliseconds: 30));
  }
  expect(
    target.hitTestable(),
    findsOneWidget,
    reason: 'Actual control must be ready before interaction',
  );
  await tester.tap(target.hitTestable());
  await tester.pumpAndSettle(
    const Duration(milliseconds: 50),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 3),
  );
}
