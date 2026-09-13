import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/features/room/domain/room_lifecycle_models.dart';
import 'package:voice_social_app/features/room/presentation/room_configuration_form.dart';

void main() {
  testWidgets('live capability flags hide unsupported room settings', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: _buildForm(
              supportsApprovalAccessMode: true,
              supportsTopicTitle: false,
              supportsAutoLockMic: false,
            ),
          ),
        ),
      ),
    );

    expect(find.text('审批房'), findsNothing);
    expect(find.text('话题标题'), findsNothing);
    expect(find.text('进入房间时自动锁定空麦'), findsNothing);
    expect(find.text('当前 development 后端只持久化一条话题内容，话题标题暂不可用。'), findsOneWidget);
    expect(find.text('当前 development 后端暂不支持自动锁麦，已隐藏此设置。'), findsOneWidget);
  });

  testWidgets('legacy approval is unselected and requires owner choice', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: _buildForm(
              accessMode: RoomAccessMode.approval,
              supportsApprovalAccessMode: true,
              supportsTopicTitle: true,
              supportsAutoLockMic: true,
            ),
          ),
        ),
      ),
    );

    expect(find.text('审批房'), findsNothing);
    final segments = tester.widget<SegmentedButton<RoomAccessMode>>(
      find.byType(SegmentedButton<RoomAccessMode>),
    );
    expect(segments.selected, isEmpty);
    expect(segments.segments.map((s) => s.value), [
      RoomAccessMode.publicRoom,
      RoomAccessMode.password,
    ]);
    expect(find.text('原入房审批模式已停用，请房主明确选择公开房或密码房后保存。'), findsOneWidget);
    expect(find.text('话题标题'), findsOneWidget);
    expect(find.text('进入房间时自动锁定空麦'), findsOneWidget);
    expect(find.text('当前 development 后端只持久化一条话题内容，话题标题暂不可用。'), findsNothing);
  });

  testWidgets('room text fields expose the backend text limits', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: _buildForm(
              supportsApprovalAccessMode: true,
              supportsTopicTitle: true,
              supportsAutoLockMic: true,
            ),
          ),
        ),
      ),
    );

    TextField field(String label) => tester.widget<TextField>(
      find.byWidgetPredicate(
        (Widget widget) =>
            widget is TextField && widget.decoration?.labelText == label,
      ),
    );

    expect(field('话题标题').maxLength, 64);
    expect(field('当前话题或房间说明').maxLength, 240);
    expect(field('进房欢迎语').maxLength, 240);
  });
}

Widget _buildForm({
  RoomAccessMode accessMode = RoomAccessMode.publicRoom,
  required bool supportsApprovalAccessMode,
  required bool supportsTopicTitle,
  required bool supportsAutoLockMic,
}) {
  return RoomConfigurationForm(
    formKey: GlobalKey<FormState>(),
    titleController: TextEditingController(text: '测试房间'),
    topicTitleController: TextEditingController(),
    topicContentController: TextEditingController(),
    welcomeController: TextEditingController(),
    passwordController: TextEditingController(),
    allowExistingPassword: false,
    accessMode: accessMode,
    showInHall: true,
    autoLockMic: false,
    supportsApprovalAccessMode: supportsApprovalAccessMode,
    supportsTopicTitle: supportsTopicTitle,
    supportsAutoLockMic: supportsAutoLockMic,
    enabled: true,
    onAccessModeChanged: (_) {},
    onShowInHallChanged: (_) {},
    onAutoLockMicChanged: (_) {},
  );
}
