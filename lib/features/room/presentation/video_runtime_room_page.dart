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
import 'package:voice_social_app/features/room/pk/domain/room_pk_models.dart';
import 'package:voice_social_app/features/room/pk/presentation/room_pk_pages.dart';
import 'package:voice_social_app/features/room/presentation/gift_sheet.dart';
import 'package:voice_social_app/features/room/presentation/room_audio_page.dart';
import 'package:voice_social_app/features/room/presentation/room_diagnostics_page.dart';
import 'package:voice_social_app/features/room/presentation/room_management_page.dart';
import 'package:voice_social_app/features/room/presentation/room_members_page.dart';
import 'package:voice_social_app/features/room/presentation/room_recovery_page.dart';
import 'package:voice_social_app/features/room/presentation/room_share_page.dart';
import 'package:voice_social_app/features/room/presentation/room_topic_page.dart';
import 'package:voice_social_app/features/room/presentation/room_join_request_status_page.dart';
import 'package:voice_social_app/features/social/domain/social_models.dart';
import 'package:voice_social_app/features/social/presentation/social_pages.dart';

enum VideoRoomExit { minimized, ended }

class VideoRuntimeRoomPage extends StatefulWidget {
  const VideoRuntimeRoomPage({
    required this.controller,
    this.allowMinimize = true,
    this.entrySource = RoomEntrySource.home,
    super.key,
  });

  final RoomController controller;
  final bool allowMinimize;
  final RoomEntrySource entrySource;

  @override
  State<VideoRuntimeRoomPage> createState() => _VideoRuntimeRoomPageState();
}

class _VideoRuntimeRoomPageState extends State<VideoRuntimeRoomPage> {
  final TextEditingController _composer = TextEditingController();
  final FocusNode _composerFocus = FocusNode();
  final ScrollController _messageScroll = ScrollController();
  Timer? _giftTimer;
  bool _showGiftCelebration = false;
  String? _giftCelebrationGiftName;
  String? _giftCelebrationTargetName;
  bool _ending = false;
  bool _allowPop = false;
  String? _presentedError;

  RoomController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _composerFocus.addListener(_onComposerFocusChanged);
    _controller.addListener(_onControllerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (_controller.status == RoomSessionStatus.idle ||
          _controller.status == RoomSessionStatus.failed) {
        _controller.join(source: widget.entrySource);
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
        canPop: _allowPop,
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
    final bool approvalPending = _controller.pendingJoinRequestRoomId != null;
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
                  onPressed: () => _popRoom(VideoRoomExit.ended),
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
                  approvalPending ? '申请已提交，等待审核' : '暂时无法进入房间',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 10),
                Text(
                  approvalPending
                      ? '房主或房管处理后，你可以再次尝试进入。'
                      : (_controller.errorMessage ?? '请检查网络后重试。'),
                ),
                const SizedBox(height: 22),
                if (approvalPending)
                  FilledButton.icon(
                    onPressed: _openJoinRequestStatus,
                    icon: const Icon(Icons.assignment_turned_in_outlined),
                    label: const Text('查看申请状态'),
                  )
                else
                  FilledButton.icon(
                    onPressed: () =>
                        _controller.join(source: widget.entrySource),
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

  void _openJoinRequestStatus() {
    final String? pendingRoomId = _controller.pendingJoinRequestRoomId;
    if (pendingRoomId == null) {
      return;
    }
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => RoomJoinRequestStatusPage(
          roomId: pendingRoomId,
          joinRequestId: _controller.pendingJoinRequestId,
          roomTitle: _controller.displayTitle,
        ),
      ),
    );
  }

  Widget _roomContent() {
    final double keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final bool composing = keyboard > 0 || _composerFocus.hasFocus;
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
                        height: composing ? 176 : 218,
                        child: GridView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 7, 12, 0),
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 4,
                                mainAxisSpacing: 5,
                                crossAxisSpacing: 6,
                                childAspectRatio: 0.88,
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
                if (composing) ...<Widget>[
                  _replySuggestions(),
                  _composerBar(),
                ] else
                  _roomDock(),
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
                ? _GiftCelebrationOverlay(
                    key: const Key('gift-celebration-overlay'),
                    giftName: _giftCelebrationGiftName,
                    targetName: _giftCelebrationTargetName,
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }

  Widget _header() {
    final int? onlineCount = _controller.snapshot?.onlineCount;
    final List<MicSeat> occupiedSeats = _controller.seats
        .where(
          (MicSeat seat) =>
              seat.isOccupied &&
              seat.userId != null &&
              (seat.userName?.trim().isNotEmpty ?? false),
        )
        .take(2)
        .toList(growable: false);
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
                  style: const TextStyle(
                    color: RoomColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  onlineCount == null
                      ? '房间号 ${_controller.roomCode}'
                      : '房间号 ${_controller.roomCode} · $onlineCount 人在线',
                  style: const TextStyle(
                    color: RoomColors.textSecondary,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 55,
            height: 30,
            child: Stack(
              children: <Widget>[
                for (int index = 0; index < occupiedSeats.length; index += 1)
                  Positioned(
                    left: index * 19,
                    child: _RoomMemberAvatar(
                      avatarUrl: occupiedSeats[index].avatarUrl,
                      size: 30,
                    ),
                  ),
                if (occupiedSeats.isEmpty)
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: _UnavailableMemberAvatar(size: 30),
                  ),
                if (onlineCount != null)
                  Positioned(
                    right: 0,
                    top: 9,
                    child: Text(
                      '$onlineCount',
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
    final int? onlineCount = _controller.snapshot?.onlineCount;
    final String topic = _controller.topic.isEmpty
        ? '欢迎来到房间，请友善交流'
        : _controller.topic;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 1, 14, 0),
      child: Row(
        children: <Widget>[
          Flexible(
            child: _AnnouncementChip(
              icon: Icons.campaign_outlined,
              eyebrow: '今晚的话题',
              label: topic,
              onTap: _openTopic,
            ),
          ),
          if (onlineCount != null) ...<Widget>[
            const SizedBox(width: 7),
            _RoomHeatChip(onlineCount: onlineCount),
          ],
        ],
      ),
    );
  }

  Widget _publicScreen() {
    final List<RoomMessage> feedMessages =
        !_controller.allowsSyntheticPublicMessages
        ? _controller.messages
        : _controller.messages.length > 1
        ? _controller.messages
        : <RoomMessage>[
            for (final MicSeat seat
                in _controller.seats
                    .where((MicSeat seat) => seat.isOccupied)
                    .take(2))
              RoomMessage(
                sender: '麦位动态',
                content:
                    '${seat.userName ?? '${seat.number} 号麦'}${seat.isSpeaking ? ' 正在说话' : ' 已在麦上'}',
                isSystem: true,
              ),
            ..._controller.messages,
          ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool compactMoodStage = constraints.maxHeight < 420;
          return Column(
            key: const Key('video-room-public-screen'),
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Text(
                    '实时公屏',
                    style: TextStyle(
                      color: RoomColors.textPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const _RoomChannelTab(label: '全部'),
                  const _RoomChannelTab(label: '房间', selected: true),
                  const Spacer(),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: RoomColors.secondary.withValues(alpha: 0.74),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 6,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(Icons.forum_outlined, size: 14),
                          SizedBox(width: 4),
                          Text(
                            '房间动态',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              if (!compactMoodStage) ...<Widget>[
                _RoomMoodStage(topic: _controller.topic),
                const SizedBox(height: 4),
              ],
              Expanded(
                child: ListView.separated(
                  controller: _messageScroll,
                  padding: EdgeInsets.fromLTRB(
                    0,
                    compactMoodStage ? 0 : 7,
                    0,
                    10,
                  ),
                  itemCount: feedMessages.length + (compactMoodStage ? 1 : 0),
                  separatorBuilder: (_, __) => const SizedBox(height: 5),
                  itemBuilder: (BuildContext context, int index) {
                    if (compactMoodStage && index == 0) {
                      return _RoomMoodStage(
                        topic: _controller.topic,
                        compact: true,
                      );
                    }
                    final int messageIndex = index - (compactMoodStage ? 1 : 0);
                    final RoomMessage message = feedMessages[messageIndex];
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 344),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: message.isSystem
                              ? RoomColors.primary.withValues(alpha: 0.12)
                              : Colors.black.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(9),
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
                            fontSize: 11,
                            height: 1.3,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _roomDock() {
    final bool joined = _controller.status == RoomSessionStatus.joined;
    final bool canChat = joined && _controller.canSendPublicMessage;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 1, 10, 8),
        child: Row(
          children: <Widget>[
            _RoomDockPill(
              icon: _controller.isOnMic
                  ? (_controller.micMuted
                        ? Icons.mic_off_rounded
                        : Icons.mic_rounded)
                  : Icons.keyboard_voice_rounded,
              label: _controller.isOnMic
                  ? (_controller.micMuted ? '开麦' : '闭麦')
                  : '上麦',
              onTap: joined
                  ? (_controller.isOnMic ? _toggleMicrophone : _showMicSheet)
                  : null,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Container(
                height: 39,
                padding: const EdgeInsets.only(left: 2, right: 1),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.27),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.09),
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        key: const Key('video-room-composer'),
                        controller: _composer,
                        focusNode: _composerFocus,
                        enabled: canChat,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                        cursorColor: RoomColors.accent,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendMessage(),
                        decoration: InputDecoration(
                          filled: false,
                          hintText: canChat ? '聊聊天…' : '当前不可发言',
                          hintStyle: const TextStyle(
                            color: RoomColors.textSecondary,
                            fontSize: 11,
                          ),
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
                    IconButton(
                      key: const Key('room-expression-button'),
                      tooltip: '表情与贴图',
                      onPressed: canChat ? _showExpressionSheet : null,
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints.tightFor(
                        width: 34,
                        height: 34,
                      ),
                      padding: EdgeInsets.zero,
                      icon: const Icon(
                        Icons.sentiment_satisfied_alt_rounded,
                        color: RoomColors.textPrimary,
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 5),
            _RoomDockAction(
              icon: Icons.redeem_rounded,
              label: '礼物',
              highlighted: true,
              onTap: joined && _controller.allows(RoomCapability.sendGift)
                  ? _showGiftSheet
                  : null,
            ),
            _RoomDockAction(
              icon: Icons.groups_2_outlined,
              label: '成员',
              onTap: joined ? _openMembers : null,
            ),
            _RoomDockAction(
              icon: Icons.grid_view_rounded,
              label: '更多',
              onTap: joined ? _showMoreSheet : null,
            ),
          ],
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
    GiftSendRequest? sentRequest;
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
          onSend: (GiftSendRequest request) async {
            final bool sent = await _controller.sendGift(
              giftId: request.gift.id.toString(),
              giftName: request.gift.name,
              receiverUserId: request.target.userId,
              targetName: request.target.name,
              quantity: request.quantity,
            );
            if (sent) {
              sentRequest = request;
            }
            return sent;
          },
          onRechargeReturn: () async {
            await _controller.reconnect();
            return _controller.giftBalance;
          },
        ),
      ),
    );
    if (sent == true && mounted) {
      _giftTimer?.cancel();
      setState(() {
        _giftCelebrationGiftName = sentRequest?.gift.name;
        _giftCelebrationTargetName = sentRequest?.target.name;
        _showGiftCelebration = true;
      });
      _giftTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) {
          setState(() {
            _showGiftCelebration = false;
            _giftCelebrationGiftName = null;
            _giftCelebrationTargetName = null;
          });
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
        canManage: _controller.allows(RoomCapability.manageMembers),
        isOnMic: _controller.isOnMic,
        onAction: (String action) {
          Navigator.of(sheetContext).pop();
          switch (action) {
            case 'management':
              _openManagement();
              return;
            case 'members':
              _openMembers();
              return;
            case 'share':
              _openShare();
              return;
            case 'topic':
              _openTopic();
              return;
            case 'audio':
              _openAudio();
              return;
            case 'recovery':
              _openRecovery();
              return;
            case 'diagnostics':
              _openDiagnostics();
              return;
            case 'pk':
              _openPk();
              return;
            case 'report':
              _openReport();
              return;
            case 'copy':
              Clipboard.setData(ClipboardData(text: _controller.roomCode));
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('房间号已复制')));
              return;
            case 'minimize':
              _minimize();
              return;
            case 'leaveMic':
              _controller.leaveMic();
              return;
            case 'leaveRoom':
              _confirmEnd();
              return;
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
          roomTitle: snapshot.title,
        ),
      ),
    );
  }

  void _openManagement() {
    final RoomSnapshot? snapshot = _controller.snapshot;
    if (snapshot == null || !_controller.allows(RoomCapability.manageMembers)) {
      return;
    }
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => RoomManagementPage(
          roomId: snapshot.roomId,
          currentUserId: _controller.currentUserId,
          currentRole: snapshot.role,
          seats: snapshot.seats,
          roomTitle: snapshot.title,
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
          roomTitle: snapshot.title,
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
        builder: (BuildContext context) => RoomAudioPage(
          isOnMic: _controller.isOnMic,
          roomTitle: _controller.snapshot?.title,
        ),
      ),
    );
  }

  void _openRecovery() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => RoomRecoveryPage(
          controller: _controller,
          roomTitle: _controller.snapshot?.title,
        ),
      ),
    );
  }

  void _openDiagnostics() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => RoomDiagnosticsPage(
          controller: _controller,
          roomTitle: _controller.snapshot?.title,
        ),
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
    final RoomPkBattle? activePk = await _fetchActivePk();
    if (!mounted) {
      return;
    }
    if (activePk?.isActive == true) {
      await _confirmEnd(activePk: activePk);
      return;
    }
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
      _popRoom(VideoRoomExit.minimized);
    }
  }

  void _popRoom(VideoRoomExit result) {
    if (_allowPop || !mounted) {
      return;
    }
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Navigator.of(context).pop(result);
      }
    });
  }

  Future<RoomPkBattle?> _fetchActivePk() async {
    final RoomSnapshot? snapshot = _controller.snapshot;
    if (snapshot == null) {
      return null;
    }
    try {
      return await AppDependencyScope.of(
        context,
      ).roomPkRepository.fetchActiveBattle(roomId: snapshot.roomId);
    } catch (_) {
      // Optional PK status must never block leaving an otherwise valid room.
      return null;
    }
  }

  Future<void> _confirmEnd({RoomPkBattle? activePk}) async {
    activePk ??= await _fetchActivePk();
    if (!mounted) {
      return;
    }
    final String content = activePk?.isActive == true
        ? '当前房间正在 PK。离开可能被服务端视为主动结束或认输；如果你在麦上，也会同时下麦并结束本次房间会话。'
        : _controller.isOnMic
        ? '离开后将同时下麦，并结束本次房间会话。'
        : '确认结束本次收听？';
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('离开房间？'),
        content: Text(content),
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
    _popRoom(VideoRoomExit.ended);
  }
}

class _AnnouncementChip extends StatelessWidget {
  const _AnnouncementChip({
    required this.icon,
    required this.label,
    this.eyebrow,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String? eyebrow;
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
            if (eyebrow != null) ...<Widget>[
              Text(
                eyebrow!,
                style: const TextStyle(
                  color: RoomColors.textPrimary,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 6),
            ],
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

class _RoomHeatChip extends StatelessWidget {
  const _RoomHeatChip({required this.onlineCount});

  final int onlineCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.people_outline_rounded, size: 13, color: RoomColors.gold),
          SizedBox(width: 3),
          Text(
            '$onlineCount',
            style: TextStyle(
              color: RoomColors.textSecondary,
              fontSize: 9,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _RoomChannelTab extends StatelessWidget {
  const _RoomChannelTab({required this.label, this.selected = false});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : RoomColors.textSecondary,
              fontSize: 12,
              fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: selected ? 20 : 0,
            height: 2,
            decoration: BoxDecoration(
              color: RoomColors.primary,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoomMoodStage extends StatelessWidget {
  const _RoomMoodStage({required this.topic, this.compact = false});

  final String topic;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Container(
        key: const Key('video-room-mood-stage-compact'),
        height: 72,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[Color(0x9E351341), Color(0x6E17132D)],
          ),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: RoomColors.primary.withValues(alpha: 0.09)),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: RoomColors.primary.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.graphic_eq_rounded,
                color: RoomColors.accent,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    '深夜放映中 · 绿色聊天',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: RoomColors.accent,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    topic.isEmpty ? '把今天的疲惫放在门外' : topic,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: RoomColors.textPrimary,
                      fontSize: 10,
                      height: 1.25,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const RuntimeWaveform(width: 30),
          ],
        ),
      );
    }
    return Column(
      key: const Key('video-room-mood-stage-standard'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          decoration: BoxDecoration(
            color: RoomColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(9),
          ),
          child: const Text(
            '温馨提示：请大家绿色聊天、友好互动，保护好个人信息。',
            style: TextStyle(
              color: RoomColors.accent,
              fontSize: 10,
              height: 1.35,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Container(
          height: 168,
          width: 258,
          padding: const EdgeInsets.fromLTRB(15, 10, 14, 10),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[Color(0x9E351341), Color(0x6E17132D)],
            ),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: RoomColors.primary.withValues(alpha: 0.09),
            ),
          ),
          child: Stack(
            children: <Widget>[
              Positioned(
                right: -6,
                top: 5,
                child: Icon(
                  Icons.music_note_rounded,
                  size: 56,
                  color: RoomColors.accent.withValues(alpha: 0.04),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Row(
                    children: <Widget>[
                      Icon(
                        Icons.graphic_eq_rounded,
                        color: RoomColors.accent,
                        size: 12,
                      ),
                      SizedBox(width: 5),
                      Text(
                        '深夜放映中',
                        style: TextStyle(
                          color: RoomColors.accent,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Spacer(),
                      RuntimeWaveform(width: 30),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    topic.isEmpty ? '把今天的疲惫放在门外' : topic,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: RoomColors.accent,
                      fontSize: 11,
                      height: 1.35,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    '静静听一会儿，也可以开麦聊聊\n愿每一次相遇都被温柔接住',
                    style: TextStyle(
                      color: Color(0xFFAFC7FF),
                      fontSize: 9,
                      height: 1.5,
                    ),
                  ),
                  const Spacer(),
                  const Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      '房间心愿墙',
                      style: TextStyle(
                        color: RoomColors.textSecondary,
                        fontSize: 8,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _VideoRoomBackground extends StatelessWidget {
  const _VideoRoomBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        const ColoredBox(color: Color(0xFF16051F)),
        Opacity(
          opacity: 0.34,
          child: Image.asset(
            'assets/runtime/room-cosmos.png',
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            color: const Color(0xFF4A123E),
            colorBlendMode: BlendMode.multiply,
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                Color(0x5C350839),
                Color(0xB02C073A),
                Color(0xF20B0918),
              ],
              stops: <double>[0, 0.54, 1],
            ),
          ),
        ),
      ],
    );
  }
}

class _RoomMemberAvatar extends StatelessWidget {
  const _RoomMemberAvatar({
    required this.avatarUrl,
    required this.size,
    this.ringColor,
  });

  final String? avatarUrl;
  final double size;
  final Color? ringColor;

  @override
  Widget build(BuildContext context) {
    final String? normalizedUrl = avatarUrl?.trim();
    final bool isAllowlistedAsset =
        normalizedUrl != null &&
        _allowlistedAvatarAssets.contains(normalizedUrl);
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isAllowlistedAsset ? null : Colors.white.withValues(alpha: 0.08),
        border: Border.all(
          color: ringColor ?? Colors.white.withValues(alpha: 0.8),
          width: 2,
        ),
      ),
      child: ClipOval(
        child: normalizedUrl == null || normalizedUrl.isEmpty
            ? const _UnavailableMemberAvatar()
            : isAllowlistedAsset
            ? Image.asset(
                normalizedUrl,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                errorBuilder: (_, __, ___) => const _UnavailableMemberAvatar(),
              )
            : Image.network(
                normalizedUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const _UnavailableMemberAvatar(),
              ),
      ),
    );
  }
}

const Set<String> _allowlistedAvatarAssets = <String>{
  'assets/runtime/avatar-copper.png',
  'assets/runtime/avatar-night.png',
  'assets/runtime/avatar-rose.png',
  'assets/runtime/avatar-silver.png',
};

class _UnavailableMemberAvatar extends StatelessWidget {
  const _UnavailableMemberAvatar({this.size = 44});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.white.withValues(alpha: 0.08),
      child: Center(
        child: Icon(
          Icons.person_outline_rounded,
          size: size * 0.52,
          color: RoomColors.textSecondary,
        ),
      ),
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
    final double seatSize = dense ? 44 : 56;
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
                  _RoomMemberAvatar(
                    avatarUrl: seat.avatarUrl,
                    size: dense ? 40 : 52,
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
                      width: dense ? 16 : 20,
                      height: dense ? 16 : 20,
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
                        size: dense ? 9 : 11,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(height: dense ? 2 : 5),
          Text(
            seat.userName ?? '${seat.number} 号麦',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: RoomColors.textPrimary,
              fontSize: dense ? 9 : 10,
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
              fontSize: dense ? 7 : 8,
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

class _RoomDockPill extends StatelessWidget {
  const _RoomDockPill({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: onTap == null ? 0.12 : 0.28),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: SizedBox(
          height: 39,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(icon, size: 15, color: RoomColors.textPrimary),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: const TextStyle(
                    color: RoomColors.textPrimary,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoomDockAction extends StatelessWidget {
  const _RoomDockAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        enabled: onTap != null,
        label: label,
        child: InkResponse(
          onTap: onTap,
          radius: 24,
          child: SizedBox(
            width: 41,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: highlighted && onTap != null
                        ? const LinearGradient(
                            colors: <Color>[
                              RoomColors.accent,
                              RoomColors.primary,
                            ],
                          )
                        : null,
                    color: highlighted
                        ? null
                        : Colors.black.withValues(
                            alpha: onTap == null ? 0.12 : 0.3,
                          ),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Icon(
                    icon,
                    size: 18,
                    color: onTap == null ? Colors.white30 : Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    color: onTap == null
                        ? Colors.white30
                        : RoomColors.textSecondary,
                    fontSize: 8,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GiftCelebrationOverlay extends StatelessWidget {
  const _GiftCelebrationOverlay({
    required this.giftName,
    required this.targetName,
    super.key,
  });

  final String? giftName;
  final String? targetName;

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
              Padding(
                padding: EdgeInsets.fromLTRB(18, 0, 120, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Text(
                      giftName == null || giftName!.trim().isEmpty
                          ? '礼物已送达'
                          : '${giftName!.trim()} 已送达',
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
                      targetName == null || targetName!.trim().isEmpty
                          ? '为房间点亮一份惊喜'
                          : '送给 ${targetName!.trim()} · 为房间点亮一份惊喜',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
              _RoomSheetTab(
                label: '表情',
                selected: _tab == 0,
                onTap: () => setState(() => _tab = 0),
              ),
              const SizedBox(width: 20),
              _RoomSheetTab(
                label: '贴图',
                selected: _tab == 1,
                onTap: () => setState(() => _tab = 1),
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
                      color: Colors.white.withValues(alpha: 0.035),
                      borderRadius: BorderRadius.circular(14),
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
    required this.canManage,
    required this.isOnMic,
    required this.onAction,
  });

  final bool canPk;
  final bool canManage;
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
      if (widget.canManage)
        const _ToolItem(
          'management',
          Icons.admin_panel_settings_outlined,
          '房管',
        ),
      const _ToolItem('members', Icons.groups_2_outlined, '成员'),
      const _ToolItem('share', Icons.ios_share_rounded, '分享'),
      const _ToolItem('topic', Icons.campaign_outlined, '公告'),
      if (widget.canPk)
        const _ToolItem('pk', Icons.sports_kabaddi_rounded, '房间 PK'),
      const _ToolItem('copy', Icons.copy_rounded, '复制房间号'),
      const _ToolItem('report', Icons.report_outlined, '举报房间'),
    ];
    final List<_ToolItem> tools = <_ToolItem>[
      const _ToolItem('audio', Icons.volume_up_outlined, '音频'),
      const _ToolItem('recovery', Icons.sync_rounded, '重新连接'),
      const _ToolItem('diagnostics', Icons.monitor_heart_outlined, '质量诊断'),
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
          Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              _RoomSheetTab(
                label: '互动玩法',
                selected: _tab == 0,
                onTap: () => setState(() => _tab = 0),
              ),
              const SizedBox(width: 24),
              _RoomSheetTab(
                label: '工具',
                selected: _tab == 1,
                onTap: () => setState(() => _tab = 1),
              ),
              const Spacer(),
              const Text(
                '房间功能',
                style: TextStyle(color: RoomColors.textSecondary, fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 16),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 14,
              crossAxisSpacing: 10,
              childAspectRatio: 0.9,
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
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.085),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.055),
                        ),
                      ),
                      child: Icon(
                        item.icon,
                        color: item.action == 'leaveRoom'
                            ? RoomColors.error
                            : RoomColors.textPrimary,
                        size: 22,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.label,
                      style: const TextStyle(
                        color: RoomColors.textSecondary,
                        fontSize: 10,
                      ),
                    ),
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

class _RoomSheetTab extends StatelessWidget {
  const _RoomSheetTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : RoomColors.textSecondary,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
              ),
            ),
            const SizedBox(height: 5),
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: selected ? 24 : 0,
              height: 2,
              decoration: BoxDecoration(
                color: RoomColors.primary,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ],
        ),
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
