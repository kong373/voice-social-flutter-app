import 'package:flutter/material.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';

/// Account-only surfaces inspired by the airy profile and settings hierarchy
/// in the Oxygen reference. They deliberately stay inside the account feature
/// so other product areas can evolve independently.
abstract final class AccountOxygenColors {
  static const Color ink = Color(0xFF24273B);
  static const Color muted = Color(0xFF777F98);
  static const Color softLavender = Color(0xFFF3F1FF);
  static const Color softBlue = Color(0xFFEDF8FF);
  static const Color line = Color(0xFFECECF4);
  static const Color violet = Color(0xFF7867E8);
  static const Color pink = Color(0xFFFF79B3);
  static const Color cyan = Color(0xFF54C5ED);
}

class AccountBrandMark extends StatelessWidget {
  const AccountBrandMark({this.size = 66, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color(0xFF83DAF5),
            AccountOxygenColors.violet,
            AccountOxygenColors.pink,
          ],
        ),
        borderRadius: BorderRadius.circular(size * 0.34),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x287566E7),
            blurRadius: 28,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Icon(
        Icons.graphic_eq_rounded,
        color: Colors.white,
        size: size * 0.5,
      ),
    );
  }
}

class AccountMistHero extends StatelessWidget {
  const AccountMistHero({
    required this.title,
    required this.subtitle,
    this.eyebrow,
    this.markSize = 68,
    this.centered = true,
    super.key,
  });

  final String? eyebrow;
  final String title;
  final String subtitle;
  final double markSize;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final CrossAxisAlignment alignment = centered
        ? CrossAxisAlignment.center
        : CrossAxisAlignment.start;
    return Column(
      crossAxisAlignment: alignment,
      children: <Widget>[
        AccountBrandMark(size: markSize),
        const SizedBox(height: 18),
        if (eyebrow != null) ...<Widget>[
          Text(
            eyebrow!,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: AccountOxygenColors.violet,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
        ],
        Text(
          title,
          textAlign: centered ? TextAlign.center : TextAlign.start,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: AccountOxygenColors.ink,
            fontSize: 27,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          textAlign: centered ? TextAlign.center : TextAlign.start,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: AccountOxygenColors.muted,
            height: 1.55,
          ),
        ),
      ],
    );
  }
}

class AccountSheet extends StatelessWidget {
  const AccountSheet({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 18,
    this.color = const Color(0xF7FFFFFF),
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final BorderRadius borderRadius = BorderRadius.circular(radius);
    return Container(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x0D24315B),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: color,
        shape: RoundedRectangleBorder(
          borderRadius: borderRadius,
          side: const BorderSide(color: Color(0xCCFFFFFF)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class AccountSectionLabel extends StatelessWidget {
  const AccountSectionLabel({required this.text, this.trailing, super.key});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 9),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: AccountOxygenColors.ink,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class AccountStatusHero extends StatelessWidget {
  const AccountStatusHero({
    required this.icon,
    required this.title,
    required this.description,
    this.tone = AccountOxygenColors.violet,
    this.badge,
    super.key,
  });

  final IconData icon;
  final String title;
  final String description;
  final Color tone;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return AccountSheet(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 17),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.11),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: tone, size: 23),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: AccountOxygenColors.ink,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                    if (badge != null) ...<Widget>[
                      const SizedBox(width: 8),
                      AccountStatusPill(label: badge!, color: tone),
                    ],
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AccountOxygenColors.muted,
                    height: 1.48,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AccountStatusPill extends StatelessWidget {
  const AccountStatusPill({
    required this.label,
    this.color = AccountOxygenColors.violet,
    super.key,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 24),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class AccountSettingRow extends StatelessWidget {
  const AccountSettingRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailingLabel,
    this.trailing,
    this.onTap,
    this.tone = AccountOxygenColors.violet,
    this.showDivider = true,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? trailingLabel;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color tone;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final Widget row = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: tone.withValues(alpha: 0.09),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: tone, size: 19),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AccountOxygenColors.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (subtitle != null) ...<Widget>[
                    const SizedBox(height: 3),
                    Text(
                      subtitle!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AccountOxygenColors.muted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (trailing != null)
              trailing!
            else if (trailingLabel != null)
              Text(
                trailingLabel!,
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(color: tone, fontSize: 11),
              ),
            if (onTap != null) ...<Widget>[
              const SizedBox(width: 5),
              const Icon(
                Icons.chevron_right_rounded,
                color: AccountOxygenColors.muted,
                size: 20,
              ),
            ],
          ],
        ),
      ),
    );
    return Column(
      children: <Widget>[
        row,
        if (showDivider)
          const Padding(
            padding: EdgeInsets.only(left: 50),
            child: Divider(height: 1, color: AccountOxygenColors.line),
          ),
      ],
    );
  }
}

class AccountNoticeStrip extends StatelessWidget {
  const AccountNoticeStrip({
    required this.icon,
    required this.text,
    this.tone = AccountOxygenColors.violet,
    super.key,
  });

  final IconData icon;
  final String text;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, color: tone, size: 18),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AccountOxygenColors.muted,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AccountPrimaryAction extends StatelessWidget {
  const AccountPrimaryAction({
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.icon,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: FilledButton(
        onPressed: busy ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: AccountOxygenColors.violet,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: busy
            ? const SizedBox.square(
                dimension: 19,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (icon != null) ...<Widget>[
                    Icon(icon, size: 18),
                    const SizedBox(width: 7),
                  ],
                  Text(label),
                ],
              ),
      ),
    );
  }
}

class AccountBottomActionBar extends StatelessWidget {
  const AccountBottomActionBar({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
        decoration: const BoxDecoration(
          color: Color(0xF5FFFFFF),
          border: Border(top: BorderSide(color: AccountOxygenColors.line)),
        ),
        child: child,
      ),
    );
  }
}

class AccountCompactProgress extends StatelessWidget {
  const AccountCompactProgress({this.label = '正在载入', super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
          const SizedBox(height: 12),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

Color accountToneForState({required bool positive, bool warning = false}) {
  if (warning) {
    return AppColors.warning;
  }
  return positive ? AppColors.success : AccountOxygenColors.violet;
}
