import 'package:voice_social_app/features/room/domain/room_operations_models.dart';

abstract interface class RoomAudioService {
  Future<RoomAudioSnapshot> inspect();

  Future<RoomAudioSnapshot> selectRoute(RoomAudioRoute route);

  Future<RoomAudioSnapshot> setMicrophoneEnabled(bool enabled);
}

class MockRoomAudioService implements RoomAudioService {
  MockRoomAudioService({DateTime? now})
    : _fixedNow = now,
      _snapshot = RoomAudioSnapshot(
        configured: true,
        route: RoomAudioRoute.speaker,
        availableRoutes: const <RoomAudioRoute>{
          RoomAudioRoute.speaker,
          RoomAudioRoute.earpiece,
          RoomAudioRoute.bluetooth,
        },
        microphonePermissionGranted: true,
        microphoneEnabled: false,
        rtcConnected: true,
        realtimeConnected: true,
        grade: RoomConnectionGrade.good,
        latencyMs: 68,
        packetLossPercent: 0.7,
        updatedAt: now ?? DateTime.now(),
      );

  final DateTime? _fixedNow;
  RoomAudioSnapshot _snapshot;

  DateTime get _currentTime => _fixedNow ?? DateTime.now();

  @override
  Future<RoomAudioSnapshot> inspect() async {
    _snapshot = _snapshot.copyWith(updatedAt: _currentTime);
    return _snapshot;
  }

  @override
  Future<RoomAudioSnapshot> selectRoute(RoomAudioRoute route) async {
    if (!_snapshot.availableRoutes.contains(route)) {
      return _snapshot;
    }
    _snapshot = _snapshot.copyWith(route: route, updatedAt: _currentTime);
    return _snapshot;
  }

  @override
  Future<RoomAudioSnapshot> setMicrophoneEnabled(bool enabled) async {
    _snapshot = _snapshot.copyWith(
      microphoneEnabled: enabled,
      updatedAt: _currentTime,
    );
    return _snapshot;
  }
}

class UnavailableRoomAudioService implements RoomAudioService {
  const UnavailableRoomAudioService();

  RoomAudioSnapshot _unavailable() => RoomAudioSnapshot(
    configured: false,
    route: RoomAudioRoute.speaker,
    availableRoutes: const <RoomAudioRoute>{RoomAudioRoute.speaker},
    microphonePermissionGranted: false,
    microphoneEnabled: false,
    rtcConnected: false,
    realtimeConnected: false,
    grade: RoomConnectionGrade.unknown,
    latencyMs: null,
    packetLossPercent: null,
    updatedAt: DateTime.now(),
  );

  @override
  Future<RoomAudioSnapshot> inspect() async => _unavailable();

  @override
  Future<RoomAudioSnapshot> selectRoute(RoomAudioRoute route) async =>
      _unavailable();

  @override
  Future<RoomAudioSnapshot> setMicrophoneEnabled(bool enabled) async =>
      _unavailable();
}
