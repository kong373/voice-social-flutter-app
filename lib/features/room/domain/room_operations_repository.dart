import 'package:voice_social_app/features/room/domain/room_operations_models.dart';

abstract interface class RoomOperationsRepository {
  MicCoordinationMode get micCoordinationMode;

  Future<RoomMemberPage> fetchOnlineMembers({
    required String roomId,
    required int page,
    int pageSize = 20,
  });

  Future<List<RoomMember>> fetchOffMicListeners(String roomId);

  Future<List<RoomMember>> fetchManagers(String roomId);

  Future<List<RoomMember>> fetchMutedUsers(String roomId);

  Future<RoomTopic> fetchTopic(String roomId);

  Future<void> updateTopic({required String roomId, required RoomTopic topic});

  Future<void> setUserMuted({
    required String roomId,
    required int userId,
    required bool muted,
  });

  Future<void> setUserRole({
    required String roomId,
    required int userId,
    required bool manager,
  });

  Future<void> kickUser({required String roomId, required int userId});

  Future<void> takeUserOffMic({
    required String roomId,
    required int backendMicIndex,
    required int userId,
  });

  Future<void> setSeatLocked({
    required String roomId,
    required int backendMicIndex,
    required bool locked,
  });

  Future<void> setSeatMuted({
    required String roomId,
    required int backendMicIndex,
    required bool muted,
  });

  Future<List<MicAccessRequest>> fetchMicRequests(String roomId);

  Future<void> submitMicRequest({
    required String roomId,
    required int userId,
    required int seatNumber,
  });

  Future<void> cancelMicRequest({required String requestId});

  Future<void> resolveMicRequest({
    required String requestId,
    required bool accepted,
  });

  Future<void> inviteUserToMic({
    required String roomId,
    required int userId,
    required int seatNumber,
  });
}

/// Optional first-party approval-room capability.
///
/// It is deliberately not part of [RoomOperationsRepository], so legacy
/// doubles and backends that only expose direct microphone coordination stay
/// source-compatible.  A live repository implements this capability only
/// when the corresponding HTTP contract is available.
abstract interface class RoomJoinRequestRepository {
  Future<RoomJoinRequestPage> fetchJoinRequests({
    required String roomId,
    int page = 1,
    int pageSize = 20,
  });

  Future<void> resolveJoinRequest({
    required String joinRequestId,
    required bool approved,
    String? requestId,
  });

  /// Reads only the authenticated applicant's own request. At least one of
  /// [roomId] or [joinRequestId] must be provided.
  Future<RoomJoinRequestApplicantStatus> fetchJoinRequestStatus({
    String? roomId,
    String? joinRequestId,
  });

  /// Cancels a pending applicant request. The idempotency key is sent only as
  /// the X-Request-Id header; it must never be put into the JSON body.
  Future<RoomJoinRequestCancellation> cancelJoinRequest({
    required String roomId,
    required String joinRequestId,
    String? requestId,
  });
}

/// Optional first-party room-ban capability used by RM-007.
abstract interface class RoomBanRepository {
  Future<RoomBannedUserPage> fetchBannedUsers({
    required String roomId,
    int page = 1,
    int pageSize = 20,
  });

  Future<void> unbanUser({
    required String roomId,
    required int userId,
    String? requestId,
  });
}

extension RoomJoinRequestRepositoryAccess on RoomOperationsRepository {
  RoomJoinRequestRepository? get roomJoinRequestCapability =>
      this is RoomJoinRequestRepository
      ? this as RoomJoinRequestRepository
      : null;

  RoomBanRepository? get roomBanCapability =>
      this is RoomBanRepository ? this as RoomBanRepository : null;
}
