import 'dart:math' as math;

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
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  Color(0xFFDDEEFF),
                  Color(0xFFF0EDFF),
                  SocialColors.page,
                ],
                stops: <double>[0, 0.34, 0.72],
              ),
            ),
          ),
          const Positioned(
            top: -86,
            right: -74,
            child: _SoftOrb(size: 260, color: Color(0x668F79FF)),
          ),
          const Positioned(
            top: 120,
            left: -110,
            child: _SoftOrb(size: 250, color: Color(0x554FBFFF)),
          ),
          child,
        ],
      ),
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
      child: SizedBox.square(
        dimension: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: <Color>[color, color.withValues(alpha: 0)],
            ),
          ),
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
    final Widget body = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: borderRadius,
        border: Border.all(color: const Color(0x0F17213C)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x120F1C3D),
            blurRadius: 22,
            offset: Offset(0, 9),
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
    return ClipRRect(
      borderRadius: borderRadius,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _OriginalRoomPainter(seed),
          child: child,
        ),
      ),
    );
  }
}

class _OriginalRoomPainter extends CustomPainter {
  _OriginalRoomPainter(String seed)
      : value = seed.codeUnits.fold<int>(19, (int a, int b) => a * 37 + b);

  final int value;

  @override
  void paint(Canvas canvas, Size size) {
    final math.Random random = math.Random(value);
    const List<List<Color>> palettes = <List<Color>>[
      <Color>[Color(0xFF6F84FF), Color(0xFFAE7CE9), Color(0xFF303A7B)],
      <Color>[Color(0xFF4AB6CE), Color(0xFF7E8EED), Color(0xFF35416C)],
      <Color>[Color(0xFFF18CB1), Color(0xFF967CDB), Color(0xFF3C3769)],
      <Color>[Color(0xFFFFBA7A), Color(0xFFEC829E), Color(0xFF57406F)],
    ];
    final List<Color> colors = palettes[value.abs() % palettes.length];
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
    canvas.drawCircle(
      Offset(size.width * 0.83, size.height * 0.16),
      size.shortestSide * 0.22,
      Paint()..color = Colors.white.withValues(alpha: 0.12),
    );
    final Paint star = Paint()..color = Colors.white.withValues(alpha: 0.6);
    for (int index = 0; index < 30; index += 1) {
      canvas.drawCircle(
        Offset(
          random.nextDouble() * size.width,
          random.nextDouble() * size.height * 0.65,
        ),
        random.nextDouble() * 1.3 + 0.3,
        star,
      );
    }
    final Path hills = Path()..moveTo(0, size.height);
    double x = 0;
    while (x <= size.width) {
      hills.lineTo(x, size.height * (0.62 + random.nextDouble() * 0.16));
      x += size.width / 7;
    }
    hills
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(hills, Paint()..color = const Color(0x66302C69));
  }

  @override
  bool shouldRepaint(covariant _OriginalRoomPainter oldDelegate) =>
      oldDelegate.value != value;
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
    final int value = seed.codeUnits.fold<int>(13, (int a, int b) => a * 31 + b);
    const List<Color> palette = <Color>[
      SocialColors.primary,
      SocialColors.secondary,
      SocialColors.accent,
      Color(0xFFFFB46F),
      Color(0xFF69C8A7),
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
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: <Color>[
              palette[value.abs() % palette.length],
              palette[(value.abs() + 2) % palette.length],
            ],
          ),
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
      color: const Color(0xF21B1A41),
      borderRadius: BorderRadius.circular(999),
      elevation: 10,
      shadowColor: const Color(0x553A2C78),
      child: InkWell(
        key: const Key('minimized-room-pill'),
        onTap: onRestore,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(5, 5, 3, 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              RuntimeAvatar(seed: title, size: 34, ringColor: Colors.white),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 110),
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 5),
              const RuntimeWaveform(width: 28),
              IconButton(
                tooltip: '退出当前房间',
                visualDensity: VisualDensity.compact,
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded, size: 18),
                color: Colors.white70,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
