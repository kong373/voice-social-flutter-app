import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/features/room/presentation/video_runtime_room_page.dart';

void main() {
  testWidgets('consent, login, room, gift, minimize, restore, and leave work', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final AppDependencies dependencies = AppDependencies.mock();
    await tester.pumpWidget(VoiceSocialApp(dependencies: dependencies));
    await tester.pumpAndSettle();

    expect(find.text('欢迎使用'), findsOneWidget);
    await tester.tap(find.text('同意并继续'));
    await tester.pumpAndSettle();

    expect(find.text('手机号登录'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, '手机号码'),
      '13800138000',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, '短信验证码'),
      '123456',
    );
    await tester.tap(find.text('登录 / 注册'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('video-runtime-home')), findsOneWidget);
    expect(find.text('正在发生'), findsOneWidget);
    await tester.tap(find.byKey(const Key('live-room-880217')));
    await tester.pumpAndSettle();

    expect(find.byType(VideoRuntimeRoomPage), findsOneWidget);
    expect(find.byKey(const Key('video-room-composer')), findsOneWidget);
    expect(find.text('礼物'), findsOneWidget);
    expect(find.text('成员'), findsOneWidget);

    await tester.tap(find.text('礼物').hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('送礼物'), findsOneWidget);
    expect(find.text('普通礼物'), findsOneWidget);
    await tester.tap(find.text('赠送 · 10').hitTestable());
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('gift-celebration-overlay')), findsOneWidget);

    await tester.tap(find.byTooltip('离开房间').hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('收起房间'), findsOneWidget);
    await tester.tap(find.text('收起房间').hitTestable());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('video-runtime-home')), findsOneWidget);
    expect(find.byKey(const Key('minimized-room-pill')), findsOneWidget);

    await tester.tap(find.byKey(const Key('minimized-room-pill')));
    await tester.pumpAndSettle();
    expect(find.byType(VideoRuntimeRoomPage), findsOneWidget);

    await tester.tap(find.byTooltip('离开房间').hitTestable());
    await tester.pumpAndSettle();
    await tester.tap(find.text('离开房间').hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('离开房间？'), findsOneWidget);
    await tester.tap(find.text('确认离开').hitTestable());
    await tester.pumpAndSettle();

    expect(find.byType(VideoRuntimeRoomPage), findsNothing);
    expect(find.byKey(const Key('video-runtime-home')), findsOneWidget);
    expect(find.byKey(const Key('minimized-room-pill')), findsNothing);
    expect(find.text('正在结束房间会话…'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
