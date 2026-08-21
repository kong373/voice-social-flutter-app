import 'package:flutter/material.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';

class SocialSkySurface extends StatelessWidget {
  const SocialSkySurface({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: SocialColors.page,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Image.asset(
            'assets/runtime/social-sky.png',
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  Color(0x00F7F9FF),
                  Color(0x48F7F9FF),
                  SocialColors.page,
                ],
                stops: <double>[0, 0.42, 0.78],
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class SocialPageScaffold extends StatelessWidget {
  const SocialPageScaffold({
    required this.body,
    this.appBar,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.resizeToAvoidBottomInset,
    super.key,
  });

  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final bool? resizeToAvoidBottomInset;

  @override
  Widget build(BuildContext context) {
    final String? inheritedFontFamily = Theme.of(
      context,
    ).textTheme.bodyMedium?.fontFamily;
    return Theme(
      data: AppTheme.social(fontFamily: inheritedFontFamily),
      child: SocialSkySurface(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: appBar,
          body: body,
          floatingActionButton: floatingActionButton,
          bottomNavigationBar: bottomNavigationBar,
          resizeToAvoidBottomInset: resizeToAvoidBottomInset,
        ),
      ),
    );
  }
}

class RoomCosmosSurface extends StatelessWidget {
  const RoomCosmosSurface({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: RoomColors.background,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Image.asset(
            'assets/runtime/room-cosmos.png',
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  Color(0x1608091B),
                  Color(0xA608091B),
                  RoomColors.background,
                ],
                stops: <double>[0, 0.48, 0.88],
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class RoomPageScaffold extends StatelessWidget {
  const RoomPageScaffold({
    required this.body,
    this.appBar,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.resizeToAvoidBottomInset,
    super.key,
  });

  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final bool? resizeToAvoidBottomInset;

  @override
  Widget build(BuildContext context) {
    final String? inheritedFontFamily = Theme.of(
      context,
    ).textTheme.bodyMedium?.fontFamily;
    return Theme(
      data: AppTheme.room(fontFamily: inheritedFontFamily),
      child: RoomCosmosSurface(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: appBar,
          body: body,
          floatingActionButton: floatingActionButton,
          bottomNavigationBar: bottomNavigationBar,
          resizeToAvoidBottomInset: resizeToAvoidBottomInset,
        ),
      ),
    );
  }
}

class SocialCard extends StatelessWidget {
  const SocialCard({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 22,
    this.onTap,
    this.color = SocialColors.card,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final BorderRadius borderRadius = BorderRadius.circular(radius);
    final Widget content = Padding(padding: padding, child: child);
    final Widget interactiveContent = onTap == null
        ? content
        : InkWell(onTap: onTap, borderRadius: borderRadius, child: content);
    return Container(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x120F1C3D),
            blurRadius: 22,
            offset: Offset(0, 9),
          ),
        ],
      ),
      child: Material(
        color: color,
        shape: RoundedRectangleBorder(
          borderRadius: borderRadius,
          side: const BorderSide(color: Color(0x0F17213C)),
        ),
        clipBehavior: Clip.antiAlias,
        child: interactiveContent,
      ),
    );
  }
}

class SocialSectionTitle extends StatelessWidget {
  const SocialSectionTitle({
    required this.title,
    this.subtitle,
    this.trailing,
    super.key,
  });

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
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              if (subtitle != null) ...<Widget>[
                const SizedBox(height: 3),
                Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class SocialPageIntro extends StatelessWidget {
  const SocialPageIntro({
    required this.icon,
    required this.title,
    required this.description,
    this.trailing,
    this.accent = SocialColors.primary,
    super.key,
  });

  final IconData icon;
  final String title;
  final String description;
  final Widget? trailing;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return SocialCard(
      padding: const EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: accent, size: 24),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(description, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          if (trailing != null) ...<Widget>[
            const SizedBox(width: 10),
            trailing!,
          ],
        ],
      ),
    );
  }
}

class SocialStateView extends StatelessWidget {
  const SocialStateView({
    required this.icon,
    required this.title,
    required this.description,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final IconData icon;
  final String title;
  final String description;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: SocialCard(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: SocialColors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: SocialColors.primary, size: 31),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 7),
              Text(
                description,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (actionLabel != null && onAction != null) ...<Widget>[
                const SizedBox(height: 20),
                FilledButton.tonal(
                  onPressed: onAction,
                  child: Text(actionLabel!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class SocialMetric extends StatelessWidget {
  const SocialMetric({
    required this.label,
    required this.value,
    this.emphasized = false,
    super.key,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: emphasized ? SocialColors.primary : SocialColors.textPrimary,
          ),
        ),
        const SizedBox(height: 3),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class RoomGlassCard extends StatelessWidget {
  const RoomGlassCard({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.radius = 18,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final BorderRadius borderRadius = BorderRadius.circular(radius);
    return Material(
      color: Colors.white.withValues(alpha: 0.055),
      shape: RoundedRectangleBorder(
        borderRadius: borderRadius,
        side: BorderSide(color: Colors.white.withValues(alpha: 0.07)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class SocialPill extends StatelessWidget {
  const SocialPill({
    required this.label,
    this.active = false,
    this.icon,
    this.onTap,
    super.key,
  });

  final String label;
  final bool active;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Color foreground = active ? Colors.white : SocialColors.textSecondary;
    final Widget body = Container(
      constraints: const BoxConstraints(minHeight: 36),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
      decoration: BoxDecoration(
        gradient: active ? SocialColors.brandGradient : null,
        color: active ? null : Colors.white.withValues(alpha: 0.76),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: active
              ? Colors.white.withValues(alpha: 0.3)
              : const Color(0x1417263F),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, color: foreground, size: 16),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              color: foreground,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
    return onTap == null
        ? body
        : InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(999),
            child: body,
          );
  }
}

class OriginalRoomArtwork extends StatelessWidget {
  const OriginalRoomArtwork({
    required this.seed,
    required this.height,
    this.borderRadius = const BorderRadius.all(Radius.circular(22)),
    this.child,
    super.key,
  });

  final String seed;
  final double height;
  final BorderRadius borderRadius;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final int value = _stableSeed(seed);
    const List<String> artwork = <String>[
      'assets/runtime/room-cover-ruby.png',
      'assets/runtime/room-cover-island.png',
      'assets/runtime/room-cover-festival.png',
      'assets/runtime/room-cover-moon.png',
    ];
    return ClipRRect(
      borderRadius: borderRadius,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Image.asset(
              artwork[value.abs() % artwork.length],
              fit: BoxFit.cover,
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    Color(0x08000000),
                    Color(0x15000000),
                    Color(0xA6000018),
                  ],
                  stops: <double>[0, 0.48, 1],
                ),
              ),
            ),
            if (child != null) child!,
          ],
        ),
      ),
    );
  }
}

class RuntimeAvatar extends StatelessWidget {
  const RuntimeAvatar({
    required this.seed,
    this.size = 44,
    this.ringColor,
    super.key,
  });

  final String seed;
  final double size;
  final Color? ringColor;

  @override
  Widget build(BuildContext context) {
    final int value = _stableSeed(seed);
    const List<String> avatars = <String>[
      'assets/runtime/avatar-rose.png',
      'assets/runtime/avatar-night.png',
      'assets/runtime/avatar-copper.png',
      'assets/runtime/avatar-silver.png',
    ];
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: ringColor ?? Colors.white.withValues(alpha: 0.8),
          width: 2,
        ),
      ),
      child: ClipOval(
        child: Image.asset(
          avatars[value.abs() % avatars.length],
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
          errorBuilder: (_, __, ___) => const ColoredBox(
            color: SocialColors.primary,
            child: Icon(Icons.person_rounded, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

int _stableSeed(String seed) =>
    seed.codeUnits.fold<int>(17, (int value, int unit) => value * 37 + unit);

class RuntimeWaveform extends StatelessWidget {
  const RuntimeWaveform({this.active = true, this.width = 42, super.key});

  final bool active;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 18,
      child: CustomPaint(painter: _RuntimeWavePainter(active)),
    );
  }
}

class _RuntimeWavePainter extends CustomPainter {
  const _RuntimeWavePainter(this.active);

  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    const List<double> values = <double>[0.35, 0.7, 1, 0.52, 0.82, 0.42, 0.66];
    final Paint paint = Paint()
      ..color = (active ? SocialColors.accent : SocialColors.textTertiary)
          .withValues(alpha: active ? 0.9 : 0.45)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final double step = size.width / values.length;
    for (int index = 0; index < values.length; index += 1) {
      final double barHeight = size.height * (active ? values[index] : 0.26);
      final double x = step * index + step / 2;
      canvas.drawLine(
        Offset(x, (size.height - barHeight) / 2),
        Offset(x, (size.height + barHeight) / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RuntimeWavePainter oldDelegate) =>
      oldDelegate.active != active;
}

class MinimizedRoomPill extends StatelessWidget {
  const MinimizedRoomPill({
    required this.title,
    required this.onRestore,
    required this.onClose,
    super.key,
  });

  final String title;
  final VoidCallback onRestore;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xF4E8E2FF),
      borderRadius: BorderRadius.circular(20),
      elevation: 10,
      shadowColor: const Color(0x3D5D4CBF),
      child: InkWell(
        key: const Key('minimized-room-pill'),
        onTap: onRestore,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(5, 5, 2, 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              RuntimeAvatar(seed: title, size: 36, ringColor: Colors.white),
              const SizedBox(width: 7),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 86),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: SocialColors.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const RuntimeWaveform(width: 31),
                  ],
                ),
              ),
              IconButton(
                tooltip: '退出当前房间',
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(
                  width: 34,
                  height: 34,
                ),
                padding: EdgeInsets.zero,
                onPressed: onClose,
                icon: const Icon(
                  Icons.power_settings_new_rounded,
                  size: 17,
                  color: SocialColors.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
