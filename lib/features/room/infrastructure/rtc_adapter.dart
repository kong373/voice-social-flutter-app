import 'package:voice_social_app/features/room/domain/room_models.dart';

abstract interface class RtcAdapter {
  Future<void> join(RtcCredentials credentials);

  Future<void> reconnect(RtcCredentials credentials);

  Future<void> setLocalAudioEnabled(bool enabled);

  Future<void> leave();
}

class MockRtcAdapter implements RtcAdapter {
  bool _joined = false;
  bool _audioEnabled = false;

  bool get joined => _joined;
  bool get audioEnabled => _audioEnabled;

  @override
  Future<void> join(RtcCredentials credentials) {
    _joined = true;
    return Future<void>.value();
  }

  @override
  Future<void> reconnect(RtcCredentials credentials) {
    _joined = true;
    return Future<void>.value();
  }

  @override
  Future<void> setLocalAudioEnabled(bool enabled) {
    if (_joined) {
      _audioEnabled = enabled;
    }
    return Future<void>.value();
  }

  @override
  Future<void> leave() {
    _audioEnabled = false;
    _joined = false;
    return Future<void>.value();
  }
}

class UnavailableRtcAdapter implements RtcAdapter {
  const UnavailableRtcAdapter();

  Never _notConfigured() => throw StateError('RTC 适配器尚未配置');

  @override
  Future<void> join(RtcCredentials credentials) async => _notConfigured();

  @override
  Future<void> reconnect(RtcCredentials credentials) async => _notConfigured();

  @override
  Future<void> setLocalAudioEnabled(bool enabled) async => _notConfigured();

  @override
  Future<void> leave() async {}
}
