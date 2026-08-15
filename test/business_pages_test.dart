import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/features/discovery/presentation/global_search_page.dart';
import 'package:voice_social_app/features/discovery/presentation/saved_rooms_page.dart';
import 'package:voice_social_app/features/discovery/presentation/search_results_page.dart';
import 'package:voice_social_app/features/room/presentation/create_room_page.dart';
import 'package:voice_social_app/features/room/presentation/room_deep_link_page.dart';

void main() {
  testWidgets('DS-003 renders room and user search results', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final AppDependencies dependencies = AppDependencies.mock();

    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: dependencies,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const SearchResultsPage(keyword: '深夜'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('房间'), findsWidgets);
    expect(find.text('深夜温柔陪伴'), findsOneWidget);
  });

  testWidgets('DS-008 separates favorites and owned rooms', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final AppDependencies dependencies = AppDependencies.mock();

    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: dependencies,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const SavedRoomsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('深夜温柔陪伴'), findsOneWidget);
    await tester.tap(find.text('我的房间'));
    await tester.pumpAndSettle();
    expect(find.text('周末松弛聊天局'), findsOneWidget);
    expect(find.text('管理'), findsOneWidget);
  });

  testWidgets('RM-001 preserves invalid form input and shows validation', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final AppDependencies dependencies = AppDependencies.mock();

    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: dependencies,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const CreateRoomPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final Finder titleField = find.widgetWithText(TextFormField, '房间名称');
    await tester.enterText(titleField, '');
    await tester.tap(find.text('保存并进入房间'));
    await tester.pump();
    expect(find.text('请输入房间名称'), findsOneWidget);
  });

  testWidgets('RM-003 shows recovery only for invalid targets', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final AppDependencies dependencies = AppDependencies.mock();

    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: dependencies,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const RoomDeepLinkPage(input: 'not-a-room'),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 180));
    await tester.pumpAndSettle();

    expect(find.text('房间链接无效'), findsOneWidget);
    expect(find.text('重新校验'), findsOneWidget);
  });

  testWidgets('DS-002 exposes direct room validation for numeric input', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.dark(), home: const GlobalSearchPage()),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '880217');
    await tester.pump();

    expect(find.text('直达房间 880217'), findsOneWidget);
  });
}
