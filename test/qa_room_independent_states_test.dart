import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/debug/qa_console/qa_fixtures.dart';
import 'package:voice_social_app/debug/qa_console/qa_models.dart';
import 'package:voice_social_app/debug/qa_console/qa_page_catalog.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/presentation/room_configuration_form.dart';
import 'package:voice_social_app/features/room/presentation/video_runtime_room_page.dart';

// Independent states of existing pages, not additional page-catalog entries.
// These behavior checks do not generate or update golden PNGs.
void main() {
  testWidgets('RM001 owned room title renders with its dark subtree color', (
    tester,
  ) async {
    await _pumpPage(tester, 'RM-001');
    final title = find.descendant(
      of: find.byKey(const ValueKey('owned-room-952700')),
      matching: find.text('周末松弛聊天局'),
    );
    final theme = Theme.of(tester.element(title));
    expect(theme.brightness, Brightness.dark);
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: title, matching: find.byType(RichText)),
    );
    expect(paragraph.text.style!.color, theme.textTheme.titleMedium!.color);
    expect(paragraph.text.style!.color, RoomColors.textPrimary);
    await _close(tester);
  });

  testWidgets(
    'RM001 create-form state opens through authorized new-room entry',
    (tester) async {
      await _pumpPage(tester, 'RM-001');
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '创建新房间'))
            .onPressed,
        isNotNull,
      );
      expect(find.byType(RoomConfigurationForm), findsNothing);
      await tester.tap(find.text('创建新房间'));
      await tester.pumpAndSettle();
      expect(find.byType(RoomConfigurationForm), findsOneWidget);
      expect(find.text('房间名称'), findsOneWidget);
      expect(find.text('创建并进入房间'), findsOneWidget);
      expect(find.byType(VideoRuntimeRoomPage), findsNothing);
      expect(tester.takeException(), isNull);
      await _close(tester);
    },
  );

  testWidgets('RM005 listener approval-picker state opens without submitting', (
    tester,
  ) async {
    await _pumpPage(tester, 'RM-005');
    final controller = tester
        .widget<VideoRuntimeRoomPage>(find.byType(VideoRuntimeRoomPage))
        .controller;
    expect(controller.role, RoomRole.listener);
    expect(controller.isOnMic, isFalse);
    expect(controller.micRequests, isEmpty);
    await tester.tap(find.text('上麦'));
    await tester.pumpAndSettle();
    expect(find.text('审批上麦'), findsOneWidget);
    expect(find.text('选择一个空麦位提交申请'), findsOneWidget);
    expect(find.byKey(const Key('approval-mic-seat-1')), findsNothing);
    expect(find.byKey(const Key('approval-mic-seat-4')), findsOneWidget);
    expect(find.byKey(const Key('approval-mic-seat-9')), findsOneWidget);
    expect(controller.isOnMic, isFalse);
    expect(controller.micRequests, isEmpty);
    expect(tester.takeException(), isNull);
    await _close(tester);
  });
}

Future<AppDependencies> _pumpPage(WidgetTester tester, String pageId) async {
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
  final entry = qaPageCatalog.singleWhere((entry) => entry.id == pageId);
  await tester.pumpWidget(
    AppDependencyScope(
      dependencies: dependencies,
      child: MaterialApp(
        theme: AppTheme.social(),
        home: entry.builder(dependencies, scenario),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return dependencies;
}

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}
