part of 'message_pages.dart';

class _MessageInfoCard extends StatelessWidget {
  const _MessageInfoCard({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.78),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, color: SocialColors.accent),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}

class _HeaderRoundButton extends StatelessWidget {
  const _HeaderRoundButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.84),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: 42,
          height: 42,
          child: Tooltip(
            message: tooltip,
            child: Icon(icon, color: SocialColors.textPrimary, size: 20),
          ),
        ),
      ),
    );
  }
}

class _MessageShortcutCard extends StatelessWidget {
  const _MessageShortcutCard({
    required this.icon,
    required this.title,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: <Widget>[
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: <Color>[accent.withValues(alpha: 0.58), accent],
                ),
                shape: BoxShape.circle,
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: accent.withValues(alpha: 0.22),
                    blurRadius: 12,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
            const SizedBox(height: 7),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: SocialColors.textSecondary,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageSearchHint extends StatelessWidget {
  const _MessageSearchHint({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.86),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            children: <Widget>[
              Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFFEAE3FF),
                ),
                child: const Icon(
                  Icons.notifications_none_rounded,
                  color: SocialColors.primary,
                  size: 17,
                ),
              ),
              const SizedBox(width: 9),
              const Expanded(
                child: Text(
                  '开启通知，心仪对象离你更近一步',
                  style: TextStyle(
                    color: SocialColors.textSecondary,
                    fontSize: 10,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: SocialColors.primary,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  '去开启',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageSupportRow extends StatelessWidget {
  const _MessageSupportRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.72),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: <Widget>[
              CircleAvatar(
                radius: 20,
                backgroundColor: Color(0xFFE8DAFF),
                child: Icon(
                  Icons.support_agent_rounded,
                  color: SocialColors.primary,
                  size: 21,
                ),
              ),
              SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '联系客服',
                      style: TextStyle(
                        color: SocialColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '如果您有疑问，可以在这里提交反馈',
                      style: TextStyle(
                        color: SocialColors.textSecondary,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: SocialColors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageListPanel extends StatelessWidget {
  const _MessageListPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.84)),
      ),
      child: child,
    );
  }
}

class _MessageInlineTabs<T> extends StatelessWidget {
  const _MessageInlineTabs({
    required this.items,
    required this.value,
    required this.onChanged,
  });

  final Map<T, String> items;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.72),
      borderRadius: BorderRadius.circular(14),
      child: Row(
        children: items.entries.map((MapEntry<T, String> item) {
          final bool active = item.key == value;
          return Expanded(
            child: InkWell(
              onTap: () => onChanged(item.key),
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      item.value,
                      style: TextStyle(
                        color: active
                            ? SocialColors.textPrimary
                            : SocialColors.textTertiary,
                        fontSize: 13,
                        fontWeight: active ? FontWeight.w900 : FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: active ? 24 : 0,
                      height: 3,
                      decoration: BoxDecoration(
                        color: SocialColors.primary,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _MessageNotificationRow extends StatelessWidget {
  const _MessageNotificationRow({
    required this.notification,
    required this.onTap,
  });

  final AppNotification notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final DateTime now = AppDependencyScope.of(context).currentTime();
    final bool system = notification.category == NotificationCategory.system;
    final Color accent = system
        ? const Color(0xFF6D9BFF)
        : const Color(0xFFFF75B8);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          children: <Widget>[
            Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: <Color>[accent.withValues(alpha: 0.55), accent],
                    ),
                  ),
                  child: Icon(
                    system
                        ? Icons.notifications_none_rounded
                        : Icons.favorite_border_rounded,
                    color: Colors.white,
                    size: 21,
                  ),
                ),
                if (notification.unread)
                  const Positioned(
                    right: -1,
                    top: -1,
                    child: CircleAvatar(
                      radius: 5,
                      backgroundColor: SocialColors.error,
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    notification.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: SocialColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    notification.summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: SocialColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text(
                  _formatMessageTime(notification.createdAt, now),
                  style: const TextStyle(
                    color: SocialColors.textTertiary,
                    fontSize: 9,
                  ),
                ),
                const SizedBox(height: 7),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: SocialColors.textTertiary,
                  size: 18,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageConversationRow extends StatelessWidget {
  const _MessageConversationRow({
    required this.conversation,
    required this.onTap,
  });

  final ConversationSummary conversation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final DateTime now = AppDependencyScope.of(context).currentTime();
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: <Widget>[
            Stack(
              children: <Widget>[
                RuntimeAvatar(seed: conversation.id, size: 48),
                if (conversation.available)
                  Positioned(
                    right: 1,
                    bottom: 2,
                    child: Container(
                      width: 11,
                      height: 11,
                      decoration: BoxDecoration(
                        color: const Color(0xFF59D8A4),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    conversation.title,
                    style: const TextStyle(
                      color: SocialColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    conversation.available
                        ? conversation.lastMessage
                        : conversation.unavailableReason,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: SocialColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text(
                  _formatMessageTime(conversation.updatedAt, now),
                  style: const TextStyle(
                    color: SocialColors.textTertiary,
                    fontSize: 9,
                  ),
                ),
                const SizedBox(height: 6),
                _UnreadBadge(count: conversation.unreadCount),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageError extends StatelessWidget {
  const _MessageError({required this.message, required this.onRetry});

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

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) {
      return const SizedBox.shrink();
    }
    return Container(
      constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: SocialColors.error,
        borderRadius: BorderRadius.circular(999),
      ),
      alignment: Alignment.center,
      child: Text(
        count > 99 ? '99+' : '$count',
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}

String _messageFor(Object error) =>
    error is ApiException ? error.message : '操作失败，请稍后重试';

String _formatMessageTime(DateTime value, DateTime now) {
  if (now.difference(value).inDays == 0) {
    return '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
  }
  return '${value.month}月${value.day}日';
}
