import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/debug/qa_console/qa_fixtures.dart';
import 'package:voice_social_app/debug/qa_console/qa_models.dart';
import 'package:voice_social_app/debug/qa_console/qa_page_catalog.dart';

void main() {
  for (final title in ['收到的邀请', '选择对手', 'PK 时长', '最近对战']) {
    testWidgets('RM013 $title renders using the room subtree theme', (
      tester,
    ) async {
      await _pumpPage(tester, 'RM-013');
      final text = find.text(title);
      await tester.scrollUntilVisible(
        text,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      _expectDarkParagraph(
        tester,
        text,
        primary: true,
        medium: title == 'PK 时长',
      );
      await _close(tester);
    });
  }

  for (final primary in [true, false]) {
    testWidgets(
      'DS001 hero ${primary ? 'title' : 'relationship'} uses its internal dark theme',
      (tester) async {
        await _pumpPage(tester, 'DS-001');
        final text = primary
            ? find.text('深夜温柔陪伴').first
            : find.text('你关注的晚星正在房间里');
        _expectDarkParagraph(tester, text, primary: primary);
        await _close(tester);
      },
    );
  }
}

void _expectDarkParagraph(
  WidgetTester tester,
  Finder text, {
  required bool primary,
  bool medium = false,
}) {
  expect(text, findsOneWidget);
  final theme = Theme.of(tester.element(text));
  expect(theme.brightness, Brightness.dark);
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: text, matching: find.byType(RichText)),
  );
  final expectedStyle = primary
      ? (medium ? theme.textTheme.titleMedium : theme.textTheme.titleLarge)
      : theme.textTheme.bodySmall;
  expect(paragraph.text.style!.color, expectedStyle!.color);
  expect(
    paragraph.text.style!.color,
    primary ? RoomColors.textPrimary : RoomColors.textSecondary,
  );
}

Future<void> _pumpPage(WidgetTester tester, String id) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final dependencies = await createQaDependencies();
  addTearDown(dependencies.dispose);
  const scenario = QaScenario(
    role: QaRole.registeredUser,
    state: QaPageState.normal,
    mockScenario: QaMockScenario.defaultData,
    network: QaNetworkScenario.normal,
  );
  await tester.pumpWidget(
    AppDependencyScope(
      dependencies: dependencies,
      child: MaterialApp(
        theme: AppTheme.social(),
        home: qaPageCatalog
            .singleWhere((entry) => entry.id == id)
            .builder(dependencies, scenario),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}
