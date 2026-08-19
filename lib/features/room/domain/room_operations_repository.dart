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
    required int backendMicIndex,
    required int userId,
  });

  Future<void> setSeatLocked({
    required int backendMicIndex,
    required bool locked,
  });

  Future<void> setSeatMuted({
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
