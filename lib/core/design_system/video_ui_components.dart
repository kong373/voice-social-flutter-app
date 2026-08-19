import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';

class LobbyTheme extends StatelessWidget {
  const LobbyTheme({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Theme(data: AppTheme.lobby(), child: child);
  }
}

class LobbyBackdrop extends StatelessWidget {
  const LobbyBackdrop({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        const ColoredBox(color: AppColors.lobbyBackground),
        const Positioned(
          top: -130,
          left: -100,
          child: _SoftOrb(size: 330, color: Color(0x99DDF3FF)),
        ),
        const Positioned(
          top: 110,
          right: -160,
          child: _SoftOrb(size: 360, color: Color(0x88EADFFF)),
        ),
        child,
      ],
    );
  }
}

class _SoftOrb extends StatelessWidget {
  const _SoftOrb({required this.size, required this.color});

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

class LobbyCard extends StatelessWidget {
  const LobbyCard({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 22,
    this.onTap,
    this.gradient,
    this.color,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  final Gradient? gradient;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final BorderRadius borderRadius = BorderRadius.circular(radius);
    final Widget content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? color ?? Colors.white : null,
        gradient: gradient,
        borderRadius: borderRadius,
        border: Border.all(color: Colors.white.withValues(alpha: 0.82)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(0xFF7D88B5).withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
    if (onTap == null) {
      return content;
    }
    return Material(
      color: Colors.transparent,
      borderRadius: borderRadius,
      child: InkWell(onTap: onTap, borderRadius: borderRadius, child: content),
    );
  }
}

class LobbyPill extends StatelessWidget {
  const LobbyPill({
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
    final Widget content = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      constraints: const BoxConstraints(minHeight: 36),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
      decoration: BoxDecoration(
        color: active ? AppColors.primary : Colors.white.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: active ? AppColors.primary : AppColors.lobbyDivider,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(
              icon,
              size: 16,
              color: active ? Colors.white : AppColors.lobbyTextSecondary,
            ),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: active ? Colors.white : AppColors.lobbyText,
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

class RoomArtwork extends StatelessWidget {
  const RoomArtwork({
    required this.seed,
    this.height = 150,
    this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(22)),
    super.key,
  });

  final String seed;
  final double height;
  final Widget? child;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    final int value = seed.codeUnits.fold<int>(17, (int a, int b) => a * 31 + b);
    return ClipRRect(
      borderRadius: borderRadius,
      child: SizedBox(
        height: height,
        child: CustomPaint(
          painter: _RoomArtworkPainter(seed: value),
          child: child,
        ),
      ),
    );
  }
}

class _RoomArtworkPainter extends CustomPainter {
  const _RoomArtworkPainter({required this.seed});

  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final math.Random random = math.Random(seed);
    final List<List<Color>> palettes = <List<Color>>[
      const <Color>[Color(0xFF8EA8FF), Color(0xFFB6A5FF), Color(0xFF6255A5)],
      const <Color>[Color(0xFF77D7F3), Color(0xFF93B6FF), Color(0xFF53619F)],
      const <Color>[Color(0xFFFF9FC8), Color(0xFFBEA3FF), Color(0xFF6A559D)],
      const <Color>[Color(0xFFFFC991), Color(0xFFFF9FC3), Color(0xFF7B5C94)],
    ];
    final List<Color> colors = palettes[seed.abs() % palettes.length];
    final Rect rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ).createShader(rect),
    );

    final Paint cloud = Paint()..color = Colors.white.withValues(alpha: 0.18);
    for (int index = 0; index < 7; index += 1) {
      final double radius = 24 + random.nextDouble() * 44;
      canvas.drawCircle(
        Offset(
          random.nextDouble() * size.width,
          size.height * (0.12 + random.nextDouble() * 0.52),
        ),
        radius,
        cloud,
      );
    }

    final Paint star = Paint()..color = Colors.white.withValues(alpha: 0.75);
    for (int index = 0; index < 28; index += 1) {
      canvas.drawCircle(
        Offset(random.nextDouble() * size.width, random.nextDouble() * size.height),
        0.5 + random.nextDouble() * 1.2,
        star,
      );
    }

    final Path hills = Path()
      ..moveTo(0, size.height)
      ..lineTo(0, size.height * 0.66);
    for (int index = 0; index <= 8; index += 1) {
      hills.lineTo(
        size.width * index / 8,
        size.height * (0.58 + random.nextDouble() * 0.18),
      );
    }
    hills
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(hills, Paint()..color = const Color(0x5524275C));
  }

  @override
  bool shouldRepaint(covariant _RoomArtworkPainter oldDelegate) =>
      oldDelegate.seed != seed;
}

class ColorAvatar extends StatelessWidget {
  const ColorAvatar({
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
    final int value = seed.codeUnits.fold<int>(11, (int a, int b) => a * 37 + b);
    final List<Color> colors = <Color>[
      AppColors.primary,
      AppColors.secondary,
      AppColors.accent,
      AppColors.success,
      AppColors.gold,
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
          color: ringColor ?? Colors.white.withValues(alpha: 0.82),
          width: 2,
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(colors: <Color>[first, second]),
        ),
        child: Icon(
          value.isEven ? Icons.person_rounded : Icons.auto_awesome_rounded,
          color: Colors.white,
          size: size * 0.52,
        ),
      ),
    );
  }
}

class VoiceWave extends StatelessWidget {
  const VoiceWave({this.active = true, this.width = 42, super.key});

  final bool active;
  final double width;

  @override
  Widget build(BuildContext context) {
    const List<double> levels = <double>[0.34, 0.66, 0.95, 0.54, 0.78, 0.4];
    return SizedBox(
      width: width,
      height: 18,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          for (final double level in levels)
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 2.4,
              height: active ? 18 * level : 5,
              decoration: BoxDecoration(
                color: active ? AppColors.accent : AppColors.textTertiary,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
        ],
      ),
    );
  }
}
