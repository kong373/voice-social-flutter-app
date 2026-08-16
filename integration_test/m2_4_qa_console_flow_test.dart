import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:voice_social_app/app/app.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/features/account/presentation/third_party_authorization_page.dart';

import 'm2_4_test_support.dart';

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'QA Console search, filter, real-page open, back, and reset stay stable',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        VoiceSocialApp(dependencies: AppDependencies.mock()),
      );
      await tester.pumpAndSettle();

      expect(find.text('M2.4 QA Console'), findsOneWidget);
      expect(find.text('69 / 69'), findsOneWidget);
      expect(find.textContaining('BackendMode: mock'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilterChip, 'AC'));
      await tester.pumpAndSettle();
      expect(find.text('12 / 69'), findsOneWidget);

      final Finder search = find.byKey(
        const ValueKey<String>('qa-page-search'),
      );
      await tester.tap(search);
      await tester.enterText(search, 'AC-004');
      await tester.pumpAndSettle();
      expect(find.text('1 / 69'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('qa-entry-AC-004')));
      await tester.pumpAndSettle();
      FocusManager.instance.primaryFocus?.unfocus();
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      final Finder openPage = find.byKey(
        const ValueKey<String>('qa-open-AC-004'),
      );
      await tester.ensureVisible(openPage);
      await tester.pumpAndSettle();
      await tester.tap(openPage);
      await tester.pumpAndSettle();
      expect(find.byType(ThirdPartyAuthorizationPage), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('qa-active-scenario-AC-004')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await captureQaScreenshot(
        tester,
        binding,
        'P1-M24-EMU-001-qa-real-page-AC-004-$qaAvdId',
      );

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('M2.4 QA Console'), findsOneWidget);
      expect(find.text('1 / 69'), findsOneWidget);

      await tester.tap(find.byTooltip('重置 Mock 数据'));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('M2.4 QA Console'), findsOneWidget);
      expect(find.byTooltip('重置 Mock 数据'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await captureQaScreenshot(
        tester,
        binding,
        'P1-M24-EMU-008-qa-console-reset-$qaAvdId',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
