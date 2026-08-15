part of 'community_pages.dart';

class _CommunityEntry {
  const _CommunityEntry({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.page,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget page;
}

class _GuildTile extends StatelessWidget {
  const _GuildTile({
    required this.guild,
    required this.onTap,
    this.prominent = false,
  });

  final GuildSummary guild;
  final VoidCallback onTap;
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: prominent
          ? AppColors.primary.withValues(alpha: 0.13)
          : AppColors.surface,
      borderRadius: BorderRadius.circular(20),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(child: Text(_initial(guild.name))),
        title: Row(
          children: <Widget>[
            Expanded(child: Text(guild.name)),
            if (guild.joined) _SmallTag(label: guild.role.label),
          ],
        ),
        subtitle: Text(
          '${guild.code} · ${guild.memberCount} 人\n${guild.description}',
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}

class _GuildHero extends StatelessWidget {
  const _GuildHero({required this.guild});

  final GuildSummary guild;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[Color(0xFF2D2455), AppColors.surface],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              CircleAvatar(radius: 30, child: Text(_initial(guild.name))),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(guild.name, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text('${guild.code} · ${guild.memberCount} 人'),
                  ],
                ),
              ),
              if (guild.joined) _SmallTag(label: guild.role.label),
            ],
          ),
          const SizedBox(height: 14),
          Text(guild.description.isEmpty ? '暂无公会介绍' : guild.description),
          const SizedBox(height: 8),
          Text('会长：${guild.ownerName.isEmpty ? '未公开' : guild.ownerName}'),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, color: AppColors.accent),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}

class _StateError extends StatelessWidget {
  const _StateError({
    required this.message,
    required this.onRetry,
    this.retryLabel = '重新加载',
  });

  final String message;
  final VoidCallback onRetry;
  final String retryLabel;

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
            FilledButton.tonal(onPressed: onRetry, child: Text(retryLabel)),
          ],
        ),
      ),
    );
  }
}

class _SmallTag extends StatelessWidget {
  const _SmallTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}

class _KeyValue extends StatelessWidget {
  const _KeyValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 88,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(child: Text(value.isEmpty ? '未提供' : value)),
        ],
      ),
    );
  }
}

String _initial(String source) {
  final String value = source.trim();
  return value.isEmpty ? '?' : String.fromCharCode(value.runes.first);
}

String _messageFor(Object error) =>
    error is ApiException ? error.message : '操作失败，请稍后重试';
