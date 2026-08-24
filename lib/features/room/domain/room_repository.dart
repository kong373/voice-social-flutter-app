import 'package:voice_social_app/core/network/api_exception.dart';
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

/// Optional capability implemented by live repositories that expose the
/// first-party gift receipt read contract. Keeping this capability separate
/// lets older room test doubles remain valid while callers still get a
/// fail-closed default through the extension below.
abstract interface class GiftReceiptRepository {
  /// Reads a first-party gift transfer without creating or mutating any
  /// idempotency state. A transfer id is preferred; request id is the
  /// recovery key after an ambiguous send response.
  Future<GiftReceipt> fetchGiftReceipt({
    String? transferId,
    String? requestId,
    int? participantUserId,
    int? senderUserId,
    int? receiverUserId,
    int? currentUserId,
  });

  Future<GiftReceipt> queryGiftReceipt({
    String? transferId,
    String? requestId,
    int? participantUserId,
    int? senderUserId,
    int? receiverUserId,
    int? currentUserId,
  }) => fetchGiftReceipt(
    transferId: transferId,
    requestId: requestId,
    participantUserId: participantUserId,
    senderUserId: senderUserId,
    receiverUserId: receiverUserId,
    currentUserId: currentUserId,
  );
}

extension GiftReceiptRepositoryAccess on RoomRepository {
  Future<GiftReceipt> fetchGiftReceipt({
    String? transferId,
    String? requestId,
    int? participantUserId,
    int? senderUserId,
    int? receiverUserId,
    int? currentUserId,
  }) {
    final GiftReceiptRepository? capability = this is GiftReceiptRepository
        ? this as GiftReceiptRepository
        : null;
    if (capability == null) {
      throw const ApiException(
        kind: ApiFailureKind.configuration,
        message: '当前后端未提供礼物回执查询契约',
      );
    }
    return capability.fetchGiftReceipt(
      transferId: transferId,
      requestId: requestId,
      participantUserId: participantUserId,
      senderUserId: senderUserId,
      receiverUserId: receiverUserId,
      currentUserId: currentUserId,
    );
  }

  Future<GiftReceipt> queryGiftReceipt({
    String? transferId,
    String? requestId,
    int? participantUserId,
    int? senderUserId,
    int? receiverUserId,
    int? currentUserId,
  }) => fetchGiftReceipt(
    transferId: transferId,
    requestId: requestId,
    participantUserId: participantUserId,
    senderUserId: senderUserId,
    receiverUserId: receiverUserId,
    currentUserId: currentUserId,
  );
}
