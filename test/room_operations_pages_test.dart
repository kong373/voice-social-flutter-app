import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/presentation/room_audio_page.dart';
import 'package:voice_social_app/features/room/presentation/room_members_page.dart';
import 'package:voice_social_app/features/room/presentation/room_topic_page.dart';

void main() {
  testWidgets('RM-006 member filters retain on-mic and listener context', (
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
          home: const RoomMembersPage(
            roomId: '9527',
            currentUserId: 10001,
            currentRole: RoomRole.listener,
            seats: <MicSeat>[
              MicSeat(
                number: 1,
                backendIndex: 1,
                state: MicSeatState.occupied,
                userId: 20001,
                userName: '房主 · 鹿屿',
                userRole: RoomRole.owner,
              ),
              MicSeat(
                number: 2,
                backendIndex: 2,
                state: MicSeatState.occupiedMuted,
                userId: 20002,
                userName: '南风',
                userRole: RoomRole.speaker,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('在线成员与听众席'), findsOneWidget);
    expect(find.textContaining('麦上'), findsWidgets);
    expect(find.text('房主 · 鹿屿'), findsOneWidget);

    await tester.tap(find.byType(ChoiceChip).at(2));
    await tester.pumpAndSettle();
    expect(find.text('阿岚'), findsOneWidget);
    expect(find.text('房主 · 鹿屿'), findsNothing);
  });

  testWidgets('RM-008 persists the authoritative topic before closing', (
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
          home: Builder(
            builder: (BuildContext context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (BuildContext context) =>
                          const RoomTopicPage(roomId: '9527', canEdit: true),
                    ),
                  ),
                  child: const Text('打开公告'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开公告'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, '公告标题'),
      '今晚只聊轻松的事',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, '公告内容'),
      '尊重彼此，不讨论隐私。',
    );
    await tester.tap(find.text('保存公告'));
    await tester.pumpAndSettle();
    expect(find.byType(RoomTopicPage), findsNothing);
  });

  testWidgets('RM-010 exposes only available audio routes', (
    WidgetTester tester,
  ) async {
    final AppDependencies dependencies = AppDependencies.mock();
    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: dependencies,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const RoomAudioPage(isOnMic: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('扬声器'), findsOneWidget);
    expect(find.text('蓝牙设备'), findsOneWidget);
    expect(find.text('有线耳机'), findsOneWidget);
    final ListTile wired = tester.widget<ListTile>(
      find.widgetWithText(ListTile, '有线耳机'),
    );
    expect(wired.enabled, isFalse);
  });
}
