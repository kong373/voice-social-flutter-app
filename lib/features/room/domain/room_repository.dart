import 'package:voice_social_app/features/room/domain/room_models.dart';

abstract interface class RoomRepository {
  Future<RoomSnapshot> enterRoom({
    required String roomId,
    required String? password,
    required RoomEntrySource source,
    required int currentUserId,
  });

  Future<RoomSnapshot> reconnectRoom({
    required String roomId,
    required int currentUserId,
  });

  Future<void> exitRoom(String roomId);

  Future<void> requestMic(int backendMicIndex);

  Future<void> leaveMic();

  Future<void> setSelfMicrophoneMuted({
    required int backendMicIndex,
    required bool muted,
  });

  Future<RoomMessage> sendPublicMessage({
    required String roomId,
    required String content,
    String? requestId,
  });

  Future<List<RoomMessage>> fetchPublicMessages(String roomId);

  Future<GiftReceipt> sendGift({
    required String roomId,
    required String giftId,
    required List<int> receiverUserIds,
    required int quantity,
    required int giftFrom,
    String? requestId,
  });
}
