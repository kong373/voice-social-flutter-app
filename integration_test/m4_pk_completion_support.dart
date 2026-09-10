import 'package:voice_social_app/features/room/pk/domain/room_pk_models.dart';

/// Q21-04: observe the existing server settlement worker; never surrender,
/// close a room, edit a clock or manufacture an early end to clean up a test.
Future<RoomPkBattle> waitForM4NaturalPkCompletion({
  required RoomPkBattle accepted,
  required Future<RoomPkBattle> Function() refresh,
  Future<void> Function(Duration)? pause,
  Duration Function()? elapsed,
}) async {
  final stopwatch = Stopwatch()..start();
  final elapsedTime = elapsed ?? () => stopwatch.elapsed;
  final sleep = pause ?? Future<void>.delayed;
  final startedAt = accepted.startedAt;
  final endsAt = accepted.endsAt;
  if (startedAt == null ||
      endsAt == null ||
      !const [
        Duration(minutes: 5),
        Duration(minutes: 10),
        Duration(minutes: 15),
      ].contains(endsAt.difference(startedAt)) ||
      accepted.remainingSeconds < 0 ||
      accepted.remainingSeconds > 900) {
    throw StateError('M4_PK_INVALID_SERVER_TIMING');
  }
  final budget = Duration(seconds: accepted.remainingSeconds + 45);
  var current = accepted;
  while (true) {
    if (current.id != accepted.id ||
        current.currentRoomId != accepted.currentRoomId ||
        current.sender.roomId != accepted.sender.roomId ||
        current.receiver.roomId != accepted.receiver.roomId ||
        current.invitationId != accepted.invitationId ||
        current.startedAt?.isAtSameMomentAs(startedAt) != true ||
        current.endsAt?.isAtSameMomentAs(endsAt) != true) {
      throw StateError('M4_PK_COMPLETION_IDENTITY_CHANGED');
    }
    if (!current.isActive) {
      final expectedCode = current.sender.score == current.receiver.score
          ? 'DRAW'
          : current.sender.score > current.receiver.score
          ? 'LEFT_WIN'
          : 'RIGHT_WIN';
      final expectedResult =
          current.currentSide.score == current.opponentSide.score
          ? RoomPkResult.draw
          : current.currentSide.score > current.opponentSide.score
          ? RoomPkResult.win
          : RoomPkResult.lose;
      if (current.stage != RoomPkBattleStage.completed ||
          current.status != 'COMPLETED' ||
          current.remainingSeconds != 0 ||
          current.completedAt?.isAtSameMomentAs(endsAt) != true ||
          current.result != expectedResult ||
          current.resultCode != expectedCode) {
        throw StateError('M4_PK_NATURAL_SETTLEMENT_NOT_PROVEN');
      }
      return current;
    }
    final remainingBudget = budget - elapsedTime();
    if (remainingBudget <= Duration.zero) {
      throw StateError('M4_PK_NATURAL_SETTLEMENT_TIMEOUT');
    }
    await sleep(
      remainingBudget < const Duration(seconds: 5)
          ? remainingBudget
          : const Duration(seconds: 5),
    );
    final requestBudget = budget - elapsedTime();
    if (requestBudget <= Duration.zero) {
      throw StateError('M4_PK_NATURAL_SETTLEMENT_TIMEOUT');
    }
    current = await refresh().timeout(
      requestBudget < const Duration(seconds: 15)
          ? requestBudget
          : const Duration(seconds: 15),
    );
  }
}
