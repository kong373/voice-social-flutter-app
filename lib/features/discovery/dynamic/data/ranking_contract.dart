import 'package:voice_social_app/core/network/api_exception.dart';
import '../domain/dynamic_models.dart';

/// The three gift-value boards have a distinct wire type from contribution.
RankingSnapshot parseRanking(
  Object? raw, {
  required RankingBoard board,
  required RankingPeriod period,
  required int page,
  required int pageSize,
  required int viewerUserId,
}) {
  final data = _map(raw);
  if (data['serverAuthoritative'] != true || data['metric'] != board.metric)
    _invalid();
  final current = _integer(data['current'], min: 1);
  final size = _integer(data['pageSize'], min: 1);
  final total = _integer(data['total']);
  final pages = _integer(data['pages']);
  if (current != page ||
      size != pageSize ||
      pages != total ~/ size + (total % size == 0 ? 0 : 1))
    _invalid();
  final list = data['list'];
  if (list is! List || !_same(list, data['records'])) _invalid();
  final offset = (page - 1) * pageSize;
  final remaining = total - offset;
  final count = remaining <= 0
      ? 0
      : remaining < size
      ? remaining
      : size;
  if (list.length != count) _invalid();
  DateTime? start, end, now;
  int excluded = 0;
  if (board.isGiftValue) {
    if (data['period'] != period.backendValue ||
        data['timezone'] != 'Asia/Shanghai' ||
        data['scoreUnit'] != 'CNY_FEN' ||
        data['scoreEncoding'] != 'DECIMAL_STRING' ||
        data['valueBasis'] != 'GIFT_VALUE')
      _invalid();
    start = _instant(data['startInclusive']);
    end = _instant(data['endExclusive']);
    now = _instant(data['serverNow']);
    // Validate the server's own window, never substitute the device's clock.
    final beijing = now.add(const Duration(hours: 8));
    var expectedStart = DateTime.utc(beijing.year, beijing.month, beijing.day);
    DateTime expectedEnd;
    switch (period) {
      case RankingPeriod.day:
        expectedEnd = expectedStart.add(const Duration(days: 1));
      case RankingPeriod.week:
        expectedStart = expectedStart.subtract(
          Duration(days: beijing.weekday - 1),
        );
        expectedEnd = expectedStart.add(const Duration(days: 7));
      case RankingPeriod.month:
        expectedStart = DateTime.utc(beijing.year, beijing.month);
        expectedEnd = DateTime.utc(beijing.year, beijing.month + 1);
    }
    if (start != expectedStart.subtract(const Duration(hours: 8)) ||
        end != expectedEnd.subtract(const Duration(hours: 8)))
      _invalid();
    excluded = _integer(data['excludedUnvaluedTransfers']);
  } else if (data.containsKey('period') ||
      data.containsKey('valueBasis') ||
      data.containsKey('scoreUnit') ||
      data.containsKey('scoreEncoding')) {
    _invalid();
  }
  final ids = <Object>{};
  final entries = <RankingEntry>[];
  for (final rawEntry in list) {
    final item = _map(rawEntry);
    final rank = _integer(item['rank'], min: 1);
    if (rank != offset + entries.length + 1) _invalid();
    final room = board == RankingBoard.room;
    final int? userId = room ? null : _integer(item['userId'], min: 1);
    final String? roomId = room ? _text(item['roomId']) : null;
    // The historical room public_id is opaque (including "100001"), not
    // necessarily a UUID. Never replace it with roomCode or a fabricated ID.
    if (!ids.add(room ? roomId! : userId!)) _invalid();
    final name = _text(item[room ? 'roomName' : 'nickName'], allowEmpty: true);
    if (room) {
      _integer(item['ownerUserId'], min: 1);
      // Legacy NULL/empty roomCode is only a display identifier, never an ID.
      if (item['roomCode'] != null && item['roomCode'] is! String) _invalid();
    }
    bool isCurrentUser = false;
    if (!room) {
      if (item['isCurrentUser'] is! bool ||
          item['isCurrentUser'] != (userId == viewerUserId))
        _invalid();
      isCurrentUser = item['isCurrentUser'] as bool;
    }
    BigInt? fen;
    num? legacy;
    DateTime? reached;
    String? transferId;
    if (board.isGiftValue) {
      fen = parseGiftRankingFen(item['score']);
      if (!item.containsKey('firstReachedAt') ||
          !item.containsKey('firstReachedTransferId'))
        _invalid();
      if (fen > BigInt.zero) {
        reached = _instant(item['firstReachedAt']);
        transferId = _text(item['firstReachedTransferId']);
        if (!RegExp(r'^[1-9][0-9]{0,19}$').hasMatch(transferId) ||
            BigInt.parse(transferId) > BigInt.parse('18446744073709551615') ||
            reached.isBefore(start!) ||
            !reached.isBefore(end!))
          _invalid();
      } else if (item['firstReachedAt'] != null ||
          item['firstReachedTransferId'] != null)
        _invalid();
    } else {
      final score = item['score'];
      if (score is! num || !score.isFinite || score < 0) _invalid();
      legacy = score;
    }
    final avatar = item['headImgUrl'];
    if (!room && avatar != null && avatar is! String) _invalid();
    entries.add(
      RankingEntry(
        rank: rank,
        userId: userId,
        roomId: roomId,
        name: name.isEmpty ? (room ? '房间 $roomId' : '用户 $userId') : name,
        avatarUrl: room ? null : avatar as String?,
        value: legacy,
        giftValueFen: fen,
        firstReachedAt: reached,
        firstReachedTransferId: transferId,
        isCurrentUser: isCurrentUser,
      ),
    );
  }
  return RankingSnapshot(
    board: board,
    period: board.isGiftValue ? period : null,
    entries: List.unmodifiable(entries),
    page: current,
    pageSize: size,
    total: total,
    pages: pages,
    startInclusive: start,
    endExclusive: end,
    serverNow: now,
    excludedUnvaluedTransfers: excluded,
    serverAuthoritative: true,
  );
}

BigInt parseGiftRankingFen(Object? value) {
  if (value is! String || !RegExp(r'^(0|[1-9][0-9]{0,64})$').hasMatch(value))
    _invalid();
  return BigInt.parse(value);
}

Map<String, Object?> _map(Object? raw) {
  if (raw is! Map<String, Object?>) _invalid();
  return raw;
}

int _integer(Object? raw, {int min = 0}) {
  if (raw is! int || raw < min || raw > 9007199254740991) _invalid();
  return raw;
}

String _text(Object? raw, {bool allowEmpty = false}) {
  if (raw is! String || (!allowEmpty && raw.trim().isEmpty)) _invalid();
  return raw;
}

DateTime _instant(Object? raw) {
  final text = _text(raw);
  if (!RegExp(
    r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?Z$',
  ).hasMatch(text))
    _invalid();
  final date = DateTime.tryParse(text);
  if (date == null ||
      !date.isUtc ||
      date.toIso8601String().substring(0, 19) != text.substring(0, 19))
    _invalid();
  return date;
}

bool _same(Object? a, Object? b) {
  if (a is Map && b is Map)
    return a.length == b.length &&
        a.keys.every((key) => b.containsKey(key) && _same(a[key], b[key]));
  if (a is List && b is List)
    return a.length == b.length &&
        List.generate(a.length, (i) => _same(a[i], b[i])).every((v) => v);
  return a == b;
}

Never _invalid() => throw const ApiException(
  kind: ApiFailureKind.protocol,
  message: '排行榜响应与当前请求或金额合同不一致',
);
