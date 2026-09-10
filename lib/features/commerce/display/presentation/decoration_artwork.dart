import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../domain/equipped_decoration.dart';

/// The same product-specific vector art is used in preview and real wear.
/// No URLs, files, network requests, membership state, or purchase mutations.
class DecorationArtwork extends StatelessWidget {
  const DecorationArtwork({
    required this.product,
    this.size = 72,
    this.progress = 1,
    super.key,
  });
  final DecorationProduct product;
  final double size;
  final double progress;

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: product.label,
    child: IgnorePointer(
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          key: ValueKey('decoration-art-${product.assetKey}'),
          painter: DecorationProductPainter(product, progress: progress),
        ),
      ),
    ),
  );
}

class DecorationProductPainter extends CustomPainter {
  const DecorationProductPainter(this.product, {this.progress = 1});
  final DecorationProduct product;
  final double progress;
  static const purple = Color(0xFF9D6AF0);
  static const pale = Color(0xFFF0DEFF);
  static const deep = Color(0xFF6343A5);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    switch (product) {
      case DecorationProduct.starRingFrame:
        _frame(canvas);
      case DecorationProduct.streamEntry:
        _entry(canvas);
      case DecorationProduct.companionBadge:
        _badge(canvas);
    }
    canvas.restore();
  }

  void _frame(Canvas canvas) {
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..shader = const SweepGradient(
        colors: [purple, pale, deep, pale, purple],
      ).createShader(const Rect.fromLTWH(4, 4, 92, 92));
    canvas.drawCircle(const Offset(50, 50), 44, ring);
    canvas.drawArc(
      const Rect.fromLTWH(2, 10, 96, 80),
      -.5,
      3.5,
      false,
      Paint()
        ..color = purple
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    canvas.drawArc(
      const Rect.fromLTWH(9, 9, 82, 82),
      .9,
      1.9,
      false,
      Paint()
        ..color = pale
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    _star(canvas, const Offset(82, 16), 9, pale);
    _star(canvas, const Offset(16, 75), 6, purple);
    canvas.drawCircle(const Offset(44, 5), 2.2, Paint()..color = pale);
  }

  void _entry(Canvas canvas) {
    final reveal = progress.isFinite ? progress.clamp(0.0, 1.0) : 0.0;
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, 100 * reveal, 100));
    final ribbon = Path()
      ..moveTo(3, 67)
      ..cubicTo(29, 12, 64, 87, 97, 26)
      ..cubicTo(71, 105, 34, 47, 3, 67)
      ..close();
    canvas.drawPath(
      ribbon,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0x006343A5), purple, pale],
        ).createShader(const Rect.fromLTWH(0, 20, 100, 65)),
    );
    for (var i = 0; i < 3; i++) {
      final trail = Path()
        ..moveTo(3, 80 - i * 7)
        ..cubicTo(40, 28 - i * 3, 63, 99 - i * 6, 94, 31 - i * 5);
      canvas.drawPath(
        trail,
        Paint()
          ..color = i == 1 ? pale : purple
          ..style = PaintingStyle.stroke
          ..strokeWidth = i == 1 ? 1.6 : .8,
      );
    }
    _star(canvas, const Offset(87, 26), 10, pale);
    _star(canvas, const Offset(65, 31), 4.5, purple);
    _star(canvas, const Offset(27, 59), 3.5, pale);
    canvas.restore();
  }

  void _badge(Canvas canvas) {
    final ribbon = Paint()..color = deep;
    canvas.drawPath(
      Path()
        ..moveTo(29, 59)
        ..lineTo(20, 91)
        ..lineTo(36, 84)
        ..lineTo(46, 96)
        ..lineTo(51, 67)
        ..close(),
      ribbon,
    );
    canvas.drawPath(
      Path()
        ..moveTo(71, 59)
        ..lineTo(80, 91)
        ..lineTo(64, 84)
        ..lineTo(54, 96)
        ..lineTo(49, 67)
        ..close(),
      ribbon,
    );
    final medallion = Path();
    for (var i = 0; i < 12; i++) {
      final a = -math.pi / 2 + i * math.pi / 6;
      final radius = i.isEven ? 37.0 : 33.0;
      final point = Offset(
        50 + math.cos(a) * radius,
        42 + math.sin(a) * radius,
      );
      if (i == 0) {
        medallion.moveTo(point.dx, point.dy);
      } else {
        medallion.lineTo(point.dx, point.dy);
      }
    }
    medallion.close();
    canvas.drawPath(
      medallion,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [pale, purple, deep],
        ).createShader(const Rect.fromLTWH(13, 5, 74, 74)),
    );
    canvas.drawCircle(
      const Offset(50, 42),
      26,
      Paint()
        ..color = pale
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3,
    );
    final bond = Paint()
      ..color = pale
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawOval(const Rect.fromLTWH(29, 31, 25, 20), bond);
    canvas.drawOval(const Rect.fromLTWH(46, 31, 25, 20), bond);
    _star(canvas, const Offset(50, 61), 4, pale);
  }

  static void _star(Canvas canvas, Offset center, double radius, Color color) {
    final path = Path();
    for (var i = 0; i < 8; i++) {
      final a = -math.pi / 2 + i * math.pi / 4;
      final r = i.isEven ? radius : radius * .28;
      final x = center.dx + math.cos(a) * r;
      final y = center.dy + math.sin(a) * r;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path..close(), Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant DecorationProductPainter oldDelegate) =>
      oldDelegate.product != product || oldDelegate.progress != progress;
}
