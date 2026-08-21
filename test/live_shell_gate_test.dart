import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/features/shell/live_read_only_pages.dart';
import 'package:voice_social_app/features/shell/main_shell.dart';
import 'package:voice_social_app/features/shell/video_runtime_pages.dart';

void main() {
  const AppEnvironment liveTestEnvironment = AppEnvironment(
    backendMode: BackendMode.live,
    apiBaseUrl: 'https://example.invalid',
    clientType: 'Android',
    clientInnerVersion: '1',
    oauthClientId: 'public-client',
    realtimeEndpoint: 'wss://example.invalid/realtime',
    deploymentEnvironment: DeploymentEnvironment.development,
  );

  Future<AppDependencies> pumpLiveShell(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final AppDependencies dependencies = AppDependencies.forTestEnvironment(
      environment: liveTestEnvironment,
    );
    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: dependencies,
        child: MaterialApp(
          theme: AppTheme.social(),
          home: MainShell(dependencies: dependencies, onSignOut: () async {}),
        ),
      ),
    );
    await tester.pump();
    return dependencies;
  }

  Future<AppDependencies> pumpLivePage(
    WidgetTester tester,
    Widget Function(AppDependencies dependencies) childBuilder,
  ) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final AppDependencies dependencies = AppDependencies.forTestEnvironment(
      environment: liveTestEnvironment,
    );
    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: dependencies,
        child: MaterialApp(
          theme: AppTheme.social(),
          home: Scaffold(body: childBuilder(dependencies)),
        ),
      ),
    );
    await tester.pump();
    return dependencies;
  }

  testWidgets('live main shell keeps read-only roots on every tab', (
    WidgetTester tester,
  ) async {
    final AppDependencies dependencies = await pumpLiveShell(tester);

    expect(dependencies.environment.isLive, isTrue);
    expect(find.byType(LiveProductHomePage), findsOneWidget);
    expect(find.byType(VideoRuntimeHomePage), findsNothing);

    await tester.tap(find.text('发现').hitTestable());
    await tester.pump();
    expect(find.byType(LiveDiscoveryHoldingPage), findsOneWidget);
    expect(find.byType(VideoRuntimeDiscoveryPage), findsNothing);

    await tester.tap(find.text('消息').hitTestable());
    await tester.pump();
    expect(find.byType(LiveMessageHoldingPage), findsOneWidget);
    expect(find.byType(VideoRuntimeMessagesPage), findsNothing);

    await tester.tap(find.text('我的').hitTestable());
    await tester.pump();
    expect(find.byType(LiveReadOnlyAccountPage), findsOneWidget);
    expect(find.byType(VideoRuntimeAccountPage), findsNothing);
  });

  testWidgets('direct runtime pages still honor live read-only boundaries', (
    WidgetTester tester,
  ) async {
    final AppDependencies discoveryDependencies = await pumpLivePage(
      tester,
      (AppDependencies dependencies) =>
          VideoRuntimeDiscoveryPage(dependencies: dependencies),
    );
    expect(discoveryDependencies.environment.isLive, isTrue);
    expect(find.byType(LiveDiscoveryHoldingPage), findsOneWidget);

    final AppDependencies messageDependencies = await pumpLivePage(
      tester,
      (AppDependencies dependencies) =>
          VideoRuntimeMessagesPage(dependencies: dependencies),
    );
    expect(messageDependencies.environment.isLive, isTrue);
    expect(find.byType(LiveMessageHoldingPage), findsOneWidget);

    final AppDependencies accountDependencies = await pumpLivePage(
      tester,
      (AppDependencies dependencies) => VideoRuntimeAccountPage(
        dependencies: dependencies,
        onOpenRoom: (_) {},
        onSignOut: () async {},
      ),
    );
    expect(accountDependencies.environment.isLive, isTrue);
    expect(find.byType(LiveReadOnlyAccountPage), findsOneWidget);
  });
}
