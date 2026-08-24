part of 'message_pages.dart';

class NotificationCenterPage extends StatefulWidget {
  const NotificationCenterPage({
    this.initialCategory = NotificationCategory.system,
    super.key,
  });

  final NotificationCategory initialCategory;

  @override
  State<NotificationCenterPage> createState() => _NotificationCenterPageState();
}

class _NotificationCenterPageState extends State<NotificationCenterPage> {
  late NotificationCategory _category;
  List<AppNotification>? _notifications;
  bool _loading = true;
  bool _clearing = false;
  String? _error;
  int _loadGeneration = 0;

  MessageRepository get _repository =>
      AppDependencyScope.of(context).messageRepository;

  @override
  void initState() {
    super.initState();
    _category = widget.initialCategory;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_notifications == null && _loading) {
      _load();
    }
  }

  Future<void> _load() async {
    final int generation = ++_loadGeneration;
    final NotificationCategory requestedCategory = _category;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final List<AppNotification> value = await _repository.fetchNotifications(
        requestedCategory,
      );
      if (mounted &&
          generation == _loadGeneration &&
          requestedCategory == _category) {
        setState(() {
          _notifications = value;
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted &&
          generation == _loadGeneration &&
          requestedCategory == _category) {
        setState(() {
          _loading = false;
          _error = _messageFor(error);
        });
      }
    }
  }

  @override
  void dispose() {
    _loadGeneration += 1;
    super.dispose();
  }

  Future<void> _clearInteraction() async {
    if (_clearing) {
      return;
    }
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('清空互动通知？'),
        content: const Text('清空后通知列表将移除，但不会删除对应动态、评论或用户关系。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('确认清空'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() => _clearing = true);
    try {
      await _repository.clearInteractionNotifications();
      if (mounted) {
        await _load();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_messageFor(error))));
      }
    } finally {
      if (mounted) {
        setState(() => _clearing = false);
      }
    }
  }

  Future<void> _open(AppNotification notification) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            NotificationDetailPage(notificationId: notification.id),
      ),
    );
    if (mounted) {
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<AppNotification> notifications =
        _notifications ?? const <AppNotification>[];
    return SocialPageScaffold(
      appBar: AppBar(
        title: const Text('系统与互动通知'),
        actions: <Widget>[
          if (_category == NotificationCategory.interaction)
            IconButton(
              tooltip: '清空互动通知',
              onPressed: _clearing ? null : _clearInteraction,
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 2, 14, 10),
            child: _MessageInlineTabs<NotificationCategory>(
              items: const <NotificationCategory, String>{
                NotificationCategory.system: '系统通知',
                NotificationCategory.interaction: '互动通知',
              },
              value: _category,
              onChanged: (NotificationCategory value) {
                setState(() {
                  _category = value;
                  _notifications = null;
                });
                _load();
              },
            ),
          ),
          if (_category == NotificationCategory.system &&
              !_repository.supportsSystemNotificationList)
            const Padding(
              padding: EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: _MessageInfoCard(
                icon: Icons.info_outline_rounded,
                text: '当前后端只确认了单条推送详情，没有用户侧系统通知列表接口；Live 模式不会生成虚假通知。',
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? _MessageError(message: _error!, onRetry: _load)
                : notifications.isEmpty
                ? Center(
                    child: Text(
                      _category == NotificationCategory.system
                          ? '暂无系统通知'
                          : '暂无互动通知',
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(14, 4, 14, 28),
                      children: <Widget>[
                        _MessageListPanel(
                          child: Column(
                            children: <Widget>[
                              for (
                                int index = 0;
                                index < notifications.length;
                                index += 1
                              ) ...<Widget>[
                                _MessageNotificationRow(
                                  notification: notifications[index],
                                  onTap: () => _open(notifications[index]),
                                ),
                                if (index < notifications.length - 1)
                                  const Divider(height: 1),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class NotificationDetailPage extends StatefulWidget {
  const NotificationDetailPage({required this.notificationId, super.key});

  final String notificationId;

  @override
  State<NotificationDetailPage> createState() => _NotificationDetailPageState();
}

class _NotificationDetailPageState extends State<NotificationDetailPage> {
  AppNotification? _notification;
  bool _loading = true;
  String? _error;

  MessageRepository get _repository =>
      AppDependencyScope.of(context).messageRepository;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_notification == null && _loading) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      AppNotification value = await _repository.fetchNotification(
        widget.notificationId,
      );
      await _repository.markNotificationRead(value.id);
      value = value.copyWith(unread: false);
      if (mounted) {
        setState(() {
          _notification = value;
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

  Future<void> _openTarget() async {
    final AppNotification notification = _notification!;
    if (!notification.targetAvailable || notification.targetId == null) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => NotificationTargetUnavailablePage(
            reason: notification.unavailableReason.isEmpty
                ? '通知目标已失效或不可访问'
                : notification.unavailableReason,
          ),
        ),
      );
      return;
    }
    final String targetId = notification.targetId!;
    final Widget target = switch (notification.targetType) {
      NotificationTargetType.user => PublicProfilePage(
        userId: int.tryParse(targetId) ?? 0,
      ),
      NotificationTargetType.room => RoomDeepLinkPage(input: targetId),
      NotificationTargetType.dynamicPost => DynamicDetailPage(postId: targetId),
      NotificationTargetType.order => OrdersPage(initialOrderNo: targetId),
      NotificationTargetType.none => NotificationTargetUnavailablePage(
        reason: notification.unavailableReason.isEmpty
            ? '当前通知没有可打开的业务目标'
            : notification.unavailableReason,
      ),
    };
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (BuildContext context) => target),
    );
  }

  @override
  Widget build(BuildContext context) {
    final DateTime now = AppDependencyScope.of(context).currentTime();
    final AppNotification? notification = _notification;
    return SocialPageScaffold(
      appBar: AppBar(title: const Text('通知详情')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _MessageError(message: _error!, onRetry: _load)
          : notification == null
          ? const Center(child: Text('通知不可用'))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: <Widget>[
                _MessageListPanel(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 18, 8, 16),
                    child: Column(
                      children: <Widget>[
                        Container(
                          width: 58,
                          height: 58,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: <Color>[
                                const Color(0xFF7DA6FF),
                                notification.category ==
                                        NotificationCategory.system
                                    ? const Color(0xFF6D7FF0)
                                    : const Color(0xFFFF75B8),
                              ],
                            ),
                          ),
                          child: Icon(
                            notification.category == NotificationCategory.system
                                ? Icons.notifications_active_outlined
                                : Icons.favorite_outline_rounded,
                            size: 28,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          notification.title,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 5),
                        Text(
                          _formatMessageTime(notification.createdAt, now),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 16),
                        Text(notification.summary, textAlign: TextAlign.center),
                        if (notification.details.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 14),
                          const Divider(height: 1),
                          const SizedBox(height: 14),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              notification.details,
                              style: const TextStyle(height: 1.55),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (notification.targetType !=
                    NotificationTargetType.none) ...<Widget>[
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _openTarget,
                    child: Text(
                      notification.targetAvailable ? '查看相关内容' : '查看不可用原因',
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class NotificationTargetUnavailablePage extends StatelessWidget {
  const NotificationTargetUnavailablePage({
    required this.reason,
    this.title = '通知目标不可用',
    this.onRetry,
    super.key,
  });

  final String title;
  final String reason;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    return SocialPageScaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: _MessageListPanel(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    width: 66,
                    height: 66,
                    decoration: const BoxDecoration(
                      color: Color(0xFFECE9FF),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.link_off_rounded,
                      size: 30,
                      color: SocialColors.primary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(
                    reason,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: SocialColors.textSecondary,
                      height: 1.45,
                    ),
                  ),
                  if (onRetry != null) ...<Widget>[
                    const SizedBox(height: 18),
                    FilledButton.tonal(
                      onPressed: () async => onRetry!(),
                      child: const Text('重新检查'),
                    ),
                  ],
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('返回消息'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
