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

    expect(find.text('审批房'), findsOneWidget);
    expect(find.text('话题标题'), findsNothing);
    expect(find.text('进入房间时自动锁定空麦'), findsNothing);
    expect(find.text('当前 development 后端只持久化一条话题内容，话题标题暂不可用。'), findsOneWidget);
    expect(find.text('当前 development 后端暂不支持自动锁麦，已隐藏此设置。'), findsOneWidget);
  });

  testWidgets('mock capability flags keep approval and optional settings', (
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

    expect(find.text('审批房'), findsOneWidget);
    expect(find.text('话题标题'), findsOneWidget);
    expect(find.text('进入房间时自动锁定空麦'), findsOneWidget);
    expect(find.text('当前 development 后端只持久化一条话题内容，话题标题暂不可用。'), findsNothing);
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
