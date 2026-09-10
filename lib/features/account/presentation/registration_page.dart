import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/design_system/runtime_surfaces.dart';
import 'package:voice_social_app/features/account/application/auth_controller.dart';
import 'package:voice_social_app/features/account/domain/auth_models.dart';
import 'package:voice_social_app/features/account/presentation/account_oxygen_components.dart';
import '../domain/registration_avatar.dart';
import 'preset_avatar_view.dart';
import '../registration_avatar/registration_avatar_host.dart';
import '../registration_avatar/registration_avatar_models.dart';

class RegistrationPage extends StatefulWidget {
  const RegistrationPage({required this.controller, super.key});

  final AuthController controller;

  @override
  State<RegistrationPage> createState() => _RegistrationPageState();
}

class _RegistrationPageState extends State<RegistrationPage> {
  final TextEditingController _nicknameController = TextEditingController();
  final TextEditingController _inviteCodeController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  int? _sex;
  String? _presetId;
  String? _choiceError;
  bool _usingUpload = false;
  RegistrationAvatarHost? _uploadHost;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_authChanged);
    _observeUpload();
  }

  @override
  void didUpdateWidget(covariant RegistrationPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_authChanged);
      widget.controller.addListener(_authChanged);
      _usingUpload = false;
      _presetId = null;
      _observeUpload();
    }
  }

  void _authChanged() {
    if (!mounted) return;
    _observeUpload();
    setState(() {});
  }

  void _observeUpload() {
    final next = widget.controller.registrationAvatarHost;
    if (identical(next, _uploadHost)) return;
    _uploadHost?.removeListener(_uploadChanged);
    _uploadHost = next;
    next?.addListener(_uploadChanged);
    if (next != null) {
      // Restoring metadata never automatically uploads or chooses an avatar.
      unawaited(Future<void>.sync(next.restore).catchError((Object _) {}));
    }
  }

  void _uploadChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_authChanged);
    _uploadHost?.removeListener(_uploadChanged);
    _nicknameController.dispose();
    _inviteCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AuthController controller = widget.controller;
    final uploading = _uploadHost?.busy == true;
    return SocialPageScaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: '返回登录',
          onPressed: controller.busy ? null : controller.cancelRegistration,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('完善资料'),
      ),
      bottomNavigationBar: AccountBottomActionBar(
        child: AccountPrimaryAction(
          label: controller.registrationOutcomeUnknown ? '返回登录确认注册结果' : '完成注册',
          busy: controller.busy || uploading,
          onPressed: controller.registrationOutcomeUnknown
              ? controller.cancelRegistration
              : _submit,
        ),
      ),
      body: SafeArea(
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 30),
          children: <Widget>[
            const AccountMistHero(
              eyebrow: 'NEW PROFILE',
              title: '留下你的声音名片',
              subtitle: '一个好记的昵称，能让房间里的朋友更快认识你',
              markSize: 56,
            ),
            const SizedBox(height: 20),
            AccountStatusPill(
              label: '已验证 · ${controller.pendingPhone}',
              color: AppColors.success,
            ),
            const SizedBox(height: 12),
            AccountSheet(
              padding: const EdgeInsets.fromLTRB(14, 15, 14, 17),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('选择头像', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 12),
                    if (_uploadHost case final host?) ...[
                      _uploadPanel(host),
                      const SizedBox(height: 14),
                      const Text('或主动选择一款默认头像'),
                      const SizedBox(height: 8),
                    ],
                    PresetAvatarPicker(
                      selectedId: _presetId,
                      enabled: !controller.busy && !uploading,
                      onSelected: (id) => setState(() {
                        _presetId = id;
                        _usingUpload = false;
                        _choiceError = null;
                      }),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _nicknameController,
                      maxLength: 24,
                      decoration: const InputDecoration(
                        labelText: '昵称',
                        hintText: '1—24 个字符',
                        prefixIcon: Icon(Icons.face_retouching_natural_rounded),
                      ),
                      validator: (String? value) {
                        final int length = value?.trim().length ?? 0;
                        return length >= 1 && length <= 24
                            ? null
                            : '请填写 1—24 个字符的昵称';
                      },
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '性别',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: AccountOxygenColors.ink,
                      ),
                    ),
                    const SizedBox(height: 9),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<int>(
                        segments: const <ButtonSegment<int>>[
                          ButtonSegment<int>(value: 0, label: Text('不公开')),
                          ButtonSegment<int>(
                            value: 1,
                            icon: Icon(Icons.male_rounded, size: 17),
                            label: Text('男'),
                          ),
                          ButtonSegment<int>(
                            value: 2,
                            icon: Icon(Icons.female_rounded, size: 17),
                            label: Text('女'),
                          ),
                        ],
                        emptySelectionAllowed: true,
                        selected: <int>{if (_sex != null) _sex!},
                        onSelectionChanged: controller.busy
                            ? null
                            : (Set<int> values) => setState(() {
                                _sex = values.isEmpty ? null : values.first;
                                _choiceError = null;
                              }),
                      ),
                    ),
                    const SizedBox(height: 13),
                    TextFormField(
                      controller: _inviteCodeController,
                      textCapitalization: TextCapitalization.characters,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: '邀请码（选填）',
                        prefixIcon: const Icon(
                          Icons.confirmation_number_outlined,
                        ),
                        suffixIcon: _inviteCodeController.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: '移除邀请码',
                                onPressed: controller.busy
                                    ? null
                                    : () =>
                                          setState(_inviteCodeController.clear),
                                icon: const Icon(Icons.close_rounded),
                              ),
                      ),
                    ),
                    if (_choiceError != null)
                      Text(
                        _choiceError!,
                        style: const TextStyle(color: AppColors.error),
                      ),
                  ],
                ),
              ),
            ),
            if (controller.errorMessage != null) ...<Widget>[
              const SizedBox(height: 16),
              Text(
                controller.errorMessage!,
                style: const TextStyle(color: AppColors.error),
              ),
            ],
            const SizedBox(height: 14),
            const AccountNoticeStrip(
              icon: Icons.visibility_outlined,
              text: '昵称会展示在个人主页、房间座位和消息会话中，之后可在个人资料中修改。',
              tone: AccountOxygenColors.cyan,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (widget.controller.busy ||
        widget.controller.registrationOutcomeUnknown ||
        _uploadHost?.busy == true)
      return;
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final ready = _usingUpload ? _uploadHost?.ready : null;
    if (_sex == null || (!_usingUpload && _presetId == null)) {
      setState(() => _choiceError = '请选择头像和性别');
      return;
    }
    if (_usingUpload && ready == null) {
      setState(() => _choiceError = '头像尚未确认上传完成，请先检查上传状态');
      return;
    }
    await widget.controller.completeRegistration(
      RegistrationProfile(
        nickname: _nicknameController.text,
        sex: _sex!,
        avatar: ready != null
            ? RegistrationAvatarChoice.uploaded(ready.assetId, ready.version)
            : RegistrationAvatarChoice.preset(_presetId!),
        inviteCode: _inviteCodeController.text.trim(),
      ),
    );
  }

  Widget _uploadPanel(RegistrationAvatarHost host) {
    final busy =
        widget.controller.busy ||
        widget.controller.registrationOutcomeUnknown ||
        host.busy;
    final preview = host.previewBytes;
    final current = host.context.isCurrent;
    final state = host.status?.state;
    final label = widget.controller.registrationOutcomeUnknown
        ? '注册结果尚未确认，请返回登录确认'
        : !current
        ? '验证码已失效，请返回登录重新获取'
        : host.busy
        ? '正在处理头像…'
        : host.ready != null
        ? '头像已上传，可以完成注册'
        : switch (state) {
            RegistrationAvatarState.rejected => '图片未通过检查，请选择默认头像或重新获取验证码后上传',
            RegistrationAvatarState.quarantined => '正在检查图片，可查询处理结果',
            RegistrationAvatarState.bound => '注册状态已变化，请返回登录确认',
            _ =>
              host.hasSelection
                  ? '原头像尚待确认，请继续处理或检查状态'
                  : '支持 JPG、PNG、WebP，单张不超过 10MB',
          };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (host.hasSelection)
          InkWell(
            key: const ValueKey('registration-upload-choice'),
            onTap: busy
                ? null
                : () => setState(() {
                    _usingUpload = true;
                    _presetId = null;
                    _choiceError = null;
                  }),
            borderRadius: BorderRadius.circular(18),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: _usingUpload ? AppColors.primary : Colors.black12,
                  width: _usingUpload ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  ClipOval(
                    child: preview == null
                        ? const SizedBox(
                            width: 64,
                            height: 64,
                            child: Icon(
                              Icons.account_circle_outlined,
                              size: 52,
                            ),
                          )
                        : _RegistrationUploadPreview(bytes: preview),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(_usingUpload ? '已选择上传头像' : '使用这张上传头像')),
                  if (_usingUpload)
                    const Icon(
                      Icons.check_circle_rounded,
                      color: AppColors.primary,
                    ),
                ],
              ),
            ),
          ),
        if (!host.hasSelection && current)
          OutlinedButton.icon(
            key: const ValueKey('registration-pick-image'),
            onPressed: busy ? null : () => _chooseImage(host),
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: const Text('从相册选择头像'),
          ),
        const SizedBox(height: 8),
        Text(label, key: const ValueKey('registration-upload-status')),
        if (host.busy)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(),
          ),
        if (host.hasSelection && host.ready == null && current && !host.busy)
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: busy
                    ? null
                    : () => _processUpload(host, host.upload),
                child: const Text('继续处理原头像'),
              ),
              TextButton(
                onPressed: busy
                    ? null
                    : () => _processUpload(host, host.recover),
                child: const Text('检查上传状态'),
              ),
            ],
          ),
        if (host.error case final error?)
          Text(error, style: const TextStyle(color: AppColors.error)),
        if (!current || host.sourceUnavailable)
          TextButton(
            onPressed: widget.controller.busy
                ? null
                : widget.controller.cancelRegistration,
            child: const Text('返回登录重新获取验证码'),
          ),
      ],
    );
  }

  Future<void> _chooseImage(RegistrationAvatarHost host) async {
    try {
      await host.choose();
      if (!mounted || !identical(host, _uploadHost) || !host.hasSelection)
        return;
      setState(() {
        _usingUpload = true;
        _presetId = null;
        _choiceError = null;
      });
      await host.upload();
    } catch (_) {
      // The host exposes a fixed, non-sensitive recovery message.
    }
  }

  Future<void> _processUpload(
    RegistrationAvatarHost host,
    Future<void> Function() action,
  ) async {
    if (!identical(host, _uploadHost) || widget.controller.busy) return;
    try {
      await action();
    } catch (_) {
      /* Keep original upload for recovery. */
    }
  }
}

/// Own the resized cache key as well as the widget's image listener. Removing
/// Image alone leaves the selected bytes in ImageCache's pending/keepAlive map.
class _RegistrationUploadPreview extends StatefulWidget {
  const _RegistrationUploadPreview({required this.bytes});

  final Uint8List bytes;

  @override
  State<_RegistrationUploadPreview> createState() =>
      _RegistrationUploadPreviewState();
}

class _RegistrationUploadPreviewState
    extends State<_RegistrationUploadPreview> {
  late ImageProvider _provider;

  ImageProvider _createProvider() =>
      ResizeImage.resizeIfNeeded(192, null, MemoryImage(widget.bytes));

  @override
  void initState() {
    super.initState();
    _provider = _createProvider();
  }

  @override
  void didUpdateWidget(covariant _RegistrationUploadPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.bytes, widget.bytes)) {
      unawaited(_provider.evict());
      _provider = _createProvider();
    }
  }

  @override
  void dispose() {
    // Evict the outer ResizeImage key, including its pending listener, so a
    // frame completing after exit cannot repopulate the global cache.
    unawaited(_provider.evict());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Image(
    image: _provider,
    width: 64,
    height: 64,
    fit: BoxFit.cover,
    errorBuilder: (_, _, _) => const SizedBox(
      width: 64,
      height: 64,
      child: Icon(Icons.image_not_supported_outlined),
    ),
  );
}
