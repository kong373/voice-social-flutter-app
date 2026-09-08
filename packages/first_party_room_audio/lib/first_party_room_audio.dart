import 'dart:async';
import 'package:flutter/services.dart';

final class RoomAudioActivity {
  const RoomAudioActivity({required this.sessionId, required this.active});
  final String sessionId;
  final bool active;
}

/// One owner per Flutter engine. Activity is a runtime lease, not media evidence.
final class FirstPartyRoomAudio {
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
  bool _disposed = false;
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
        if (data is! Map ||
            data.length != 2 ||
            data['sessionId'] is! String ||
            (data['sessionId'] as String).length != 36 ||
            !_uuid.hasMatch(data['sessionId'] as String) ||
            data['active'] is! bool) {
          _events.addError(const FormatException('Invalid room audio event'));
          return;
        }
        final event = RoomAudioActivity(
          sessionId: data['sessionId'] as String,
          active: data['active'] as bool,
        );
        if (!event.active && event.sessionId == _session) _clear();
        _events.add(event);
      },
      onError: (Object _) {
        final id = _session;
        _clear();
        if (id != null)
          _events.add(RoomAudioActivity(sessionId: id, active: false));
      },
    );
  }

  Future<bool> _bool(String method, Map<String, Object> args) async {
    try {
      return await _channel.invokeMethod<Object?>(method, args) == true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> start({required String sessionId, required bool microphone}) =>
      _serial(() async {
        _validate(sessionId);
        if (_disposed || (_session != null && _session != sessionId))
          return false;
        _listen();
        final ok = await _bool('start', {
          'sessionId': sessionId,
          'microphone': microphone,
        });
        if (ok) {
          _session = sessionId;
          _heartbeat ??= Timer.periodic(const Duration(seconds: 10), (_) {
            unawaited(
              _serial(() async {
                final id = _session;
                if (id != null && !await _bool('renew', {'sessionId': id})) {
                  _clear();
                  _events.add(RoomAudioActivity(sessionId: id, active: false));
                }
              }),
            );
          });
        }
        return ok;
      });

  Future<void> stop({required String sessionId}) => _serial(() async {
    _validate(sessionId);
    if (_disposed) return;
    if (_session == sessionId) _clear();
    await _channel.invokeMethod<void>('stop', {'sessionId': sessionId});
  });

  Future<bool> isActive({required String sessionId}) => _serial(() async {
    _validate(sessionId);
    if (_disposed) return false;
    return _bool('isActive', {'sessionId': sessionId});
  });

  void _clear() {
    _session = null;
    _heartbeat?.cancel();
    _heartbeat = null;
  }

  Future<void> dispose() => _serial(() async {
    if (_disposed) return;
    _disposed = true;
    final id = _session;
    _clear();
    try {
      if (id != null)
        await _channel.invokeMethod<void>('stop', {'sessionId': id});
    } finally {
      await _subscription?.cancel();
      await _events.close();
    }
  });
}
