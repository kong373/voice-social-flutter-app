import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/core/storage/key_value_store.dart';
import 'package:voice_social_app/features/account/application/auth_controller.dart';
import 'package:voice_social_app/features/account/data/auth_session_manager.dart';
import 'package:voice_social_app/features/account/data/device_identity_provider.dart';
import 'package:voice_social_app/features/account/data/mock_auth_repository.dart';
import 'package:voice_social_app/features/account/domain/auth_models.dart';
import 'package:voice_social_app/features/account/presentation/preset_avatar_view.dart';
import 'package:voice_social_app/features/account/presentation/registration_page.dart';

void main() {
  testWidgets('registration starts without a selected sex or avatar', (
    tester,
  ) async {
    final controller = _Controller();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(home: RegistrationPage(controller: controller)),
    );
    expect(
      tester
          .widget<SegmentedButton<int>>(find.byType(SegmentedButton<int>))
          .selected,
      isEmpty,
    );
    expect(find.byType(PresetAvatarPicker), findsOneWidget);
    expect(
      tester
          .widget<PresetAvatarPicker>(find.byType(PresetAvatarPicker))
          .selectedId,
      isNull,
    );
    expect(find.textContaining('生日'), findsNothing);
    expect(find.textContaining('18 岁'), findsNothing);
  });

  testWidgets('nickname alone cannot register and invite removal is explicit', (
    tester,
  ) async {
    final controller = _Controller();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(home: RegistrationPage(controller: controller)),
    );
    await tester.enterText(find.widgetWithText(TextFormField, '昵称'), '朋友');
    await tester.tap(find.text('完成注册'));
    await tester.pump();
    expect(controller.submissions, isEmpty);
    expect(find.text('请选择头像和性别'), findsOneWidget);
  });
  testWidgets('explicit preset and sex zero register without birthday', (
    tester,
  ) async {
    final controller = _Controller();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(home: RegistrationPage(controller: controller)),
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('preset-avatar-option:avatar-preset-sea')),
    );
    await tester.tap(
      find.byKey(const ValueKey('preset-avatar-option:avatar-preset-sea')),
    );
    await tester.enterText(find.widgetWithText(TextFormField, '昵称'), '鲸');
    await tester.ensureVisible(find.text('不公开'));
    await tester.tap(find.text('不公开'));
    await tester.ensureVisible(find.widgetWithText(TextFormField, '邀请码（选填）'));
    await tester.enterText(
      find.widgetWithText(TextFormField, '邀请码（选填）'),
      'BAD-INVITE',
    );
    await tester.tap(find.text('完成注册'));
    await tester.pump();
    final first = controller.submissions.single;
    expect(first.nickname, '鲸');
    expect(first.sex, 0);
    expect(first.avatar?.reference, 'avatar-preset-sea');
    expect(first.birthday, isNull);
    expect(first.inviteCode, 'BAD-INVITE');
    expect(
      tester
          .widget<TextFormField>(find.widgetWithText(TextFormField, '邀请码（选填）'))
          .controller!
          .text,
      'BAD-INVITE',
    );
    await tester.ensureVisible(find.byTooltip('移除邀请码'));
    await tester.tap(find.byTooltip('移除邀请码'));
    await tester.pump();
    await tester.tap(find.text('完成注册'));
    await tester.pump();
    expect(controller.submissions.last.inviteCode, isEmpty);
    expect(controller.submissions.last.avatar?.reference, 'avatar-preset-sea');
  });
}

class _Controller extends AuthController {
  factory _Controller() {
    final manager = AuthSessionManager(MemoryKeyValueStore());
    return _Controller._(manager);
  }
  _Controller._(AuthSessionManager manager)
    : super(
        repository: const MockAuthRepository(),
        sessionManager: manager,
        deviceIdentityProvider: DeviceIdentityProvider(
          environment: AppEnvironment.mock(),
          sessionManager: manager,
        ),
      );
  final submissions = <RegistrationProfile>[];
  @override
  Future<bool> completeRegistration(RegistrationProfile profile) async {
    submissions.add(profile);
    return false;
  }
}
