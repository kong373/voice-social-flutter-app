import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/domain/room_repository.dart';

class MockRoomRepository implements RoomRepository {
  MockRoomRepository();

  RoomSnapshot? _snapshot;

  @override
  Future<RoomSnapshot> enterRoom({
    required String roomId,
    required String? password,
    required RoomEntrySource source,
    required int currentUserId,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 320));
    _snapshot = RoomSnapshot(
      roomId: roomId,
      roomCode: roomId,
      title: '深夜温柔陪伴',
      topic: '今晚话题：最近让你觉得被治愈的一件小事',
      ownerId: 20001,
      role: RoomRole.listener,
      seats: <MicSeat>[
        const MicSeat(
          number: 1,
          backendIndex: 1,
          state: MicSeatState.occupied,
          userId: 20001,
          userName: '房主 · 鹿屿',
          isSpeaking: true,
          userRole: RoomRole.owner,
        ),
        const MicSeat(
          number: 2,
          backendIndex: 2,
          state: MicSeatState.occupiedMuted,
          userId: 20002,
          userName: '南风',
        ),
        const MicSeat(
          number: 3,
          backendIndex: 3,
          state: MicSeatState.occupied,
          userId: 20003,
          userName: '晚星',
        ),
        const MicSeat(
          number: 4,
          backendIndex: 4,
          state: MicSeatState.available,
        ),
        const MicSeat(
          number: 5,
          backendIndex: 5,
          state: MicSeatState.locked,
        ),
        const MicSeat(
          number: 6,
          backendIndex: 6,
          state: MicSeatState.available,
        ),
        const MicSeat(
          number: 7,
          backendIndex: 7,
          state: MicSeatState.mutedAvailable,
        ),
        const MicSeat(
          number: 8,
          backendIndex: 8,
          state: MicSeatState.available,
        ),
      ],
      rtc: RtcCredentials(
        solution: RtcSolution.agora,
        token: 'mock-rtc-token',
        channelId: roomId,
        userId: currentUserId,
      ),
      publicScreenEnabled: true,
      pictureMessagesAllowed: false,
      autoLockMic: false,
      giftCatalogAvailable: true,
      giftBalance: 1200,
      onlineCount: 36,
    );
    return _snapshot!;
  }

  @override
  Future<RoomSnapshot> reconnectRoom({
    required String roomId,
    required int currentUserId,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return _requireSnapshot();
  }

  @override
  Future<void> exitRoom(String roomId) async {
    // Keep the test double deterministic. Loading and failure behavior are
    // exercised by dedicated repositories instead of a fake timer hidden in
    // the default click-through fixture.
  }

  @override
  Future<void> requestMic(int backendMicIndex) async {
    final RoomSnapshot snapshot = _requireSnapshot();
    final int index = snapshot.seats.indexWhere(
      (MicSeat seat) =>
          seat.backendIndex == backendMicIndex && seat.isAvailable,
    );
    if (index < 0) {
      throw const ApiException(
        kind: ApiFailureKind.business,
        message: '麦位状态已变化，请重新选择',
      );
    }
    final List<MicSeat> seats = List<MicSeat>.of(snapshot.seats)
      ..[index] = snapshot.seats[index].copyWith(
        state: MicSeatState.occupied,
        userId: snapshot.rtc.userId,
        userName: '我',
        userRole: RoomRole.speaker,
      );
    _snapshot = snapshot.copyWith(role: RoomRole.speaker, seats: seats);
  }

  @override
  Future<void> leaveMic() async {
    final RoomSnapshot snapshot = _requireSnapshot();
    final List<MicSeat> seats = <MicSeat>[
      for (final MicSeat seat in snapshot.seats)
        if (seat.userId == snapshot.rtc.userId)
          seat.copyWith(
            state: MicSeatState.available,
            clearUserId: true,
            clearUserName: true,
            clearAvatarUrl: true,
            isSpeaking: false,
            userRole: RoomRole.listener,
          )
        else
          seat,
    ];
    _snapshot = snapshot.copyWith(role: RoomRole.listener, seats: seats);
  }

  @override
  Future<void> setSelfMicrophoneMuted({
    required int backendMicIndex,
    required bool muted,
  }) async {
    final RoomSnapshot snapshot = _requireSnapshot();
    final int index = snapshot.seats.indexWhere(
      (MicSeat seat) => seat.backendIndex == backendMicIndex,
    );
    if (index < 0) {
      return;
    }
    final List<MicSeat> seats = List<MicSeat>.of(snapshot.seats)
      ..[index] = snapshot.seats[index].copyWith(
        state: muted
            ? MicSeatState.occupiedMuted
            : MicSeatState.occupied,
      );
    _snapshot = snapshot.copyWith(seats: seats);
  }

  @override
  Future<void> sendPublicMessage({
    required String roomId,
    required String content,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
  }

  @override
  Future<GiftReceipt> sendGift({
    required String roomId,
    required int giftId,
    required List<int> receiverUserIds,
    required int quantity,
    required int giftFrom,
  }) async {
    final RoomSnapshot snapshot = _requireSnapshot();
    final int total = giftId == 101
        ? 10 * quantity
        : giftId == 102
            ? 66 * quantity
            : 188 * quantity;
    final int balance = snapshot.giftBalance ?? 0;
    if (total > balance) {
      throw const ApiException(
        kind: ApiFailureKind.business,
        message: '礼物币余额不足',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 220));
    final int remaining = balance - total;
    _snapshot = snapshot.copyWith(giftBalance: remaining);
    return GiftReceipt(success: true, remainingBalance: remaining);
  }

  RoomSnapshot _requireSnapshot() {
    final RoomSnapshot? snapshot = _snapshot;
    if (snapshot == null) {
      throw const ApiException(
        kind: ApiFailureKind.business,
        message: '当前未加入房间',
      );
    }
    return snapshot;
  }
}
