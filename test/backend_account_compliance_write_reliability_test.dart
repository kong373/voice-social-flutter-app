import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/account/compliance/data/backend_account_compliance_repository.dart';
import 'package:voice_social_app/features/account/compliance/domain/account_compliance.dart';

import 'support/media_http_fakes.dart';

const String _sessionId = '22222222-2222-4222-8222-222222222222';
const String _penaltyId = '33333333-3333-4333-8333-333333333333';
const String _appealId = '44444444-4444-4444-8444-444444444444';
const _legacyRealNameReceipt = <String, Object?>{
  'status': 'PENDING',
  'statusCode': 1,
  'providerStatus': 'FIRST_PARTY_REVIEW',
  'reviewStatus': 'FIRST_PARTY_REVIEW',
  'reviewMode': 'FIRST_PARTY_MANUAL_REVIEW',
  'providerInvocation': false,
};
const _currentRealName = <String, Object?>{
  'status': 'VERIFIED',
  'statusCode': 2,
  'needsAgeResubmission': true,
  'canSubmit': true,
  'providerStatus': 'FIRST_PARTY_REVIEW',
  'reviewStatus': 'FIRST_PARTY_REVIEW',
  'reviewMode': 'FIRST_PARTY_MANUAL_REVIEW',
  'providerInvocation': false,
};

void main() {
  for (final status in ['REJECTED', 'VERIFIED']) {
    test(
      'legacy PENDING receipt restores through strict current $status GET',
      () async {
        final requests = <RequestRecord>[];
        final server = await _startServer((request) async {
          requests.add(request);
          expect(request.path, '/app-mini-api/mini/v1/account/real-name');
          if (requests.length == 1) {
            await _reply(request, status: 500, code: 500);
          } else if (request.method == 'POST') {
            await _reply(request, data: _legacyRealNameReceipt);
          } else {
            expect(request.method, 'GET');
            await _reply(
              request,
              data: <String, Object?>{
                ..._legacyRealNameReceipt,
                'status': status,
                'statusCode': status == 'REJECTED' ? 3 : 2,
                'needsAgeResubmission': status == 'VERIFIED',
                'canSubmit': true,
              },
            );
          }
        });
        addTearDown(() => server.close(force: true));
        final repository = BackendAccountComplianceRepository(
          apiClient: _client(server),
          currentUserIdProvider: () => 10001,
          identityGeneration: () => 1,
        );
        await expectLater(
          repository.submitRealName(
            realName: '测试用户',
            idNumber: '110105491231002',
          ),
          throwsA(isA<ApiException>()),
        );
        await repository.submitRealName(
          realName: '测试用户',
          idNumber: '110105491231002',
        );
        expect(requests.map((request) => request.method), [
          'POST',
          'POST',
          'GET',
        ]);
        expect(requests[1].requestId, requests[0].requestId);
        expect(requests[0].requestId, isNotEmpty);
        expect(requests[1].body, requests[0].body);
        expect(requests.last.body, isEmpty);
        // The shared transport gives GET its own trace ID, not the write key.
        expect(requests.last.requestId, isNot(requests.first.requestId));
        expect(
          requests.last.httpRequest.headers.value('Authorization'),
          'Bearer contract-test',
        );
      },
    );
  }

  for (final invalid in <String, Map<String, Object?>>{
    'one missing flag': {'needsAgeResubmission': false},
    'both null flags': {'needsAgeResubmission': null, 'canSubmit': null},
    'inconsistent flags': {'needsAgeResubmission': false, 'canSubmit': true},
    'string flag': {'needsAgeResubmission': false, 'canSubmit': 'false'},
    'legacy verified': {'status': 'VERIFIED', 'statusCode': 2},
    'noncanonical status': {'status': 'pending'},
    'invoked provider': {'providerInvocation': true},
    'noninteger code': {'statusCode': 1.0},
  }.entries) {
    test(
      'legacy receipt rejects ${invalid.key} without a current read',
      () async {
        final requests = <RequestRecord>[];
        final server = await _startServer((request) async {
          requests.add(request);
          await _reply(
            request,
            data: {..._legacyRealNameReceipt, ...invalid.value},
          );
        });
        addTearDown(() => server.close(force: true));
        final repository = BackendAccountComplianceRepository(
          apiClient: _client(server),
          currentUserIdProvider: () => 10001,
          identityGeneration: () => 1,
        );
        for (var attempt = 0; attempt < 2; attempt++) {
          await expectLater(
            repository.submitRealName(
              realName: '测试用户',
              idNumber: '110105491231002',
            ),
            throwsA(
              isA<ApiException>().having(
                (e) => e.kind,
                'kind',
                ApiFailureKind.protocol,
              ),
            ),
          );
        }
        expect(requests.map((r) => r.method), ['POST', 'POST']);
        expect(requests.last.requestId, requests.first.requestId);
        expect(requests.last.body, requests.first.body);
      },
    );
  }

  for (final failure in [
    'missing flags',
    'inconsistent flags',
    'provider',
    '401',
    '500',
  ]) {
    test(
      'legacy receipt $failure GET retains command and retries only the read',
      () async {
        final requests = <RequestRecord>[];
        final server = await _startServer((request) async {
          requests.add(request);
          if (request.method == 'POST') {
            await _reply(request, data: _legacyRealNameReceipt);
          } else if (requests.length == 2) {
            final status = int.tryParse(failure);
            await _reply(
              request,
              status: status ?? 200,
              code: status ?? 200,
              data: switch (failure) {
                'missing flags' => _legacyRealNameReceipt,
                'inconsistent flags' => {
                  ..._currentRealName,
                  'canSubmit': false,
                },
                'provider' => {..._currentRealName, 'providerInvocation': true},
                _ => null,
              },
            );
          } else {
            await _reply(request, data: _currentRealName);
          }
        });
        addTearDown(() => server.close(force: true));
        final repository = BackendAccountComplianceRepository(
          apiClient: _client(server),
          currentUserIdProvider: () => 10001,
          identityGeneration: () => 1,
        );
        await expectLater(
          repository.submitRealName(
            realName: '测试用户',
            idNumber: '110105491231002',
          ),
          throwsA(
            isA<ApiException>().having((e) => e.kind, 'kind', switch (failure) {
              '401' => ApiFailureKind.unauthorized,
              '500' => ApiFailureKind.server,
              _ => ApiFailureKind.protocol,
            }),
          ),
        );
        await repository.submitRealName(
          realName: '测试用户',
          idNumber: '110105491231002',
        );
        expect(requests.map((r) => r.method), ['POST', 'GET', 'GET']);
        expect(
          requests.where((r) => r.method == 'POST').single.requestId,
          isNotEmpty,
        );
        expect(requests.skip(1).every((r) => r.body.isEmpty), isTrue);
      },
    );
  }

  for (final aba in [false, true]) {
    test(
      'legacy read delayed open ${aba ? 'ABA' : 'A to B'} never sends old identity',
      () async {
        final actor = TestMediaIdentity();
        addTearDown(actor.dispose);
        final reached = Completer<void>(), release = Completer<void>();
        final http = MediaFakeHttp(
          (request) => MediaFakeResponse.json(
            request.method == 'POST'
                ? _legacyRealNameReceipt
                : _currentRealName,
          ),
        );
        http.beforeOpen = (count) async {
          if (count == 2) {
            reached.complete();
            await release.future;
          }
        };
        final repository = BackendAccountComplianceRepository(
          apiClient: http.api(actor),
          currentUserIdProvider: () => actor.user,
          identityGeneration: () => actor.generation,
        );
        final operation = expectLater(
          repository.submitRealName(
            realName: '测试用户',
            idNumber: '110105491231002',
          ),
          throwsA(
            isA<ApiException>().having(
              (e) => e.kind,
              'kind',
              ApiFailureKind.unauthorized,
            ),
          ),
        );
        await reached.future.timeout(const Duration(seconds: 5));
        actor.change(2);
        if (aba) actor.change(1);
        release.complete();
        await operation;
        expect(http.requests.map((r) => r.method), ['POST', 'GET']);
        expect(http.requests.last.aborted, isTrue);
        expect(http.requests.last.closes, 0);
        expect(http.requests.last.body, isEmpty);
        expect(http.requests.last.headers.value('Authorization'), isNull);
        expect(
          http.requests.first.headers.value('Authorization'),
          'Bearer contract-A-old',
        );
      },
    );
  }

  for (final aba in [false, true]) {
    test(
      'legacy read 401 ${aba ? 'ABA forbids replay' : 'same identity refreshes only GET'}',
      () async {
        final actor = TestMediaIdentity();
        addTearDown(actor.dispose);
        var gets = 0;
        final http = MediaFakeHttp((request) {
          if (request.method == 'POST')
            return MediaFakeResponse.json(_legacyRealNameReceipt);
          if (++gets == 1)
            return MediaFakeResponse.json(null, status: 401, code: 401);
          return MediaFakeResponse.json(_currentRealName);
        });
        final repository = BackendAccountComplianceRepository(
          apiClient: http.api(
            actor,
            refresh: () async {
              if (aba) {
                actor.change(2);
                actor.change(1);
              } else {
                actor.refreshToken();
              }
              return true;
            },
          ),
          currentUserIdProvider: () => actor.user,
          identityGeneration: () => actor.generation,
        );
        final operation = repository.submitRealName(
          realName: '测试用户',
          idNumber: '110105491231002',
        );
        if (aba) {
          await expectLater(
            operation,
            throwsA(
              isA<ApiException>().having(
                (e) => e.kind,
                'kind',
                ApiFailureKind.unauthorized,
              ),
            ),
          );
          expect(http.requests.map((r) => r.method), ['POST', 'GET']);
        } else {
          await operation;
          expect(http.requests.map((r) => r.method), ['POST', 'GET', 'GET']);
          expect(
            http.requests.last.headers.value('Authorization'),
            actor.token,
          );
          expect(
            http.requests.last.headers.value('X-Request-Id'),
            http.requests[1].headers.value('X-Request-Id'),
          );
        }
      },
    );
  }

  for (final fails in [false, true]) {
    test(
      'legacy read late ${fails ? 'failure' : 'success'} after ABA is obsolete',
      () async {
        final actor = TestMediaIdentity();
        addTearDown(actor.dispose);
        final reached = Completer<void>(),
            reply = Completer<HttpClientResponse>();
        final http = MediaFakeHttp((request) {
          if (request.method == 'POST')
            return MediaFakeResponse.json(_legacyRealNameReceipt);
          reached.complete();
          return reply.future;
        });
        final repository = BackendAccountComplianceRepository(
          apiClient: http.api(actor),
          currentUserIdProvider: () => actor.user,
          identityGeneration: () => actor.generation,
        );
        final operation = expectLater(
          repository.submitRealName(
            realName: '测试用户',
            idNumber: '110105491231002',
          ),
          throwsA(
            isA<ApiException>().having(
              (e) => e.kind,
              'kind',
              ApiFailureKind.unauthorized,
            ),
          ),
        );
        await reached.future.timeout(const Duration(seconds: 5));
        actor.change(2);
        actor.change(1);
        if (fails) {
          reply.completeError(const SocketException('obsolete response'));
        } else {
          reply.complete(MediaFakeResponse.json(_currentRealName));
        }
        await operation;
        expect(http.requests.map((r) => r.method), ['POST', 'GET']);
      },
    );
  }

  test(
    'ambiguous retry reuses one request id for real-name submission',
    () async {
      final List<String> requestIds = <String>[];
      int attempts = 0;
      final HttpServer server = await _startServer((
        RequestRecord request,
      ) async {
        expect(request.path, '/app-mini-api/mini/v1/account/real-name');
        expect(request.method, 'POST');
        expect(jsonDecode(request.body), <String, Object?>{
          'legalName': '张三',
          'identityNumber': '42010619960820123X',
        });
        requestIds.add(request.requestId);
        attempts++;
        if (attempts == 1) {
          await _reply(request, status: 500, code: 500, message: 'temporary');
          return;
        }
        await _reply(
          request,
          data: <String, Object?>{
            'status': 'PENDING',
            'statusCode': 1,
            'needsAgeResubmission': false,
            'canSubmit': false,
            'providerStatus': 'FIRST_PARTY_REVIEW',
            'reviewStatus': 'FIRST_PARTY_REVIEW',
            'reviewMode': 'FIRST_PARTY_MANUAL_REVIEW',
            'providerInvocation': false,
          },
        );
      });
      addTearDown(() => server.close(force: true));

      final BackendAccountComplianceRepository repository =
          BackendAccountComplianceRepository(
            apiClient: _client(server),
            supportsRealNameSubmission: true,
            currentUserIdProvider: () => 10001,
            identityGeneration: () => 1,
          );
      await expectLater(
        repository.submitRealName(
          realName: '张三',
          idNumber: '42010619960820123X',
        ),
        throwsA(isA<ApiException>()),
      );
      await repository.submitRealName(
        realName: ' 张三 ',
        idNumber: '420106 19960820123x',
      );

      expect(attempts, 2);
      expect(requestIds.first, isNotEmpty);
      expect(requestIds.first, requestIds.last);
      expect(requestIds.first.length, lessThanOrEqualTo(80));
    },
  );

  test('concurrent identical account mutation is single-flight', () async {
    final Completer<void> release = Completer<void>();
    final Completer<void> requestStarted = Completer<void>();
    int requests = 0;
    final HttpServer server = await _startServer((RequestRecord request) async {
      expect(request.path, '/app-mini-api/mini/v1/account/real-name');
      requests++;
      requestStarted.complete();
      await release.future;
      await _reply(
        request,
        data: <String, Object?>{
          'status': 'PENDING',
          'statusCode': 1,
          'needsAgeResubmission': false,
          'canSubmit': false,
          'providerStatus': 'FIRST_PARTY_REVIEW',
          'reviewStatus': 'FIRST_PARTY_REVIEW',
          'reviewMode': 'FIRST_PARTY_MANUAL_REVIEW',
          'providerInvocation': false,
        },
      );
    });
    addTearDown(() => server.close(force: true));

    final BackendAccountComplianceRepository repository =
        BackendAccountComplianceRepository(
          apiClient: _client(server),
          supportsRealNameSubmission: true,
          currentUserIdProvider: () => 10001,
          identityGeneration: () => 1,
        );
    final Future<void> first = repository.submitRealName(
      realName: '张三',
      idNumber: '42010619960820123X',
    );
    final Future<void> second = repository.submitRealName(
      realName: ' 张三 ',
      idNumber: '420106 19960820123X',
    );
    expect(identical(first, second), isTrue);
    await requestStarted.future;
    expect(requests, 1);
    release.complete();
    await Future.wait(<Future<void>>[first, second]);
  });

  test(
    'independent account mutations receive independent request ids',
    () async {
      final List<RequestRecord> requests = <RequestRecord>[];
      final HttpServer server = await _startServer((
        RequestRecord request,
      ) async {
        requests.add(request);
        switch (request.path) {
          case '/app-mini-api/mini/v1/account/real-name':
            await _reply(
              request,
              data: <String, Object?>{
                'status': 'PENDING',
                'statusCode': 1,
                'needsAgeResubmission': false,
                'canSubmit': false,
                'providerStatus': 'FIRST_PARTY_REVIEW',
                'reviewStatus': 'FIRST_PARTY_REVIEW',
                'reviewMode': 'FIRST_PARTY_MANUAL_REVIEW',
                'providerInvocation': false,
              },
            );
          case '/app-mini-api/mini/v1/account/sessions/$_sessionId':
            await _reply(
              request,
              data: <String, Object?>{
                'sessionId': _sessionId,
                'status': 'REVOKED',
                'revoked': true,
              },
            );
          case '/app-register-api/userAccount/v1/delete':
            await _reply(request, data: _coolingOffData());
          case '/app-api/user/openYouthMode':
            await _reply(
              request,
              data: <String, Object?>{
                'isYouthMode': 1,
                'youthModeEnabled': true,
              },
            );
          case '/app-api/user/turnOffYouthMode':
            await _reply(
              request,
              data: <String, Object?>{
                'isYouthMode': 0,
                'youthModeEnabled': false,
              },
            );
          default:
            await _reply(request, status: 404, code: 404, message: 'not found');
        }
      });
      addTearDown(() => server.close(force: true));

      final BackendAccountComplianceRepository repository =
          BackendAccountComplianceRepository(
            apiClient: _client(server),
            supportsRealNameSubmission: true,
            currentUserIdProvider: () => 10001,
            identityGeneration: () => 1,
          );
      await repository.submitRealName(
        realName: '张三',
        idNumber: '42010619960820123X',
      );
      await repository.revokeDeviceSession(_sessionId);
      await repository.requestCancellation(smsCode: 'ignored');
      expect(await repository.setYouthMode(enabled: true, pin: '2468'), isTrue);
      expect(
        await repository.setYouthMode(enabled: false, pin: '2468'),
        isFalse,
      );

      final List<String> ids = requests
          .map((RequestRecord item) => item.requestId)
          .toList();
      expect(requests, hasLength(5));
      expect(ids.every((String id) => id.isNotEmpty), isTrue);
      expect(ids.toSet(), hasLength(ids.length));
    },
  );

  test(
    'malformed 2xx response fails closed and retains its request id',
    () async {
      final List<String> requestIds = <String>[];
      final HttpServer server = await _startServer((
        RequestRecord request,
      ) async {
        requestIds.add(request.requestId);
        await _reply(
          request,
          data: <String, Object?>{
            'status': 'PENDING',
            // statusCode is intentionally absent: the response must not be
            // treated as a successful real-name transition.
            'needsAgeResubmission': false,
            'canSubmit': false,
            'providerStatus': 'FIRST_PARTY_REVIEW',
            'reviewStatus': 'FIRST_PARTY_REVIEW',
            'reviewMode': 'FIRST_PARTY_MANUAL_REVIEW',
            'providerInvocation': false,
          },
        );
      });
      addTearDown(() => server.close(force: true));

      final BackendAccountComplianceRepository repository =
          BackendAccountComplianceRepository(
            apiClient: _client(server),
            supportsRealNameSubmission: true,
            currentUserIdProvider: () => 10001,
            identityGeneration: () => 1,
          );
      for (int attempt = 0; attempt < 2; attempt++) {
        await expectLater(
          repository.submitRealName(
            realName: '李四',
            idNumber: '42010619960820123X',
          ),
          throwsA(
            isA<ApiException>().having(
              (ApiException error) => error.kind,
              'kind',
              ApiFailureKind.protocol,
            ),
          ),
        );
      }
      expect(requestIds, hasLength(2));
      expect(requestIds.first, requestIds.last);
    },
  );

  test(
    'appeal retry preserves request id across a preflight and POST failure',
    () async {
      final List<String> requestIds = <String>[];
      int postAttempts = 0;
      final HttpServer server = await _startServer((
        RequestRecord request,
      ) async {
        if (request.path == '/app-api/accappeal/queryAppealInfo') {
          await _reply(
            request,
            data: <String, Object?>{
              'penalty': <String, Object?>{
                'penaltyId': _penaltyId,
                'type': 'ACCOUNT_BAN',
                'reason': '测试处罚',
              },
              'appeal': <String, Object?>{},
            },
          );
          return;
        }
        expect(request.path, '/app-api/accappeal/commitAppeal');
        requestIds.add(request.requestId);
        postAttempts++;
        if (postAttempts == 1) {
          await _reply(request, status: 500, code: 500, message: 'temporary');
          return;
        }
        await _reply(
          request,
          data: <String, Object?>{
            'appealId': _appealId,
            'penaltyId': _penaltyId,
            'reason': '处罚信息需要复核',
            'status': 'SUBMITTED',
          },
        );
      });
      addTearDown(() => server.close(force: true));

      final BackendAccountComplianceRepository repository =
          BackendAccountComplianceRepository(apiClient: _client(server));
      Future<AppealCase> submit() => repository.submitAppeal(
        account: 'user-1',
        nickname: '晚星',
        reason: '处罚信息需要复核',
        reasonType: '1',
        explanation: '本人正常使用，请复核。',
      );
      await expectLater(submit(), throwsA(isA<ApiException>()));
      expect((await submit()).state, AppealState.pending);
      expect(requestIds, hasLength(2));
      expect(requestIds.first, requestIds.last);
    },
  );
}

Map<String, Object?> _coolingOffData() => <String, Object?>{
  'eligible': false,
  'status': 'COOLING_OFF',
  'canLogout': false,
  'canCancel': true,
  'requiresConfirmation': true,
  'immediateDeletion': false,
  'latestRequest': <String, Object?>{
    'status': 'COOLING_OFF',
    'coolingEndsAt': '2026-08-29T08:00:00Z',
  },
};

class RequestRecord {
  RequestRecord(HttpRequest request, this.body)
    : httpRequest = request,
      method = request.method,
      path = request.uri.path,
      requestId = request.headers.value('X-Request-Id') ?? '';

  final HttpRequest httpRequest;
  final String body;
  final String method;
  final String path;
  final String requestId;
}

Future<HttpServer> _startServer(
  Future<void> Function(RequestRecord request) handler,
) async {
  final HttpServer server = await HttpServer.bind(
    InternetAddress.loopbackIPv4,
    0,
  );
  server.listen((HttpRequest request) async {
    final String raw = await utf8.decoder.bind(request).join();
    await handler(RequestRecord(request, raw));
  });
  return server;
}

Future<void> _reply(
  RequestRecord request, {
  int status = 200,
  int code = 200,
  String message = 'OK',
  Object? data,
}) async {
  request.httpRequest.response
    ..statusCode = status
    ..headers.contentType = ContentType.json
    ..write(
      jsonEncode(<String, Object?>{
        'code': code,
        'message': message,
        'data': data,
      }),
    );
  await request.httpRequest.response.close();
}

ApiClient _client(HttpServer server) => ApiClient(
  baseUri: Uri.parse('http://${server.address.address}:${server.port}/'),
  clientType: 'Android',
  clientInnerVersion: '6',
  authorizationProvider: () => 'Bearer contract-test',
);
