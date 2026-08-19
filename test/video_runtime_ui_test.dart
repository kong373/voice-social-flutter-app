import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/features/discovery/home_page.dart';
import 'package:voice_social_app/features/room/application/room_controller.dart';
import 'package:voice_social_app/features/room/application/room_session_coordinator.dart';
import 'package:voice_social_app/features/shell/main_shell.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('video-derived design system separates lobby and room themes', () {
    final ThemeData lobby = AppTheme.lobby();
    final ThemeData room = AppTheme.dark();

    expect(lobby.brightness, Brightness.light);
    expect(room.brightness, Brightness.dark);
    expect(lobby.colorScheme.primary, AppColors.primary);
    expect(room.colorScheme.primary, AppColors.primary);
    expect(lobby.scaffoldBackgroundColor, AppColors.lobbyBackground);
    expect(room.scaffoldBackgroundColor, AppColors.background);
  });

  testWidgets('home uses the mixed-density social lobby hierarchy',
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
          theme: AppTheme.lobby(),
          home: const Scaffold(body: HomePage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('video-runtime-home')), findsOneWidget);
    expect(find.text('搜索房间、用户或房间号'), findsOneWidget);
    expect(find.text('收藏与我的房间'), findsOneWidget);
    expect(find.text('创建房间'), findsWidgets);
    expect(find.text('此刻适合你的房间'), findsOneWidget);
    expect(find.text('正在发生'), findsWidgets);
    expect(find.text('进入'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('minimized active room remains visible above the fixed root nav',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final AppDependencies dependencies = AppDependencies.mock();
    final RoomController controller = dependencies.createRoomController(
      roomId: '880217',
      title: '深夜温柔陪伴',
    );
    final RoomSessionCoordinator coordinator = RoomSessionCoordinator.instance;
    coordinator.attach(
      controller: controller,
      roomId: '880217',
      title: '深夜温柔陪伴',
    );
    coordinator.minimize();
    addTearDown(() {
      coordinator.detach(controller);
      controller.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lobby(),
        home: MainShell(
          dependencies: dependencies,
          onSignOut: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('minimized-room-pill')), findsOneWidget);
    expect(find.text('房间仍在继续 · 点击恢复'), findsOneWidget);
    expect(find.text('首页'), findsOneWidget);
    expect(find.text('发现'), findsOneWidget);
    expect(find.text('消息'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
