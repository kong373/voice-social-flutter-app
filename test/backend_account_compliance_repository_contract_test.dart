import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/account/compliance/data/backend_account_compliance_repository.dart';
import 'package:voice_social_app/features/account/compliance/domain/account_compliance.dart';

void main() {
  test(
    'account compliance snapshot uses the live routes and parses state',
    () async {
      final List<_RequestRecord> requests = <_RequestRecord>[];
      final HttpServer server = await _startServer((
        HttpRequest request,
        Object? body,
      ) async {
        requests.add(_RequestRecord(request, body));
        switch (request.uri.path) {
          case '/app-api/user/getPersonalData':
            return _reply(
              request,
              data: <String, Object?>{
                'id': 10001,
                'loginName': '13800138000',
                'nickName': '晚星',
                'realNameAuthStatus': 1,
                'forbiddenState': 2,
                'forbiddenReason': '设备风控复核中',
              },
            );
          case '/app-api/user/other/getMatchButtonAndYouthMode':
            return _reply(
              request,
              data: <String, Object?>{'isOpenMinorMode': 1},
            );
          case '/app-api/user/queryUserLogout':
            return _reply(
              request,
              data: <String, Object?>{
                'flat': 1,
                'msg': '可以注销',
                'phone': '13800138000',
              },
            );
          case '/app-api/appBase/getVersionInformation':
            return _reply(
              request,
              data: <String, Object?>{
                'isUpdate': 1,
                'isForceUpgrade': 1,
                'versionStr': '6.1.0',
                'upgradeLog': '修复问题',
                'upgradePackageUrl': 'https://example.test/app.apk',
              },
            );
          default:
            return _reply(
              request,
              status: 404,
              code: 404,
              message: 'not found',
            );
        }
      });
      addTearDown(() => server.close(force: true));

      final BackendAccountComplianceRepository repository =
          BackendAccountComplianceRepository(apiClient: _client(server));
      final AccountComplianceSnapshot snapshot = await repository.fetchSnapshot(
        account: 'fallback-account',
        currentVersion: 6,
        platformType: 1,
      );

      expect(snapshot.account, '13800138000');
      expect(snapshot.nickname, '晚星');
      expect(snapshot.verificationState, VerificationState.verified);
      expect(snapshot.youthModeEnabled, isTrue);
      expect(snapshot.restriction.kind, RestrictionKind.device);
      expect(snapshot.restriction.reason, '设备风控复核中');
      expect(snapshot.cancellation.allowed, isTrue);
      expect(snapshot.cancellation.mobile, '138****8000');
      expect(snapshot.versionInfo.hasUpdate, isTrue);
      expect(snapshot.versionInfo.forceUpdate, isTrue);
      expect(snapshot.versionInfo.versionName, '6.1.0');
      expect(snapshot.sessions.single.isCurrent, isTrue);

      expect(
        requests.map((_RequestRecord request) => request.path),
        containsAllInOrder(<String>[
          '/app-api/user/getPersonalData',
          '/app-api/user/other/getMatchButtonAndYouthMode',
          '/app-api/user/queryUserLogout',
          '/app-api/appBase/getVersionInformation',
        ]),
      );
      final _RequestRecord version = requests.singleWhere(
        (_RequestRecord request) =>
            request.path == '/app-api/appBase/getVersionInformation',
      );
      expect(version.method, 'POST');
      expect(version.body, <String, Object?>{
        'innerVersion': 6,
        'platformType': 1,
      });
    },
  );

  test(
    'appeal, cancellation, and youth-mode mutations preserve wire contracts',
    () async {
      final List<_RequestRecord> requests = <_RequestRecord>[];
      final HttpServer server = await _startServer((
        HttpRequest request,
        Object? body,
      ) async {
        requests.add(_RequestRecord(request, body));
        switch (request.uri.path) {
          case '/app-api/accappeal/queryAppealInfo':
            return _reply(
              request,
              data: <String, Object?>{
                'account': '13800138000',
                'nickname': '晚星',
                'reason': '风控',
                'reasonType': '1',
                'hasAppealRecord': '1',
              },
            );
          case '/app-api/accappeal/commitAppeal':
            expect(body, <String, Object?>{
              'account': '13800138000',
              'nickname': '晚星',
              'reason': '风控',
              'reasonType': '1',
              'illustrate': '本人正常使用，请复核。',
              'cutPics': <String>[],
            });
            return _reply(request, data: <String, Object?>{});
          case '/app-api/accappeal/queryAppealProcess':
            return _reply(
              request,
              data: <String, Object?>{
                'account': '13800138000',
                'nickname': '晚星',
                'process': '审核中',
                'result': '',
              },
            );
          case '/app-register-api/userAccount/v1/delete':
            expect(request.uri.queryParameters, <String, String>{
              'smsCode': '123456',
            });
            return _reply(request, data: null);
          case '/app-api/user/openYouthMode':
            expect(request.uri.queryParameters, <String, String>{
              'minorModePwd': '2468',
            });
            return _reply(request, data: null);
          default:
            return _reply(
              request,
              status: 404,
              code: 404,
              message: 'not found',
            );
        }
      });
      addTearDown(() => server.close(force: true));
      final BackendAccountComplianceRepository repository =
          BackendAccountComplianceRepository(apiClient: _client(server));

      final AppealCase queried = await repository.queryAppeal(
        account: '13800138000',
        reasonType: '1',
      );
      expect(queried.state, AppealState.pending);
      final AppealCase submitted = await repository.submitAppeal(
        account: '13800138000',
        nickname: '晚星',
        reason: '风控',
        reasonType: '1',
        explanation: '本人正常使用，请复核。',
      );
      expect(submitted.state, AppealState.pending);
      await repository.requestCancellation(smsCode: '123456');
      expect(await repository.setYouthMode(enabled: true, pin: '2468'), isTrue);

      expect(requests[0].method, 'POST');
      expect(requests[0].body, <String, Object?>{
        'account': '13800138000',
        'reasonType': '1',
      });
      expect(requests[2].path, '/app-api/accappeal/queryAppealProcess');
      expect(requests[3].method, 'DELETE');
      expect(requests[4].method, 'GET');
    },
  );

  test('account error envelopes remain authentication failures', () async {
    final HttpServer server = await _startServer(
      (HttpRequest request, Object? body) => _reply(
        request,
        status: 401,
        code: 40100,
        message: '登录已过期',
        data: null,
      ),
    );
    addTearDown(() => server.close(force: true));
    final BackendAccountComplianceRepository repository =
        BackendAccountComplianceRepository(apiClient: _client(server));

    await expectLater(
      repository.queryAppeal(account: '13800138000', reasonType: '1'),
      throwsA(
        isA<ApiException>().having(
          (ApiException error) => error.kind,
          'kind',
          ApiFailureKind.unauthorized,
        ),
      ),
    );
  });
}

class _RequestRecord {
  _RequestRecord(HttpRequest request, this.body)
    : method = request.method,
      path = request.uri.path;

  final String method;
  final String path;
  final Object? body;
}

Future<HttpServer> _startServer(
  Future<void> Function(HttpRequest request, Object? body) handler,
) async {
  final HttpServer server = await HttpServer.bind(
    InternetAddress.loopbackIPv4,
    0,
  );
  server.listen((HttpRequest request) async {
    final String raw = await utf8.decoder.bind(request).join();
    final Object? body = raw.trim().isEmpty ? null : jsonDecode(raw);
    await handler(request, body);
  });
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

ApiClient _client(HttpServer server) => ApiClient(
  baseUri: Uri.parse('http://${server.address.address}:${server.port}/'),
  clientType: 'Android',
  clientInnerVersion: '6',
  authorizationProvider: () => 'Bearer contract-test',
);
