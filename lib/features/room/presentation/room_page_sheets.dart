part of 'room_page.dart';

extension _RoomPageSheets on _RoomPageState {
  Future<void> _confirmLeave() async {
    if (_controller.status == RoomSessionStatus.leaving) {
      return;
    }
    final bool? shouldLeave = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('离开房间？'),
        content: Text(
          _controller.isOnMic
              ? '离开后将同时下麦，本次房间上下文不会保留。'
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
    await _controller.leaveRoom();
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
              '选择空闲麦位并提交申请。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
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
                                        : '麦位状态已变化，请重试',
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
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (BuildContext sheetContext) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('在线成员', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            for (final String member in <String>[
              '鹿屿 · 房主',
              '南风 · 麦上',
              '晚星 · 麦上',
              '白桃 · 听众',
              '小满 · 听众',
            ])
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(child: Icon(Icons.person_rounded)),
                title: Text(member),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(sheetContext).pop(),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showGiftSheet() async {
    final bool? sent = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (BuildContext context) => GiftSheet(
        balance: _controller.giftBalance,
        targets: _controller.seats
            .where((MicSeat seat) => seat.userName != null)
            .map((MicSeat seat) => seat.userName!)
            .toList(growable: false),
        onSend: (GiftSendRequest request) => _controller.sendGift(
          giftName: request.gift.name,
          targetName: request.target,
          unitPrice: request.gift.price,
          quantity: request.quantity,
        ),
      ),
    );
    if (!mounted || sent == null) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(sent ? '礼物已送出' : '赠送失败，请重试')),
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
            ListTile(
              leading: const Icon(Icons.network_check_rounded),
              title: const Text('模拟弱网恢复'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _controller.simulateReconnect();
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
}
