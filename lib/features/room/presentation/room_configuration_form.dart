import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/features/room/domain/room_lifecycle_models.dart';

class RoomConfigurationForm extends StatelessWidget {
  const RoomConfigurationForm({
    required this.formKey,
    required this.titleController,
    required this.topicTitleController,
    required this.topicContentController,
    required this.welcomeController,
    required this.passwordController,
    required this.accessMode,
    required this.showInHall,
    required this.autoLockMic,
    required this.enabled,
    required this.onAccessModeChanged,
    required this.onShowInHallChanged,
    required this.onAutoLockMicChanged,
    super.key,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController titleController;
  final TextEditingController topicTitleController;
  final TextEditingController topicContentController;
  final TextEditingController welcomeController;
  final TextEditingController passwordController;
  final RoomAccessMode accessMode;
  final bool showInHall;
  final bool autoLockMic;
  final bool enabled;
  final ValueChanged<RoomAccessMode> onAccessModeChanged;
  final ValueChanged<bool> onShowInHallChanged;
  final ValueChanged<bool> onAutoLockMicChanged;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const _SectionTitle(
            title: '房间基础信息',
            description: '普通固定 8 麦房间，一屏只突出创建或保存这一项主任务。',
          ),
          TextFormField(
            controller: titleController,
            enabled: enabled,
            maxLength: 64,
            decoration: const InputDecoration(labelText: '房间名称'),
            validator: (String? value) {
              final String normalized = value?.trim() ?? '';
              if (normalized.isEmpty) {
                return '请输入房间名称';
              }
              if (normalized.length > 64) {
                return '房间名称不能超过 64 个字符';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: topicTitleController,
            enabled: enabled,
            maxLength: 64,
            decoration: const InputDecoration(
              labelText: '话题标题',
              hintText: '例如：今晚话题',
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: topicContentController,
            enabled: enabled,
            minLines: 3,
            maxLines: 5,
            maxLength: 500,
            decoration: const InputDecoration(
              labelText: '当前话题或房间说明',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: welcomeController,
            enabled: enabled,
            minLines: 2,
            maxLines: 4,
            maxLength: 300,
            decoration: const InputDecoration(
              labelText: '进房欢迎语',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 22),
          const _SectionTitle(
            title: '进入方式',
            description: '公开房可直接进入；密码房必须设置 4 位数字密码。',
          ),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<RoomAccessMode>(
              showSelectedIcon: false,
              segments: const <ButtonSegment<RoomAccessMode>>[
                ButtonSegment<RoomAccessMode>(
                  value: RoomAccessMode.publicRoom,
                  icon: Icon(Icons.public_rounded),
                  label: Text('公开房'),
                ),
                ButtonSegment<RoomAccessMode>(
                  value: RoomAccessMode.password,
                  icon: Icon(Icons.lock_outline_rounded),
                  label: Text('密码房'),
                ),
              ],
              selected: <RoomAccessMode>{accessMode},
              onSelectionChanged: enabled
                  ? (Set<RoomAccessMode> value) =>
                        onAccessModeChanged(value.first)
                  : null,
            ),
          ),
          if (accessMode == RoomAccessMode.password) ...<Widget>[
            const SizedBox(height: 12),
            TextFormField(
              controller: passwordController,
              enabled: enabled,
              obscureText: true,
              maxLength: 4,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(4),
              ],
              decoration: const InputDecoration(labelText: '4 位房间密码'),
              validator: (String? value) {
                if (!RegExp(r'^\d{4}$').hasMatch(value ?? '')) {
                  return '请输入 4 位数字密码';
                }
                return null;
              },
            ),
          ],
          const SizedBox(height: 22),
          const _SectionTitle(title: '房间规则', description: '只配置当前已确认的普通语音房能力。'),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: showInHall,
            onChanged: enabled ? onShowInHallChanged : null,
            title: const Text('在首页房间发现中展示'),
            subtitle: const Text('关闭后仍可通过房间号、收藏和分享进入'),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: autoLockMic,
            onChanged: enabled ? onAutoLockMicChanged : null,
            title: const Text('进入房间时自动锁定空麦'),
            subtitle: const Text('房主或房管可在麦位管理中逐一解锁'),
          ),
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: RoomColors.surfaceHigh,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(Icons.info_outline_rounded, color: RoomColors.accent),
                SizedBox(width: 10),
                Expanded(child: Text('保存后，房间名称、话题、进入方式与麦位规则会立即生效。')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.description});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 5),
          Text(description, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
