import '../../commerce/display/domain/equipped_decoration.dart';
import 'room_operations_models.dart';

/// One instance belongs to one viewer identity generation, across minimized
/// pages and reconnects. Membership time, not seat time, identifies an entry.
class RoomEntryDecorationGate {
  final _latest = <(String, int), DateTime>{};
  final _initializedRooms = <String>{};
  bool _full = false;

  List<RoomMember> consume({
    required String roomId,
    required int viewerId,
    required List<RoomMember> members,
    required DateTime now,
  }) {
    if (_full || viewerId <= 0) return const [];
    if (!_initializedRooms.contains(roomId) &&
        _initializedRooms.length >= 5000) {
      _full = true;
      return const [];
    }
    final initial = _initializedRooms.add(roomId);
    final entered = <RoomMember>[];
    for (final member in members) {
      final joinedAt = member.joinedAt;
      if (!member.online || joinedAt == null) continue;
      final key = (roomId, member.userId);
      final previous = _latest[key];
      if (previous != null && !joinedAt.isAfter(previous)) continue;
      // Do not evict old membership markers and accidentally replay them.
      if (previous == null && _latest.length >= 5000) {
        _full = true;
        return const [];
      }
      _latest[key] = joinedAt;
      if (initial && member.userId != viewerId) continue;
      if (entryFor(member, now) != null) entered.add(member);
    }
    entered.sort((a, b) => a.joinedAt!.compareTo(b.joinedAt!));
    return entered;
  }

  static EquippedDecoration? entryFor(RoomMember member, DateTime now) {
    if (!member.online) return null;
    final entries = member.equippedDecorations
        .where((item) => item.product == DecorationProduct.streamEntry)
        .toList();
    return entries.length == 1 && entries.single.isActiveAt(now)
        ? entries.single
        : null;
  }
}
