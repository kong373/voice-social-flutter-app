import 'package:flutter/material.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/design_system/runtime_surfaces.dart';
import 'package:voice_social_app/features/room/domain/room_operations_models.dart';
import 'package:voice_social_app/features/room/domain/room_operations_repository.dart';
import 'package:voice_social_app/features/room/presentation/room_oxygen_components.dart';

/// Applicant-side status and cancellation surface for approval-only rooms.
///
/// All displayed state comes from the authenticated first-party status
/// endpoint. The page never infers success from a cancel response; it reads
/// the status again before showing the resulting state.
class RoomJoinRequestStatusPage extends StatefulWidget {
  const RoomJoinRequestStatusPage({
    required this.roomId,
    this.joinRequestId,
    this.roomTitle,
    this.repositoryOverride,
    super.key,
  });

  final String roomId;
  final String? joinRequestId;
  final String? roomTitle;
  final RoomJoinRequestRepository? repositoryOverride;

  @override
  State<RoomJoinRequestStatusPage> createState() =>
      _RoomJoinRequestStatusPageState();
}

class _RoomJoinRequestStatusPageState extends State<RoomJoinRequestStatusPage> {
  RoomJoinRequestRepository? _repository;
  RoomJoinRequestApplicantStatus? _status;
  String? _error;
  bool _loading = true;
  bool _busy = false;
  int _operationEpoch = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_repository != null) {
      return;
    }
    _repository = widget.repositoryOverride;
    if (_repository == null) {
      _repository = AppDependencyScope.of(
        context,
      ).roomOperationsRepository.roomJoinRequestCapability;
    }
    _load();
  }

  Future<void> _load({bool showLoading = true}) async {
    final RoomJoinRequestRepository? repository = _repository;
    if (_busy) {
      return;
    }
    if (repository == null) {
      setState(() {
        _loading = false;
        _error = '当前环境未提供入房申请状态能力';
      });
      return;
    }
    final int operationEpoch = ++_operationEpoch;
    if (showLoading && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final RoomJoinRequestApplicantStatus value = await repository
          .fetchJoinRequestStatus(
            roomId: widget.roomId,
            joinRequestId: widget.joinRequestId,
          );
      if (!mounted || operationEpoch != _operationEpoch) {
        return;
      }
      setState(() {
        _status = value;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted || operationEpoch != _operationEpoch) {
        return;
      }
      setState(() {
        _loading = false;
        _error = _messageFor(error);
      });
    }
  }

  Future<void> _cancel() async {
    final RoomJoinRequestRepository? repository = _repository;
    final RoomJoinRequestApplicantStatus? current = _status;
    if (repository == null ||
        current == null ||
        _busy ||
        _loading ||
        !current.canCancel) {
      return;
    }
    final int operationEpoch = ++_operationEpoch;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await repository.cancelJoinRequest(
        roomId: current.roomId,
        joinRequestId: current.joinRequestId,
      );
      // A successful mutation is not enough to paint CANCELLED. The GET is
      // authoritative and also covers a durable replay response.
      final RoomJoinRequestApplicantStatus latest = await repository
          .fetchJoinRequestStatus(
            roomId: current.roomId,
            joinRequestId: current.joinRequestId,
          );
      if (!mounted || operationEpoch != _operationEpoch) {
        return;
      }
      setState(() {
        _status = latest;
        _busy = false;
        _error = null;
      });
      if (latest.status == RoomJoinRequestStatus.cancelled) {
        _showMessage('入房申请已撤回');
      }
    } catch (error) {
      if (!mounted || operationEpoch != _operationEpoch) {
        return;
      }
      setState(() {
        _busy = false;
        _error = _messageFor(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return RoomPageScaffold(
      appBar: roomOxygenAppBar(
        title: '入房申请状态',
        leading: IconButton(
          tooltip: '返回',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        actions: <Widget>[
          IconButton(
            tooltip: '刷新权威状态',
            onPressed: _loading || _busy ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading && _status == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _status == null) {
      return _buildError();
    }
    final RoomJoinRequestApplicantStatus? status = _status;
    if (status == null) {
      return _buildError();
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
      children: <Widget>[
        RoomOxygenContextBar(
          title: widget.roomTitle?.trim().isNotEmpty == true
              ? widget.roomTitle!.trim()
              : '房间 ${status.roomId}',
          subtitle: '申请编号 ${status.joinRequestId}',
          seed: status.roomId,
          status: _roomStateLabel(status.roomState),
          statusColor: _roomStateColor(status.roomState),
        ),
        const SizedBox(height: 16),
        RoomOxygenSection(
          title: '申请进度',
          subtitle: '以下内容来自服务端的本人申请视图',
          icon: Icons.assignment_turned_in_outlined,
          child: _buildStatusCard(status),
        ),
        if (_error != null) ...<Widget>[
          const SizedBox(height: 12),
          _buildInlineError(),
        ],
      ],
    );
  }

  Widget _buildStatusCard(RoomJoinRequestApplicantStatus status) {
    final Color accent = _statusColor(status.status);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(_statusIcon(status.status), color: accent, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _statusLabel(status.status),
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            RoomOxygenPill(
              label: status.banned ? '已限制' : _roomStateLabel(status.roomState),
              active: true,
              accent: status.banned ? RoomColors.error : accent,
            ),
          ],
        ),
        const SizedBox(height: 14),
        _DetailRow(label: '房间状态', value: _roomStateLabel(status.roomState)),
        _DetailRow(label: '申请状态', value: _statusLabel(status.status)),
        if (status.banned) const _DetailRow(label: '进入权限', value: '当前被房间限制'),
        if (status.message?.trim().isNotEmpty == true) ...<Widget>[
          const SizedBox(height: 10),
          Text('申请留言', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          Text(status.message!, style: Theme.of(context).textTheme.bodyMedium),
        ],
        const SizedBox(height: 18),
        if (status.isPending && status.canCancel)
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _busy || _loading ? null : _cancel,
              icon: _busy
                  ? const SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.undo_rounded),
              label: Text(_busy ? '正在撤回…' : '撤回申请'),
            ),
          )
        else
          Text(
            _availabilityMessage(status),
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: RoomGlassCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.cloud_off_rounded, color: RoomColors.warning),
              const SizedBox(height: 10),
              Text(
                _error ?? '无法读取申请状态',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInlineError() {
    return RoomGlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: <Widget>[
          const Icon(Icons.error_outline_rounded, color: RoomColors.error),
          const SizedBox(width: 8),
          Expanded(child: Text(_error!)),
          TextButton(
            onPressed: _busy || _loading ? null : _load,
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  static String _messageFor(Object error) {
    if (error is ApiException) {
      return error.message;
    }
    return '操作失败，请刷新后重试';
  }

  static String _statusLabel(RoomJoinRequestStatus status) {
    return switch (status) {
      RoomJoinRequestStatus.pending => '待审核',
      RoomJoinRequestStatus.cancelled => '已撤回',
      RoomJoinRequestStatus.approved => '已同意',
      RoomJoinRequestStatus.rejected => '已拒绝',
    };
  }

  static String _roomStateLabel(String state) {
    return state == 'OPEN' ? '房间开放' : '房间已关闭';
  }

  static Color _roomStateColor(String state) {
    return state == 'OPEN' ? RoomColors.success : RoomColors.warning;
  }

  static Color _statusColor(RoomJoinRequestStatus status) {
    return switch (status) {
      RoomJoinRequestStatus.pending => RoomColors.primary,
      RoomJoinRequestStatus.cancelled => RoomColors.textSecondary,
      RoomJoinRequestStatus.approved => RoomColors.success,
      RoomJoinRequestStatus.rejected => RoomColors.error,
    };
  }

  static IconData _statusIcon(RoomJoinRequestStatus status) {
    return switch (status) {
      RoomJoinRequestStatus.pending => Icons.hourglass_top_rounded,
      RoomJoinRequestStatus.cancelled => Icons.undo_rounded,
      RoomJoinRequestStatus.approved => Icons.check_circle_outline_rounded,
      RoomJoinRequestStatus.rejected => Icons.cancel_outlined,
    };
  }

  static String _availabilityMessage(RoomJoinRequestApplicantStatus status) {
    if (status.banned) {
      return '当前被房间限制，无法撤回或再次进入。';
    }
    return switch (status.status) {
      RoomJoinRequestStatus.pending =>
        status.roomState == 'OPEN' ? '当前申请仍在等待房主或房管处理。' : '房间已关闭，申请不可再操作。',
      RoomJoinRequestStatus.cancelled => '申请已撤回，可在房间开放时重新申请。',
      RoomJoinRequestStatus.approved => '申请已通过，请返回房间继续操作。',
      RoomJoinRequestStatus.rejected => '申请未通过，如需进入请重新提交申请。',
    };
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 72,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: Text(value, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
