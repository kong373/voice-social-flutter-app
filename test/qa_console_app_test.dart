import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/debug/qa_console/qa_gate.dart';

void main() {
  test('live mode rejects the QA console even in a debug QA build', () {
    expect(
      shouldUseQaConsole(isLive: true, requested: true, isDebug: true),
      isFalse,
    );
    expect(
      shouldUseQaConsole(isLive: false, requested: true, isDebug: true),
      isTrue,
    );
  });

  test('live mode rejects the unauthenticated runtime demo shell', () {
    expect(
      shouldUseVideoRuntimeDemo(isLive: true, requested: true, isDebug: true),
      isFalse,
    );
    expect(
      shouldUseVideoRuntimeDemo(isLive: false, requested: true, isDebug: true),
      isTrue,
    );
  });

  testWidgets('application root obeys the hardened QA console gate', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      VoiceSocialApp(dependencies: AppDependencies.mock()),
    );
    await tester.pumpAndSettle();

    if (qaConsoleEnabled) {
      expect(find.text('M2.4 QA Console'), findsOneWidget);
      expect(find.text('69 / 69'), findsOneWidget);
      expect(find.textContaining('BackendMode: mock'), findsOneWidget);
      expect(find.text('同意并继续'), findsNothing);

      await tester.tap(find.widgetWithText(FilterChip, 'AC'));
      await tester.pumpAndSettle();
      expect(find.text('12 / 69'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey<String>('qa-page-search')),
        'AC-004',
      );
      await tester.pumpAndSettle();
      expect(find.text('1 / 69'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('qa-entry-AC-004')));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const ValueKey<String>('qa-console-directory')),
        const Offset(0, -360),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('qa-open-AC-004')));
      await tester.pumpAndSettle();
      expect(find.text('第三方账号绑定与分享授权'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('qa-active-scenario-AC-004')),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('一键回到 QA 目录'));
      await tester.pumpAndSettle();
      expect(find.text('M2.4 QA Console'), findsOneWidget);
      expect(find.text('1 / 69'), findsOneWidget);

      await tester.tap(find.byTooltip('重置 Mock 数据'));
      await tester.pumpAndSettle();
      expect(find.text('M2.4 QA Console'), findsOneWidget);
      expect(find.byTooltip('重置 Mock 数据'), findsOneWidget);
    } else {
      expect(find.text('M2.4 QA Console'), findsNothing);
      expect(find.text('同意并继续'), findsOneWidget);
    }
  });

  testWidgets('live application never routes into the Mock QA console', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const AppEnvironment liveEnvironment = AppEnvironment(
      backendMode: BackendMode.live,
      apiBaseUrl: 'https://example.invalid',
      clientType: 'Android',
      clientInnerVersion: '6',
      oauthClientId: 'public-client',
      realtimeEndpoint: '',
      deploymentEnvironment: DeploymentEnvironment.development,
    );

    await tester.pumpWidget(
      VoiceSocialApp(
        dependencies: AppDependencies.forTestEnvironment(
          environment: liveEnvironment,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('M2.4 QA Console'), findsNothing);
    expect(find.textContaining('BackendMode: mock'), findsNothing);
  });
}
