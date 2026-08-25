part of 'community_pages.dart';

abstract final class _CommunityPalette {
  static const Color ink = Color(0xFF22253C);
  static const Color muted = Color(0xFF747A94);
  static const Color violet = Color(0xFF7764F4);
  static const Color violetDark = Color(0xFF4B3E9E);
  static const Color line = Color(0xFFE9EAF3);
  static const Color gold = Color(0xFFF5B84C);
}

class _CommunityEntry {
  const _CommunityEntry({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.page,
    required this.tint,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget page;
  final Color tint;
}

class _CommunitySection extends StatelessWidget {
  const _CommunitySection({
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.tint = Colors.white,
    this.onTap,
    this.radius = 18,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color tint;
  final VoidCallback? onTap;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final BorderRadius borderRadius = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tint,
        borderRadius: borderRadius,
        border: Border.all(color: Colors.white.withValues(alpha: 0.84)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x0C21294A),
            blurRadius: 18,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: borderRadius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: borderRadius,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class _CommunityHero extends StatelessWidget {
  const _CommunityHero({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.trailing,
    this.colors = const <Color>[
      Color(0xFF6F63EE),
      Color(0xFF9A7AF5),
      Color(0xFFFFA1C2),
    ],
  });

  final String eyebrow;
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget? trailing;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 130),
      padding: const EdgeInsets.fromLTRB(18, 17, 16, 17),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: colors.first.withValues(alpha: 0.2),
            blurRadius: 26,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned(
            right: -18,
            top: -34,
            child: Container(
              width: 116,
              height: 116,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.12),
              ),
            ),
          ),
          Positioned(
            right: 48,
            bottom: -45,
            child: Container(
              width: 82,
              height: 82,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.13),
                  width: 13,
                ),
              ),
            ),
          ),
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      eyebrow,
                      style: const TextStyle(
                        color: Color(0xE6FFFFFF),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        height: 1.12,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xE8FFFFFF),
                        fontSize: 12,
                        height: 1.38,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              trailing ??
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.34),
                      ),
                    ),
                    child: Icon(icon, color: Colors.white, size: 29),
                  ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CommunityGlyph extends StatelessWidget {
  const _CommunityGlyph({
    required this.icon,
    required this.tint,
    this.size = 42,
  });

  final IconData icon;
  final Color tint;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.12),
        shape: BoxShape.circle,
        border: Border.all(color: tint.withValues(alpha: 0.17)),
      ),
      child: Icon(icon, color: tint, size: size * 0.49),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, this.subtitle, this.trailing});

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: const TextStyle(
                  color: _CommunityPalette.ink,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (subtitle != null) ...<Widget>[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: const TextStyle(
                    color: _CommunityPalette.muted,
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
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
    return _CommunitySection(
      onTap: onTap,
      tint: prominent ? const Color(0xFFF4F0FF) : Colors.white,
      padding: const EdgeInsets.fromLTRB(13, 12, 11, 12),
      child: Row(
        children: <Widget>[
          _LetterAvatar(
            label: guild.name,
            prominent: prominent,
            imagePath: prominent ? 'assets/runtime/avatar-night.png' : null,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        guild.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _CommunityPalette.ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (guild.joined) ...<Widget>[
                      const SizedBox(width: 6),
                      _SmallTag(label: guild.role.label),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${guild.code ?? '公会编号未提供'}  ·  ${guild.memberCount} 人',
                  style: const TextStyle(
                    color: _CommunityPalette.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  guild.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _CommunityPalette.muted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          const Icon(
            Icons.chevron_right_rounded,
            color: _CommunityPalette.muted,
            size: 21,
          ),
        ],
      ),
    );
  }
}

class _GuildHero extends StatelessWidget {
  const _GuildHero({required this.guild});

  final GuildSummary guild;

  @override
  Widget build(BuildContext context) {
    return _CommunityHero(
      eyebrow: guild.code ?? '公会编号未提供',
      title: guild.name,
      subtitle: guild.description.isEmpty ? '一起在声音里遇见同频的人' : guild.description,
      icon: Icons.groups_rounded,
      colors: const <Color>[
        Color(0xFF3E326F),
        Color(0xFF6756C6),
        Color(0xFFB078D2),
      ],
      trailing: _LetterAvatar(
        label: guild.name,
        prominent: true,
        imagePath: 'assets/runtime/avatar-night.png',
        size: 64,
      ),
    );
  }
}

class _LetterAvatar extends StatelessWidget {
  const _LetterAvatar({
    required this.label,
    this.prominent = false,
    this.imagePath,
    this.size = 44,
  });

  final String label;
  final bool prominent;
  final String? imagePath;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: prominent
            ? const LinearGradient(
                colors: <Color>[
                  Color(0xFFFFD377),
                  Color(0xFFFF8EBA),
                  Color(0xFF8C75FF),
                ],
              )
            : const LinearGradient(
                colors: <Color>[Color(0xFF9FE1FF), Color(0xFF9C82F8)],
              ),
      ),
      child: ClipOval(
        child: ColoredBox(
          color: Colors.white,
          child: imagePath == null
              ? Center(
                  child: Text(
                    _initial(label),
                    style: TextStyle(
                      color: _CommunityPalette.violetDark,
                      fontSize: size * 0.33,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                )
              : Image.asset(imagePath!, fit: BoxFit.cover),
        ),
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
    return _CommunitySection(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      tint: const Color(0xF7FFFFFF),
      radius: 16,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _CommunityGlyph(icon: icon, tint: _CommunityPalette.violet, size: 32),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: _CommunityPalette.muted,
                fontSize: 12,
                height: 1.42,
              ),
            ),
          ),
        ],
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
        padding: const EdgeInsets.all(24),
        child: _CommunitySection(
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const _CommunityGlyph(
                icon: Icons.cloud_off_rounded,
                tint: _CommunityPalette.violet,
                size: 58,
              ),
              const SizedBox(height: 13),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.tonal(onPressed: onRetry, child: Text(retryLabel)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SmallTag extends StatelessWidget {
  const _SmallTag({required this.label, this.tint = _CommunityPalette.violet});

  final String label;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tint.withValues(alpha: 0.12)),
      ),
      child: Text(
        label,
        maxLines: 1,
        style: TextStyle(
          color: tint,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          height: 1.15,
        ),
      ),
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
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 82,
            child: Text(
              label,
              style: const TextStyle(
                color: _CommunityPalette.muted,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '未提供' : value,
              style: const TextStyle(
                color: _CommunityPalette.ink,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressLine extends StatelessWidget {
  const _ProgressLine({
    required this.value,
    this.tint = _CommunityPalette.violet,
  });

  final double value;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: LinearProgressIndicator(
        minHeight: 5,
        value: value.clamp(0, 1),
        backgroundColor: tint.withValues(alpha: 0.11),
        valueColor: AlwaysStoppedAnimation<Color>(tint),
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
