import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/account/compliance/data/backend_account_compliance_repository.dart';
import 'package:voice_social_app/features/account/compliance/domain/account_compliance.dart';

const String _sessionId = '22222222-2222-4222-8222-222222222222';
const String _penaltyId = '33333333-3333-4333-8333-333333333333';
const String _appealId = '44444444-4444-4444-8444-444444444444';

void main() {
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
            'providerStatus': 'VENDOR_BLOCKED',
            'reviewMode': 'FIRST_PARTY_MANUAL_REVIEW',
          },
        );
      });
      addTearDown(() => server.close(force: true));

      final BackendAccountComplianceRepository repository =
          BackendAccountComplianceRepository(apiClient: _client(server));
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
          'providerStatus': 'VENDOR_BLOCKED',
          'reviewMode': 'FIRST_PARTY_MANUAL_REVIEW',
        },
      );
    });
    addTearDown(() => server.close(force: true));

    final BackendAccountComplianceRepository repository =
        BackendAccountComplianceRepository(apiClient: _client(server));
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
                'providerStatus': 'VENDOR_BLOCKED',
                'reviewMode': 'FIRST_PARTY_MANUAL_REVIEW',
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
          BackendAccountComplianceRepository(apiClient: _client(server));
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
            'providerStatus': 'VENDOR_BLOCKED',
            'reviewMode': 'FIRST_PARTY_MANUAL_REVIEW',
          },
        );
      });
      addTearDown(() => server.close(force: true));

      final BackendAccountComplianceRepository repository =
          BackendAccountComplianceRepository(apiClient: _client(server));
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
