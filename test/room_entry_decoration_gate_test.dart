import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/features/room/domain/room_entry_decoration_gate.dart';
import 'package:voice_social_app/features/room/domain/room_operations_models.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/commerce/display/domain/equipped_decoration.dart';

void main() {
  final now = DateTime.utc(2026, 9, 10);
  test(
    'first view suppresses historical others and emits only current viewer entry once',
    () {
      final gate = RoomEntryDecorationGate();
      final members = [
        entryMember(1, now),
        entryMember(2, now.subtract(const Duration(days: 1))),
      ];
      expect(
        gate
            .consume(roomId: 'a', viewerId: 1, members: members, now: now)
            .map((m) => m.userId),
        [1],
      );
      expect(
        gate.consume(roomId: 'a', viewerId: 1, members: members, now: now),
        isEmpty,
      );
    },
  );
  test(
    'new membership plays once; seat or mute changes and older joinedAt never replay',
    () {
      final gate = RoomEntryDecorationGate();
      gate.consume(
        roomId: 'a',
        viewerId: 1,
        members: [entryMember(2, now)],
        now: now,
      );
      final later = now.add(const Duration(seconds: 1));
      final member = entryMember(2, later);
      expect(
        gate.consume(roomId: 'a', viewerId: 1, members: [member], now: later),
        hasLength(1),
      );
      expect(
        gate.consume(
          roomId: 'a',
          viewerId: 1,
          members: [member.copyWith(seatNumber: 4, isMuted: true)],
          now: later,
        ),
        isEmpty,
      );
      expect(
        gate.consume(
          roomId: 'a',
          viewerId: 1,
          members: [entryMember(2, now)],
          now: later,
        ),
        isEmpty,
      );
    },
  );
  test(
    'returning to a room or renewing a lease cannot replay the same membership',
    () {
      final gate = RoomEntryDecorationGate();
      var gateRoomSeen = 0;
      for (final room in ['a', 'b', 'a']) {
        expect(
          gate.consume(
            roomId: room,
            viewerId: 1,
            members: [entryMember(1, now)],
            now: now,
          ),
          room == 'a' && gateRoomSeen++ > 0 ? isEmpty : hasLength(1),
        );
      }
    },
  );
  test(
    'unknown missing offline and expired entry rights do not animate later on equip',
    () {
      final gate = RoomEntryDecorationGate();
      final cases = [
        entryMember(1, now, decorations: []),
        entryMember(
          2,
          now,
          decorations: [entryDecoration(key: 'decoration/unknown')],
        ),
        entryMember(3, now, online: false),
        entryMember(5, now, decorations: [entryDecoration(expiry: now)]),
      ];
      expect(
        gate.consume(roomId: 'a', viewerId: 1, members: cases, now: now),
        isEmpty,
      );
      expect(
        gate.consume(
          roomId: 'a',
          viewerId: 1,
          members: [entryMember(1, now)],
          now: now,
        ),
        isEmpty,
      );
    },
  );
  test(
    'authoritative joinedAt is not rejected because the device clock is behind the server',
    () {
      final gate = RoomEntryDecorationGate();
      expect(
        gate.consume(
          roomId: 'a',
          viewerId: 1,
          members: [entryMember(1, now.add(const Duration(minutes: 5)))],
          now: now,
        ),
        hasLength(1),
      );
    },
  );
}

EquippedDecoration entryDecoration({
  String key = 'decoration/stream-entry',
  DateTime? expiry,
}) => EquippedDecoration(
  decorationId: '00000000-0000-0000-0000-000000000003',
  type: 'ROOM_ENTRY',
  assetKey: key,
  expiresAt: expiry,
);
RoomMember entryMember(
  int id,
  DateTime joined, {
  List<EquippedDecoration>? decorations,
  bool online = true,
  String? name,
}) => RoomMember(
  userId: id,
  name: name ?? 'User$id',
  role: RoomRole.listener,
  presence: RoomMemberPresence.listener,
  joinedAt: joined,
  online: online,
  equippedDecorations: decorations ?? [entryDecoration()],
);
