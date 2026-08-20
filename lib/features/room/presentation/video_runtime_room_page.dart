import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/design_system/runtime_surfaces.dart';
import 'package:voice_social_app/features/room/application/room_controller.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/domain/room_operations_models.dart';
import 'package:voice_social_app/features/room/domain/room_permission_policy.dart';
import 'package:voice_social_app/features/room/pk/presentation/room_pk_pages.dart';
import 'package:voice_social_app/features/room/presentation/gift_sheet.dart';
import 'package:voice_social_app/features/room/presentation/room_audio_page.dart';
import 'package:voice_social_app/features/room/presentation/room_diagnostics_page.dart';
import 'package:voice_social_app/features/room/presentation/room_members_page.dart';
import 'package:voice_social_app/features/room/presentation/room_recovery_page.dart';
import 'package:voice_social_app/features/room/presentation/room_share_page.dart';
import 'package:voice_social_app/features/room/presentation/room_topic_page.dart';
import 'package:voice_social_app/features/social/domain/social_models.dart';
import 'package:voice_social_app/features/social/presentation/social_pages.dart';

enum VideoRoomExit { minimized, ended }

class VideoRuntimeRoomPage extends StatefulWidget {
  const VideoRuntimeRoomPage({
    required this.controller,
    this.allowMinimize = true,
    super.key,
  });

  final RoomController controller;
  final bool allowMinimize;

  @override
  State<VideoRuntimeRoomPage> createState() => _VideoRuntimeRoomPageState();
}

class _VideoRuntimeRoomPageState extends State<VideoRuntimeRoomPage> {
  final TextEditingController _composer = TextEditingController();
  final FocusNode _composerFocus = FocusNode();
  final ScrollController _messageScroll = ScrollController();
  Timer? _giftTimer;
  bool _showGiftCelebration = false;
  bool _ending = false;
  bool _followingHost = false;
  String? _presentedError;

  RoomController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _composerFocus.addListener(_onComposerFocusChanged);
    _controller.addListener(_onControllerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _controller.join();
      }
    });
  }

  @override
  void dispose() {
    _giftTimer?.cancel();
    _composerFocus
      ..removeListener(_onComposerFocusChanged)
      ..dispose();
    _controller.removeListener(_onControllerChanged);
    _composer.dispose();
    _messageScroll.dispose();
    super.dispose();
  }

  void _onComposerFocusChanged() {
    if (mounted) setState(() {});
  }

  void _onControllerChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
    final String? error = _controller.errorMessage;
    if (error != null && error != _presentedError) {
      _presentedError = error;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error)));
        _controller.clearError();
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_messageScroll.hasClients) {
        _messageScroll.animateTo(
          _messageScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 170),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final String? inheritedFontFamily = Theme.of(
      context,
    ).textTheme.bodyMedium?.fontFamily;
    return Theme(
      data: AppTheme.room(fontFamily: inheritedFontFamily),
      child: PopScope<Object?>(
        canPop: false,
        onPopInvokedWithResult: (bool didPop, Object? result) {
          if (!didPop) {
            _showExitChoices();
          }
        },
        child: Scaffold(
          resizeToAvoidBottomInset: false,
          body: switch (_controller.status) {
            RoomSessionStatus.idle ||
            RoomSessionStatus.joining => _joiningState(),
            RoomSessionStatus.failed when _controller.snapshot == null =>
              _failureState(),
            _ => _roomContent(),
          },
        ),
      ),
    );
  }

  Widget _joiningState() {
    return Stack(
      children: <Widget>[
        const _VideoRoomBackground(),
        SafeArea(
          child: Column(
            children: <Widget>[
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  tooltip: '离开房间',
                  onPressed: _showExitChoices,
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
              const Spacer(),
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text('正在进入房间', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text('正在同步房间状态', style: Theme.of(context).textTheme.bodySmall),
              const Spacer(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _failureState() {
    return Stack(
      children: <Widget>[
        const _VideoRoomBackground(),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                IconButton(
                  tooltip: '返回',
                  onPressed: () =>
                      Navigator.of(context).pop(VideoRoomExit.ended),
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                const Spacer(),
                const Icon(
                  Icons.wifi_off_rounded,
                  size: 46,
                  color: RoomColors.warning,
                ),
                const SizedBox(height: 18),
                Text(
                  '暂时无法进入房间',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 10),
                Text(_controller.errorMessage ?? '请检查网络后重试。'),
                const SizedBox(height: 22),
                FilledButton.icon(
                  onPressed: () => _controller.join(),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('重新进入'),
                ),
                const Spacer(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _roomContent() {
    final double keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Stack(
      children: <Widget>[
        const _VideoRoomBackground(),
        SafeArea(
          child: AnimatedPadding(
            duration: const Duration(milliseconds: 210),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.only(bottom: keyboard),
            child: Column(
              children: <Widget>[
                _header(),
                _announcement(),
                Expanded(
                  child: Column(
                    children: <Widget>[
                      SizedBox(
                        height: keyboard > 0 ? 198 : 252,
                        child: GridView.builder(
                          padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 4,
                                mainAxisSpacing: 8,
                                crossAxisSpacing: 8,
                                childAspectRatio: 0.8,
                              ),
                          itemCount: _controller.seats.length,
                          itemBuilder: (BuildContext context, int index) =>
                              _VideoMicSeat(seat: _controller.seats[index]),
                        ),
                      ),
                      Expanded(child: _publicScreen()),
                    ],
                  ),
                ),
                if (keyboard > 0 || _composerFocus.hasFocus)
                  _replySuggestions(),
                _composerBar(),
                if (keyboard == 0) _actions(),
              ],
            ),
          ),
        ),
        if (_controller.realtimeDegraded &&
            _controller.status == RoomSessionStatus.joined)
          const _StatusChip(label: '实时状态可能延迟'),
        if (_controller.status == RoomSessionStatus.reconnecting)
          const _StatusChip(label: '网络波动，正在恢复连接…'),
        if (_ending || _controller.status == RoomSessionStatus.leaving)
          const _BlockingProgress(label: '正在结束房间会话…'),
        IgnorePointer(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            child: _showGiftCelebration
                ? const _GiftCelebrationOverlay(
                    key: Key('gift-celebration-overlay'),
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 7, 8, 3),
      child: Row(
        children: <Widget>[
          RuntimeAvatar(seed: _controller.roomId, size: 38),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  _controller.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  _controller.snapshot?.onlineCount == null
                      ? '房间号 ${_controller.roomCode}'
                      : '房间号 ${_controller.roomCode} · ${_controller.snapshot!.onlineCount} 人在线',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Semantics(
            button: true,
            selected: _followingHost,
            label: _followingHost ? '已关注房主' : '关注房主',
            child: Material(
              color: _followingHost
                  ? Colors.white.withValues(alpha: 0.13)
                  : RoomColors.primary.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(999),
              child: InkWell(
                key: const Key('room-follow-host'),
                onTap: () => setState(() => _followingHost = !_followingHost),
                borderRadius: BorderRadius.circular(999),
                child: SizedBox(
                  height: 30,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 9),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Icon(Icons.favorite_rounded, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          _followingHost ? '已关注' : '关注',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 55,
            child: Stack(
              children: <Widget>[
                const RuntimeAvatar(seed: 'room-member-1', size: 30),
                const Positioned(
                  left: 19,
                  child: RuntimeAvatar(seed: 'room-member-2', size: 30),
                ),
                Positioned(
                  right: 0,
                  top: 9,
                  child: Text(
                    '${_controller.snapshot?.onlineCount ?? 0}',
                    style: const TextStyle(
                      color: RoomColors.textSecondary,
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '离开房间',
            visualDensity: VisualDensity.compact,
            onPressed: _showExitChoices,
            icon: const Icon(Icons.close_rounded, size: 21),
          ),
        ],
      ),
    );
  }

  Widget _announcement() {
    final String topic = _controller.topic.isEmpty
        ? '欢迎来到房间，请友善交流'
        : _controller.topic;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 2, 14, 0),
      child: Column(
        children: <Widget>[
          _AnnouncementChip(
            icon: Icons.campaign_outlined,
            label: topic,
            onTap: _openTopic,
          ),
          const SizedBox(height: 5),
          const _AnnouncementChip(
            icon: Icons.workspace_premium_outlined,
            label: '房间等级正在积累 · 欢迎留下聊聊',
          ),
        ],
      ),
    );
  }

  Widget _publicScreen() {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 6, 14, 6),
      alignment: Alignment.bottomLeft,
      child: ShaderMask(
        shaderCallback: (Rect bounds) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Colors.transparent, Colors.white, Colors.white],
          stops: <double>[0, 0.3, 1],
        ).createShader(bounds),
        blendMode: BlendMode.dstIn,
        child: ListView.separated(
          controller: _messageScroll,
          padding: const EdgeInsets.only(top: 24),
          itemCount: _controller.messages.length + 1,
          separatorBuilder: (_, __) => const SizedBox(height: 7),
          itemBuilder: (BuildContext context, int index) {
            if (index == 0) {
              return _RoomConversationCard(topic: _controller.topic);
            }
            final RoomMessage message = _controller.messages[index - 1];
            return Align(
              alignment: Alignment.centerLeft,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 330),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Text.rich(
                  TextSpan(
                    children: <InlineSpan>[
                      TextSpan(
                        text: '${message.sender}  ',
                        style: TextStyle(
                          color: message.isSystem
                              ? RoomColors.gold
                              : RoomColors.accent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      TextSpan(text: message.content),
                    ],
                  ),
                  style: const TextStyle(
                    color: RoomColors.textPrimary,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _composerBar() {
    final bool enabled =
        _controller.status == RoomSessionStatus.joined &&
        _controller.canSendPublicMessage;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.fromLTRB(6, 3, 4, 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.27),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          IconButton(
            key: const Key('room-expression-button'),
            tooltip: '表情与贴图',
            onPressed: enabled ? _showExpressionSheet : null,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.mood_rounded, color: RoomColors.accent),
          ),
          Expanded(
            child: TextField(
              key: const Key('video-room-composer'),
              controller: _composer,
              focusNode: _composerFocus,
              enabled: enabled,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              cursorColor: RoomColors.accent,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendMessage(),
              decoration: InputDecoration(
                filled: false,
                hintText: enabled ? '聊聊天…' : '当前不可发送公屏消息',
                hintStyle: const TextStyle(color: RoomColors.textSecondary),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
              ),
            ),
          ),
          IconButton.filled(
            tooltip: '发送',
            onPressed: enabled ? _sendMessage : null,
            icon: const Icon(Icons.arrow_upward_rounded),
            style: IconButton.styleFrom(
              backgroundColor: RoomColors.primary,
              foregroundColor: Colors.white,
              minimumSize: const Size(36, 36),
            ),
          ),
        ],
      ),
    );
  }

  Widget _replySuggestions() {
    const List<String> suggestions = <String>[
      '前面还有几首？',
      '今天过得怎么样？',
      '主播声音很好听',
      '还有人要连麦吗？',
    ];
    return SizedBox(
      height: 39,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 3, 12, 5),
        itemCount: suggestions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 7),
        itemBuilder: (BuildContext context, int index) => ActionChip(
          label: Text(suggestions[index]),
          labelStyle: const TextStyle(
            color: RoomColors.textPrimary,
            fontSize: 10,
          ),
          backgroundColor: Colors.white.withValues(alpha: 0.1),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.09)),
          visualDensity: VisualDensity.compact,
          onPressed: () {
            _composer.text = suggestions[index];
            _composer.selection = TextSelection.collapsed(
              offset: _composer.text.length,
            );
          },
        ),
      ),
    );
  }

  Widget _actions() {
    final bool joined = _controller.status == RoomSessionStatus.joined;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: <Widget>[
            _RoomAction(
              icon: _controller.isOnMic
                  ? (_controller.micMuted
                        ? Icons.mic_off_rounded
                        : Icons.mic_rounded)
                  : Icons.keyboard_voice_rounded,
              label: _controller.isOnMic
                  ? (_controller.micMuted ? '开麦' : '闭麦')
                  : '上麦',
              enabled: joined,
              onTap: _controller.isOnMic ? _toggleMicrophone : _showMicSheet,
            ),
            _RoomAction(
              icon: Icons.groups_2_rounded,
              label: '成员',
              enabled: joined,
              onTap: _openMembers,
            ),
            _RoomAction(
              icon: Icons.redeem_rounded,
              label: '礼物',
              highlighted: true,
              enabled: joined && _controller.allows(RoomCapability.sendGift),
              onTap: _showGiftSheet,
            ),
            _RoomAction(
              icon: Icons.apps_rounded,
              label: '更多',
              enabled: joined,
              onTap: _showMoreSheet,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendMessage() async {
    final bool sent = await _controller.sendPublicMessage(_composer.text);
    if (sent) {
      _composer.clear();
    }
  }

  Future<void> _showExpressionSheet() async {
    _composerFocus.unfocus();
    final _RoomExpression? expression =
        await showModalBottomSheet<_RoomExpression>(
          context: context,
          useSafeArea: true,
          isScrollControlled: true,
          backgroundColor: const Color(0xFF14152E),
          barrierColor: Colors.black.withValues(alpha: 0.42),
          builder: (BuildContext context) => const FractionallySizedBox(
            heightFactor: 0.42,
            child: _RoomExpressionSheet(),
          ),
        );
    if (expression == null || !mounted) {
      return;
    }
    final String current = _composer.text;
    final String separator = current.isEmpty || current.endsWith(' ')
        ? ''
        : ' ';
    _composer.text = '$current$separator${expression.token}';
    _composer.selection = TextSelection.collapsed(
      offset: _composer.text.length,
    );
    _composerFocus.requestFocus();
  }

  Future<void> _toggleMicrophone() async {
    await _controller.toggleMicrophone();
  }

  Future<void> _showMicSheet() async {
    final List<MicSeat> available = _controller.seats
        .where((MicSeat seat) => seat.isAvailable)
        .toList(growable: false);
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: const Color(0xFF14152E),
      builder: (BuildContext sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('选择麦位', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 14),
            if (available.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: Text('当前没有可用麦位')),
              )
            else
              GridView.count(
                shrinkWrap: true,
                crossAxisCount: 4,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                children: <Widget>[
                  for (final MicSeat seat in available)
                    InkWell(
                      onTap: () async {
                        Navigator.of(sheetContext).pop();
                        await _controller.requestMic(seat.number);
                      },
                      borderRadius: BorderRadius.circular(18),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Center(child: Text('${seat.number} 号麦')),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showGiftSheet() async {
    final List<GiftTarget> targets = _controller.seats
        .where(
          (MicSeat seat) =>
              seat.isOccupied &&
              seat.userId != null &&
              seat.userName != null &&
              seat.userId != _controller.currentUserId,
        )
        .map(
          (MicSeat seat) =>
              GiftTarget(userId: seat.userId!, name: seat.userName!),
        )
        .toList(growable: false);
    final String account =
        AppDependencyScope.of(context).sessionManager.session?.mobile ?? '';
    final bool? sent = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF13142C),
      barrierColor: Colors.black.withValues(alpha: 0.4),
      builder: (BuildContext context) => FractionallySizedBox(
        heightFactor: 0.58,
        child: GiftSheet(
          account: account,
          targets: targets,
          balance: _controller.giftBalance,
          onSend: (GiftSendRequest request) => _controller.sendGift(
            giftId: request.gift.id,
            giftName: request.gift.name,
            receiverUserId: request.target.userId,
            targetName: request.target.name,
            quantity: request.quantity,
          ),
          onRechargeReturn: () async {
            await _controller.reconnect();
            return _controller.giftBalance;
          },
        ),
      ),
    );
    if (sent == true && mounted) {
      _giftTimer?.cancel();
      setState(() => _showGiftCelebration = true);
      _giftTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) {
          setState(() => _showGiftCelebration = false);
        }
      });
    }
  }

  Future<void> _showMoreSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF14152E),
      builder: (BuildContext sheetContext) => _RoomToolsSheet(
        canPk: _controller.allows(RoomCapability.startPk),
        isOnMic: _controller.isOnMic,
        onAction: (String action) {
          Navigator.of(sheetContext).pop();
          switch (action) {
            case 'members':
              _openMembers();
            case 'share':
              _openShare();
            case 'topic':
              _openTopic();
            case 'audio':
              _openAudio();
            case 'recovery':
              _openRecovery();
            case 'diagnostics':
              _openDiagnostics();
            case 'pk':
              _openPk();
            case 'report':
              _openReport();
            case 'copy':
              Clipboard.setData(ClipboardData(text: _controller.roomCode));
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('房间号已复制')));
            case 'minimize':
              _minimize();
            case 'leaveMic':
              _controller.leaveMic();
            case 'leaveRoom':
              _confirmEnd();
          }
        },
      ),
    );
  }

  void _openMembers() {
    final RoomSnapshot? snapshot = _controller.snapshot;
    if (snapshot == null) {
      return;
    }
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => RoomMembersPage(
          roomId: snapshot.roomId,
          currentUserId: _controller.currentUserId,
          currentRole: snapshot.role,
          seats: snapshot.seats,
        ),
      ),
    );
  }

  void _openShare() {
    final RoomSnapshot? snapshot = _controller.snapshot;
    if (snapshot == null) {
      return;
    }
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => RoomSharePage(
          roomId: snapshot.roomId,
          roomCode: snapshot.roomCode,
          roomTitle: snapshot.title,
        ),
      ),
    );
  }

  Future<void> _openTopic() async {
    final RoomSnapshot? snapshot = _controller.snapshot;
    if (snapshot == null) {
      return;
    }
    final RoomTopic? topic = await Navigator.of(context).push<RoomTopic>(
      MaterialPageRoute<RoomTopic>(
        builder: (BuildContext context) => RoomTopicPage(
          roomId: snapshot.roomId,
          canEdit: _controller.allows(RoomCapability.editRoom),
        ),
      ),
    );
    if (topic != null) {
      _controller.applyAuthoritativeTopic(topic.content);
    }
  }

  void _openAudio() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            RoomAudioPage(isOnMic: _controller.isOnMic),
      ),
    );
  }

  void _openRecovery() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            RoomRecoveryPage(controller: _controller),
      ),
    );
  }

  void _openDiagnostics() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            RoomDiagnosticsPage(controller: _controller),
      ),
    );
  }

  void _openPk() {
    final RoomSnapshot? snapshot = _controller.snapshot;
    if (snapshot == null || !_controller.allows(RoomCapability.startPk)) {
      return;
    }
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => RoomPkPreparationPage(
          roomId: snapshot.roomId,
          roomTitle: snapshot.title,
        ),
      ),
    );
  }

  void _openReport() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => ReportPage(
          targetType: ReportTargetType.room,
          targetId: _controller.roomId,
          targetName: _controller.displayTitle,
        ),
      ),
    );
  }

  Future<void> _showExitChoices() async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: const Color(0xFF14152E),
      builder: (BuildContext sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (widget.allowMinimize)
              ListTile(
                leading: const Icon(Icons.picture_in_picture_alt_rounded),
                title: const Text('收起房间'),
                subtitle: const Text('保留当前会话，可从悬浮房间恢复'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _minimize();
                },
              ),
            ListTile(
              leading: const Icon(
                Icons.logout_rounded,
                color: RoomColors.error,
              ),
              title: const Text('离开房间'),
              subtitle: Text(_controller.isOnMic ? '将同时下麦并结束房间会话' : '结束本次收听'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _confirmEnd();
              },
            ),
            ListTile(
              leading: const Icon(Icons.close_rounded),
              title: const Text('取消'),
              onTap: () => Navigator.of(sheetContext).pop(),
            ),
          ],
        ),
      ),
    );
  }

  void _minimize() {
    if (widget.allowMinimize) {
      Navigator.of(context).pop(VideoRoomExit.minimized);
    }
  }

  Future<void> _confirmEnd() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('离开房间？'),
        content: Text(
          _controller.isOnMic ? '离开后将同时下麦，并结束本次房间会话。' : '确认结束本次收听？',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('继续留在房间'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('确认离开'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _endRoom();
    }
  }

  Future<void> _endRoom() async {
    if (_ending) {
      return;
    }
    setState(() => _ending = true);
    final bool left = await _controller.leaveRoom();
    if (!mounted) {
      return;
    }
    if (!left && _controller.status != RoomSessionStatus.left) {
      setState(() => _ending = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('离开房间失败，请重试')));
      return;
    }
    Navigator.of(context).pop(VideoRoomExit.ended);
  }
}

class _AnnouncementChip extends StatelessWidget {
  const _AnnouncementChip({
    required this.icon,
    required this.label,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white.withValues(alpha: 0.065),
    borderRadius: BorderRadius.circular(999),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 13, color: RoomColors.gold),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: RoomColors.textSecondary,
                  fontSize: 10,
                ),
              ),
            ),
            if (onTap != null)
              const Icon(
                Icons.chevron_right_rounded,
                size: 14,
                color: RoomColors.textSecondary,
              ),
          ],
        ),
      ),
    ),
  );
}

class _RoomConversationCard extends StatelessWidget {
  const _RoomConversationCard({required this.topic});

  final String topic;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Container(
      width: 255,
      padding: const EdgeInsets.fromLTRB(13, 11, 13, 12),
      decoration: BoxDecoration(
        color: const Color(0x9C29123F),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.055)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Row(
            children: <Widget>[
              Icon(Icons.forum_rounded, color: RoomColors.accent, size: 14),
              SizedBox(width: 6),
              Text(
                '今晚的话题',
                style: TextStyle(
                  color: RoomColors.accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            topic.isEmpty ? '最近有什么让你觉得被治愈的小事？' : topic,
            style: const TextStyle(
              color: RoomColors.textPrimary,
              fontSize: 12,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '可以聊聊今天的心情，也可以安静听一会儿。',
            style: TextStyle(color: RoomColors.textSecondary, fontSize: 10),
          ),
        ],
      ),
    ),
  );
}

class _VideoRoomBackground extends StatelessWidget {
  const _VideoRoomBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Image.asset(
          'assets/runtime/room-cosmos.png',
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                Color(0x521A0638),
                Color(0x94210844),
                Color(0xEC090B1E),
              ],
              stops: <double>[0, 0.52, 1],
            ),
          ),
        ),
      ],
    );
  }
}

class _VideoMicSeat extends StatelessWidget {
  const _VideoMicSeat({required this.seat});

  final MicSeat seat;

  @override
  Widget build(BuildContext context) {
    final bool occupied = seat.isOccupied && seat.userName != null;
    final bool speaking = seat.isSpeaking;
    final bool dense = MediaQuery.textScalerOf(context).scale(1) > 1.15;
    final double seatSize = dense ? 50 : 58;
    final Color ring = speaking
        ? RoomColors.success
        : occupied
        ? RoomColors.primary
        : seat.state == MicSeatState.locked
        ? RoomColors.gold
        : Colors.white.withValues(alpha: 0.22);
    return Semantics(
      label: '${seat.number} 号麦，${seat.userName ?? _stateLabel(seat.state)}',
      child: Column(
        children: <Widget>[
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: seatSize,
            height: seatSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: occupied
                  ? LinearGradient(
                      colors: seat.number.isEven
                          ? const <Color>[RoomColors.primary, RoomColors.accent]
                          : const <Color>[
                              RoomColors.secondary,
                              RoomColors.primary,
                            ],
                    )
                  : null,
              color: occupied ? null : Colors.white.withValues(alpha: 0.055),
              border: Border.all(color: ring, width: speaking ? 3 : 1.6),
              boxShadow: speaking
                  ? <BoxShadow>[
                      BoxShadow(
                        color: RoomColors.success.withValues(alpha: 0.42),
                        blurRadius: 22,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                if (occupied)
                  RuntimeAvatar(
                    seed: '${seat.userId}-${seat.number}',
                    size: dense ? 46 : 54,
                    ringColor: Colors.transparent,
                  )
                else
                  Icon(
                    seat.state == MicSeatState.locked
                        ? Icons.lock_rounded
                        : Icons.add_rounded,
                    color: RoomColors.textSecondary,
                    size: 22,
                  ),
                if (occupied)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: dense ? 18 : 20,
                      height: dense ? 18 : 20,
                      decoration: BoxDecoration(
                        color: seat.state == MicSeatState.occupiedMuted
                            ? RoomColors.error
                            : const Color(0xFF292A4E),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: RoomColors.background,
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        seat.state == MicSeatState.occupiedMuted
                            ? Icons.mic_off_rounded
                            : Icons.mic_rounded,
                        color: Colors.white,
                        size: 11,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(height: dense ? 3 : 6),
          Text(
            seat.userName ?? '${seat.number} 号麦',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: RoomColors.textPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: dense ? 0 : 2),
          Text(
            speaking ? '正在说话' : _stateLabel(seat.state),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: speaking ? RoomColors.success : RoomColors.textSecondary,
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }

  static String _stateLabel(MicSeatState state) => switch (state) {
    MicSeatState.available => '空闲',
    MicSeatState.locked => '已锁定',
    MicSeatState.mutedAvailable => '空麦闭麦',
    MicSeatState.occupied => '麦上',
    MicSeatState.occupiedMuted => '已静音',
  };
}

class _RoomAction extends StatelessWidget {
  const _RoomAction({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: enabled ? onTap : null,
      radius: 30,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: highlighted && enabled
                  ? const LinearGradient(
                      colors: <Color>[RoomColors.primary, RoomColors.secondary],
                    )
                  : null,
              color: highlighted
                  ? null
                  : Colors.white.withValues(alpha: enabled ? 0.09 : 0.035),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Icon(
              icon,
              color: enabled ? Colors.white : Colors.white38,
              size: 22,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            style: TextStyle(
              color: enabled ? RoomColors.textPrimary : Colors.white38,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

class _GiftCelebrationOverlay extends StatelessWidget {
  const _GiftCelebrationOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: const Alignment(0, -0.22),
      child: Container(
        height: 132,
        margin: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x997A5BEB),
              blurRadius: 36,
              spreadRadius: 3,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              Image.asset(
                'assets/runtime/gift-celebration-banner.png',
                fit: BoxFit.cover,
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: <Color>[Color(0xA921124D), Color(0x1021124D)],
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(18, 0, 120, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Text(
                      '晚星 送出星河心意',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        shadows: <Shadow>[
                          Shadow(color: Colors.black54, blurRadius: 8),
                        ],
                      ),
                    ),
                    SizedBox(height: 5),
                    Text(
                      '礼物已送达 · 为房间点亮一份惊喜',
                      style: TextStyle(color: Colors.white70, fontSize: 10),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoomExpression {
  const _RoomExpression({
    required this.label,
    required this.token,
    required this.asset,
  });

  final String label;
  final String token;
  final String asset;
}

class _RoomExpressionSheet extends StatefulWidget {
  const _RoomExpressionSheet();

  @override
  State<_RoomExpressionSheet> createState() => _RoomExpressionSheetState();
}

class _RoomExpressionSheetState extends State<_RoomExpressionSheet> {
  int _tab = 0;

  static const List<_RoomExpression> _expressions = <_RoomExpression>[
    _RoomExpression(
      label: '晚安',
      token: '[晚安]',
      asset: 'assets/runtime/avatar-night.png',
    ),
    _RoomExpression(
      label: '收到',
      token: '[收到]',
      asset: 'assets/runtime/avatar-silver.png',
    ),
    _RoomExpression(
      label: '喜欢',
      token: '[喜欢]',
      asset: 'assets/runtime/avatar-rose.png',
    ),
    _RoomExpression(
      label: '加油',
      token: '[加油]',
      asset: 'assets/runtime/avatar-copper.png',
    ),
    _RoomExpression(
      label: '倾听',
      token: '[认真听]',
      asset: 'assets/runtime/avatar-silver.png',
    ),
    _RoomExpression(
      label: '同感',
      token: '[同感]',
      asset: 'assets/runtime/avatar-night.png',
    ),
    _RoomExpression(
      label: '支持',
      token: '[支持]',
      asset: 'assets/runtime/avatar-copper.png',
    ),
    _RoomExpression(
      label: '陪伴',
      token: '[陪伴]',
      asset: 'assets/runtime/avatar-rose.png',
    ),
  ];

  static const List<_RoomExpression> _stickers = <_RoomExpression>[
    _RoomExpression(
      label: '星河鲸鱼',
      token: '[星河鲸鱼]',
      asset: 'assets/runtime/gift-whale.png',
    ),
    _RoomExpression(
      label: '花开时刻',
      token: '[花开时刻]',
      asset: 'assets/runtime/gift-blossom.png',
    ),
    _RoomExpression(
      label: '同行车票',
      token: '[同行车票]',
      asset: 'assets/runtime/gift-ticket.png',
    ),
    _RoomExpression(
      label: '房间庆典',
      token: '[房间庆典]',
      asset: 'assets/runtime/gift-celebration-banner.png',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final List<_RoomExpression> visible = _tab == 0 ? _expressions : _stickers;
    return Padding(
      key: const Key('room-expression-sheet'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      child: Column(
        children: <Widget>[
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              const Text(
                '表情与贴图',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              SegmentedButton<int>(
                showSelectedIcon: false,
                segments: const <ButtonSegment<int>>[
                  ButtonSegment<int>(
                    value: 0,
                    label: Text('表情', style: TextStyle(color: Colors.white)),
                  ),
                  ButtonSegment<int>(
                    value: 1,
                    label: Text('贴图', style: TextStyle(color: Colors.white)),
                  ),
                ],
                selected: <int>{_tab},
                onSelectionChanged: (Set<int> value) =>
                    setState(() => _tab = value.first),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.86,
              ),
              itemCount: visible.length,
              itemBuilder: (BuildContext context, int index) {
                final _RoomExpression item = visible[index];
                return InkWell(
                  key: Key('room-expression-${item.label}'),
                  onTap: () => Navigator.of(context).pop(item),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.065),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.06),
                      ),
                    ),
                    child: Column(
                      children: <Widget>[
                        Expanded(child: Image.asset(item.asset)),
                        const SizedBox(height: 4),
                        Text(
                          item.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: RoomColors.textSecondary,
                            fontSize: 9,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RoomToolsSheet extends StatefulWidget {
  const _RoomToolsSheet({
    required this.canPk,
    required this.isOnMic,
    required this.onAction,
  });

  final bool canPk;
  final bool isOnMic;
  final void Function(String action) onAction;

  @override
  State<_RoomToolsSheet> createState() => _RoomToolsSheetState();
}

class _RoomToolsSheetState extends State<_RoomToolsSheet> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final List<_ToolItem> interactions = <_ToolItem>[
      const _ToolItem('members', Icons.groups_2_outlined, '成员'),
      const _ToolItem('share', Icons.ios_share_rounded, '分享'),
      const _ToolItem('topic', Icons.campaign_outlined, '公告'),
      if (widget.canPk)
        const _ToolItem('pk', Icons.sports_kabaddi_rounded, '房间 PK'),
      const _ToolItem('copy', Icons.copy_rounded, '复制房间号'),
    ];
    final List<_ToolItem> tools = <_ToolItem>[
      const _ToolItem('audio', Icons.volume_up_outlined, '音频'),
      const _ToolItem('recovery', Icons.sync_rounded, '重新连接'),
      const _ToolItem('diagnostics', Icons.monitor_heart_outlined, '质量诊断'),
      const _ToolItem('report', Icons.report_outlined, '举报'),
      const _ToolItem('minimize', Icons.picture_in_picture_alt_rounded, '收起房间'),
      if (widget.isOnMic)
        const _ToolItem('leaveMic', Icons.mic_off_outlined, '主动下麦'),
      const _ToolItem('leaveRoom', Icons.logout_rounded, '离开房间'),
    ];
    final List<_ToolItem> visible = _tab == 0 ? interactions : tools;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SegmentedButton<int>(
            showSelectedIcon: false,
            segments: const <ButtonSegment<int>>[
              ButtonSegment<int>(value: 0, label: Text('互动')),
              ButtonSegment<int>(value: 1, label: Text('工具')),
            ],
            selected: <int>{_tab},
            onSelectionChanged: (Set<int> values) =>
                setState(() => _tab = values.first),
          ),
          const SizedBox(height: 18),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 16,
              crossAxisSpacing: 10,
              childAspectRatio: 0.82,
            ),
            itemCount: visible.length,
            itemBuilder: (BuildContext context, int index) {
              final _ToolItem item = visible[index];
              return InkWell(
                onTap: () => widget.onAction(item.action),
                borderRadius: BorderRadius.circular(18),
                child: Column(
                  children: <Widget>[
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Icon(
                        item.icon,
                        color: item.action == 'leaveRoom'
                            ? RoomColors.error
                            : RoomColors.primary,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(item.label, style: const TextStyle(fontSize: 11)),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ToolItem {
  const _ToolItem(this.action, this.icon, this.label);

  final String action;
  final IconData icon;
  final String label;
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Container(
          margin: const EdgeInsets.only(top: 58),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xF228294A),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(label, style: const TextStyle(color: RoomColors.warning)),
        ),
      ),
    );
  }
}

class _BlockingProgress extends StatelessWidget {
  const _BlockingProgress({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.55),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF181931),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const CircularProgressIndicator(),
              const SizedBox(height: 14),
              Text(label),
            ],
          ),
        ),
      ),
    );
  }
}
