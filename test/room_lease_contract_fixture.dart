import 'package:voice_social_app/features/room/data/room_lease_binding.dart';

const roomLeaseSessionId = '11111111-1111-4111-8111-111111111111';

Map<String, Object?> roomLeaseWireFixture({
  String sessionId = roomLeaseSessionId,
}) => {
  'sessionId': sessionId,
  'sequence': 0,
  'serverTime': '2026-09-08T00:00:00Z',
  'expiresAt': '2026-09-08T00:01:30Z',
  'heartbeatIntervalSeconds': 20,
  'leaseDurationSeconds': 90,
};

// Existing business-contract tests start after a successful admission. New
// lease tests exercise that admission over HTTP without this fixture adapter.
RoomLeaseBinding admittedRoomFixture({
  String roomId = '9527',
  int userId = 10001,
}) {
  final binding = RoomLeaseBinding();
  binding.bind(
    binding.beginEntry('fixture'),
    roomId,
    userId,
    parseRoomLease(roomLeaseWireFixture(), sessionId: roomLeaseSessionId),
  );
  return binding;
}

Object? withRoomLeaseFixture(Object? raw) {
  if (raw is! Map<String, Object?> ||
      raw['joined'] == false ||
      raw['status'] == 'PENDING_APPROVAL')
    return raw;
  final sessionId = raw['sessionId'] ?? roomLeaseSessionId;
  return {
    ...raw,
    'sessionId': sessionId,
    'roomLease':
        raw['roomLease'] ??
        roomLeaseWireFixture(sessionId: sessionId as String),
  };
}
