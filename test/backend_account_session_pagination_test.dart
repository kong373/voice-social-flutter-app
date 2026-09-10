import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/account/compliance/data/backend_account_compliance_repository.dart';
import 'package:voice_social_app/features/account/compliance/domain/account_compliance.dart';

import 'backend_account_compliance_repository_contract_test.dart' as contract;

Map<String, Object?> page(int number, {int total = 21}) {
  final start = (number - 1) * 20;
  return <String, Object?>{
    'total': total,
    'pageNum': number,
    'pageSize': 20,
    'pages': (total + 19) ~/ 20,
    'hasMore': number < (total + 19) ~/ 20,
    'list': <Object?>[
      for (int i = start; i < total && i < start + 20; i++)
        <String, Object?>{
          'sessionId': 'session-$i',
          'deviceId': 'device-$i',
          'active': true,
          'current': i == 0,
          'createdAt': '2026-09-01T00:00:00Z',
          'lastUsedAt': '',
        },
    ],
  };
}

Future<AccountComplianceSnapshot> fetch(
  Future<void> Function(contract.RequestRecord) sessions, {
  int userId = 1,
  int restrictionTotal = 0,
}) async {
  final server = await contract.startServer((request) async {
    if (request.path.endsWith('/sessions')) return sessions(request);
    final data = switch (request.path) {
      '/app-api/user/getPersonalData' => <String, Object?>{
        'userId': userId,
        'loginName': 'user',
        'nickName': 'User',
      },
      '/app-api/user/other/getMatchButtonAndYouthMode' => <String, Object?>{
        'youthModeEnabled': false,
      },
      '/app-mini-api/mini/v1/account/restrictions' => <String, Object?>{
        'restricted': false,
        'accountUsable': false,
        'total': restrictionTotal,
        'list': <Object?>[],
      },
      '/app-api/user/queryUserLogout' => <String, Object?>{
        'canLogout': true,
        'canCancel': false,
        'eligible': true,
        'status': 'NONE',
        'latestRequest': <String, Object?>{},
        'requiresConfirmation': true,
        'immediateDeletion': false,
      },
      '/app-api/appBase/getVersionInformation' => <String, Object?>{
        'isUpdate': 0,
        'latest': <String, Object?>{},
        'providerInvocation': false,
      },
      '/app-mini-api/mini/v1/account/real-name' => <String, Object?>{
        'status': 'UNVERIFIED',
        'statusCode': 0,
        'needsAgeResubmission': false,
        'canSubmit': true,
        'providerStatus': 'FIRST_PARTY_REVIEW',
        'reviewStatus': 'FIRST_PARTY_REVIEW',
        'reviewMode': 'FIRST_PARTY_MANUAL_REVIEW',
        'providerInvocation': false,
      },
      _ => throw StateError('Unexpected route ${request.path}'),
    };
    await contract.reply(request, data: data);
  });
  addTearDown(() => server.close(force: true));
  return BackendAccountComplianceRepository(
    apiClient: contract.client(server),
    currentDeviceIdProvider: () => 'device-0',
  ).fetchSnapshot(
    account: 'user',
    expectedUserId: 1,
    currentVersion: 6,
    platformType: 1,
  );
}

void main() {
  final protocolError = throwsA(
    isA<ApiException>().having((e) => e.kind, 'kind', ApiFailureKind.protocol),
  );
  test('reads all 21 active sessions across two pages', () async {
    final queries = <Map<String, String>>[];
    final snapshot = await fetch((request) async {
      queries.add(request.query);
      final number = int.parse(request.query['pageNum'] ?? '1');
      await contract.reply(request, data: page(number));
    });
    expect(
      snapshot.sessions.map((s) => s.id),
      List.generate(21, (i) => 'session-$i'),
    );
    expect(snapshot.sessions.first.isCurrent, isTrue);
    expect(snapshot.sessions.last.canRevoke, isTrue);
    expect(snapshot.accountUsable, isFalse);
    expect(queries, [
      {'pageNum': '1', 'pageSize': '20', 'scope': 'active'},
      {'pageNum': '2', 'pageSize': '20', 'scope': 'active'},
    ]);
  });

  for (final total in [0, 20, 40, 41]) {
    test('reads exact complete pagination for total $total', () async {
      var calls = 0;
      final snapshot = await fetch((request) async {
        calls++;
        await contract.reply(request, data: page(calls, total: total));
      });
      expect(snapshot.sessions, hasLength(total));
      expect(calls, total == 0 ? 1 : (total + 19) ~/ 20);
    });
  }

  final invalidPages = <String, Map<String, Object?> Function()>{
    'duplicate across pages': () =>
        page(2)..['list'] = [(page(1)['list']! as List).first],
    'repeated first page': () => page(1),
    'wrong page': () => page(2)..['pageNum'] = 3,
    'hasMore contradiction': () => page(2)..['hasMore'] = true,
    'empty intermediate page': () => page(2, total: 41)..['list'] = [],
    'changed total': () => page(2, total: 22),
    'changed pageSize': () => page(2)..['pageSize'] = 19,
    'wrong pages': () => page(2)..['pages'] = 3,
    'missing metadata': () => page(2)..remove('pages'),
    'metadata disappears': () => <String, Object?>{
      'total': 1,
      'list': page(2)['list'],
    },
    'invalid active': () => page(2)
      ..['list'] = [
        <String, Object?>{
          ...(page(2)['list']! as List).first as Map<String, Object?>,
          'active': 'true',
        },
      ],
  };
  for (final entry in invalidPages.entries) {
    test('rejects ${entry.key} without returning partial success', () async {
      var calls = 0;
      await expectLater(
        fetch((request) async {
          calls++;
          await contract.reply(
            request,
            data: calls == 1
                ? page(
                    1,
                    total: entry.key == 'empty intermediate page' ? 41 : 21,
                  )
                : entry.value(),
          );
        }),
        protocolError,
      );
      expect(calls, 2);
    });
  }

  test(
    'second page HTTP failure propagates and a fresh call can recover',
    () async {
      var calls = 0;
      await expectLater(
        fetch((request) async {
          calls++;
          await contract.reply(
            request,
            data: page(1),
            status: calls == 2 ? 500 : 200,
            code: calls == 2 ? 500 : 200,
          );
        }),
        throwsA(isA<ApiException>().having((e) => e.httpStatus, 'status', 500)),
      );
      expect(calls, 2);
      final snapshot = await fetch((request) async {
        await contract.reply(
          request,
          data: page(int.parse(request.query['pageNum']!)),
        );
      });
      expect(snapshot.sessions, hasLength(21));
    },
  );

  for (final scenario in [
    'early end',
    'duplicate within page',
    'unbounded total',
    'legacy incomplete',
    'partial metadata',
  ]) {
    test('rejects $scenario on first page', () async {
      var calls = 0;
      await expectLater(
        fetch((request) async {
          calls++;
          final data = page(1);
          switch (scenario) {
            case 'early end':
              data['hasMore'] = false;
            case 'duplicate within page':
              final list = data['list']! as List;
              list[1] = list[0];
            case 'unbounded total':
              data.addAll(page(1, total: 2001));
            case 'legacy incomplete':
              for (final key in ['pageNum', 'pageSize', 'pages', 'hasMore']) {
                data.remove(key);
              }
            case 'partial metadata':
              data.remove('hasMore');
          }
          await contract.reply(request, data: data);
        }),
        protocolError,
      );
      expect(calls, 1);
    });
  }

  test(
    'active query rejects revoked history instead of counting it as a device',
    () async {
      final data = page(1, total: 2);
      for (final key in ['pageNum', 'pageSize', 'pages', 'hasMore']) {
        data.remove(key);
      }
      ((data['list']! as List).last as Map)['active'] = false;
      await expectLater(
        fetch((r) => contract.reply(r, data: data)),
        protocolError,
      );
    },
  );

  test(
    'current session uses family authority, not a shared device ID',
    () async {
      final data = page(1, total: 2);
      ((data['list']! as List).last as Map)['deviceId'] = 'device-0';
      final snapshot = await fetch((r) => contract.reply(r, data: data));
      expect(snapshot.sessions, hasLength(2));
      expect(snapshot.sessions.first.isCurrent, isTrue);
      expect(snapshot.sessions.first.canRevoke, isFalse);
      expect(snapshot.sessions.last.isCurrent, isFalse);
      expect(snapshot.sessions.last.canRevoke, isTrue);
    },
  );

  for (final malformed in ['missing', 'string', 'wrong device', 'duplicate']) {
    test('rejects $malformed current-session authority', () async {
      final data = page(1, total: 2);
      final first = (data['list']! as List).first as Map;
      final last = (data['list']! as List).last as Map;
      switch (malformed) {
        case 'missing':
          first.remove('current');
        case 'string':
          first['current'] = 'true';
        case 'wrong device':
          first['deviceId'] = 'another-device';
        case 'duplicate':
          last['deviceId'] = 'device-0';
          last['current'] = true;
      }
      await expectLater(
        fetch((r) => contract.reply(r, data: data)),
        protocolError,
      );
    });
  }

  test('userId mismatch fails before requesting sessions', () async {
    var calls = 0;
    await expectLater(
      fetch((r) async {
        calls++;
        await contract.reply(r, data: page(1));
      }, userId: 2),
      protocolError,
    );
    expect(calls, 0);
  });

  test('restriction total validation stays strict', () async {
    await expectLater(
      fetch(
        (r) => contract.reply(r, data: page(1, total: 0)),
        restrictionTotal: 1,
      ),
      protocolError,
    );
  });
}
