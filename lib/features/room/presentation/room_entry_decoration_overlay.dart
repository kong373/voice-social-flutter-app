import 'dart:async';
import 'package:flutter/material.dart';
import '../../../app/app_dependencies.dart';
import '../../../app/app_dependency_scope.dart';
import '../../commerce/display/domain/equipped_decoration.dart';
import '../../commerce/display/presentation/decoration_artwork.dart';
import '../application/room_controller.dart';
import '../data/backend_room_operations_repository.dart';
import '../domain/room_entry_decoration_gate.dart';
import '../domain/room_models.dart';
import '../domain/room_operations_models.dart';
import '../domain/room_permission_policy.dart';

/// Optional first-party member reads only. No join, lease renewal, publishing,
/// asset download or writes. A failed/partial read never becomes an entry.
class RoomEntryDecorationOverlay extends StatefulWidget {
  const RoomEntryDecorationOverlay({required this.controller, super.key});
  final RoomController controller;
  @override
  State<RoomEntryDecorationOverlay> createState() =>
      _RoomEntryDecorationOverlayState();
}

class _ViewerHistory {
  _ViewerHistory(this.identity);
  final (int?, int) identity;
  final gate = RoomEntryDecorationGate();
}

class _RoomEntryDecorationOverlayState extends State<RoomEntryDecorationOverlay>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static final _histories = Expando<_ViewerHistory>();
  AppDependencies? _dependencies;
  late final AnimationController _animation;
  Timer? _timer;
  Object? _flight;
  int _epoch = 0;
  (int?, int)? _identity;
  String? _session;
  int? _leaseGeneration;
  bool _invalid = false;
  bool _foreground = true;
  bool _visible = true;
  final _queue = <RoomMember>[];
  Map<int, RoomMember> _members = {};
  RoomMember? _current;
  (int?, int) get _viewer => (
    _dependencies!.sessionManager.session?.userId,
    _dependencies!.sessionManager.identityGeneration,
  );
  bool get _valid {
    final deps = _dependencies;
    if (!mounted || deps == null || _invalid || !_foreground || !_visible)
      return false;
    final controller = widget.controller;
    final repository = deps.roomOperationsRepository;
    return _identity == _viewer &&
        _viewer.$1 == controller.currentUserId &&
        _session != null &&
        _session == controller.snapshot?.sessionId &&
        controller.isEntryIdentityCurrent &&
        controller.status == RoomSessionStatus.joined &&
        controller.allows(RoomCapability.viewMembers) &&
        (repository is! BackendRoomOperationsRepository ||
            repository.leaseBinding.generation == _leaseGeneration);
  }

  @override
  void initState() {
    super.initState();
    _animation =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 1800),
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed) _next();
        });
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    widget.controller.addListener(_sync);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final deps = AppDependencyScope.of(context);
    if (_dependencies == null) {
      _dependencies = deps;
      deps.sessionManager.addListener(_identityChanged);
      _bind();
    } else if (!identical(_dependencies, deps)) {
      _invalid = true;
    }
    _visible = ModalRoute.of(context)?.isCurrent ?? true;
    _sync();
  }

  void _bind() {
    _identity = _viewer;
    _session = widget.controller.snapshot?.sessionId;
    final repository = _dependencies!.roomOperationsRepository;
    _leaseGeneration = repository is BackendRoomOperationsRepository
        ? repository.leaseBinding.generation
        : null;
  }

  @override
  void didUpdateWidget(covariant RoomEntryDecorationOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.controller, widget.controller)) return;
    oldWidget.controller.removeListener(_sync);
    widget.controller.addListener(_sync);
    _pause();
    _invalid = false;
    _bind();
    _sync();
  }

  void _identityChanged() {
    if (_identity != _viewer) _invalid = true;
    _sync();
  }

  void _sync() {
    if (_dependencies == null) return;
    if (!_valid) {
      _pause();
      return;
    }
    if (_timer == null && _flight == null) unawaited(_read());
  }

  void _pause() {
    _epoch++;
    _timer?.cancel();
    _timer = null;
    _flight = null;
    _queue.clear();
    _members = {};
    _animation.stop();
    if (_current != null && mounted) setState(() => _current = null);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
  }

  Future<void> _read() async {
    if (!_valid || _flight != null) return;
    final flight = Object();
    _flight = flight;
    final epoch = _epoch;
    bool current() => _valid && epoch == _epoch && identical(_flight, flight);
    try {
      final members = <int, RoomMember>{};
      var complete = false;
      int? total;
      int? pages;
      for (var page = 1; page <= 100; page++) {
        final result = await _dependencies!.roomOperationsRepository
            .fetchOnlineMembers(
              roomId: widget.controller.roomId,
              page: page,
              pageSize: 50,
            );
        if (!current()) return;
        total ??= result.total;
        pages ??= result.pages;
        if (result.page != page ||
            result.total != total ||
            result.pages != pages ||
            result.total < 0 ||
            result.items.length > 50 ||
            (result.hasMore && result.items.isEmpty))
          return;
        for (final member in result.items) {
          if (members.containsKey(member.userId)) return;
          members[member.userId] = member;
        }
        if (!result.hasMore) {
          complete = true;
          break;
        }
      }
      if (!complete || !current() || members.length != total) return;
      final manager = _dependencies!.sessionManager;
      var history = _histories[manager];
      if (history == null || history.identity != _viewer) {
        history = _ViewerHistory(_viewer);
        _histories[manager] = history;
      }
      _members = members;
      final events = history.gate.consume(
        roomId: widget.controller.roomId,
        viewerId: widget.controller.currentUserId,
        members: members.values.toList(),
        now: DateTime.now(),
      );
      // Bound visual backlog; discarded entries remain consumed, not replayed.
      _queue.addAll(events.take((8 - _queue.length).clamp(0, 8)));
      if (_current == null || !_stillCurrent(_current!)) _next();
    } catch (_) {
      // Optional decoration read errors do not replace room business errors.
    } finally {
      if (identical(_flight, flight)) {
        _flight = null;
        if (_valid)
          _timer = Timer(const Duration(seconds: 5), () {
            _timer = null;
            _sync();
          });
      }
    }
  }

  bool _stillCurrent(RoomMember event) {
    final latest = _members[event.userId];
    if (latest == null || latest.joinedAt != event.joinedAt) return false;
    final currentArt = RoomEntryDecorationGate.entryFor(latest, DateTime.now());
    final originalArt = RoomEntryDecorationGate.entryFor(event, DateTime.now());
    return currentArt != null &&
        originalArt != null &&
        currentArt.decorationId == originalArt.decorationId &&
        currentArt.assetKey == originalArt.assetKey;
  }

  void _next() {
    if (!mounted) return;
    _animation.stop();
    RoomMember? next;
    while (_valid && _queue.isNotEmpty) {
      final candidate = _queue.removeAt(0);
      if (_stillCurrent(candidate)) {
        next = candidate;
        break;
      }
    }
    setState(() => _current = next);
    if (next != null) _animation.forward(from: 0);
  }

  @override
  void dispose() {
    _epoch++;
    _timer?.cancel();
    _dependencies?.sessionManager.removeListener(_identityChanged);
    widget.controller.removeListener(_sync);
    WidgetsBinding.instance.removeObserver(this);
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _animation,
    builder: (context, _) {
      final member = _current;
      if (!_valid || member == null || !_stillCurrent(member))
        return const SizedBox.shrink();
      final t = _animation.value;
      final opacity = t < .2
          ? t / .2
          : t > .8
          ? (1 - t) / .2
          : 1.0;
      return Positioned(
        left: 24,
        right: 24,
        bottom: 150,
        child: IgnorePointer(
          child: Opacity(
            opacity: opacity.clamp(0, 1),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: const LinearGradient(
                  colors: [Color(0xE86343A5), Color(0xE89D6AF0)],
                ),
              ),
              child: Row(
                children: [
                  DecorationArtwork(
                    product: DecorationProduct.streamEntry,
                    size: 76,
                    progress: (t * 4).clamp(0, 1),
                  ),
                  Expanded(
                    child: Text(
                      '${member.name} 进入房间',
                      key: ValueKey('entry-decoration-${member.userId}'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
