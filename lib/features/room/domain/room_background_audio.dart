import 'dart:async';
import 'dart:math';

/// Native runtime eligibility, not proof of activated audio, media quality or a
/// server lease. Platform implementations may only observe audio capability.
enum RoomAudioInterruptionPhase { began, ended }

class RoomBackgroundAudioActivity {
  const RoomBackgroundAudioActivity({
    required this.sessionId,
    required this.active,
    this.interruption,
  });

  final String sessionId;
  final bool active;
  final RoomAudioInterruptionPhase? interruption;
}

/// Host wiring injects this port only on supported platforms, otherwise null.
/// IDs are adapter-local UUIDs, never business IDs or RTC credentials. Native
/// start/stop must be serialized and stop must target only the supplied ID.
abstract interface class RoomBackgroundAudioPort {
  Future<bool> start({required String sessionId, required bool microphone});
  Future<void> stop({required String sessionId});
  Future<bool> isActive({required String sessionId});
  Stream<RoomBackgroundAudioActivity> get activities;
}

/// One opaque UUID per RTC generation. No cached `true` authorizes a heartbeat:
/// [confirmActive] always queries native with a bounded wait. Timed-out native
/// work stays on the serial tail until it settles, so it cannot overtake a stop
/// or a newer start. Availability may be lost; ownership must never be guessed.
class RoomBackgroundAudioLease {
  RoomBackgroundAudioLease(this._port) {
    _subscription = _port.activities.listen(
      (event) {
        if (event.sessionId != _sessionId || event.active) return;
        if (event.interruption == RoomAudioInterruptionPhase.began &&
            (_active || _starting)) {
          _interruption = RoomAudioInterruptionPhase.began;
          _invalidate(keepInterruption: true);
        } else if (event.interruption == RoomAudioInterruptionPhase.ended &&
            _interruption == RoomAudioInterruptionPhase.began) {
          _interruption = RoomAudioInterruptionPhase.ended;
          _changes.add(null);
        } else if (event.interruption == null) {
          _loseActivity();
        }
      },
      onError: (Object _) => _loseActivity(),
      onDone: _loseActivity,
    );
  }

  static const _timeout = Duration(seconds: 2);
  static final _random = Random.secure();
  final RoomBackgroundAudioPort _port;
  final _changes = StreamController<void>.broadcast(sync: true);
  late final StreamSubscription<RoomBackgroundAudioActivity> _subscription;
  Future<void> _tail = Future<void>.value();
  String? _sessionId;
  int _revision = 0;
  bool _active = false;
  bool _starting = false;
  bool _disposed = false;
  RoomAudioInterruptionPhase? _interruption;

  bool get hasActiveLease => !_disposed && _active && _sessionId != null;
  Stream<void> get changes => _changes.stream;
  RoomAudioInterruptionPhase? get interruption => _interruption;

  void begin() {
    unawaited(end());
    if (_disposed) return;
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    _sessionId =
        '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  bool _current(String id, int revision) =>
      !_disposed && _sessionId == id && _revision == revision;

  Future<T> _serial<T>(Future<T> Function() action) {
    final next = _tail.then((_) => action());
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  Future<bool> start({
    required bool microphone,
    required bool Function() allowed,
  }) async {
    final id = _sessionId;
    final revision = _revision;
    if (id == null || _disposed || !allowed()) return false;
    _starting = true;
    try {
      return await _serial(() async {
        if (!_current(id, revision) || !allowed()) return false;
        final ok = await _port.start(sessionId: id, microphone: microphone);
        if (!_current(id, revision) || !allowed()) {
          if (_current(id, revision)) _invalidate();
          await _quietStop(id);
          return false;
        }
        if (!ok) {
          _invalidate();
          await _quietStop(id);
          return false;
        }
        final changed = !_active;
        _active = true;
        _interruption = null;
        _starting = false;
        if (changed) _changes.add(null);
        return true;
      }).timeout(_timeout);
    } catch (_) {
      if (_current(id, revision)) _loseActivity();
      return false;
    } finally {
      if (_current(id, revision)) _starting = false;
    }
  }

  Future<bool> confirmActive() async {
    final id = _sessionId;
    final revision = _revision;
    if (id == null || !hasActiveLease) return false;
    try {
      final ok = await _serial(() async {
        if (!_current(id, revision) || !_active) return false;
        return await _port.isActive(sessionId: id);
      }).timeout(_timeout);
      if (!_current(id, revision) || !_active) return false;
      if (!ok) _loseActivity();
      return ok;
    } catch (_) {
      if (_current(id, revision)) _loseActivity();
      return false;
    }
  }

  void _invalidate({bool keepInterruption = false}) {
    if (!keepInterruption) _interruption = null;
    ++_revision;
    _active = false;
    _starting = false;
    if (!_disposed) _changes.add(null);
  }

  void _loseActivity() {
    if (_disposed || (!_active && !_starting && _interruption == null)) return;
    final id = _sessionId;
    _invalidate();
    if (id != null) unawaited(_boundedStop(id));
  }

  /// Network interruption keeps the generation's UUID but removes eligibility.
  void suspend() => _loseActivity();

  Future<void> _quietStop(String id) async {
    try {
      await _port.stop(sessionId: id);
    } catch (_) {
      // Teardown may be unavailable. Never turn that uncertainty into true.
    }
  }

  Future<void> _boundedStop(String id) async {
    try {
      await _serial(() => _quietStop(id)).timeout(_timeout);
    } catch (_) {
      // Keep the underlying operation ordered, but do not block RTC teardown.
    }
  }

  Future<void> end() {
    final id = _sessionId;
    _sessionId = null;
    _invalidate();
    return id == null ? Future<void>.value() : _boundedStop(id);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    final stopping = end();
    _disposed = true;
    await _subscription.cancel();
    await stopping;
    await _changes.close();
  }
}
