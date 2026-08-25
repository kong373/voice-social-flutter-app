import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/discovery/data/mock_discovery_repository.dart';
import 'package:voice_social_app/features/discovery/domain/discovery_models.dart';
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

  testWidgets('runtime search renders first-party reviewed suggestions', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.social(),
        home: GlobalSearchPage(repository: MockDiscoveryRepository()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('你可能想找'), findsOneWidget);
    expect(find.text('深夜陪伴'), findsOneWidget);
    expect(find.text('音乐点唱'), findsOneWidget);
  });

  testWidgets('suggestion failure is non-blocking and offers retry', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.social(),
        home: GlobalSearchPage(repository: _FailingDiscoveryRepository()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('搜索建议暂时不可用'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.text('搜索范围'), findsOneWidget);
  });
}

class _FailingDiscoveryRepository extends MockDiscoveryRepository {
  @override
  Future<List<DiscoverySearchSuggestion>> fetchSearchSuggestions({
    int limit = 10,
  }) {
    throw const ApiException(
      kind: ApiFailureKind.network,
      message: '搜索建议暂时不可用',
    );
  }
}
