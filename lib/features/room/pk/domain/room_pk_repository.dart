import 'package:voice_social_app/features/room/pk/domain/room_pk_models.dart';

abstract interface class RoomPkRepository {
  bool get supportsRealtimeInvitations;
  bool get supportsSurrender;

  Future<RoomPkProcess> fetchProcess({
    required String roomId,
    required void Function() requireCurrent,
  });

  Future<List<RoomPkOpponent>> fetchHotOpponents({
    required String roomId,
    void Function()? requireCurrent,
  });

  Future<List<RoomPkOpponent>> searchOpponents({
    required String roomId,
    required String keyword,
    void Function()? requireCurrent,
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
    void Function()? requireCurrent,
  });

  Future<RoomPkInvitation> refreshInvitation(RoomPkInvitation invitation);

  Future<RoomPkBattle> acceptInvitation(
    RoomPkInvitation invitation, {
    void Function()? requireCurrent,
  });

  Future<void> rejectInvitation(
    RoomPkInvitation invitation, {
    void Function()? requireCurrent,
  });

  Future<RoomPkBattle?> fetchActiveBattle({required String roomId});

  Future<RoomPkBattle> refreshBattle({
    required String roomId,
    required String battleId,
  });

  /// Retired by Q21-04. Existing callers must fail without a network request
  /// or state mutation; this is not an available gameplay operation.
  Future<RoomPkBattle> surrender({
    required String roomId,
    required String battleId,
  });

  Future<RoomPkBattle> end({required String roomId, required String battleId});

  Future<List<RoomPkRecord>> fetchHistory({
    required String roomId,
    void Function()? requireCurrent,
    int pageNum = 1,
    int pageSize = 20,
  });
}
