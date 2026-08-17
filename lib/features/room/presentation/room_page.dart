import 'package:flutter/material.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/features/room/application/room_controller.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/presentation/gift_sheet.dart';
import 'package:voice_social_app/shared/widgets/scoped_placeholder_page.dart';

part 'room_page_sheets.dart';
part 'room_widgets.dart';

class RoomPage extends StatefulWidget {
  const RoomPage({
    required this.roomId,
    required this.title,
    super.key,
  });

  final String roomId;
  final String title;

  @override
  State<RoomPage> createState() => _RoomPageState();
}

class _RoomPageState extends State<RoomPage> {
  late final RoomController _controller;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _messageScrollController = ScrollController();
  bool _allowPop = false;

  @override
  void initState() {
    super.initState();
    _controller = RoomController(roomId: widget.roomId, title: widget.title)
      ..addListener(_handleControllerUpdate);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_handleControllerUpdate)
      ..dispose();
    _messageController.dispose();
    _messageScrollController.dispose();
    super.dispose();
  }

  void _handleControllerUpdate() {
    if (!mounted) {
      return;
    }
    setState(() {});
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

  void _finishLeavingRoom() {
    if (!mounted) {
      return;
    }
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Navigator.of(context).pop();
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
        body: Stack(
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
                            childAspectRatio: 0.76,
                          ),
                          itemCount: _controller.seats.length,
                          itemBuilder: (BuildContext context, int index) {
                            return _MicSeatTile(
                              seat: _controller.seats[index],
                            );
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
            if (_controller.status == RoomSessionStatus.reconnecting)
              const _StatusBanner(label: '网络波动，正在恢复连接…'),
            if (_controller.status == RoomSessionStatus.leaving)
              const _BlockingProgress(label: '正在离开房间…'),
          ],
        ),
      ),
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
                  _controller.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  '房间号 ${_controller.roomId} · 36 人在线',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '分享房间',
            onPressed: () => _openScopedPage(
              pageId: 'RM-009',
              title: '房间分享',
              description: '选择分享方式，或复制房间号邀请好友。',
            ),
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
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: const Row(
        children: <Widget>[
          Icon(Icons.graphic_eq_rounded, size: 18, color: AppColors.accent),
          SizedBox(width: 8),
          Expanded(child: Text('今晚话题：最近让你觉得被治愈的一件小事')),
        ],
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
              Text(
                '仅显示进房后的消息',
                style: Theme.of(context).textTheme.bodySmall,
              ),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: _messageController,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendMessage(),
              decoration: const InputDecoration(
                hintText: '说点什么…',
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            tooltip: '发送',
            onPressed: _sendMessage,
            icon: const Icon(Icons.arrow_upward_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
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
              onTap: _controller.isOnMic
                  ? _controller.toggleMicrophone
                  : _showMicRequestSheet,
            ),
            _RoomAction(
              icon: Icons.groups_2_rounded,
              label: '成员',
              onTap: _showMembersSheet,
            ),
            _RoomAction(
              icon: Icons.redeem_rounded,
              label: '礼物',
              onTap: _showGiftSheet,
            ),
            _RoomAction(
              icon: Icons.tune_rounded,
              label: '更多',
              onTap: _showMoreSheet,
            ),
          ],
        ),
      ),
    );
  }

  void _sendMessage() {
    _controller.sendPublicMessage(_messageController.text);
    _messageController.clear();
  }

  void _openScopedPage({
    required String pageId,
    required String title,
    required String description,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => ScopedPlaceholderPage(
          pageId: pageId,
          title: title,
          description: description,
        ),
      ),
    );
  }
}
