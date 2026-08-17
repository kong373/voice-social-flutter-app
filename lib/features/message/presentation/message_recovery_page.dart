part of 'message_pages.dart';

class MessagePermissionRecoveryPage extends StatefulWidget {
  const MessagePermissionRecoveryPage({super.key});

  @override
  State<MessagePermissionRecoveryPage> createState() =>
      _MessagePermissionRecoveryPageState();
}

class _MessagePermissionRecoveryPageState
    extends State<MessagePermissionRecoveryPage> {
  MessageRecoverySnapshot? _snapshot;
  bool _loading = true;
  bool _requesting = false;
  String? _error;

  MessageRepository get _repository =>
      AppDependencyScope.of(context).messageRepository;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_snapshot == null && _loading) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final MessageRecoverySnapshot value =
          await _repository.fetchRecoverySnapshot();
      if (mounted) {
        setState(() {
          _snapshot = value;
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _messageFor(error);
        });
      }
    }
  }

  Future<void> _requestPermission() async {
    if (_requesting) {
      return;
    }
    setState(() => _requesting = true);
    try {
      final MessageRecoverySnapshot value =
          await _repository.requestNotificationPermission();
      if (mounted) {
        setState(() => _snapshot = value);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_messageFor(error))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _requesting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final MessageRecoverySnapshot? snapshot = _snapshot;
    return Scaffold(
      appBar: AppBar(title: const Text('通知权限与消息恢复')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _MessageError(message: _error!, onRetry: _load)
              : snapshot == null
                  ? const Center(child: Text('消息恢复状态不可用'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                        children: <Widget>[
                          _MessageInfoCard(
                            icon: snapshot.privateRealtimeAvailable
                                ? Icons.cloud_done_outlined
                                : Icons.cloud_off_outlined,
                            text: snapshot.message,
                          ),
                          const SizedBox(height: 14),
                          Material(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(20),
                            child: Padding(
                              padding: const EdgeInsets.all(18),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    '私聊实时通道',
                                    style: Theme.of(context).textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(snapshot.privateRealtimeAvailable
                                      ? '当前可用'
                                      : '腾讯 IM 尚未接入'),
                                  const Divider(height: 26),
                                  Text(
                                    '系统通知权限',
                                    style: Theme.of(context).textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(_permissionLabel(
                                      snapshot.notificationPermission)),
                                  const Divider(height: 26),
                                  Text(
                                    '最近通知同步',
                                    style: Theme.of(context).textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(snapshot.lastNotificationSyncAt == null
                                      ? '尚未完成同步'
                                      : _formatMessageTime(
                                          snapshot.lastNotificationSyncAt!,
                                        )),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          const _MessageInfoCard(
                            icon: Icons.history_toggle_off_rounded,
                            text: '恢复只刷新服务端确认存在的会话和通知。不会编造断线期间私聊、补出不存在的历史正文，也不会把互动通知当成腾讯 IM 消息。',
                          ),
                          const SizedBox(height: 18),
                          if (_repository.supportsNativeNotificationPermission)
                            FilledButton.icon(
                              onPressed:
                                  _requesting ? null : _requestPermission,
                              icon: _requesting
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.notifications_active_outlined),
                              label: Text(
                                _requesting ? '请求中…' : '请求系统通知权限',
                              ),
                            )
                          else
                            const _MessageInfoCard(
                              icon: Icons.settings_outlined,
                              text: '原生通知权限适配器尚未接入，Live 模式不会把未知状态显示成已授权。',
                            ),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            onPressed: _load,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('刷新恢复状态'),
                          ),
                        ],
                      ),
                    ),
    );
  }

  static String _permissionLabel(
    NativeNotificationPermissionState state,
  ) =>
      switch (state) {
        NativeNotificationPermissionState.unknown => '尚未请求',
        NativeNotificationPermissionState.allowed => '已允许',
        NativeNotificationPermissionState.denied => '已拒绝',
        NativeNotificationPermissionState.restricted => '受系统限制',
        NativeNotificationPermissionState.unavailable => '适配器未接入',
      };
}
