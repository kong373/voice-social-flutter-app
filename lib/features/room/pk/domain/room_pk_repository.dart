import 'package:voice_social_app/features/room/pk/domain/room_pk_models.dart';

abstract interface class RoomPkRepository {
  bool get supportsRealtimeInvitations;
  bool get supportsSurrender;

  Future<List<RoomPkOpponent>> fetchHotOpponents({required String roomId});

  Future<List<RoomPkOpponent>> searchOpponents({
    required String roomId,
    required String keyword,
    int pageNum = 1,
    int pageSize = 20,
  });

  Future<RoomPkInvitation?> fetchIncomingInvitation({required String roomId});

  Future<RoomPkInvitation> sendInvitation({
    required String roomId,
    required int inviterUserId,
    required RoomPkOpponent opponent,
    required String punishmentTheme,
    required int durationMinutes,
  });

  Future<RoomPkInvitation> refreshInvitation(RoomPkInvitation invitation);

  Future<RoomPkBattle> acceptInvitation(RoomPkInvitation invitation);

  Future<void> rejectInvitation(RoomPkInvitation invitation);

  Future<RoomPkBattle?> fetchActiveBattle({required String roomId});

  Future<RoomPkBattle> refreshBattle({
    required String roomId,
    required String battleId,
  });

  Future<RoomPkBattle> surrender({
    required String roomId,
    required String battleId,
  });

  Future<RoomPkBattle> end({required String roomId, required String battleId});

  Future<List<RoomPkRecord>> fetchHistory({
    required String roomId,
    int pageNum = 1,
    int pageSize = 20,
  });
}
