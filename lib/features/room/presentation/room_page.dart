import 'package:flutter/material.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/features/room/application/room_controller.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/domain/room_operations_models.dart';
import 'package:voice_social_app/features/room/domain/room_operations_repository.dart';
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
import 'package:voice_social_app/features/social/domain/social_models.dart';
import 'package:voice_social_app/features/social/presentation/social_pages.dart';

part 'room_page_sheets.dart';
part 'room_widgets.dart';

class RoomPage extends StatefulWidget {
  const RoomPage({
    required this.roomId,
    required this.title,
    this.entrySource = RoomEntrySource.home,
    super.key,
  });

  final String roomId;
  final String title;
  final RoomEntrySource entrySource;

  @override
  State<RoomPage> createState() => _RoomPageState();
}

class _RoomPageState extends State<RoomPage> {
  RoomController? _controllerInstance;
  RoomController get _controller => _controllerInstance!;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _messageScrollController = ScrollController();
  bool _allowPop = false;
  String? _presentedError;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controllerInstance != null) {
      return;
    }
    _controllerInstance = AppDependencyScope.of(context).createRoomController(
      roomId: widget.roomId,
      title: widget.title,
    )..addListener(_handleControllerUpdate);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _controller.join(source: widget.entrySource);
      }
    });
  }

  @override
  void dispose() {
    final RoomController? controller = _controllerInstance;
    if (controller != null) {
      controller
        ..removeListener(_handleControllerUpdate)
        ..dispose();
    }
    _messageController.dispose();
    _messageScrollController.dispose();
    super.dispose();
  }

  void _handleControllerUpdate() {
    if (!mounted) {
      return;
    }
    setState(() {});
    final String? error = _controller.errorMessage;
    if (error != null &&
        error != _presentedError &&
        _controller.status == RoomSessionStatus.joined) {
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
      if (_messageScrollController.hasClients) {
        _messageScrollController.animateTo(
          _messageScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: _allowPop,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop && !_allowPop) {
          _confirmLeave();
        }
      },
      child: Scaffold(
        body: switch (_controller.status) {
          RoomSessionStatus.idle ||
          RoomSessionStatus.joining => _buildJoiningState(),
          RoomSessionStatus.failed when _controller.snapshot == null =>
            _buildJoinFailure(),
          _ => _buildRoomContent(),
        },
      ),
    );
  }

  Widget _buildJoiningState() {
    return Stack(
      children: <Widget>[
        const _RoomBackground(),
        SafeArea(
          child: Column(
            children: <Widget>[
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  tooltip: '离开房间',
                  onPressed: _confirmLeave,
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
              const Spacer(),
              const CircularProgressIndicator(),
              const SizedBox(height: 18),
              Text('正在进入房间…', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text('正在获取房间状态', style: Theme.of(context).textTheme.bodySmall),
              const Spacer(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildJoinFailure() {
    return Stack(
      children: <Widget>[
        const _RoomBackground(),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                IconButton(
                  tooltip: '返回首页',
                  onPressed: _exitWithoutSession,
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                const Spacer(),
                const Icon(
                  Icons.wifi_off_rounded,
                  size: 44,
                  color: AppColors.warning,
                ),
                const SizedBox(height: 20),
                Text(
                  '暂时无法进入房间',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 10),
                Text(
                  _controller.errorMessage ?? '请检查网络后重试。',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => _controller.join(source: widget.entrySource),
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

  Widget _buildRoomContent() {
    return Stack(
      children: <Widget>[
        const _RoomBackground(),
        SafeArea(
          child: Column(
            children: <Widget>[
              _buildHeader(),
              _buildTopic(),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                  children: <Widget>[
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 4,
                            mainAxisSpacing: 16,
                            crossAxisSpacing: 8,
                            mainAxisExtent: 106,
                          ),
                      itemCount: _controller.seats.length,
                      itemBuilder: (BuildContext context, int index) {
                        return _MicSeatTile(seat: _controller.seats[index]);
                      },
                    ),
                    const SizedBox(height: 10),
                    _buildPublicScreen(),
                  ],
                ),
              ),
              _buildComposer(),
              _buildActions(),
            ],
          ),
        ),
        if (_controller.realtimeDegraded &&
            _controller.status == RoomSessionStatus.joined)
          const _StatusBanner(label: '实时状态可能延迟，可在“更多”中重新连接'),
        if (_controller.status == RoomSessionStatus.reconnecting)
          const _StatusBanner(label: '网络波动，正在恢复连接…'),
        if (_controller.status == RoomSessionStatus.leaving)
          const _BlockingProgress(label: '正在离开房间…'),
        if (_controller.status == RoomSessionStatus.kicked ||
            _controller.status == RoomSessionStatus.closed)
          _RemoteExitOverlay(
            title: _controller.status == RoomSessionStatus.kicked
                ? '已被移出房间'
                : '房间已不可用',
            message: _controller.errorMessage ?? '本次房间会话已经结束。',
            onExit: _exitWithoutSession,
          ),
      ],
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 12, 6),
      child: Row(
        children: <Widget>[
          IconButton(
            tooltip: '离开房间',
            onPressed: _confirmLeave,
            icon: const Icon(Icons.close_rounded),
          ),
          const SizedBox(width: 4),
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
                      ? '房间号 ${_controller.roomCode} · 在线人数更新中'
                      : '房间号 ${_controller.roomCode} · ${_controller.snapshot!.onlineCount} 人在线',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '分享房间',
            onPressed: _openSharePage,
            icon: const Icon(Icons.ios_share_rounded),
          ),
          IconButton(
            tooltip: '更多',
            onPressed: _showMoreSheet,
            icon: const Icon(Icons.more_horiz_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildTopic() {
    final String topic = _controller.topic.isEmpty
        ? '房间暂未设置当前话题'
        : _controller.topic;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _openTopicPage,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Row(
            children: <Widget>[
              const Icon(
                Icons.graphic_eq_rounded,
                size: 18,
                color: AppColors.accent,
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(topic)),
              const Icon(Icons.chevron_right_rounded, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPublicScreen() {
    return Container(
      height: 210,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xB20D1020),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text('实时公屏', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              Text('仅显示进房后的消息', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.separated(
              controller: _messageScrollController,
              itemCount: _controller.messages.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (BuildContext context, int index) {
                final RoomMessage message = _controller.messages[index];
                return Text.rich(
                  TextSpan(
                    children: <InlineSpan>[
                      TextSpan(
                        text: '${message.sender}  ',
                        style: TextStyle(
                          color: message.isSystem
                              ? AppColors.warning
                              : AppColors.accent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      TextSpan(text: message.content),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComposer() {
    final bool enabled =
        _controller.status == RoomSessionStatus.joined &&
        _controller.canSendPublicMessage;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: _messageController,
              enabled: enabled,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendMessage(),
              decoration: InputDecoration(
                hintText: enabled ? '说点什么…' : '当前不可发送公屏消息',
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            tooltip: '发送',
            onPressed: enabled ? _sendMessage : null,
            icon: const Icon(Icons.arrow_upward_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    final bool joined = _controller.status == RoomSessionStatus.joined;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
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
                  : '申请上麦',
              enabled:
                  joined &&
                  (_controller.isOnMic
                      ? _controller.allows(RoomCapability.toggleMicrophone)
                      : _controller.allows(RoomCapability.requestMic)),
              onTap: _controller.isOnMic
                  ? _toggleMicrophone
                  : _showMicRequestSheet,
            ),
            _RoomAction(
              icon: Icons.groups_2_rounded,
              label: '成员',
              enabled: joined,
              onTap: _openMembersPage,
            ),
            _RoomAction(
              icon: Icons.redeem_rounded,
              label: '礼物',
              enabled: joined && _controller.allows(RoomCapability.sendGift),
              onTap: _showGiftSheet,
            ),
            _RoomAction(
              icon: Icons.tune_rounded,
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
    final String content = _messageController.text;
    final bool sent = await _controller.sendPublicMessage(content);
    if (sent) {
      _messageController.clear();
    }
  }

  Future<void> _toggleMicrophone() async {
    final bool updated = await _controller.toggleMicrophone();
    if (!mounted || updated) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('麦克风状态更新失败，请重试')));
  }

  void _exitWithoutSession() {
    if (_allowPop) {
      return;
    }
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  void _openRoomReportPage() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => ReportPage(
          targetType: ReportTargetType.room,
          targetId: widget.roomId,
          targetName: widget.title,
        ),
      ),
    );
  }
}
