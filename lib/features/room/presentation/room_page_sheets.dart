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

    RoomPkBattle? activePk;
    final RoomSnapshot? snapshot = _controller.snapshot;
    if (snapshot != null) {
      try {
        activePk = await AppDependencyScope.of(
          context,
        ).roomPkRepository.fetchActiveBattle(roomId: snapshot.roomId);
      } catch (_) {
        // Leaving the room must remain possible even if the optional PK status
        // check is temporarily unavailable.
      }
    }
    if (!mounted) {
      return;
    }

    final String content = activePk?.isActive == true
        ? '当前房间正在 PK。离开可能被服务端视为主动结束或认输；如果你在麦上，也会同时下麦并结束本次房间会话。'
        : _controller.isOnMic
        ? '离开后将同时下麦，并结束本次房间会话。'
        : '确认结束本次收听并返回首页？';
    final bool? shouldLeave = await showDialog<bool>(
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
    if (shouldLeave != true || !mounted) {
      return;
    }

    var transportCleanupTimedOut = false;
    final bool left = await _controller.leaveRoom().timeout(
      const Duration(milliseconds: 1500),
      onTimeout: () {
        transportCleanupTimedOut = true;
        return true;
      },
    );
    if (!mounted) {
      return;
    }
    if (!left) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_controller.errorMessage ?? '离开房间失败，请重试')),
      );
      return;
    }
    if (transportCleanupTimedOut) {
      _allowPop = true;
    }
    _removeRoomRoute(roomRoute);
  }

  Future<void> _showMicRequestSheet() async {
    final RoomSnapshot? snapshot = _controller.snapshot;
    if (snapshot == null) {
      return;
    }
    final RoomOperationsRepository operations = AppDependencyScope.of(
      context,
    ).roomOperationsRepository;
    final List<MicSeat> available = _controller.seats
        .where((MicSeat seat) => seat.isAvailable)
        .toList(growable: false);
    MicAccessRequest? pending;
    if (operations.micCoordinationMode == MicCoordinationMode.approval) {
      final List<MicAccessRequest> requests = await operations.fetchMicRequests(
        snapshot.roomId,
      );
      for (final MicAccessRequest request in requests) {
        if (request.member.userId == _controller.currentUserId &&
            request.status == MicRequestStatus.pending) {
          pending = request;
          break;
        }
      }
    }
    if (!mounted) {
      return;
    }

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
              operations.micCoordinationMode == MicCoordinationMode.approval
                  ? '提交后等待房主或房管处理，麦位变化以服务端权威状态为准。'
                  : '当前普通房为直接上麦模式，只可选择空闲且未锁定的麦位。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            if (pending != null) ...<Widget>[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.hourglass_top_rounded),
                title: Text('已申请 ${pending.seatNumber} 号麦'),
                subtitle: const Text('等待房主或房管处理'),
              ),
              FilledButton.tonal(
                onPressed: () async {
                  await operations.cancelMicRequest(requestId: pending!.id);
                  if (!sheetContext.mounted) {
                    return;
                  }
                  Navigator.of(sheetContext).pop();
                  if (mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('上麦申请已取消')));
                  }
                },
                child: const Text('取消申请'),
              ),
            ] else if (available.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Text('当前没有可申请的麦位'),
              )
            else
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: <Widget>[
                  for (final MicSeat seat in available)
                    FilledButton.tonal(
                      onPressed: _controller.micRequestPending
                          ? null
                          : () async {
                              Navigator.of(sheetContext).pop();
                              if (operations.micCoordinationMode ==
                                  MicCoordinationMode.approval) {
                                await operations.submitMicRequest(
                                  roomId: snapshot.roomId,
                                  userId: _controller.currentUserId,
                                  seatNumber: seat.number,
                                );
                                if (!mounted) {
                                  return;
                                }
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      '已提交 ${seat.number} 号麦申请，等待处理',
                                    ),
                                  ),
                                );
                                return;
                              }
                              final bool accepted = await _controller
                                  .requestMic(seat.number);
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
                ],
              ),
            if (operations.micCoordinationMode ==
                MicCoordinationMode.unavailable) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                '当前房间未配置可用的上麦协议。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openMembersPage() async {
    final RoomSnapshot? snapshot = _controller.snapshot;
    if (snapshot == null) {
      return;
    }
    await Navigator.of(context).push<void>(
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

  Future<void> _openManagementPage() async {
    final RoomSnapshot? snapshot = _controller.snapshot;
    if (snapshot == null || !_controller.allows(RoomCapability.manageMembers)) {
      return;
    }
    final bool? changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext context) => RoomManagementPage(
          roomId: snapshot.roomId,
          currentUserId: _controller.currentUserId,
          currentRole: snapshot.role,
          seats: snapshot.seats,
        ),
      ),
    );
    if (changed == true && mounted) {
      await _controller.reconnect();
    }
  }

  Future<void> _openTopicPage() async {
    final RoomSnapshot? snapshot = _controller.snapshot;
    if (snapshot == null) {
      return;
    }
    final RoomTopic? authoritative = await Navigator.of(context)
        .push<RoomTopic>(
          MaterialPageRoute<RoomTopic>(
            builder: (BuildContext context) => RoomTopicPage(
              roomId: snapshot.roomId,
              canEdit: _controller.allows(RoomCapability.editRoom),
            ),
          ),
        );
    if (authoritative != null && mounted) {
      _controller.applyAuthoritativeTopic(authoritative.content);
    }
  }

  void _openSharePage() {
    final RoomSnapshot? snapshot = _controller.snapshot;
    if (snapshot == null) {
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => RoomSharePage(
          roomId: snapshot.roomId,
          roomCode: snapshot.roomCode,
          roomTitle: snapshot.title,
        ),
      ),
    );
  }

  void _openAudioPage() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            RoomAudioPage(isOnMic: _controller.isOnMic),
      ),
    );
  }

  void _openRecoveryPage() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            RoomRecoveryPage(controller: _controller),
      ),
    );
  }

  void _openDiagnosticsPage() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            RoomDiagnosticsPage(controller: _controller),
      ),
    );
  }

  void _openPkPage() {
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
      backgroundColor: RoomColors.surface,
      builder: (BuildContext context) => GiftSheet(
        balance: _controller.giftBalance,
        account: account,
        targets: targets,
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
    );
    if (!mounted || sent != true) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('礼物已送出')));
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
            if (_controller.allows(RoomCapability.manageMembers))
              ListTile(
                leading: const Icon(Icons.admin_panel_settings_outlined),
                title: const Text('房间管理'),
                subtitle: const Text('成员治理、麦位管理和上麦申请'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _openManagementPage();
                },
              ),
            if (_controller.allows(RoomCapability.startPk))
              ListTile(
                leading: const Icon(Icons.sports_kabaddi_rounded),
                title: const Text('房间 PK'),
                subtitle: const Text('邀请、准备、对战比分和服务端结算'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _openPkPage();
                },
              ),
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
                    SnackBar(content: Text(left ? '已离开麦位' : '下麦失败，请重试')),
                  );
                },
              ),
            ListTile(
              leading: const Icon(Icons.volume_up_rounded),
              title: const Text('音频与麦克风'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _openAudioPage();
              },
            ),
            ListTile(
              leading: const Icon(Icons.sync_rounded),
              title: const Text('弱网重连与会话恢复'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _openRecoveryPage();
              },
            ),
            ListTile(
              leading: const Icon(Icons.monitor_heart_rounded),
              title: const Text('房间质量诊断'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _openDiagnosticsPage();
              },
            ),
            ListTile(
              leading: const Icon(Icons.report_outlined),
              title: const Text('举报房间'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _openRoomReportPage();
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
}
