import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/features/room/pk/domain/room_pk_models.dart';

import '../integration_test/m4_pk_completion_support.dart';

void main() {
  test('M4 live PK never calls retired surrender or forces early cleanup', () {
    final source = File(
      'integration_test/m4_first_party_live_integration_test.dart',
    ).readAsStringSync();
    expect(source, isNot(contains('roomPkRepository.surrender(')));
    expect(source, isNot(contains('pk_accept_and_end_compensated')));
    expect(source, contains('waitForM4NaturalPkCompletion('));
    expect(source, contains('pk_natural_score_settlement_confirmed'));
  });
  final start = DateTime.utc(2026, 9, 10);
  final end = start.add(const Duration(minutes: 5));
  RoomPkBattle battle({bool completed = false, String id = 'battle'}) =>
      RoomPkBattle(
        id: id,
        currentRoomId: 'left',
        invitationId: 'invitation',
        sender: const RoomPkSide(
          roomId: 'left',
          roomCode: '1',
          roomName: 'A',
          score: 100,
        ),
        receiver: const RoomPkSide(
          roomId: 'right',
          roomCode: '2',
          roomName: 'B',
          score: 50,
        ),
        remainingSeconds: completed ? 0 : 5,
        punishmentTheme: '展示主题',
        stage: completed
            ? RoomPkBattleStage.completed
            : RoomPkBattleStage.fighting,
        status: completed ? 'COMPLETED' : 'IN_PROGRESS',
        resultCode: completed ? 'LEFT_WIN' : 'UNDECIDED',
        result: completed ? RoomPkResult.win : null,
        startedAt: start,
        endsAt: end,
        completedAt: completed ? end : null,
        updatedAt: completed ? end : start,
      );

  test('waits for authoritative natural completion using reads only', () async {
    var elapsed = Duration.zero;
    var reads = 0;
    final result = await waitForM4NaturalPkCompletion(
      accepted: battle(),
      refresh: () async => ++reads == 1 ? battle() : battle(completed: true),
      pause: (duration) async => elapsed += duration,
      elapsed: () => elapsed,
    );
    expect(reads, 2);
    expect(elapsed, const Duration(seconds: 10));
    expect(result.status, 'COMPLETED');
  });

  test(
    'already settled exact battle needs no mutation or extra read',
    () async {
      final accepted = battle(completed: true);
      final result = await waitForM4NaturalPkCompletion(
        accepted: accepted,
        refresh: () async => throw StateError('unexpected read'),
      );
      expect(identical(result, accepted), isTrue);
    },
  );

  test('a different battle is never accepted as cleanup evidence', () async {
    await expectLater(
      waitForM4NaturalPkCompletion(
        accepted: battle(),
        refresh: () async => battle(completed: true, id: 'replacement'),
        pause: (_) async {},
      ),
      throwsStateError,
    );
  });

  test('remaining zero without authoritative settlement times out', () async {
    var elapsed = Duration.zero;
    var reads = 0;
    await expectLater(
      waitForM4NaturalPkCompletion(
        accepted: battle().copyWith(remainingSeconds: 0),
        refresh: () async {
          reads++;
          return battle().copyWith(remainingSeconds: 0);
        },
        pause: (duration) async => elapsed += duration,
        elapsed: () => elapsed,
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'reason',
          'M4_PK_NATURAL_SETTLEMENT_TIMEOUT',
        ),
      ),
    );
    expect(elapsed, const Duration(seconds: 45));
    expect(reads, 8);
  });

  test(
    'early room close or surrender cannot replace natural completion',
    () async {
      for (final invalid in [
        battle(
          completed: true,
        ).copyWith(completedAt: end.subtract(const Duration(seconds: 1))),
        battle(completed: true).copyWith(result: RoomPkResult.surrendered),
        battle(completed: true).copyWith(status: 'SURRENDERED'),
        battle(completed: true).copyWith(result: RoomPkResult.draw),
        battle(completed: true).copyWith(resultCode: 'RIGHT_WIN'),
      ]) {
        await expectLater(
          waitForM4NaturalPkCompletion(
            accepted: invalid,
            refresh: () async => throw StateError('unexpected read'),
          ),
          throwsStateError,
        );
      }
    },
  );

  test('unsupported timing cannot create an unbounded wait', () async {
    await expectLater(
      waitForM4NaturalPkCompletion(
        accepted: battle().copyWith(
          endsAt: start.add(const Duration(hours: 1)),
        ),
        refresh: () async => throw StateError('unexpected read'),
      ),
      throwsStateError,
    );
  });
}
