import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app.dart';
import 'package:voice_social_app/app/app_dependencies.dart';

void main() {
  testWidgets('consent, login, room, gift, and leave flow work', (
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

    expect(find.text('此刻适合你的房间'), findsOneWidget);
    await tester.tap(find.text('进入房间'));
    await tester.pumpAndSettle();

    expect(find.text('深夜温柔陪伴'), findsOneWidget);
    expect(find.text('实时公屏'), findsOneWidget);
    expect(find.text('仅显示进房后的消息'), findsOneWidget);

    await tester.tap(find.text('礼物'));
    await tester.pumpAndSettle();
    expect(find.text('送礼物'), findsOneWidget);
    expect(find.text('普通礼物'), findsOneWidget);
    await tester.tap(find.text('赠送 · 10'));
    await tester.pumpAndSettle();
    expect(find.text('礼物已送出'), findsOneWidget);

    await tester.tap(find.byTooltip('离开房间'));
    await tester.pumpAndSettle();
    expect(find.text('离开房间？'), findsOneWidget);
    await tester.tap(find.text('确认离开'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('此刻适合你的房间'), findsOneWidget);
  });
}
