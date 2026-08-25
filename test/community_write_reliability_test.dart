import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/features/community/data/backend_community_repository.dart';
import 'package:voice_social_app/features/community/domain/community_request_id.dart';

void main() {
  test('community request ids are secure-shaped, bounded, and classified', () {
    final String first = newCommunityRequestId('flutter-community-test');
    final String second = newCommunityRequestId('flutter-community-test');
    expect(first, matches(RegExp(r'^flutter-community-test-[0-9a-f]{32}$')));
    expect(first.length, lessThanOrEqualTo(80));
    expect(second, isNot(first));

    expect(
      shouldRetainCommunityWriteRequest(
        const ApiException(
          kind: ApiFailureKind.timeout,
          message: 'response lost',
        ),
      ),
      isTrue,
    );
    expect(
      shouldRetainCommunityWriteRequest(
        const ApiException(
          kind: ApiFailureKind.conflict,
          code: 40901,
          httpStatus: 409,
          message: 'unknown commit',
        ),
      ),
      isTrue,
    );
    expect(
      shouldRetainCommunityWriteRequest(
        const ApiException(
          kind: ApiFailureKind.conflict,
          code: 40902,
          httpStatus: 409,
          message: 'unknown commit',
        ),
      ),
      isTrue,
    );
    expect(
      shouldRetainCommunityWriteRequest(
        const ApiException(
          kind: ApiFailureKind.conflict,
          code: 40903,
          httpStatus: 409,
          message: 'definitive conflict',
        ),
      ),
      isFalse,
    );
    expect(
      shouldRetainCommunityWriteRequest(
        const ApiException(
          kind: ApiFailureKind.validation,
          code: 40001,
          httpStatus: 400,
          message: 'invalid',
        ),
      ),
      isFalse,
    );
  });

  test(
    'same community intent single-flights and rotates after success',
    () async {
      final Completer<void> release = Completer<void>();
      final Completer<void> firstSeen = Completer<void>();
      int applyCalls = 0;
      final _Harness harness = await _Harness.start((
        RequestRecord request,
      ) async {
        if (request.path.endsWith('/applyForMembership')) {
          applyCalls += 1;
          if (applyCalls == 1) {
            firstSeen.complete();
            await release.future;
          }
          return _Reply.ok(<String, Object?>{
            'applicationId': 'application-1',
            'guildId': 'guild-1',
            'status': 'PENDING',
          });
        }
        return _Reply.ok(<String, Object?>{});
      });
      addTearDown(harness.close);

      final Future<void> first = harness.repository.applyToJoinGuild('guild-1');
      await firstSeen.future;
      final Future<void> second = harness.repository.applyToJoinGuild(
        'guild-1',
      );
      expect(
        harness.requests.where(
          (RequestRecord item) => item.path.endsWith('/applyForMembership'),
        ),
        hasLength(1),
      );
      release.complete();
      await Future.wait(<Future<void>>[first, second]);

      await harness.repository.applyToJoinGuild('guild-1');
      final List<RequestRecord> writes = harness.requests
          .where(
            (RequestRecord item) => item.path.endsWith('/applyForMembership'),
          )
          .toList(growable: false);
      expect(writes, hasLength(2));
      expect(writes[0].requestId, isNotEmpty);
      expect(writes[0].requestId, isNot(writes[1].requestId));
    },
  );

  test(
    'ambiguous community retry retains id while definitive conflict rotates',
    () async {
      int attempts = 0;
      final _Harness harness = await _Harness.start((RequestRecord request) {
        if (request.path.endsWith('/applyForMembership')) {
          attempts += 1;
          if (attempts == 1) {
            return const _Reply(
              statusCode: 500,
              code: 50001,
              message: 'committed but response unknown',
              data: null,
            );
          }
          if (attempts == 3) {
            return const _Reply(
              statusCode: 409,
              code: 40903,
              message: 'already resolved',
              data: null,
            );
          }
          return _Reply.ok(<String, Object?>{
            'applicationId': 'application-1',
            'guildId': 'guild-1',
            'status': 'PENDING',
          });
        }
        return _Reply.ok(<String, Object?>{});
      });
      addTearDown(harness.close);

      await expectLater(
        harness.repository.applyToJoinGuild('guild-1'),
        throwsA(isA<ApiException>()),
      );
      await harness.repository.applyToJoinGuild('guild-1');
      await expectLater(
        harness.repository.applyToJoinGuild('guild-1'),
        throwsA(isA<ApiException>()),
      );
      await harness.repository.applyToJoinGuild('guild-1');

      final List<RequestRecord> writes = harness.requests
          .where(
            (RequestRecord item) => item.path.endsWith('/applyForMembership'),
          )
          .toList(growable: false);
      expect(writes, hasLength(4));
      expect(writes[0].requestId, writes[1].requestId);
      expect(writes[1].requestId, isNot(writes[2].requestId));
      expect(writes[2].requestId, isNot(writes[3].requestId));
    },
  );

  test(
    'guild sign keeps one id across 40901 and 40902 on one business day',
    () async {
      int attempts = 0;
      final _Harness harness = await _Harness.start((RequestRecord request) {
        if (request.path.endsWith('/guild/sign/status')) {
          return _Reply.ok(_availableGuildSignStatus());
        }
        if (request.path.endsWith('/guild/sign')) {
          attempts += 1;
          if (attempts == 1) {
            return const _Reply(
              statusCode: 409,
              code: 40901,
              message: 'unknown commit',
              data: null,
            );
          }
          if (attempts == 2) {
            return const _Reply(
              statusCode: 409,
              code: 40902,
              message: 'unknown commit',
              data: null,
            );
          }
          return _Reply.ok(<String, Object?>{
            'guildId': 'guild-1',
            'signed': true,
            'signedToday': true,
            'isSign': true,
            'alreadySigned': false,
            'signDate': '2026-08-23',
            'businessDate': '2026-08-23',
            'rewardPoints': 1,
            'status': 'SIGNED',
            'providerInvocation': false,
          });
        }
        return const _Reply.ok(<String, Object?>{});
      });
      addTearDown(harness.close);

      await expectLater(
        harness.repository.signGuild('guild-1'),
        throwsA(isA<ApiException>()),
      );
      await expectLater(
        harness.repository.signGuild('guild-1'),
        throwsA(isA<ApiException>()),
      );
      await harness.repository.signGuild('guild-1');

      final List<RequestRecord> writes = harness.requests
          .where((RequestRecord item) => item.path.endsWith('/guild/sign'))
          .toList(growable: false);
      expect(writes, hasLength(3));
      expect(writes[0].requestId, writes[1].requestId);
      expect(writes[1].requestId, writes[2].requestId);
    },
  );

  test(
    'guild sign trusts the backend business date over the device date',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        if (request.path.endsWith('/guild/sign/status')) {
          return _Reply.ok(_availableGuildSignStatus());
        }
        if (request.path.endsWith('/guild/sign')) {
          return _Reply.ok(<String, Object?>{
            'guildId': 'guild-1',
            'signed': true,
            'signedToday': true,
            'isSign': true,
            'alreadySigned': false,
            'signDate': '2026-08-23',
            'businessDate': '2026-08-23',
            'rewardPoints': 1,
            'status': 'SIGNED',
            'providerInvocation': false,
          });
        }
        return const _Reply.ok(<String, Object?>{});
      });
      addTearDown(harness.close);

      await harness.repository.signGuild('guild-1');

      expect(
        harness.requests.where(
          (RequestRecord item) => item.path.endsWith('/guild/sign'),
        ),
        hasLength(1),
      );
    },
  );

  test(
    'guild sign rotates a retained id after the local business date changes',
    () async {
      DateTime now = DateTime(2026, 8, 23, 23, 59);
      int attempts = 0;
      final _Harness harness = await _Harness.start((RequestRecord request) {
        if (request.path.endsWith('/guild/sign/status')) {
          final String date =
              '${now.year.toString().padLeft(4, '0')}-'
              '${now.month.toString().padLeft(2, '0')}-'
              '${now.day.toString().padLeft(2, '0')}';
          return _Reply.ok(_availableGuildSignStatus(businessDate: date));
        }
        if (request.path.endsWith('/guild/sign')) {
          attempts += 1;
          if (attempts == 1) {
            return const _Reply(
              statusCode: 409,
              code: 40901,
              message: 'unknown commit',
              data: null,
            );
          }
          return _Reply.ok(<String, Object?>{
            'guildId': 'guild-1',
            'signed': true,
            'signedToday': true,
            'isSign': true,
            'alreadySigned': false,
            'signDate':
                '${now.year.toString().padLeft(4, '0')}-'
                '${now.month.toString().padLeft(2, '0')}-'
                '${now.day.toString().padLeft(2, '0')}',
            'businessDate':
                '${now.year.toString().padLeft(4, '0')}-'
                '${now.month.toString().padLeft(2, '0')}-'
                '${now.day.toString().padLeft(2, '0')}',
            'rewardPoints': 1,
            'status': 'SIGNED',
            'providerInvocation': false,
          });
        }
        return const _Reply.ok(<String, Object?>{});
      });
      addTearDown(harness.close);

      await expectLater(
        harness.repository.signGuild('guild-1'),
        throwsA(isA<ApiException>()),
      );
      now = DateTime(2026, 8, 24, 0, 1);
      await harness.repository.signGuild('guild-1');

      final List<RequestRecord> writes = harness.requests
          .where((RequestRecord item) => item.path.endsWith('/guild/sign'))
          .toList(growable: false);
      expect(writes, hasLength(2));
      expect(writes[0].requestId, isNot(writes[1].requestId));
    },
  );

  test('guild sign rejects a stale signDate response', () async {
    final _Harness harness = await _Harness.start((RequestRecord request) {
      if (request.path.endsWith('/guild/sign/status')) {
        return _Reply.ok(_availableGuildSignStatus());
      }
      if (request.path.endsWith('/guild/sign')) {
        return _Reply.ok(<String, Object?>{
          'guildId': 'guild-1',
          'signed': true,
          'signedToday': true,
          'isSign': true,
          'alreadySigned': false,
          'signDate': '2026-08-22',
          'businessDate': '2026-08-23',
          'rewardPoints': 1,
          'status': 'SIGNED',
          'providerInvocation': false,
        });
      }
      return const _Reply.ok(<String, Object?>{});
    });
    addTearDown(harness.close);

    await expectLater(
      harness.repository.signGuild('guild-1'),
      throwsA(
        isA<ApiException>().having(
          (ApiException error) => error.kind,
          'kind',
          ApiFailureKind.protocol,
        ),
      ),
    );
  });

  test('daily check-in rejects a stale businessDate response', () async {
    final _Harness harness = await _Harness.start((RequestRecord request) {
      if (request.path.endsWith('/completeDailySignIn')) {
        return _Reply.ok(<String, Object?>{
          'signed': true,
          'signedToday': true,
          'isSign': true,
          'alreadySigned': false,
          'businessDate': '2026-08-22',
          'taskId': 100,
          'providerInvocation': false,
        });
      }
      return const _Reply.ok(<String, Object?>{});
    });
    addTearDown(harness.close);

    await expectLater(
      harness.repository.completeDailyCheckIn(),
      throwsA(
        isA<ApiException>().having(
          (ApiException error) => error.kind,
          'kind',
          ApiFailureKind.protocol,
        ),
      ),
    );
  });

  test(
    'daily check-in trusts the backend business date over the device date',
    () async {
      final DateTime backendNow = DateTime(2026, 8, 23);
      bool signed = false;
      final _Harness harness = await _Harness.start((RequestRecord request) {
        if (request.path.endsWith('/completeDailySignIn')) {
          signed = true;
          return _Reply.ok(<String, Object?>{
            'signed': true,
            'signedToday': true,
            'isSign': true,
            'alreadySigned': false,
            'businessDate': '2026-08-23',
            'taskId': 100,
            'providerInvocation': false,
          });
        }
        return _dailyTaskCenterReply(request, backendNow, signedToday: signed);
      });
      addTearDown(harness.close);

      final snapshot = await harness.repository.completeDailyCheckIn();

      expect(snapshot.signedToday, isTrue);
    },
  );

  test(
    'daily check-in keeps its id across unknown conflicts but not across dates',
    () async {
      DateTime now = DateTime(2026, 8, 23, 23, 59);
      int attempts = 0;
      String? signedDate;
      final _Harness harness = await _Harness.start((RequestRecord request) {
        if (request.path.endsWith('/completeDailySignIn')) {
          attempts += 1;
          if (attempts == 1) {
            return const _Reply(
              statusCode: 409,
              code: 40901,
              message: 'unknown commit',
              data: null,
            );
          }
          if (attempts == 2) {
            return const _Reply(
              statusCode: 409,
              code: 40902,
              message: 'unknown commit',
              data: null,
            );
          }
          final String date =
              '${now.year.toString().padLeft(4, '0')}-'
              '${now.month.toString().padLeft(2, '0')}-'
              '${now.day.toString().padLeft(2, '0')}';
          signedDate = date;
          return _Reply.ok(<String, Object?>{
            'signed': true,
            'signedToday': true,
            'isSign': true,
            'alreadySigned': false,
            'businessDate': date,
            'taskId': 100,
            'providerInvocation': false,
          });
        }
        final String currentDate =
            '${now.year.toString().padLeft(4, '0')}-'
            '${now.month.toString().padLeft(2, '0')}-'
            '${now.day.toString().padLeft(2, '0')}';
        return _dailyTaskCenterReply(
          request,
          now,
          signedToday: signedDate == currentDate,
        );
      });
      addTearDown(harness.close);

      await expectLater(
        harness.repository.completeDailyCheckIn(),
        throwsA(isA<ApiException>()),
      );
      await expectLater(
        harness.repository.completeDailyCheckIn(),
        throwsA(isA<ApiException>()),
      );
      await harness.repository.completeDailyCheckIn();
      final String firstDayRequestId = harness.requests
          .firstWhere(
            (RequestRecord item) => item.path.endsWith('/completeDailySignIn'),
          )
          .requestId;
      final String secondAttemptRequestId = harness.requests
          .where(
            (RequestRecord item) => item.path.endsWith('/completeDailySignIn'),
          )
          .elementAt(1)
          .requestId;
      expect(firstDayRequestId, secondAttemptRequestId);

      now = DateTime(2026, 8, 24, 0, 1);
      await harness.repository.completeDailyCheckIn();
      final List<RequestRecord> writes = harness.requests
          .where(
            (RequestRecord item) => item.path.endsWith('/completeDailySignIn'),
          )
          .toList(growable: false);
      expect(writes, hasLength(4));
      expect(writes[2].requestId, isNot(writes[3].requestId));
    },
  );

  test('401 recovery replays the same community request id', () async {
    int recoveryCalls = 0;
    int attempts = 0;
    final _Harness harness = await _Harness.start(
      (RequestRecord request) {
        if (request.path.endsWith('/applyForMembership')) {
          attempts += 1;
          if (attempts == 1) {
            return const _Reply(
              statusCode: 401,
              code: 401,
              message: 'expired',
              data: null,
            );
          }
          return _Reply.ok(<String, Object?>{
            'applicationId': 'application-1',
            'guildId': 'guild-1',
            'status': 'PENDING',
          });
        }
        return _Reply.ok(<String, Object?>{});
      },
      unauthorizedRecovery: () async {
        recoveryCalls += 1;
        return true;
      },
    );
    addTearDown(harness.close);

    await harness.repository.applyToJoinGuild('guild-1');

    final List<RequestRecord> writes = harness.requests
        .where(
          (RequestRecord item) => item.path.endsWith('/applyForMembership'),
        )
        .toList(growable: false);
    expect(recoveryCalls, 1);
    expect(writes, hasLength(2));
    expect(writes[0].requestId, isNotEmpty);
    expect(writes[0].requestId, writes[1].requestId);
  });

  test('conflicting member mutations serialize per member entity', () async {
    final Completer<void> release = Completer<void>();
    final Completer<void> firstSeen = Completer<void>();
    int calls = 0;
    final _Harness harness = await _Harness.start((
      RequestRecord request,
    ) async {
      if (request.path.endsWith('/memberBanOrUnseal')) {
        calls += 1;
        if (calls == 1) {
          firstSeen.complete();
          await release.future;
        }
        final Map<String, Object?> body = request.body! as Map<String, Object?>;
        return _Reply.ok(<String, Object?>{
          'guildId': 'guild-1',
          'userId': 7,
          'muted': body['muted'],
        });
      }
      return _Reply.ok(<String, Object?>{});
    });
    addTearDown(harness.close);

    final Future<void> mute = harness.repository.setGuildMemberMuted(
      guildId: 'guild-1',
      userId: 7,
      muted: true,
    );
    await firstSeen.future;
    final Future<void> unmute = harness.repository.setGuildMemberMuted(
      guildId: 'guild-1',
      userId: 7,
      muted: false,
    );
    expect(calls, 1);
    release.complete();
    await Future.wait(<Future<void>>[mute, unmute]);

    final List<RequestRecord> writes = harness.requests
        .where((RequestRecord item) => item.path.endsWith('/memberBanOrUnseal'))
        .toList(growable: false);
    expect(writes, hasLength(2));
    expect((writes[0].body! as Map<String, Object?>)['muted'], isTrue);
    expect((writes[1].body! as Map<String, Object?>)['muted'], isFalse);
    expect(writes[0].requestId, isNot(writes[1].requestId));
  });
}

class _Harness {
  _Harness._(this.server, this.requests, this.repository);

  final HttpServer server;
  final List<RequestRecord> requests;
  final BackendCommunityRepository repository;

  static Future<_Harness> start(
    FutureOr<_Reply> Function(RequestRecord request) handler, {
    UnauthorizedRecovery? unauthorizedRecovery,
  }) async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final List<RequestRecord> requests = <RequestRecord>[];
    final BackendCommunityRepository repository = BackendCommunityRepository(
      apiClient: ApiClient(
        baseUri: Uri.parse('http://${server.address.address}:${server.port}/'),
        clientType: 'Android',
        clientInnerVersion: '6',
        authorizationProvider: () => 'Bearer reliability-test',
        unauthorizedRecovery: unauthorizedRecovery,
      ),
      routes: const BackendRouteCatalog(),
    );
    final _Harness harness = _Harness._(server, requests, repository);
    server.listen((HttpRequest request) async {
      final String rawBody = await utf8.decoder.bind(request).join();
      final Object? decodedBody = rawBody.trim().isEmpty
          ? null
          : jsonDecode(rawBody);
      final RequestRecord record = RequestRecord(
        method: request.method,
        path: request.uri.path,
        requestId: request.headers.value('X-Request-Id') ?? '',
        body: decodedBody is Map
            ? Map<String, Object?>.from(decodedBody)
            : decodedBody,
      );
      requests.add(record);
      final _Reply reply = await handler(record);
      request.response.statusCode = reply.statusCode;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(<String, Object?>{
          'code': reply.code,
          'message': reply.message,
          'data': reply.data,
        }),
      );
      await request.response.close();
    });
    return harness;
  }

  Future<void> close() => server.close(force: true);
}

class RequestRecord {
  const RequestRecord({
    required this.method,
    required this.path,
    required this.requestId,
    required this.body,
  });

  final String method;
  final String path;
  final String requestId;
  final Object? body;
}

class _Reply {
  const _Reply({
    required this.statusCode,
    required this.code,
    required this.message,
    required this.data,
  });

  const _Reply.ok(Object? data)
    : statusCode = 200,
      code = 200,
      message = 'OK',
      data = data;

  final int statusCode;
  final int code;
  final String message;
  final Object? data;
}

Map<String, Object?> _availableGuildSignStatus({
  String businessDate = '2026-08-23',
}) => <String, Object?>{
  'guildId': 'guild-1',
  'hasGuild': true,
  'member': true,
  'signed': false,
  'signedToday': false,
  'isSign': false,
  'alreadySigned': false,
  'businessDate': businessDate,
  'signDate': '',
  'rewardPoints': 0,
  'status': 'AVAILABLE',
  'providerInvocation': false,
};

_Reply _dailyTaskCenterReply(
  RequestRecord request,
  DateTime now, {
  bool signedToday = true,
}) {
  final String date =
      '${now.year.toString().padLeft(4, '0')}-'
      '${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';
  final Map<String, Object?> task = <String, Object?>{
    'taskId': 101,
    'id': 101,
    'taskCode': 'DAILY_SIGN_IN',
    'taskName': '签到',
    'title': '签到',
    'description': '签到',
    'taskDesc': '签到',
    'currentValue': 1,
    'progress': 1,
    'targetValue': 1,
    'target': 1,
    'rewardDesc': '1积分',
    'reward': '1积分',
    'isReceive': false,
    'claimed': false,
    'status': 1,
    'businessDate': date,
  };
  final List<Map<String, Object?>> rewards =
      List<Map<String, Object?>>.generate(7, (int index) {
        final String rewardDate = DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: 6 - index))
            .toIso8601String()
            .split('T')
            .first;
        return <String, Object?>{
          'day': index + 1,
          'signDay': index + 1,
          'date': rewardDate,
          'rewardDesc': '1积分',
          'reward': '1积分',
          'completed': index < 6,
          'isSign': index < 6,
          'today': index == 6,
          'isToday': index == 6,
        };
      });
  return switch (request.path) {
    '/app-api/taskSystem/queryTaskRecords' => _Reply.ok(<String, Object?>{
      'list': <Object?>[task],
      'records': <Object?>[task],
      'total': 1,
      'type': 1,
      'providerInvocation': false,
    }),
    '/app-api/taskSystem/querySignReward' => _Reply.ok(<String, Object?>{
      'list': rewards,
      'records': rewards,
      'total': 7,
      'cycleStart': rewards.first['date'],
      'cycleEnd': rewards.last['date'],
      'providerInvocation': false,
    }),
    '/app-api/taskSystem/queryTodaySignStatus' => _Reply.ok(<String, Object?>{
      'signedToday': signedToday,
      'isSign': signedToday,
      'continuousDays': signedToday ? 1 : 0,
      'consecutiveDays': signedToday ? 1 : 0,
      'businessDate': date,
      'providerInvocation': false,
    }),
    _ => const _Reply.ok(<String, Object?>{}),
  };
}
