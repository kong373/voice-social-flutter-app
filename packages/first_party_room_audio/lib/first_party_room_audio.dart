import 'dart:async';
import 'package:flutter/services.dart';

final class RoomAudioActivity {
  const RoomAudioActivity({required this.sessionId, required this.active});
  final String sessionId;
  final bool active;
}

/// One owner per Flutter engine. Activity is a runtime lease, not media evidence.
final class FirstPartyRoomAudio {
  FirstPartyRoomAudio({this.channelTimeout = const Duration(seconds: 5)}) {
    if (channelTimeout <= Duration.zero) {
      throw ArgumentError('channelTimeout must be positive');
    }
  }

  final Duration channelTimeout;
  static const _channel = MethodChannel('voice_social_app/room_audio');
  static const _eventChannel = EventChannel(
    'voice_social_app/room_audio/events',
  );
  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
  final _events = StreamController<RoomAudioActivity>.broadcast();
  StreamSubscription<dynamic>? _subscription;
  Timer? _heartbeat;
  String? _session;
  String? _starting;
  int _revision = 0;
  bool _disposed = false;
  Future<void>? _disposal;
  final _unconfirmedStops = <String>{};
  Future<void> _tail = Future<void>.value();

  Stream<RoomAudioActivity> get events => _events.stream;

  static void _validate(String id) {
    if (id.length != 36 || !_uuid.hasMatch(id))
      throw ArgumentError('Invalid sessionId');
  }

  Future<T> _serial<T>(Future<T> Function() action) {
    final next = _tail.then((_) => action());
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  void _listen() {
    _subscription ??= _eventChannel.receiveBroadcastStream().listen(
      (dynamic data) {
        if (_disposed) return;
        if (data is! Map ||
            data.length != 2 ||
            data['sessionId'] is! String ||
            (data['sessionId'] as String).length != 36 ||
            !_uuid.hasMatch(data['sessionId'] as String) ||
            data['active'] is! bool) {
          final id = _session ?? _starting;
          if (id != null) _invalidate(id, cleanup: true);
          _events.addError(const FormatException('Invalid room audio event'));
          return;
        }
        final event = RoomAudioActivity(
          sessionId: data['sessionId'] as String,
          active: data['active'] as bool,
        );
        // A late positive signal cannot revive an invalidated generation.
        if (event.active &&
            event.sessionId != _session &&
            event.sessionId != _starting)
          return;
        if (!event.active &&
            (event.sessionId == _session || event.sessionId == _starting)) {
          _invalidate(event.sessionId, cleanup: false);
          return;
        }
        _events.add(event);
      },
      onError: (Object _) {
        if (_disposed) return;
        final id = _session ?? _starting;
        if (id != null) _invalidate(id, cleanup: true);
      },
    );
  }

  Future<Object?> _invoke(String method, Map<String, Object> args) =>
      _channel.invokeMethod<Object?>(method, args).timeout(channelTimeout);

  // null means uncertain state, distinct from an explicit rejected promotion.
  Future<bool?> _bool(String method, Map<String, Object> args) async {
    try {
      final value = await _invoke(method, args);
      return value is bool ? value : null;
    } on TimeoutException {
      return null;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<void> _stop(String id) async {
    _unconfirmedStops.add(id);
    final value = await _invoke('stop', {'sessionId': id});
    if (value != null) {
      throw PlatformException(
        code: 'invalid_response',
        message: 'Invalid room audio response',
      );
    }
    _unconfirmedStops.remove(id);
  }

  Future<void> _bestEffortStop(String id) async {
    try {
      await _stop(id);
    } on TimeoutException {
      // Unknown native cleanup outcome. Native lease expiration is the fallback.
    } on PlatformException {
      // Do not expose platform details or claim cleanup confirmation.
    } on MissingPluginException {
      // Engine may already be detached.
    }
  }

  void _invalidate(String id, {required bool cleanup}) {
    if (_session == id || _starting == id) {
      _clear();
      _events.add(RoomAudioActivity(sessionId: id, active: false));
      // Capture the original generation; never read _session after awaiting.
      if (cleanup) unawaited(_bestEffortStop(id));
    }
  }

  Future<bool> start({
    required String sessionId,
    required bool microphone,
  }) => _serial(() async {
    _validate(sessionId);
    if (_disposed || (_session != null && _session != sessionId)) return false;
    _starting = sessionId;
    final revision = ++_revision;
    _listen();
    final ok = await _bool('start', {
      'sessionId': sessionId,
      'microphone': microphone,
    });
    if (revision != _revision) return false;
    if (ok == null) {
      _invalidate(sessionId, cleanup: true);
      return false;
    }
    _starting = null;
    if (ok) {
      _session = sessionId;
      _heartbeat ??= Timer.periodic(const Duration(seconds: 10), (_) {
        unawaited(
          _serial(() async {
            final id = _session;
            if (id != null && await _bool('renew', {'sessionId': id}) != true) {
              _invalidate(id, cleanup: true);
            }
          }),
        );
      });
    }
    return ok;
  });

  Future<void> stop({required String sessionId}) => _serial(() async {
    _validate(sessionId);
    if (_disposed) {
      await _disposal;
      return;
    }
    if (_session == sessionId) _clear();
    await _stop(sessionId);
  });

  Future<bool> isActive({required String sessionId}) => _serial(() async {
    _validate(sessionId);
    if (_disposed) return false;
    final revision = _revision;
    final active = await _bool('isActive', {'sessionId': sessionId});
    if (revision != _revision) return false;
    if (active != true) _invalidate(sessionId, cleanup: active == null);
    return active == true;
  });

  void _clear() {
    _session = null;
    _starting = null;
    _revision++;
    _heartbeat?.cancel();
    _heartbeat = null;
  }

  Future<void> dispose() => _disposal ??= _serial(() async {
    _disposed = true;
    final id = _session;
    final toStop = {..._unconfirmedStops, if (id != null) id};
    _clear();
    try {
      await Future.wait(toStop.map(_stop));
    } finally {
      try {
        await _subscription?.cancel().timeout(channelTimeout);
      } finally {
        await _events.close().timeout(channelTimeout);
      }
    }
  });
}
