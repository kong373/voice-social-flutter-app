import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/features/room/presentation/gift_sheet.dart';
import 'package:voice_social_app/features/room/presentation/video_runtime_room_page.dart';
import 'package:voice_social_app/features/shell/main_shell.dart';

void main() {
  test('video runtime uses separate light lobby and immersive room themes', () {
    expect(AppTheme.social().brightness, Brightness.light);
    expect(AppTheme.room().brightness, Brightness.dark);
    expect(
      AppTheme.social().bottomNavigationBarTheme.type,
      BottomNavigationBarType.fixed,
    );
  });

  testWidgets('home enters room, opens gift sheet and minimizes the session', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final AppDependencies dependencies = AppDependencies.mock();
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

    expect(find.byKey(const Key('video-runtime-home')), findsOneWidget);
    expect(find.text('首页'), findsOneWidget);
    expect(find.text('发现'), findsOneWidget);
    expect(find.text('消息'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);

    final Finder roomCard = find.byKey(const Key('live-room-880217'));
    expect(roomCard, findsOneWidget);
    await tester.tap(roomCard);
    await tester.pumpAndSettle();

    expect(find.byType(VideoRuntimeRoomPage), findsOneWidget);
    expect(find.text('礼物'), findsOneWidget);
    expect(find.text('成员'), findsOneWidget);
    expect(find.byKey(const Key('video-room-composer')), findsOneWidget);

    await tester.tap(find.text('礼物').hitTestable());
    await tester.pumpAndSettle();
    expect(find.byType(GiftSheet), findsOneWidget);
    Navigator.of(tester.element(find.byType(GiftSheet))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('离开房间').hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('收起房间'), findsOneWidget);
    await tester.tap(find.text('收起房间').hitTestable());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('minimized-room-pill')), findsOneWidget);
    await tester.tap(find.byKey(const Key('minimized-room-pill')));
    await tester.pumpAndSettle();
    expect(find.byType(VideoRuntimeRoomPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('light lobby remains stable at 360x800 and 1.3 text scale', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(864, 1920);
    tester.view.devicePixelRatio = 2.4;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final AppDependencies dependencies = AppDependencies.mock();
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
        child: AppDependencyScope(
          dependencies: dependencies,
          child: MaterialApp(
            theme: AppTheme.social(),
            home: MainShell(dependencies: dependencies, onSignOut: () async {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('video-runtime-home')), findsOneWidget);
    expect(find.text('正在发生'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
