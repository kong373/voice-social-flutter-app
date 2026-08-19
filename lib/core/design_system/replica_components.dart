import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';

/// Shared visual primitives for the clean-room APK-inspired interface.
///
/// The implementation deliberately uses deterministic Flutter drawing rather
/// than copying branded images, logos or proprietary artwork from the APK.
class ReplicaAppBackdrop extends StatelessWidget {
  const ReplicaAppBackdrop({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.background,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  Color(0xFF121143),
                  Color(0xFF080D25),
                  AppColors.background,
                ],
                stops: <double>[0, 0.38, 1],
              ),
            ),
          ),
          const Positioned(
            top: -160,
            left: -130,
            child: _GlowOrb(size: 360, color: Color(0x4D7E64FF)),
          ),
          const Positioned(
            top: 120,
            right: -180,
            child: _GlowOrb(size: 380, color: Color(0x3358D8FF)),
          ),
          const Positioned(
            bottom: -220,
            left: 40,
            child: _GlowOrb(size: 420, color: Color(0x29FF6EAF)),
          ),
          child,
        ],
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: <Color>[color, color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}

class ReplicaPanel extends StatelessWidget {
  const ReplicaPanel({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 22,
    this.onTap,
    this.borderColor,
    this.color,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  final Color? borderColor;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final BorderRadius borderRadius = BorderRadius.circular(radius);
    final Widget body = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? AppColors.surface.withValues(alpha: 0.90),
        borderRadius: borderRadius,
        border: Border.all(
          color: borderColor ?? Colors.white.withValues(alpha: 0.075),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.24),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
    if (onTap == null) {
      return body;
    }
    return Material(
      color: Colors.transparent,
      borderRadius: borderRadius,
      child: InkWell(onTap: onTap, borderRadius: borderRadius, child: body),
    );
  }
}

class ReplicaSectionTitle extends StatelessWidget {
  const ReplicaSectionTitle({
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
                const SizedBox(height: 4),
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

class ReplicaPill extends StatelessWidget {
  const ReplicaPill({
    required this.label,
    this.icon,
    this.active = false,
    this.onTap,
    this.compact = false,
    super.key,
  });

  final String label;
  final IconData? icon;
  final bool active;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final Color foreground = active ? Colors.white : AppColors.textSecondary;
    final Widget content = Container(
      constraints: const BoxConstraints(minHeight: 36),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 13,
        vertical: compact ? 7 : 9,
      ),
      decoration: BoxDecoration(
        gradient: active
            ? const LinearGradient(
                colors: <Color>[AppColors.primary, AppColors.secondary],
              )
            : null,
        color: active ? null : AppColors.surfaceHigh.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: active
              ? Colors.white.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 16, color: foreground),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) {
      return content;
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: content,
    );
  }
}

class ReplicaIconTile extends StatelessWidget {
  const ReplicaIconTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.accent = AppColors.primary,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[
                    accent.withValues(alpha: 0.30),
                    AppColors.surfaceHigh.withValues(alpha: 0.82),
                  ],
                ),
                border: Border.all(color: accent.withValues(alpha: 0.28)),
              ),
              child: Icon(icon, color: accent),
            ),
            const SizedBox(height: 7),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}

class ReplicaRoomArtwork extends StatelessWidget {
  const ReplicaRoomArtwork({
    required this.seed,
    this.height = 150,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.child,
    super.key,
  });

  final String seed;
  final double height;
  final BorderRadius borderRadius;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final int value = seed.codeUnits.fold<int>(
      17,
      (int a, int b) => a * 31 + b,
    );
    final List<List<Color>> palettes = <List<Color>>[
      const <Color>[Color(0xFF31245D), Color(0xFF111A40), Color(0xFF071020)],
      const <Color>[Color(0xFF183D5C), Color(0xFF17204B), Color(0xFF080E26)],
      const <Color>[Color(0xFF512142), Color(0xFF292153), Color(0xFF080D22)],
      const <Color>[Color(0xFF2D356B), Color(0xFF142B4E), Color(0xFF070C20)],
      const <Color>[Color(0xFF5C3324), Color(0xFF31204C), Color(0xFF080D20)],
    ];
    final List<Color> colors = palettes[value.abs() % palettes.length];
    return ClipRRect(
      borderRadius: borderRadius,
      child: SizedBox(
        height: height,
        child: CustomPaint(
          painter: _RoomArtworkPainter(seed: value, colors: colors),
          child: child,
        ),
      ),
    );
  }
}

class _RoomArtworkPainter extends CustomPainter {
  const _RoomArtworkPainter({required this.seed, required this.colors});

  final int seed;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    final Paint background = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: colors,
      ).createShader(rect);
    canvas.drawRect(rect, background);

    final math.Random random = math.Random(seed);
    final Paint star = Paint()..color = Colors.white.withValues(alpha: 0.58);
    for (int index = 0; index < 42; index += 1) {
      final Offset point = Offset(
        random.nextDouble() * size.width,
        random.nextDouble() * size.height * 0.62,
      );
      canvas.drawCircle(point, random.nextDouble() * 1.4 + 0.35, star);
    }

    final Paint moon = Paint()
      ..shader =
          const RadialGradient(
            colors: <Color>[Color(0xFFF5EEFF), Color(0xFF9C7CFF)],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * 0.78, size.height * 0.22),
              radius: size.shortestSide * 0.14,
            ),
          );
    canvas.drawCircle(
      Offset(size.width * 0.78, size.height * 0.22),
      size.shortestSide * 0.085,
      moon,
    );

    final Path mountain = Path()
      ..moveTo(0, size.height)
      ..lineTo(0, size.height * 0.72);
    double x = 0;
    while (x <= size.width) {
      mountain.lineTo(x, size.height * (0.58 + random.nextDouble() * 0.2));
      x += size.width / 8;
    }
    mountain
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(mountain, Paint()..color = const Color(0xD9070A1C));

    final Paint reflection = Paint()..strokeCap = StrokeCap.round;
    for (int index = 0; index < 18; index += 1) {
      final double y = size.height * (0.76 + random.nextDouble() * 0.22);
      final double startX = random.nextDouble() * size.width;
      reflection
        ..color = (index.isEven ? AppColors.primary : AppColors.accent)
            .withValues(alpha: 0.13 + random.nextDouble() * 0.18)
        ..strokeWidth = 1 + random.nextDouble() * 2;
      canvas.drawLine(
        Offset(startX, y),
        Offset(math.min(size.width, startX + 16 + random.nextDouble() * 90), y),
        reflection,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RoomArtworkPainter oldDelegate) =>
      oldDelegate.seed != seed || oldDelegate.colors != colors;
}

class ReplicaAvatar extends StatelessWidget {
  const ReplicaAvatar({
    required this.seed,
    this.size = 42,
    this.ringColor,
    super.key,
  });

  final String seed;
  final double size;
  final Color? ringColor;

  @override
  Widget build(BuildContext context) {
    final int value = seed.codeUnits.fold<int>(
      11,
      (int a, int b) => a * 37 + b,
    );
    final List<Color> colors = <Color>[
      AppColors.primary,
      AppColors.secondary,
      AppColors.accent,
      AppColors.success,
      AppColors.warning,
    ];
    final Color first = colors[value.abs() % colors.length];
    final Color second = colors[(value.abs() + 2) % colors.length];
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: ringColor ?? Colors.white.withValues(alpha: 0.18),
          width: 2,
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[first, second.withValues(alpha: 0.72)],
          ),
        ),
        child: Icon(
          value.isEven ? Icons.person_rounded : Icons.auto_awesome_rounded,
          color: Colors.white.withValues(alpha: 0.92),
          size: size * 0.52,
        ),
      ),
    );
  }
}

class ReplicaWaveform extends StatelessWidget {
  const ReplicaWaveform({
    this.active = true,
    this.width = 46,
    this.height = 18,
    super.key,
  });

  final bool active;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(painter: _WaveformPainter(active: active)),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  const _WaveformPainter({required this.active});

  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = (active ? AppColors.accent : AppColors.textSecondary)
          .withValues(alpha: active ? 0.88 : 0.42)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    const List<double> levels = <double>[
      0.32,
      0.62,
      0.9,
      0.48,
      0.76,
      0.36,
      0.68,
    ];
    final double step = size.width / levels.length;
    for (int index = 0; index < levels.length; index += 1) {
      final double barHeight = size.height * (active ? levels[index] : 0.28);
      final double x = step * index + step / 2;
      canvas.drawLine(
        Offset(x, (size.height - barHeight) / 2),
        Offset(x, (size.height + barHeight) / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) =>
      oldDelegate.active != active;
}
