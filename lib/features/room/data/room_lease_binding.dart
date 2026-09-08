import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';

/// One source of membership for the live room and operations repositories.
/// Authentication epochs are supplied by the session owner, never by userId.
class RoomLeaseBinding {
  RoomLeaseBinding({int Function()? authenticationGeneration})
    : _authenticationGeneration = authenticationGeneration ?? (() => 0);

  final int Function() _authenticationGeneration;
  int? _authEpoch;
  int _generation = 0;
  String? _pendingIntent;
  RoomLeaseMembership? _current;

  int get generation {
    final authEpoch = _authenticationGeneration();
    if (_authEpoch != authEpoch) {
      _authEpoch = authEpoch;
      _generation++;
      _current = null;
      _pendingIntent = null;
    }
    return _generation;
  }

  RoomLeaseMembership? get current {
    generation;
    return _current;
  }

  int beginEntry(String intent) {
    generation;
    if (_pendingIntent != intent) {
      _generation++;
      _current = null;
      _pendingIntent = intent;
    }
    return _generation;
  }

  void check(int expected) {
    if (generation != expected) throw stale();
  }

  void bind(int expected, String roomId, int userId, RoomSessionLease lease) {
    check(expected);
    _current = RoomLeaseMembership(roomId, userId, lease);
    _pendingIntent = null;
  }

  RoomLeaseMembership require([String? roomId]) {
    final membership = current;
    if (membership == null || (roomId != null && membership.roomId != roomId)) {
      throw stale();
    }
    return membership;
  }

  void clear(int expected) {
    if (generation != expected) return;
    _generation++;
    _current = null;
    _pendingIntent = null;
  }

  static ApiException stale() => const ApiException(
    kind: ApiFailureKind.conflict,
    code: 40937,
    message: '房间会话代次已变化，请重新进入房间',
  );
}

class RoomLeaseMembership {
  RoomLeaseMembership(this.roomId, this.userId, this.lease);
  final String roomId;
  final int userId;
  RoomSessionLease lease;
  int? pendingSequence;
  String? pendingRequestId;
}

RoomSessionLease parseRoomLease(Object? raw, {required Object? sessionId}) {
  const failure = ApiException(
    kind: ApiFailureKind.protocol,
    message: '服务端房间租约无效',
  );
  if (raw is! Map<String, Object?> ||
      sessionId is! String ||
      raw['sessionId'] != sessionId ||
      raw['sequence'] is! int ||
      raw['heartbeatIntervalSeconds'] is! int ||
      raw['leaseDurationSeconds'] is! int)
    throw failure;
  (DateTime, int) utc(Object? value) {
    if (value is! String) throw failure;
    final match = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,9}))?(?:Z|\+00:00)$',
    ).firstMatch(value);
    final parsed = DateTime.tryParse(value);
    if (match == null ||
        parsed == null ||
        !parsed.isUtc ||
        parsed.year != int.parse(match[1]!) ||
        parsed.month != int.parse(match[2]!) ||
        parsed.day != int.parse(match[3]!) ||
        parsed.hour != int.parse(match[4]!) ||
        parsed.minute != int.parse(match[5]!) ||
        parsed.second != int.parse(match[6]!))
      throw failure;
    final nanos = int.parse((match[7] ?? '').padRight(9, '0'));
    return (parsed, nanos % 1000);
  }

  final (serverTime, serverNanos) = utc(raw['serverTime']);
  final (expiresAt, expiryNanos) = utc(raw['expiresAt']);
  // Instant may carry nanoseconds. Check bounds before DateTime's microsecond
  // truncation, so 90s + 1ns cannot pass as exactly 90s.
  final micros = expiresAt.difference(serverTime).inMicroseconds;
  if (micros < 0 ||
      micros > 90000000 ||
      (micros == 0 && expiryNanos < serverNanos) ||
      (micros == 90000000 && expiryNanos > serverNanos))
    throw failure;
  final lease = RoomSessionLease(
    sessionId: sessionId,
    sequence: raw['sequence']! as int,
    serverTime: serverTime,
    expiresAt: expiresAt,
    heartbeatIntervalSeconds: raw['heartbeatIntervalSeconds']! as int,
    leaseDurationSeconds: raw['leaseDurationSeconds']! as int,
  );
  if (!lease.isValid) throw failure;
  return lease;
}
