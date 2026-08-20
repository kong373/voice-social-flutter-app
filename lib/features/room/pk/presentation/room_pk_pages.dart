import 'dart:async';

import 'package:flutter/material.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/design_system/runtime_surfaces.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/room/pk/domain/room_pk_models.dart';
import 'package:voice_social_app/features/room/pk/domain/room_pk_repository.dart';

class RoomPkPreparationPage extends StatefulWidget {
  const RoomPkPreparationPage({
    required this.roomId,
    required this.roomTitle,
    super.key,
  });

  final String roomId;
  final String roomTitle;

  @override
  State<RoomPkPreparationPage> createState() => _RoomPkPreparationPageState();
}

class _RoomPkPreparationPageState extends State<RoomPkPreparationPage> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _punishmentController = TextEditingController(
    text: '输的一方分享今天最想放下的事',
  );
  final List<RoomPkOpponent> _opponents = <RoomPkOpponent>[];
  final List<RoomPkRecord> _history = <RoomPkRecord>[];
  RoomPkOpponent? _selectedOpponent;
  RoomPkInvitation? _incoming;
  RoomPkInvitation? _outgoing;
  RoomPkBattle? _activeBattle;
  int _durationMinutes = 5;
  bool _loading = true;
  bool _busy = false;
  bool _searching = false;
  String? _error;

  RoomPkRepository get _repository =>
      AppDependencyScope.of(context).roomPkRepository;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading && _opponents.isEmpty && _error == null) {
      _load();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _punishmentController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final List<Object?> result = await Future.wait<Object?>(<Future<Object?>>[
        _repository.fetchHotOpponents(roomId: widget.roomId),
        _repository.fetchIncomingInvitation(roomId: widget.roomId),
        _repository.fetchActiveBattle(roomId: widget.roomId),
        _repository.fetchHistory(roomId: widget.roomId),
      ]);
      if (!mounted) {
        return;
      }
      setState(() {
        _opponents
          ..clear()
          ..addAll(result[0] as List<RoomPkOpponent>);
        _incoming = result[1] as RoomPkInvitation?;
        _activeBattle = result[2] as RoomPkBattle?;
        _history
          ..clear()
          ..addAll(result[3] as List<RoomPkRecord>);
        if (_selectedOpponent != null) {
          final String selectedRoomId = _selectedOpponent!.roomId;
          _selectedOpponent = _opponents
              .where((RoomPkOpponent item) => item.roomId == selectedRoomId)
              .firstOrNull;
        }
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _messageFor(error);
        });
      }
    }
  }

  Future<void> _search() async {
    if (_searching) {
      return;
    }
    setState(() => _searching = true);
    try {
      final List<RoomPkOpponent> values = await _repository.searchOpponents(
        roomId: widget.roomId,
        keyword: _searchController.text,
      );
      if (mounted) {
        setState(() {
          _opponents
            ..clear()
            ..addAll(values);
          _selectedOpponent = null;
        });
      }
    } catch (error) {
      if (mounted) {
        _showMessage(_messageFor(error));
      }
    } finally {
      if (mounted) {
        setState(() => _searching = false);
      }
    }
  }

  Future<void> _sendInvitation() async {
    final RoomPkOpponent? opponent = _selectedOpponent;
    if (opponent == null || _busy) {
      _showMessage('请先选择一个可邀请的房间');
      return;
    }
    final String punishment = _punishmentController.text.trim();
    if (punishment.isEmpty || punishment.length > 20) {
      _showMessage('惩罚主题需为 1～20 个字');
      return;
    }
    final int inviterUserId =
        AppDependencyScope.of(context).sessionManager.session?.userId ?? 0;
    setState(() => _busy = true);
    try {
      final RoomPkInvitation invitation = await _repository.sendInvitation(
        roomId: widget.roomId,
        inviterUserId: inviterUserId,
        opponent: opponent,
        punishmentTheme: punishment,
        durationMinutes: _durationMinutes,
      );
      if (mounted) {
        setState(() => _outgoing = invitation);
        _showMessage('PK 邀请已发送，等待对方确认');
      }
    } catch (error) {
      if (mounted) {
        _showMessage(_messageFor(error));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _refreshOutgoing() async {
    final RoomPkInvitation? outgoing = _outgoing;
    if (outgoing == null || _busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      final RoomPkInvitation updated = await _repository.refreshInvitation(
        outgoing,
      );
      if (!mounted) {
        return;
      }
      setState(() => _outgoing = updated);
      if (updated.status == RoomPkInvitationStatus.accepted) {
        final RoomPkBattle? battle = await _repository.fetchActiveBattle(
          roomId: widget.roomId,
        );
        if (battle == null) {
          _showMessage('对方已接受，正在等待服务端建立对局');
          return;
        }
        setState(() => _activeBattle = battle);
        await _openBattle(battle);
      } else if (updated.status != RoomPkInvitationStatus.pending) {
        _showMessage(_invitationStatusText(updated.status));
      }
    } catch (error) {
      if (mounted) {
        _showMessage(_messageFor(error));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _resolveIncoming(bool accepted) async {
    final RoomPkInvitation? incoming = _incoming;
    if (incoming == null || _busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      if (accepted) {
        final RoomPkBattle battle = await _repository.acceptInvitation(
          incoming,
        );
        if (!mounted) {
          return;
        }
        setState(() {
          _incoming = incoming.copyWith(
            status: RoomPkInvitationStatus.accepted,
          );
          _activeBattle = battle;
        });
        await _openBattle(battle);
      } else {
        await _repository.rejectInvitation(incoming);
        if (mounted) {
          setState(() {
            _incoming = incoming.copyWith(
              status: RoomPkInvitationStatus.rejected,
            );
          });
          _showMessage('已拒绝 PK 邀请');
        }
      }
    } catch (error) {
      if (mounted) {
        _showMessage(_messageFor(error));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _openBattle(RoomPkBattle battle) async {
    final bool? returnToRoom = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext context) =>
            RoomPkBattlePage(roomId: widget.roomId, initialBattle: battle),
      ),
    );
    if (!mounted) {
      return;
    }
    if (returnToRoom == true) {
      Navigator.of(context).pop();
      return;
    }
    await _load();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return RoomPageScaffold(
      appBar: AppBar(title: const Text('PK 邀请与准备')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _PkError(message: _error!, onRetry: _load)
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                children: <Widget>[
                  const _PkInfoCard(
                    icon: Icons.info_outline_rounded,
                    text: '只保留普通房间 PK：邀请、接受或拒绝、计时比分和结算。其他未确认玩法均不提供。',
                  ),
                  if (!_repository.supportsRealtimeInvitations) ...<Widget>[
                    const SizedBox(height: 10),
                    const _PkInfoCard(
                      icon: Icons.sync_rounded,
                      text: '实时邀请通道尚未接入，当前通过手动刷新服务端状态确认是否开战。',
                    ),
                  ],
                  if (_activeBattle != null) ...<Widget>[
                    const SizedBox(height: 16),
                    _ActiveBattleCard(
                      battle: _activeBattle!,
                      onOpen: () => _openBattle(_activeBattle!),
                    ),
                  ],
                  if (_incoming != null &&
                      _incoming!.status ==
                          RoomPkInvitationStatus.pending) ...<Widget>[
                    const SizedBox(height: 20),
                    Text(
                      '收到的邀请',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 10),
                    _IncomingInvitationCard(
                      invitation: _incoming!,
                      busy: _busy,
                      onAccept: () => _resolveIncoming(true),
                      onReject: () => _resolveIncoming(false),
                    ),
                  ],
                  const SizedBox(height: 22),
                  Text('选择对手', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          textInputAction: TextInputAction.search,
                          onSubmitted: (_) => _search(),
                          decoration: const InputDecoration(
                            hintText: '输入房间号或房间名称',
                            prefixIcon: Icon(Icons.search_rounded),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        tooltip: '搜索房间',
                        onPressed: _searching ? null : _search,
                        icon: _searching
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.arrow_forward_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_opponents.isEmpty)
                    const _PkInfoCard(
                      icon: Icons.search_off_rounded,
                      text: '当前没有可邀请的房间，可稍后刷新或换一个房间号搜索。',
                    )
                  else
                    for (final RoomPkOpponent opponent in _opponents)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _OpponentTile(
                          opponent: opponent,
                          selected:
                              _selectedOpponent?.roomId == opponent.roomId,
                          onSelect: opponent.isInPk
                              ? null
                              : () => setState(
                                  () => _selectedOpponent = opponent,
                                ),
                        ),
                      ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _punishmentController,
                    maxLength: 20,
                    decoration: const InputDecoration(
                      labelText: '惩罚主题',
                      hintText: '双方都能理解、可正常完成的轻量惩罚',
                      prefixIcon: Icon(Icons.flag_outlined),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text('PK 时长', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  SegmentedButton<int>(
                    showSelectedIcon: false,
                    segments: const <ButtonSegment<int>>[
                      ButtonSegment<int>(value: 5, label: Text('5 分钟')),
                      ButtonSegment<int>(value: 10, label: Text('10 分钟')),
                      ButtonSegment<int>(value: 15, label: Text('15 分钟')),
                    ],
                    selected: <int>{_durationMinutes},
                    onSelectionChanged: _busy
                        ? null
                        : (Set<int> values) =>
                              setState(() => _durationMinutes = values.first),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _busy || _activeBattle?.isActive == true
                          ? null
                          : _sendInvitation,
                      icon: const Icon(Icons.sports_kabaddi_rounded),
                      label: Text(_busy ? '提交中…' : '发送 PK 邀请'),
                    ),
                  ),
                  if (_outgoing != null) ...<Widget>[
                    const SizedBox(height: 12),
                    _OutgoingInvitationCard(
                      invitation: _outgoing!,
                      busy: _busy,
                      onRefresh: _refreshOutgoing,
                    ),
                  ],
                  const SizedBox(height: 24),
                  Text('最近对战', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 10),
                  if (_history.isEmpty)
                    const _PkInfoCard(
                      icon: Icons.history_rounded,
                      text: '当前没有可展示的 PK 记录。',
                    )
                  else
                    for (final RoomPkRecord record in _history)
                      _PkRecordTile(record: record),
                ],
              ),
            ),
    );
  }
}

class RoomPkBattlePage extends StatefulWidget {
  const RoomPkBattlePage({
    required this.roomId,
    required this.initialBattle,
    super.key,
  });

  final String roomId;
  final RoomPkBattle initialBattle;

  @override
  State<RoomPkBattlePage> createState() => _RoomPkBattlePageState();
}

class _RoomPkBattlePageState extends State<RoomPkBattlePage> {
  late RoomPkBattle _battle;
  RoomPkRepository? _repositoryInstance;
  Timer? _timer;
  bool _refreshing = false;
  String? _error;

  RoomPkRepository get _repository => _repositoryInstance!;

  @override
  void initState() {
    super.initState();
    _battle = widget.initialBattle;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_repositoryInstance != null) {
      return;
    }
    _repositoryInstance = AppDependencyScope.of(context).roomPkRepository;
    _schedulePolling();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _schedulePolling() {
    _timer?.cancel();
    if (!_battle.isActive) {
      return;
    }
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
  }

  Future<void> _refresh() async {
    if (_refreshing || !_battle.isActive) {
      return;
    }
    setState(() {
      _refreshing = true;
      _error = null;
    });
    try {
      final RoomPkBattle value = await _repository.refreshBattle(
        roomId: widget.roomId,
        battleId: _battle.id,
      );
      if (!mounted) {
        return;
      }
      setState(() => _battle = value);
      if (!value.isActive) {
        _timer?.cancel();
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = _messageFor(error));
      }
    } finally {
      if (mounted) {
        setState(() => _refreshing = false);
      }
    }
  }

  Future<void> _surrender() async {
    if (!_repository.supportsSurrender) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('当前服务端未确认普通房 PK 主动认输接口')));
      return;
    }
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('确认认输？'),
        content: const Text('确认后本场 PK 立即结束，并按主动认输记录结果。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('继续对战'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('确认认输'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    try {
      final RoomPkBattle value = await _repository.surrender(
        roomId: widget.roomId,
        battleId: _battle.id,
      );
      if (mounted) {
        setState(() => _battle = value);
        _timer?.cancel();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_messageFor(error))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final RoomPkSide current = _battle.currentSide;
    final RoomPkSide opponent = _battle.opponentSide;
    final int totalScore = current.score + opponent.score;
    final double currentRatio = totalScore == 0
        ? 0.5
        : current.score / totalScore;
    return RoomPageScaffold(
      appBar: AppBar(
        title: const Text('PK 对战与结算'),
        actions: <Widget>[
          IconButton(
            tooltip: '刷新比分',
            onPressed: _refreshing ? null : _refresh,
            icon: _refreshing
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: <Widget>[
          if (!_repository.supportsRealtimeInvitations)
            const _PkInfoCard(
              icon: Icons.sync_rounded,
              text: '第三方实时通道尚未接入，本页通过服务端轮询刷新比分和剩余时间。',
            ),
          const SizedBox(height: 12),
          _BattleHeader(
            current: current,
            opponent: opponent,
            remainingSeconds: _battle.remainingSeconds,
            stage: _battle.stage,
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 12,
              value: currentRatio.clamp(0, 1),
              backgroundColor: RoomColors.secondary.withValues(alpha: 0.28),
            ),
          ),
          const SizedBox(height: 14),
          _PkInfoCard(
            icon: Icons.flag_outlined,
            text: _battle.punishmentTheme.isEmpty
                ? '本场未设置惩罚主题'
                : '惩罚主题：${_battle.punishmentTheme}',
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 10),
            _PkInfoCard(
              icon: Icons.warning_amber_rounded,
              text: '$_error。页面保留上一次有效比分，可继续刷新。',
            ),
          ],
          const SizedBox(height: 22),
          _SupporterSection(title: '${current.roomName} 支持榜', side: current),
          const SizedBox(height: 16),
          _SupporterSection(title: '${opponent.roomName} 支持榜', side: opponent),
          const SizedBox(height: 24),
          if (_battle.stage == RoomPkBattleStage.completed)
            _ResultCard(battle: _battle)
          else ...<Widget>[
            OutlinedButton.icon(
              onPressed: _surrender,
              icon: const Icon(Icons.flag_rounded),
              label: Text(_repository.supportsSurrender ? '主动认输' : '认输接口未接入'),
            ),
            const SizedBox(height: 8),
            Text(
              '返回房间不会结束 PK；只有服务端结算或明确认输才会结束本场。',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('返回房间'),
          ),
        ],
      ),
    );
  }
}

class _OpponentTile extends StatelessWidget {
  const _OpponentTile({
    required this.opponent,
    required this.selected,
    required this.onSelect,
  });

  final RoomPkOpponent opponent;
  final bool selected;
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? RoomColors.primary.withValues(alpha: 0.18)
          : RoomColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        onTap: onSelect,
        leading: CircleAvatar(child: Text(_initial(opponent.roomName))),
        title: Text(opponent.roomName),
        subtitle: Text(
          '房间号 ${opponent.roomCode} · ${opponent.onlineUsers} 人在线'
          '${opponent.label.isEmpty ? '' : ' · ${opponent.label}'}',
        ),
        trailing: opponent.isInPk
            ? const _PkTag(label: 'PK 中')
            : Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected ? RoomColors.primary : RoomColors.textSecondary,
              ),
      ),
    );
  }
}

class _IncomingInvitationCard extends StatelessWidget {
  const _IncomingInvitationCard({
    required this.invitation,
    required this.busy,
    required this.onAccept,
    required this.onReject,
  });

  final RoomPkInvitation invitation;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: RoomColors.surface,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              invitation.opponent.roomName,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              '${invitation.durationMinutes} 分钟 · ${invitation.punishmentTheme}',
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: busy ? null : onReject,
                    child: const Text('拒绝'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: busy ? null : onAccept,
                    child: const Text('接受并准备'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OutgoingInvitationCard extends StatelessWidget {
  const _OutgoingInvitationCard({
    required this.invitation,
    required this.busy,
    required this.onRefresh,
  });

  final RoomPkInvitation invitation;
  final bool busy;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: RoomColors.surfaceHigh,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Row(
          children: <Widget>[
            const Icon(Icons.outgoing_mail, color: RoomColors.accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('已邀请 ${invitation.opponent.roomName}'),
                  const SizedBox(height: 4),
                  Text(
                    _invitationStatusText(invitation.status),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: '刷新邀请状态',
              onPressed:
                  busy || invitation.status != RoomPkInvitationStatus.pending
                  ? null
                  : onRefresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveBattleCard extends StatelessWidget {
  const _ActiveBattleCard({required this.battle, required this.onOpen});

  final RoomPkBattle battle;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: RoomColors.primary.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(20),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        leading: const Icon(Icons.sports_kabaddi_rounded),
        title: const Text('当前房间正在 PK'),
        subtitle: Text(
          '${battle.currentSide.score} : ${battle.opponentSide.score} · ${_formatDuration(battle.remainingSeconds)}',
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onOpen,
      ),
    );
  }
}

class _BattleHeader extends StatelessWidget {
  const _BattleHeader({
    required this.current,
    required this.opponent,
    required this.remainingSeconds,
    required this.stage,
  });

  final RoomPkSide current;
  final RoomPkSide opponent;
  final int remainingSeconds;
  final RoomPkBattleStage stage;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: RoomColors.surface,
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(child: _PkSideCard(side: current, mine: true)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Column(
                    children: <Widget>[
                      Text(
                        stage == RoomPkBattleStage.completed
                            ? '已结束'
                            : _formatDuration(remainingSeconds),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      const Text('VS'),
                    ],
                  ),
                ),
                Expanded(child: _PkSideCard(side: opponent, mine: false)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PkSideCard extends StatelessWidget {
  const _PkSideCard({required this.side, required this.mine});

  final RoomPkSide side;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        CircleAvatar(radius: 28, child: Text(_initial(side.roomName))),
        const SizedBox(height: 8),
        Text(
          side.roomName,
          maxLines: 2,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 6),
        Text(
          '${side.score}',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: mine ? RoomColors.accent : RoomColors.secondary,
          ),
        ),
      ],
    );
  }
}

class _SupporterSection extends StatelessWidget {
  const _SupporterSection({required this.title, required this.side});

  final String title;
  final RoomPkSide side;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: RoomColors.surface,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            if (side.supporters.isEmpty)
              Text('当前暂无有效贡献数据', style: Theme.of(context).textTheme.bodySmall)
            else
              for (int index = 0; index < side.supporters.length; index += 1)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    radius: 18,
                    child: Text('${index + 1}'),
                  ),
                  title: Text(side.supporters[index].nickname),
                  trailing: Text('${side.supporters[index].value}'),
                ),
          ],
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.battle});

  final RoomPkBattle battle;

  @override
  Widget build(BuildContext context) {
    final RoomPkResult result = battle.result ?? RoomPkResult.canceled;
    final String title = switch (result) {
      RoomPkResult.win => '本房获胜',
      RoomPkResult.lose => '本房落败',
      RoomPkResult.draw => '本场平局',
      RoomPkResult.surrendered => '本房主动认输',
      RoomPkResult.canceled => '本场已取消',
    };
    return Material(
      color: RoomColors.surfaceHigh,
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: <Widget>[
            Icon(
              result == RoomPkResult.win
                  ? Icons.emoji_events_rounded
                  : Icons.flag_rounded,
              size: 42,
              color: result == RoomPkResult.win
                  ? RoomColors.warning
                  : RoomColors.textSecondary,
            ),
            const SizedBox(height: 10),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              '${battle.currentSide.score} : ${battle.opponentSide.score}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            if (battle.punishmentTheme.isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                result == RoomPkResult.win
                    ? '对方执行：${battle.punishmentTheme}'
                    : '本房执行：${battle.punishmentTheme}',
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PkRecordTile extends StatelessWidget {
  const _PkRecordTile({required this.record});

  final RoomPkRecord record;

  @override
  Widget build(BuildContext context) {
    final String label = switch (record.result) {
      RoomPkResult.win => '胜',
      RoomPkResult.lose => '负',
      RoomPkResult.draw => '平',
      RoomPkResult.surrendered => '认输',
      RoomPkResult.canceled => '取消',
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(child: Text(label)),
      title: Text(record.opponentRoomName),
      subtitle: Text(_formatDate(record.completedAt)),
      trailing: Text('${record.currentScore} : ${record.opponentScore}'),
    );
  }
}

class _PkInfoCard extends StatelessWidget {
  const _PkInfoCard({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: RoomColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, color: RoomColors.accent),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}

class _PkError extends StatelessWidget {
  const _PkError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.cloud_off_rounded, size: 44),
            const SizedBox(height: 14),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: onRetry, child: const Text('重新加载')),
          ],
        ),
      ),
    );
  }
}

class _PkTag extends StatelessWidget {
  const _PkTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: RoomColors.primary.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}

String _messageFor(Object error) =>
    error is ApiException ? error.message : '操作失败，请稍后重试';

String _initial(String source) {
  final String value = source.trim();
  return value.isEmpty ? '?' : String.fromCharCode(value.runes.first);
}

String _invitationStatusText(RoomPkInvitationStatus status) => switch (status) {
  RoomPkInvitationStatus.pending => '等待对方确认',
  RoomPkInvitationStatus.accepted => '对方已接受',
  RoomPkInvitationStatus.rejected => '对方已拒绝',
  RoomPkInvitationStatus.expired => '邀请已过期',
  RoomPkInvitationStatus.canceled => '邀请已取消',
};

String _formatDuration(int seconds) {
  final int safe = seconds.clamp(0, 24 * 60 * 60).toInt();
  final int minutes = safe ~/ 60;
  final int remaining = safe % 60;
  return '${minutes.toString().padLeft(2, '0')}:${remaining.toString().padLeft(2, '0')}';
}

String _formatDate(DateTime value) =>
    '${value.month}月${value.day}日 ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final Iterator<T> iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
