part of 'room_page.dart';

extension _RoomPageSheets on _RoomPageState {
  Future<void> _confirmLeave() async {
    if (_controller.status == RoomSessionStatus.leaving) {
      return;
    }
    final Route<dynamic>? roomRoute = ModalRoute.of(context);
    if (_controller.status == RoomSessionStatus.failed &&
        _controller.snapshot == null) {
      _removeRoomRoute(roomRoute);
      return;
    }

    final bool? shouldLeave = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('离开房间？'),
        content: Text(
          _controller.isOnMic
              ? '离开后将同时下麦，并结束本次房间会话。'
              : '确认结束本次收听并返回首页？',
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
    if (shouldLeave != true || !mounted) {
      return;
    }
    final bool left = await _controller.leaveRoom();
    if (!mounted) {
      return;
    }
    if (!left) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_controller.errorMessage ?? '离开房间失败，请重试'),
        ),
      );
      return;
    }
    _removeRoomRoute(roomRoute);
  }

  Future<void> _showMicRequestSheet() async {
    final List<MicSeat> available = _controller.seats
        .where((MicSeat seat) => seat.isAvailable)
        .toList(growable: false);
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (BuildContext sheetContext) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('选择麦位', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              '只可选择当前空闲且未锁定的麦位。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            if (available.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Text('当前没有可申请的麦位'),
              )
            else
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: available
                    .map(
                      (MicSeat seat) => FilledButton.tonal(
                        onPressed: _controller.micRequestPending
                            ? null
                            : () async {
                                Navigator.of(sheetContext).pop();
                                final bool accepted =
                                    await _controller.requestMic(seat.number);
                                if (!mounted) {
                                  return;
                                }
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      accepted
                                          ? '已上 ${seat.number} 号麦'
                                          : _controller.errorMessage ??
                                              '麦位状态已变化，请重试',
                                    ),
                                  ),
                                );
                              },
                        child: Text('${seat.number} 号麦'),
                      ),
                    )
                    .toList(growable: false),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showMembersSheet() async {
    final List<MicSeat> occupied = _controller.seats
        .where((MicSeat seat) => seat.isOccupied && seat.userName != null)
        .toList(growable: false);
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (BuildContext sheetContext) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text('在线成员', style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                Text(
                  '麦上 ${occupied.length} 人',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (occupied.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Text('当前麦上暂无用户'),
              )
            else
              for (final MicSeat seat in occupied)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    child: Text('${seat.number}'),
                  ),
                  title: Text(seat.userName!),
                  subtitle: Text(_roleLabel(seat.userRole)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(sheetContext).pop(),
                ),
            const SizedBox(height: 8),
            Text(
              '可在成员页查看完整听众席；房主和房管可进行成员管理。',
              style: Theme.of(context).textTheme.bodySmall,
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
              seat.userId != _controller.currentUserId &&
              seat.userName != null,
        )
        .map(
          (MicSeat seat) => GiftTarget(
            userId: seat.userId!,
            name: seat.userName!,
          ),
        )
        .toList(growable: false);

    final bool? sent = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (BuildContext context) => GiftSheet(
        balance: _controller.giftBalance,
        targets: targets,
        onSend: (GiftSendRequest request) => _controller.sendGift(
          giftId: request.gift.id,
          giftName: request.gift.name,
          receiverUserId: request.target.userId,
          targetName: request.target.name,
          quantity: request.quantity,
        ),
      ),
    );
    if (!mounted || sent != true) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('礼物已送出')),
    );
  }

  Future<void> _showMoreSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (BuildContext sheetContext) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (_controller.isOnMic)
              ListTile(
                leading: const Icon(Icons.keyboard_voice_outlined),
                title: const Text('主动下麦'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  final bool left = await _controller.leaveMic();
                  if (!mounted) {
                    return;
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(left ? '已离开麦位' : '下麦失败，请重试'),
                    ),
                  );
                },
              ),
            ListTile(
              leading: const Icon(Icons.volume_up_rounded),
              title: const Text('音频与麦克风'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _openScopedPage(
                  pageId: 'RM-010',
                  title: '音频与麦克风',
                  description: '管理扬声器、听筒、蓝牙、耳机与麦克风。',
                );
              },
            ),
            if (_controller.realtimeDegraded)
              ListTile(
                leading: const Icon(Icons.refresh_rounded),
                title: const Text('重新连接房间'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _controller.reconnect();
                },
              ),
            ListTile(
              leading: const Icon(Icons.monitor_heart_rounded),
              title: const Text('房间质量诊断'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _openScopedPage(
                  pageId: 'RM-012',
                  title: '房间质量诊断',
                  description: '检查网络、延迟、丢包与音频设备状态。',
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.report_outlined),
              title: const Text('举报房间'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _openScopedPage(
                  pageId: 'US-008',
                  title: '举报房间',
                  description: '选择举报原因并补充必要说明。',
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _removeRoomRoute(Route<dynamic>? roomRoute) {
    if (!mounted) {
      return;
    }
    if (roomRoute == null) {
      _exitWithoutSession();
      return;
    }
    _allowPop = true;
    Navigator.of(context).removeRoute(roomRoute);
  }

  static String _roleLabel(RoomRole role) {
    return switch (role) {
      RoomRole.owner => '房主',
      RoomRole.moderator => '房管',
      RoomRole.platformModerator => '平台管理',
      RoomRole.speaker => '麦上用户',
      RoomRole.guest || RoomRole.listener => '房间成员',
    };
  }
}
