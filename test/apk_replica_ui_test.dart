import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/design_system/replica_components.dart';
import 'package:voice_social_app/features/discovery/home_page.dart';

void main() {
  test('replica theme keeps the approved dark social palette', () {
    final ThemeData theme = AppTheme.dark();
    expect(theme.brightness, Brightness.dark);
    expect(theme.colorScheme.primary, AppColors.primary);
    expect(theme.colorScheme.secondary, AppColors.secondary);
    expect(theme.scaffoldBackgroundColor, Colors.transparent);
    expect(theme.bottomNavigationBarTheme.type, BottomNavigationBarType.fixed);
    expect(theme.extensions[ReplicaThemeData], isNotNull);
  });

  testWidgets('home renders the APK-inspired room discovery hierarchy',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final AppDependencies dependencies = AppDependencies.mock();
    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: dependencies,
        child: MaterialApp(
          theme: AppTheme.dark(),
          builder: (BuildContext context, Widget? child) => ReplicaAppBackdrop(
            child: child ?? const SizedBox.shrink(),
          ),
          home: const Scaffold(body: HomePage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('apk-replica-home')), findsOneWidget);
    expect(find.text('搜索房间、用户或房间号'), findsOneWidget);
    expect(find.text('收藏与房间'), findsOneWidget);
    expect(find.text('创建房间'), findsWidgets);
    expect(find.text('此刻适合你的房间'), findsOneWidget);
    expect(find.text('正在发生'), findsWidgets);
    expect(find.text('进入'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('room artwork and panels remain stable on compact viewport',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(864, 1920);
    tester.view.devicePixelRatio = 2.4;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const ReplicaAppBackdrop(
          child: Scaffold(
            body: SafeArea(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: ReplicaPanel(
                  child: ReplicaRoomArtwork(
                    seed: 'compact-room',
                    height: 180,
                    child: Align(
                      alignment: Alignment.bottomLeft,
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: ReplicaPill(
                          label: '正在热聊',
                          icon: Icons.graphic_eq_rounded,
                          active: true,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('正在热聊'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
