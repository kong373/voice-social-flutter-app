import 'package:flutter/material.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/design_system/runtime_surfaces.dart';

PreferredSizeWidget roomOxygenAppBar({
  required String title,
  Widget? leading,
  List<Widget> actions = const <Widget>[],
}) {
  return AppBar(
    toolbarHeight: 52,
    titleSpacing: 0,
    leading: leading,
    title: Text(title),
    actions: actions,
  );
}

class RoomOxygenContextBar extends StatelessWidget {
  const RoomOxygenContextBar({
    required this.title,
    required this.subtitle,
    this.seed = 'room-880217',
    this.status = '房间内',
    this.statusColor = RoomColors.accent,
    this.trailing,
    super.key,
  });

  final String title;
  final String subtitle;
  final String seed;
  final String status;
  final Color statusColor;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return RoomGlassCard(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      radius: 16,
      child: Row(
        children: <Widget>[
          RuntimeAvatar(seed: seed, size: 38, ringColor: statusColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (trailing != null)
            trailing!
          else
            RoomOxygenPill(label: status, active: true, accent: statusColor),
        ],
      ),
    );
  }
}

class RoomOxygenSection extends StatelessWidget {
  const RoomOxygenSection({
    required this.title,
    required this.child,
    this.subtitle,
    this.icon,
    this.trailing,
    this.padding = const EdgeInsets.all(14),
    super.key,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(icon, size: 16, color: RoomColors.accent),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Text(title, style: Theme.of(context).textTheme.titleSmall),
            ),
            if (trailing != null) trailing!,
          ],
        ),
        if (subtitle != null) ...<Widget>[
          const SizedBox(height: 3),
          Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
        ],
        const SizedBox(height: 9),
        RoomGlassCard(padding: padding, radius: 16, child: child),
      ],
    );
  }
}

class RoomOxygenPill extends StatelessWidget {
  const RoomOxygenPill({
    required this.label,
    this.icon,
    this.active = false,
    this.enabled = true,
    this.accent = RoomColors.primary,
    this.onTap,
    super.key,
  });

  final String label;
  final IconData? icon;
  final bool active;
  final bool enabled;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Color foreground = !enabled
        ? RoomColors.textSecondary.withValues(alpha: 0.48)
        : active
        ? Colors.white
        : RoomColors.textSecondary;
    final Widget content = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      constraints: const BoxConstraints(minHeight: 30),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: active
            ? accent.withValues(alpha: 0.76)
            : Colors.white.withValues(alpha: enabled ? 0.055 : 0.025),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: active
              ? accent.withValues(alpha: 0.95)
              : Colors.white.withValues(alpha: enabled ? 0.09 : 0.04),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 14, color: foreground),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              color: foreground,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
    if (onTap == null || !enabled) {
      return content;
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: content,
    );
  }
}

class RoomOxygenNotice extends StatelessWidget {
  const RoomOxygenNotice({
    required this.icon,
    required this.message,
    this.accent = RoomColors.accent,
    this.title,
    super.key,
  });

  final IconData icon;
  final String? title;
  final String message;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: accent.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 17, color: accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (title != null) ...<Widget>[
                  Text(title!, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 2),
                ],
                Text(message, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class RoomOxygenMetric extends StatelessWidget {
  const RoomOxygenMetric({
    required this.label,
    required this.value,
    required this.ok,
    super.key,
  });

  final String label;
  final String value;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: <Widget>[
          Icon(
            ok ? Icons.check_circle_rounded : Icons.info_outline_rounded,
            size: 16,
            color: ok ? RoomColors.success : RoomColors.warning,
          ),
          const SizedBox(width: 9),
          Expanded(child: Text(label)),
          Text(
            value,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: ok ? RoomColors.success : RoomColors.warning,
            ),
          ),
        ],
      ),
    );
  }
}
