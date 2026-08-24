import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/account/compliance/data/backend_account_compliance_repository.dart';

const String _sessionId = '22222222-2222-4222-8222-222222222222';
const String _penaltyId = '33333333-3333-4333-8333-333333333333';
const String _appealId = '44444444-4444-4444-8444-444444444444';

void main() {
  test(
    'account high-risk writes surface 403/409/422/500 without local success',
    () async {
      for (final _Operation operation in _Operation.values) {
        for (final int status in <int>[403, 409, 422, 500]) {
          final List<_Request> requests = <_Request>[];
          final HttpServer server = await _startServer((HttpRequest request) {
            return _handleOperation(
              request,
              operation: operation,
              status: status,
              requests: requests,
            );
          });
          final BackendAccountComplianceRepository repository =
              BackendAccountComplianceRepository(apiClient: _client(server));
          addTearDown(() => server.close(force: true));

          await expectLater(
            _invoke(operation, repository),
            throwsA(
              isA<ApiException>()
                  .having(
                    (ApiException error) => error.httpStatus,
                    'httpStatus',
                    status,
                  )
                  .having(
                    (ApiException error) => error.kind,
                    'kind',
                    _failureKind(status),
                  ),
            ),
          );
          expect(
            requests.where(((_Request request) => request.isMutation)),
            isNotEmpty,
            reason: '${operation.name} did not issue its mutation request',
          );
        }
      }
    },
  );

  test(
    '401 recovery replays every high-risk write with the same request id',
    () async {
      for (final _Operation operation in _Operation.values) {
        final List<_Request> requests = <_Request>[];
        int recoveryCalls = 0;
        final HttpServer server = await _startServer((HttpRequest request) {
          return _handleOperation(
            request,
            operation: operation,
            status: recoveryCalls == 0 ? 401 : 200,
            requests: requests,
          ).then<void>((_) {
            if (request.uri.path != '/app-api/accappeal/queryAppealInfo' ||
                request.method != 'GET') {
              // The first mutation response invokes the fake token refresh;
              // the second is the replay response.
              recoveryCalls++;
            }
          });
        });
        final ApiClient apiClient = _client(
          server,
          unauthorizedRecovery: () async {
            recoveryCalls++;
            return true;
          },
        );
        final BackendAccountComplianceRepository repository =
            BackendAccountComplianceRepository(apiClient: apiClient);
        addTearDown(() => server.close(force: true));

        await _invoke(operation, repository);

        final List<_Request> mutationRequests = requests
            .where(((_Request request) => request.isMutation))
            .toList();
        expect(
          mutationRequests,
          hasLength(2),
          reason: '${operation.name} did not perform exactly one replay',
        );
        expect(mutationRequests[0].requestId, isNotEmpty);
        expect(mutationRequests[0].requestId, mutationRequests[1].requestId);
      }
    },
  );
}

enum _Operation { cancellation, deviceRevoke, appeal, youthMode }

Future<void> _invoke(
  _Operation operation,
  BackendAccountComplianceRepository repository,
) async {
  switch (operation) {
    case _Operation.cancellation:
      await repository.requestCancellation(smsCode: 'ignored');
    case _Operation.deviceRevoke:
      await repository.revokeDeviceSession(_sessionId);
    case _Operation.appeal:
      await repository.submitAppeal(
        account: 'user-1',
        nickname: '晚星',
        reason: '账号安全策略命中',
        reasonType: '1',
        explanation: '本人正常使用账号，希望平台核对具体处罚证据。',
      );
    case _Operation.youthMode:
      await repository.setYouthMode(enabled: true, pin: '2468');
  }
}

Future<void> _handleOperation(
  HttpRequest request, {
  required _Operation operation,
  required int status,
  required List<_Request> requests,
}) async {
  final String rawBody = await utf8.decoder.bind(request).join();
  final _Request captured = _Request(
    request,
    body: rawBody,
    isMutation: request.uri.path != '/app-api/accappeal/queryAppealInfo',
  );
  requests.add(captured);
  if (request.uri.path == '/app-api/accappeal/queryAppealInfo') {
    await _reply(
      request,
      data: <String, Object?>{
        'penalty': <String, Object?>{
          'penaltyId': _penaltyId,
          'type': 'ACCOUNT_BAN',
          'reason': '账号安全策略命中',
        },
        'appeal': <String, Object?>{},
      },
    );
    return;
  }
  if (status != 200) {
    await _reply(
      request,
      status: status,
      code: status,
      message: 'HTTP $status',
    );
    return;
  }
  final Object data = switch (operation) {
    _Operation.cancellation => _coolingOffData,
    _Operation.deviceRevoke => <String, Object?>{
      'sessionId': _sessionId,
      'status': 'REVOKED',
      'revoked': true,
    },
    _Operation.appeal => <String, Object?>{
      'appealId': _appealId,
      'penaltyId': _penaltyId,
      'reason': '账号安全策略命中',
      'status': 'SUBMITTED',
    },
    _Operation.youthMode => <String, Object?>{
      'isYouthMode': 1,
      'youthModeEnabled': true,
    },
  };
  await _reply(request, data: data);
}

ApiFailureKind _failureKind(int status) => switch (status) {
  403 => ApiFailureKind.forbidden,
  409 => ApiFailureKind.conflict,
  422 => ApiFailureKind.validation,
  _ => ApiFailureKind.server,
};

Map<String, Object?> get _coolingOffData => <String, Object?>{
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

class _Request {
  _Request(HttpRequest request, {required this.body, required this.isMutation})
    : method = request.method,
      path = request.uri.path,
      requestId = request.headers.value('X-Request-Id') ?? '';

  final String method;
  final String path;
  final String body;
  final String requestId;
  final bool isMutation;
}

Future<HttpServer> _startServer(
  Future<void> Function(HttpRequest request) handler,
) async {
  final HttpServer server = await HttpServer.bind(
    InternetAddress.loopbackIPv4,
    0,
  );
  server.listen((HttpRequest request) async => handler(request));
  return server;
}

Future<void> _reply(
  HttpRequest request, {
  int status = 200,
  int code = 200,
  String message = 'OK',
  Object? data,
}) async {
  request.response
    ..statusCode = status
    ..headers.contentType = ContentType.json
    ..write(
      jsonEncode(<String, Object?>{
        'code': code,
        'message': message,
        'data': data,
      }),
    );
  await request.response.close();
}

ApiClient _client(
  HttpServer server, {
  UnauthorizedRecovery? unauthorizedRecovery,
}) => ApiClient(
  baseUri: Uri.parse('http://${server.address.address}:${server.port}/'),
  clientType: 'Android',
  clientInnerVersion: '6',
  authorizationProvider: () => 'Bearer contract-test',
  unauthorizedRecovery: unauthorizedRecovery,
);
