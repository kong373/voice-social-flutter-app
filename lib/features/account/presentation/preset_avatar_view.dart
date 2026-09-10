import 'package:flutter/material.dart';
import 'package:voice_social_app/features/account/domain/preset_avatar.dart';

const Color _avatarInk = Color(0xFF485460);
const Color _selectionColor = Color(0xFF397D70);

/// Native vector preview. Unknown identifiers render a neutral silhouette.
class PresetAvatarView extends StatelessWidget {
  const PresetAvatarView({required this.presetId, this.size = 64, super.key})
    : assert(size > 0 && size < double.infinity);

  final String presetId;
  final double size;

  @override
  Widget build(BuildContext context) {
    final avatar = PresetAvatars.byId(presetId);

    return Semantics(
      image: true,
      label: avatar == null ? '头像不可用' : '${avatar.label}头像',
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: size,
        child: RepaintBoundary(
          child: CustomPaint(painter: _PresetAvatarPainter(avatar?.id)),
        ),
      ),
    );
  }
}

/// Controlled picker: selection belongs exclusively to the parent.
///
/// Null or unknown selectedId selects nothing. A tap only reports an exact
/// catalog ID; it never changes selection, focus or keyboard state itself.
class PresetAvatarPicker extends StatelessWidget {
  const PresetAvatarPicker({
    required this.selectedId,
    required this.onSelected,
    this.enabled = true,
    super.key,
  });

  final String? selectedId;
  final ValueChanged<String> onSelected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.maybeOf(context);
    final reduceMotion =
        (media?.disableAnimations ?? false) ||
        (media?.accessibleNavigation ?? false);
    final duration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 120);

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : 312.0;
        final itemWidth = ((availableWidth - 24) / 3)
            .clamp(80.0, 112.0)
            .toDouble();

        return Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final avatar in PresetAvatars.values)
              _PresetAvatarOption(
                avatar: avatar,
                width: itemWidth,
                selected: selectedId == avatar.id,
                enabled: enabled,
                duration: duration,
                onSelected: onSelected,
              ),
          ],
        );
      },
    );
  }
}

class _PresetAvatarOption extends StatelessWidget {
  const _PresetAvatarOption({
    required this.avatar,
    required this.width,
    required this.selected,
    required this.enabled,
    required this.duration,
    required this.onSelected,
  });

  final PresetAvatar avatar;
  final double width;
  final bool selected;
  final bool enabled;
  final Duration duration;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final VoidCallback? activate = enabled ? () => onSelected(avatar.id) : null;

    // One accessibility node owns the label, state and action.
    // Descendant text, avatar and check mark must not repeat the announcement.
    return Semantics(
      key: ValueKey<String>('preset-avatar-option:${avatar.id}'),
      container: true,
      excludeSemantics: true,
      button: true,
      selected: selected,
      enabled: enabled,
      label: avatar.label,
      onTap: activate,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: activate,
        child: SizedBox(
          width: width,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Opacity(
                opacity: enabled ? 1 : 0.5,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox.square(
                      dimension: 76,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          AnimatedContainer(
                            duration: duration,
                            curve: Curves.easeOut,
                            width: 76,
                            height: 76,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                width: 2.5,
                                color: selected
                                    ? _selectionColor
                                    : Colors.transparent,
                              ),
                            ),
                            child: PresetAvatarView(
                              presetId: avatar.id,
                              size: 64,
                            ),
                          ),
                          if (selected)
                            const Positioned(
                              right: 0,
                              bottom: 0,
                              child: SizedBox.square(
                                dimension: 20,
                                child: CustomPaint(
                                  painter: _SelectionMarkPainter(),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      avatar.label,
                      textAlign: TextAlign.center,
                      softWrap: true,
                      style: const TextStyle(
                        color: _avatarInk,
                        fontSize: 14,
                        height: 1.3,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Artwork uses a shared 100 × 100 coordinate system.
///
/// Large silhouettes distinguish the characters at small sizes; facial
/// details use the same simple shapes and strokes across the catalog.
class _PresetAvatarPainter extends CustomPainter {
  const _PresetAvatarPainter(this.presetId);

  final String? presetId;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    if (!side.isFinite || side <= 0) {
      return;
    }

    final background = switch (presetId) {
      'avatar-preset-moon' => const Color(0xFFF0EBFA),
      'avatar-preset-sun' => const Color(0xFFFFF2DD),
      'avatar-preset-cloud' => const Color(0xFFEAF3FB),
      'avatar-preset-star' => const Color(0xFFFFEDE7),
      'avatar-preset-sea' => const Color(0xFFE4F5F3),
      'avatar-preset-leaf' => const Color(0xFFEEF4E7),
      _ => const Color(0xFFEDF0F3),
    };

    canvas.save();
    canvas.translate((size.width - side) / 2, (size.height - side) / 2);
    canvas.scale(side / 100);
    canvas.clipPath(Path()..addOval(const Rect.fromLTWH(0, 0, 100, 100)));
    _disc(canvas, background, 50, 50, 50);

    switch (presetId) {
      case 'avatar-preset-moon':
        _moonRabbit(canvas, background);
        break;
      case 'avatar-preset-sun':
        _sunLion(canvas);
        break;
      case 'avatar-preset-cloud':
        _cloudCat(canvas);
        break;
      case 'avatar-preset-star':
        _starFox(canvas);
        break;
      case 'avatar-preset-sea':
        _seaWhale(canvas);
        break;
      case 'avatar-preset-leaf':
        _leafBear(canvas);
        break;
      default:
        _placeholder(canvas);
    }

    canvas.restore();
  }

  void _moonRabbit(Canvas c, Color background) {
    const fur = Color(0xFFFFFDFC);
    const body = Color(0xFFE3DDF2);
    const ear = Color(0xFFF0CFD9);

    // Crescent behind the long ears.
    _disc(c, const Color(0xFFE6CC7F), 26, 27, 17);
    _disc(c, background, 33, 22, 16);

    _oval(c, body, 24, 76, 54, 38);
    _oval(c, fur, 30, 14, 15, 45);
    _oval(c, fur, 55, 17, 15, 42);
    _oval(c, ear, 35, 20, 5, 27);
    _oval(c, ear, 60, 23, 5, 24);
    _oval(c, fur, 22, 43, 57, 44);

    _face(c, 50, 61);
    _oval(c, fur, 27, 82, 17, 9);
    _oval(c, fur, 58, 82, 17, 9);
    _star(c, const Color(0xFFD3B863), 82, 40, 5);
  }

  void _sunLion(Canvas c) {
    const mane = Color(0xFFEDB16A);
    const fur = Color(0xFFF7CF86);
    const muzzle = Color(0xFFFFEACA);

    _oval(c, fur, 29, 79, 42, 34);
    _disc(c, mane, 50, 51, 34);
    for (final center in const <Offset>[
      Offset(50, 20),
      Offset(71, 28),
      Offset(80, 49),
      Offset(72, 72),
      Offset(50, 80),
      Offset(28, 72),
      Offset(20, 49),
      Offset(29, 28),
    ]) {
      _disc(c, mane, center.dx, center.dy, 11);
    }

    _disc(c, fur, 31, 35, 9);
    _disc(c, fur, 69, 35, 9);
    _disc(c, const Color(0xFFDAA367), 31, 35, 4.5);
    _disc(c, const Color(0xFFDAA367), 69, 35, 4.5);
    _disc(c, fur, 50, 53, 25);
    _oval(c, muzzle, 35, 54, 30, 21);

    _face(c, 50, 50);
    _stroke(
      c,
      Path()
        ..moveTo(45, 33)
        ..lineTo(47, 38)
        ..moveTo(55, 33)
        ..lineTo(53, 38),
      const Color(0xFFD49A52),
    );
  }

  void _cloudCat(Canvas c) {
    const fur = Color(0xFFBDCEE5);
    const innerEar = Color(0xFFECCBD4);

    _disc(c, Colors.white, 24, 37, 13);
    _disc(c, Colors.white, 43, 28, 17);
    _disc(c, Colors.white, 64, 32, 16);
    _disc(c, Colors.white, 79, 41, 10);
    c.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(13, 35, 74, 20),
        const Radius.circular(10),
      ),
      Paint()..color = Colors.white,
    );

    _oval(c, fur, 26, 76, 49, 39);
    _shape(
      c,
      Path()
        ..moveTo(25, 60)
        ..lineTo(23, 32)
        ..quadraticBezierTo(39, 37, 44, 48)
        ..close(),
      fur,
    );
    _shape(
      c,
      Path()
        ..moveTo(56, 48)
        ..quadraticBezierTo(63, 37, 78, 32)
        ..lineTo(75, 60)
        ..close(),
      fur,
    );
    _shape(
      c,
      Path()
        ..moveTo(28, 40)
        ..lineTo(30, 54)
        ..lineTo(39, 48)
        ..close(),
      innerEar,
    );
    _shape(
      c,
      Path()
        ..moveTo(72, 40)
        ..lineTo(70, 54)
        ..lineTo(62, 48)
        ..close(),
      innerEar,
    );
    _oval(c, fur, 23, 44, 54, 44);
    _face(c, 50, 61);

    _stroke(
      c,
      Path()
        ..moveTo(49, 47)
        ..lineTo(49, 52)
        ..moveTo(18, 64)
        ..lineTo(29, 66)
        ..moveTo(18, 71)
        ..lineTo(29, 70)
        ..moveTo(71, 66)
        ..lineTo(82, 64)
        ..moveTo(71, 70)
        ..lineTo(82, 71),
      const Color(0xFF8096B1),
      width: 1.8,
    );
    _oval(c, const Color(0xFFDCE5F1), 38, 84, 24, 15);
  }

  void _starFox(Canvas c) {
    const fur = Color(0xFFEAA984);
    const pale = Color(0xFFFFF0DF);
    const innerEar = Color(0xFFC98273);

    _star(c, const Color(0xFFE5BF68), 79, 22, 10);
    _oval(c, fur, 29, 77, 43, 36);

    _shape(
      c,
      Path()
        ..moveTo(24, 59)
        ..lineTo(19, 20)
        ..quadraticBezierTo(38, 28, 45, 46)
        ..close(),
      fur,
    );
    _shape(
      c,
      Path()
        ..moveTo(55, 46)
        ..quadraticBezierTo(66, 30, 81, 24)
        ..lineTo(76, 60)
        ..close(),
      fur,
    );
    _shape(
      c,
      Path()
        ..moveTo(25, 31)
        ..lineTo(29, 48)
        ..lineTo(37, 44)
        ..close(),
      innerEar,
    );
    _shape(
      c,
      Path()
        ..moveTo(75, 34)
        ..lineTo(63, 44)
        ..lineTo(72, 49)
        ..close(),
      innerEar,
    );

    _shape(
      c,
      Path()
        ..moveTo(24, 43)
        ..quadraticBezierTo(50, 34, 76, 43)
        ..quadraticBezierTo(82, 65, 50, 85)
        ..quadraticBezierTo(18, 65, 24, 43)
        ..close(),
      fur,
    );
    _shape(
      c,
      Path()
        ..moveTo(26, 55)
        ..quadraticBezierTo(39, 65, 50, 63)
        ..quadraticBezierTo(61, 65, 74, 55)
        ..quadraticBezierTo(74, 74, 50, 83)
        ..quadraticBezierTo(26, 74, 26, 55)
        ..close(),
      pale,
    );

    _face(c, 50, 57, eyeSpread: 25);
    _oval(c, pale, 40, 83, 20, 18);
  }

  void _seaWhale(Canvas c) {
    const water = Color(0xFFC4E7E5);
    const whale = Color(0xFF7ABABD);
    const belly = Color(0xFFDAF0EA);
    const detail = Color(0xFF5C999F);

    _shape(
      c,
      Path()
        ..moveTo(0, 77)
        ..quadraticBezierTo(17, 69, 34, 77)
        ..quadraticBezierTo(51, 85, 68, 77)
        ..quadraticBezierTo(85, 69, 100, 77)
        ..lineTo(100, 100)
        ..lineTo(0, 100)
        ..close(),
      water,
    );

    // Raised tail is separate from the large rounded head.
    _shape(
      c,
      Path()
        ..moveTo(73, 62)
        ..quadraticBezierTo(80, 43, 92, 38)
        ..quadraticBezierTo(97, 49, 88, 55)
        ..quadraticBezierTo(96, 52, 99, 61)
        ..quadraticBezierTo(89, 74, 74, 69)
        ..close(),
      whale,
    );
    _oval(c, whale, 17, 36, 65, 45);
    _oval(c, belly, 25, 64, 47, 13);
    _shape(
      c,
      Path()
        ..moveTo(49, 64)
        ..quadraticBezierTo(69, 66, 66, 83)
        ..quadraticBezierTo(54, 83, 49, 64)
        ..close(),
      detail,
    );

    _disc(c, _avatarInk, 35, 55, 2.6);
    _oval(c, const Color(0xFFECCCD1), 24, 60, 10, 5);
    _stroke(
      c,
      Path()
        ..moveTo(28, 65)
        ..quadraticBezierTo(33, 69, 38, 64),
      _avatarInk,
      width: 1.9,
    );
    _stroke(
      c,
      Path()
        ..moveTo(45, 36)
        ..quadraticBezierTo(42, 23, 32, 24)
        ..moveTo(45, 36)
        ..quadraticBezierTo(45, 21, 54, 18),
      detail,
      width: 2.6,
    );
    _oval(c, detail, 27, 19, 6, 8);
    _oval(c, detail, 52, 13, 6, 8);

    _stroke(
      c,
      Path()
        ..moveTo(10, 87)
        ..quadraticBezierTo(20, 82, 30, 87)
        ..quadraticBezierTo(40, 92, 50, 87)
        ..moveTo(70, 87)
        ..quadraticBezierTo(80, 82, 90, 87),
      const Color(0xFFF1FBF7),
      width: 2.4,
    );
  }

  void _leafBear(Canvas c) {
    const fur = Color(0xFFE4CFAC);
    const muzzle = Color(0xFFFFEFDA);
    const leaf = Color(0xFF8BAF83);
    const leafLight = Color(0xFFB2CB91);

    _oval(c, fur, 25, 76, 51, 37);
    _disc(c, fur, 30, 38, 12);
    _disc(c, fur, 70, 38, 12);
    _disc(c, const Color(0xFFC9AE8D), 30, 38, 6);
    _disc(c, const Color(0xFFC9AE8D), 70, 38, 6);
    _oval(c, fur, 21, 36, 58, 51);
    _oval(c, muzzle, 35, 57, 30, 21);
    _face(c, 50, 54);

    _shape(
      c,
      Path()
        ..moveTo(49, 34)
        ..quadraticBezierTo(32, 25, 40, 10)
        ..quadraticBezierTo(62, 12, 49, 34)
        ..close(),
      leaf,
    );
    _shape(
      c,
      Path()
        ..moveTo(51, 32)
        ..quadraticBezierTo(62, 15, 79, 22)
        ..quadraticBezierTo(73, 37, 51, 32)
        ..close(),
      leafLight,
    );
    _stroke(
      c,
      Path()
        ..moveTo(50, 40)
        ..quadraticBezierTo(48, 28, 44, 20)
        ..moveTo(50, 34)
        ..lineTo(67, 26),
      const Color(0xFF6C936A),
      width: 2,
    );
    _oval(c, muzzle, 29, 83, 16, 10);
    _oval(c, muzzle, 57, 83, 16, 10);
  }

  void _placeholder(Canvas c) {
    const silhouette = Color(0xFFB9C3CD);
    _disc(c, silhouette, 50, 36, 14);
    _oval(c, silhouette, 21, 57, 58, 53);
  }

  void _face(Canvas c, double x, double eyeY, {double eyeSpread = 22}) {
    final half = eyeSpread / 2;
    _disc(c, _avatarInk, x - half, eyeY, 2.3);
    _disc(c, _avatarInk, x + half, eyeY, 2.3);
    _oval(c, const Color(0xFFEBC3C7), x - half - 9, eyeY + 6, 10, 5);
    _oval(c, const Color(0xFFEBC3C7), x + half - 1, eyeY + 6, 10, 5);
    _oval(c, _avatarInk, x - 3, eyeY + 6, 6, 4);
    _stroke(
      c,
      Path()
        ..moveTo(x, eyeY + 9)
        ..lineTo(x, eyeY + 12)
        ..moveTo(x - 5, eyeY + 12)
        ..quadraticBezierTo(x - 2, eyeY + 16, x, eyeY + 12)
        ..quadraticBezierTo(x + 2, eyeY + 16, x + 5, eyeY + 12),
      _avatarInk,
      width: 1.7,
    );
  }

  void _star(Canvas c, Color color, double x, double y, double r) {
    _shape(
      c,
      Path()
        ..moveTo(x, y - r)
        ..lineTo(x + r * 0.28, y - r * 0.3)
        ..lineTo(x + r, y - r * 0.25)
        ..lineTo(x + r * 0.43, y + r * 0.2)
        ..lineTo(x + r * 0.62, y + r * 0.9)
        ..lineTo(x, y + r * 0.48)
        ..lineTo(x - r * 0.62, y + r * 0.9)
        ..lineTo(x - r * 0.43, y + r * 0.2)
        ..lineTo(x - r, y - r * 0.25)
        ..lineTo(x - r * 0.28, y - r * 0.3)
        ..close(),
      color,
    );
  }

  void _disc(Canvas c, Color color, double x, double y, double radius) {
    c.drawCircle(Offset(x, y), radius, Paint()..color = color);
  }

  void _oval(
    Canvas c,
    Color color,
    double x,
    double y,
    double width,
    double height,
  ) {
    c.drawOval(Rect.fromLTWH(x, y, width, height), Paint()..color = color);
  }

  void _shape(Canvas c, Path path, Color color) {
    c.drawPath(path, Paint()..color = color);
  }

  void _stroke(Canvas c, Path path, Color color, {double width = 2}) {
    c.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _PresetAvatarPainter oldDelegate) {
    return oldDelegate.presetId != presetId;
  }
}

/// Canvas check mark, independent of icon fonts and external assets.
class _SelectionMarkPainter extends CustomPainter {
  const _SelectionMarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final double side = size.shortestSide;
    if (!side.isFinite || side <= 0) return;
    final Offset center = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(center, side / 2, Paint()..color = Colors.white);
    canvas.drawCircle(center, side * 0.43, Paint()..color = _selectionColor);
    canvas.drawPath(
      Path()
        ..moveTo(size.width * 0.28, size.height * 0.51)
        ..lineTo(size.width * 0.44, size.height * 0.67)
        ..lineTo(size.width * 0.73, size.height * 0.35),
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = side * 0.10
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SelectionMarkPainter oldDelegate) => false;
}
