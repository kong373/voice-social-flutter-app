import 'dart:async';
import 'package:flutter/widgets.dart';
import '../domain/equipped_decoration.dart';
import 'decoration_artwork.dart';

/// Pure display of an already-authorized projection, never a local equip.
/// With a child this overlays a transparent avatar frame without changing its
/// layout. Without a child it displays a standalone badge (or nothing).
class EquippedDecorationView extends StatefulWidget {
  const EquippedDecorationView({
    required this.decorations,
    required this.product,
    this.enabled = true,
    this.size = 32,
    this.child,
    this.now,
    super.key,
  });
  final List<EquippedDecoration> decorations;
  final DecorationProduct product;
  final bool enabled;
  final double size;
  final Widget? child;
  final DateTime Function()? now;
  @override
  State<EquippedDecorationView> createState() => _EquippedDecorationViewState();
}

class _EquippedDecorationViewState extends State<EquippedDecorationView>
    with WidgetsBindingObserver {
  Timer? _expiryTimer;
  DateTime get _now => (widget.now ?? DateTime.now)();
  EquippedDecoration? get _current {
    if (!widget.enabled) return null;
    final matching = widget.decorations
        .where((item) => item.product == widget.product)
        .toList();
    if (matching.length != 1 || !matching.single.isActiveAt(_now)) return null;
    return matching.single;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _schedule();
  }

  @override
  void didUpdateWidget(covariant EquippedDecorationView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _schedule();
  }

  void _schedule() {
    _expiryTimer?.cancel();
    final expiry = _current?.expiresAt;
    if (expiry == null) return;
    final delay = expiry.difference(_now);
    _expiryTimer = Timer(
      delay > const Duration(hours: 1) ? const Duration(hours: 1) : delay,
      () {
        if (!mounted) return;
        setState(() {});
        _schedule();
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      setState(() {});
      _schedule();
    }
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_current == null) return widget.child ?? const SizedBox.shrink();
    final art = DecorationArtwork(product: widget.product, size: widget.size);
    return widget.child == null
        ? art
        : Stack(
            alignment: Alignment.center,
            children: [
              widget.child!,
              Positioned.fill(child: art),
            ],
          );
  }
}
