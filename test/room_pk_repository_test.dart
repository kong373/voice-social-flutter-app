import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/room/pk/data/mock_room_pk_repository.dart';
import 'package:voice_social_app/features/room/pk/domain/room_pk_models.dart';

void main() {
  test(
    'outgoing room PK invitation becomes a server-authoritative battle',
    () async {
      final MockRoomPkRepository repository = MockRoomPkRepository();
      final List<RoomPkOpponent> opponents = await repository.fetchHotOpponents(
        roomId: '880217',
      );
      final RoomPkOpponent target = opponents.firstWhere(
        (RoomPkOpponent item) => !item.isInPk,
      );

      RoomPkInvitation invitation = await repository.sendInvitation(
        roomId: '880217',
        inviterUserId: 10001,
        opponent: target,
        punishmentTheme: '分享今天最开心的事',
        durationMinutes: 5,
      );
      expect(invitation.status, RoomPkInvitationStatus.pending);

      invitation = await repository.refreshInvitation(invitation);
      expect(invitation.status, RoomPkInvitationStatus.pending);
      invitation = await repository.refreshInvitation(invitation);
      expect(invitation.status, RoomPkInvitationStatus.accepted);

      RoomPkBattle? battle = await repository.fetchActiveBattle(
        roomId: '880217',
      );
      expect(battle, isNotNull);
      expect(battle!.currentSide.roomId, '880217');

      for (int index = 0; index < 5; index += 1) {
        battle = await repository.refreshBattle(
          roomId: '880217',
          battleId: battle!.id,
        );
      }
      expect(battle!.stage, RoomPkBattleStage.completed);
      expect(battle.result, isNotNull);
      expect(await repository.fetchHistory(roomId: '880217'), isNotEmpty);
    },
  );

  test(
    'incoming invitation and surrender stay bound to the exact battle',
    () async {
      final MockRoomPkRepository repository = MockRoomPkRepository();
      final RoomPkInvitation? incoming = await repository
          .fetchIncomingInvitation(roomId: '880217');
      expect(incoming, isNotNull);

      final RoomPkBattle battle = await repository.acceptInvitation(incoming!);
      expect(battle.isActive, isTrue);
      await expectLater(
        repository.rejectInvitation(incoming),
        throwsA(isA<ApiException>()),
      );

      final RoomPkBattle surrendered = await repository.surrender(
        roomId: '880217',
        battleId: battle.id,
      );
      expect(surrendered.stage, RoomPkBattleStage.completed);
      expect(surrendered.result, RoomPkResult.surrendered);

      await expectLater(
        repository.surrender(roomId: '880217', battleId: battle.id),
        throwsA(isA<ApiException>()),
      );
    },
  );
}
