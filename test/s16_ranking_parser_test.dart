import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/discovery/dynamic/data/ranking_contract.dart';
import 'package:voice_social_app/features/discovery/dynamic/domain/dynamic_models.dart';
import 's16_ranking_fixtures.dart';

void main() {
  RankingSnapshot parse(
    Object? raw, {
    RankingBoard board = RankingBoard.charm,
    RankingPeriod period = RankingPeriod.day,
    int page = 1,
    int size = 20,
  }) => parseRanking(
    raw,
    board: board,
    period: period,
    page: page,
    pageSize: size,
    viewerUserId: 10001,
  );
  final protocol = throwsA(
    isA<ApiException>().having((e) => e.kind, 'kind', ApiFailureKind.protocol),
  );
  test(
    'legacy room public_id and NULL roomCode remain valid display/navigation data',
    () {
      final wire = rankingWire(board: RankingBoard.room);
      (wire['list'] as List<Map<String, Object?>>).single['roomId'] = '100001';
      expect(
        parse(wire, board: RankingBoard.room).entries.single.roomId,
        '100001',
      );
    },
  );
  for (final score in [
    '0',
    '1',
    '10100',
    '9007199254740993',
    '184467440737095516150',
    '9' * 65,
  ]) {
    test('exact DECIMAL_STRING $score never traverses num', () {
      final entry = parse(rankingWire(score: score)).entries.single;
      expect(entry.giftValueFen, BigInt.parse(score));
      expect(entry.value, isNull);
      final padded = score.padLeft(3, '0');
      expect(
        entry.displayValue,
        '${padded.substring(0, padded.length - 2)}.${padded.substring(padded.length - 2)} 元',
      );
    });
  }
  test(
    'server windows cover Beijing New Year, Monday and leap month without local now',
    () {
      final cases = [
        (
          RankingPeriod.day,
          '2026-12-31T16:00:00Z',
          '2027-01-01T16:00:00Z',
          '2026-12-31T16:00:00Z',
        ),
        (
          RankingPeriod.week,
          '2026-12-27T16:00:00Z',
          '2027-01-03T16:00:00Z',
          '2027-01-01T04:00:00Z',
        ),
        (
          RankingPeriod.month,
          '2028-01-31T16:00:00Z',
          '2028-02-29T16:00:00Z',
          '2028-02-29T12:00:00Z',
        ),
      ];
      for (final (period, start, end, now) in cases) {
        final wire = {
          ...rankingWire(period: period, total: 0),
          'startInclusive': start,
          'endExclusive': end,
          'serverNow': now,
        };
        expect(
          parse(wire, period: period).startInclusive,
          DateTime.parse(start),
        );
        expect(
          () => parse({...wire, 'serverNow': end}, period: period),
          protocol,
        );
      }
    },
  );
  for (final score in [
    null,
    100,
    1.5,
    -1,
    true,
    '',
    '01',
    '-1',
    '+1',
    '1.0',
    '1e3',
    ' 1',
    'NaN',
    '9' * 66,
  ]) {
    test(
      'rejects malformed gift score $score',
      () => expect(() => parse(rankingWire(score: score)), protocol),
    );
  }
  for (final board in [
    RankingBoard.charm,
    RankingBoard.wealth,
    RankingBoard.room,
  ]) {
    for (final period in RankingPeriod.values) {
      test(
        '${board.name}/${period.name} accepts exact wire, server order and current window',
        () {
          final result = parse(
            rankingWire(board: board, period: period),
            board: board,
            period: period,
          );
          expect(result.period, period);
          expect(result.serverNow, DateTime.utc(2026, 9, 9, 4));
          expect(result.serverAuthoritative, isTrue);
          expect(result.entries.single.firstReachedTransferId, '1');
        },
      );
    }
  }
  final invalidFields = <String, Object?>{
    'period': 'MONTH',
    'timezone': 'UTC',
    'metric': 'WEALTH',
    'scoreUnit': 'GIFT_COIN',
    'scoreEncoding': 'NUMBER',
    'valueBasis': 'METRIC',
    'serverAuthoritative': false,
    'serverNow': '2026-09-09 04:00:00',
    'startInclusive': '2026-09-08T00:00:00Z',
    'endExclusive': '2026-09-09T00:00:00Z',
    'excludedUnvaluedTransfers': -1,
    'current': 2,
    'pageSize': 10,
    'total': 0,
    'pages': 2,
    'records': [],
  };
  for (final field in invalidFields.entries) {
    test(
      'wrong ${field.key} fails closed',
      () => expect(
        () => parse({...rankingWire(), field.key: field.value}),
        protocol,
      ),
    );
    test('missing ${field.key} fails closed', () {
      final wire = rankingWire()..remove(field.key);
      expect(() => parse(wire), protocol);
    });
  }
  test(
    'real server paging, zero result and out-of-range page preserve metadata',
    () {
      final result = parse(
        rankingWire(page: 2, size: 1, total: 2),
        page: 2,
        size: 1,
      );
      expect(result.entries.single.rank, 2);
      expect(result.total, 2);
      expect(result.hasMore, isFalse);
      expect(parse(rankingWire(page: 10, total: 2), page: 10).entries, isEmpty);
      expect(parse(rankingWire(total: 0)).pages, 0);
    },
  );
  test(
    'keeps authoritative order, does not sort equal values on the client',
    () {
      final wire = rankingWire(total: 2);
      final rows = wire['list'] as List<Map<String, Object?>>;
      rows[0]['userId'] = 90000;
      rows[0]['isCurrentUser'] = false;
      expect(parse(wire).entries.first.userId, 90000);
    },
  );
  test(
    'rejects duplicate IDs, false self flag, wrong rank or invalid reached pair',
    () {
      for (final change in [
        {'rank': 2},
        {'isCurrentUser': false},
        {'firstReachedAt': null},
        {'firstReachedAt': '2026-09-09T16:00:00Z'},
        {'firstReachedTransferId': '18446744073709551616'},
        {'firstReachedAt': '2026-09-32T00:00:00Z'},
      ]) {
        final wire = rankingWire();
        (wire['list'] as List<Map<String, Object?>>).single.addAll(change);
        expect(() => parse(wire), protocol);
      }
      final wire = rankingWire(total: 2);
      (wire['list'] as List<Map<String, Object?>>)[1].addAll({
        'userId': 10001,
        'isCurrentUser': true,
      });
      expect(() => parse(wire), protocol);
    },
  );
  test(
    'contribution remains numeric cumulative, not a mislabeled gift board',
    () {
      final result = parse(
        rankingWire(board: RankingBoard.contribution),
        board: RankingBoard.contribution,
      );
      expect(result.period, isNull);
      expect(result.entries.single.value, 700);
      expect(result.entries.single.giftValueFen, isNull);
      expect(result.entries.single.displayValue, '700');
      final wire = rankingWire(board: RankingBoard.contribution);
      (wire['list'] as List<Map<String, Object?>>).single['score'] = '700';
      expect(() => parse(wire, board: RankingBoard.contribution), protocol);
      expect(
        () => parse({
          ...rankingWire(board: RankingBoard.contribution),
          'period': 'DAY',
        }, board: RankingBoard.contribution),
        protocol,
      );
    },
  );
}
