import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/features/discovery/data/mock_discovery_repository.dart';
import 'package:voice_social_app/features/discovery/dynamic/data/mock_dynamic_repository.dart';
import 'package:voice_social_app/features/discovery/dynamic/presentation/dynamic_pages.dart';
import 'package:voice_social_app/features/message/data/mock_message_repository.dart';
import 'package:voice_social_app/features/shell/main_shell.dart';
import 'package:voice_social_app/features/shell/video_runtime_pages.dart';

void main() {
  testWidgets(
    'live MainShell discovery keeps publish above unobstructed tabs',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final AppDependencies dependencies = AppDependencies.forTestEnvironment(
        environment: const AppEnvironment(
          backendMode: BackendMode.live,
          apiBaseUrl: 'https://example.invalid',
          clientType: 'Android',
          clientInnerVersion: '1',
          oauthClientId: 'public-client',
          realtimeEndpoint: '',
          deploymentEnvironment: DeploymentEnvironment.development,
        ),
        discoveryRepository: MockDiscoveryRepository(),
        dynamicRepository: MockDynamicRepository(),
        messageRepository: MockMessageRepository(),
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
      await tester.pumpAndSettle();

      await tester.tap(find.text('发现').last.hitTestable());
      await tester.pumpAndSettle();
      expect(find.byType(DiscoveryFeedPage), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);

      await tester.tap(find.byTooltip('发布动态'));
      await tester.pumpAndSettle();
      expect(find.byType(PublishDynamicPage), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.text('我的').last.hitTestable());
      await tester.pumpAndSettle();
      expect(find.byType(DiscoveryFeedPage), findsNothing);
      expect(find.byType(VideoRuntimeAccountPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('standalone DiscoveryFeedPage retains its floating publisher', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.social(),
        home: DiscoveryFeedPage(repository: MockDynamicRepository()),
      ),
    );
    await tester.pumpAndSettle();

    final Finder publisher = find.byType(FloatingActionButton);
    expect(publisher, findsOneWidget);
    await tester.tap(publisher);
    await tester.pumpAndSettle();
    expect(find.byType(PublishDynamicPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
