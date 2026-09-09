import 'package:voice_social_app/features/discovery/dynamic/domain/dynamic_models.dart';

const s16RoomId = '12345678-1234-1234-1234-123456789abc';
Map<String, Object?> rankingWire({
  RankingBoard board = RankingBoard.charm,
  RankingPeriod period = RankingPeriod.day,
  int page = 1,
  int size = 20,
  int total = 1,
  int userId = 10001,
  String name = '当前榜单',
  Object? score = '10100',
}) {
  final offset = (page - 1) * size;
  final count = (total - offset).clamp(0, size);
  final entries = List.generate(
    count,
    (i) => <String, Object?>{
      'rank': offset + i + 1,
      if (board == RankingBoard.room) ...{
        'roomId': i == 0
            ? s16RoomId
            : '12345678-1234-1234-1234-${i.toString().padLeft(12, '0')}',
        'roomName': name,
        'roomCode': null,
        'ownerUserId': 10001,
      } else ...{
        'userId': userId + i,
        'nickName': name,
        'headImgUrl': '',
        'isCurrentUser': userId + i == 10001,
      },
      'score': board.isGiftValue ? score : 700,
      if (board.isGiftValue) ...{
        'firstReachedAt': score == '0' ? null : '2026-09-09T03:10:00.123456Z',
        'firstReachedTransferId': score == '0' ? null : '${offset + i + 1}',
      },
    },
  );
  return {
    'list': entries,
    'records': entries,
    'current': page,
    'pageSize': size,
    'total': total,
    'pages': (total + size - 1) ~/ size,
    'metric': board.metric,
    'serverAuthoritative': true,
    if (board.isGiftValue) ...{
      'period': period.backendValue,
      'timezone': 'Asia/Shanghai',
      'startInclusive': switch (period) {
        RankingPeriod.day => '2026-09-08T16:00:00Z',
        RankingPeriod.week => '2026-09-06T16:00:00Z',
        RankingPeriod.month => '2026-08-31T16:00:00Z',
      },
      'endExclusive': switch (period) {
        RankingPeriod.day => '2026-09-09T16:00:00Z',
        RankingPeriod.week => '2026-09-13T16:00:00Z',
        RankingPeriod.month => '2026-09-30T16:00:00Z',
      },
      'serverNow': '2026-09-09T04:00:00Z',
      'scoreUnit': 'CNY_FEN',
      'scoreEncoding': 'DECIMAL_STRING',
      'valueBasis': 'GIFT_VALUE',
      'excludedUnvaluedTransfers': 0,
    },
  };
}
