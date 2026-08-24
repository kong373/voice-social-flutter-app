import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/features/discovery/presentation/global_search_page.dart';

void main() {
  testWidgets('default search does not render unverified suggestions', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.social(), home: const GlobalSearchPage()),
    );
    await tester.pumpAndSettle();

    expect(find.text('你可能想找'), findsNothing);
    expect(find.text('深夜陪伴'), findsNothing);
  });

  testWidgets('QA search fixture renders explicit recent and suggestions', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.social(),
        home: const GlobalSearchPage(
          initialRecent: <String>['深夜陪伴', '880217', '南风'],
          suggestions: <String>['深夜陪伴', '音乐点唱', '轻松闲聊', '新朋友'],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('你可能想找'), findsOneWidget);
    expect(find.text('880217'), findsOneWidget);
    expect(find.text('南风'), findsOneWidget);
    expect(find.text('音乐点唱'), findsOneWidget);
    expect(find.text('轻松闲聊'), findsOneWidget);
    expect(find.text('新朋友'), findsOneWidget);
  });
}
