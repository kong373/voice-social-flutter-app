import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/features/account/compliance/data/backend_account_compliance_repository.dart';
import 'package:voice_social_app/features/account/compliance/domain/account_compliance.dart';

void main() {
  test(
    'live account permissions are unavailable until a native authority is wired',
    () async {
      final HttpServer server = await _startServer(_validSnapshotHandler);
      addTearDown(() => server.close(force: true));

      final BackendAccountComplianceRepository repository =
          BackendAccountComplianceRepository(apiClient: _client(server));
      final AccountComplianceSnapshot snapshot = await repository.fetchSnapshot(
        account: 'user-1',
        currentVersion: 6,
        platformType: 1,
      );

      expect(snapshot.permissions, hasLength(3));
      expect(
        snapshot.permissions.every(
          (PermissionSetting item) => item.state == PermissionState.unavailable,
        ),
        isTrue,
      );
      expect(
        snapshot.permissions.every(
          (PermissionSetting item) => item.managedByPlatform == null,
        ),
        isTrue,
      );
    },
  );

  test('live permission mutation cannot report a successful grant', () async {
    final HttpServer server = await _startServer(_validSnapshotHandler);
    addTearDown(() => server.close(force: true));
    final BackendAccountComplianceRepository repository =
        BackendAccountComplianceRepository(apiClient: _client(server));

    await expectLater(
      repository.setPermissionState(
        kind: PermissionKind.microphone,
        state: PermissionState.granted,
      ),
      throwsA(
        isA<Exception>().having(
          (Exception error) => error.toString(),
          'message',
          contains('原生平台适配器'),
        ),
      ),
    );
  });
}

Future<void> _validSnapshotHandler(HttpRequest request) async {
  final Map<String, Object?> data = switch (request.uri.path) {
    '/app-api/user/getPersonalData' => <String, Object?>{
      'loginName': 'user-1',
      'nickName': '用户',
    },
    '/app-api/user/other/getMatchButtonAndYouthMode' => <String, Object?>{
      'isYouthMode': 0,
      'youthModeEnabled': false,
    },
    '/app-mini-api/mini/v1/account/restrictions' => <String, Object?>{
      'restricted': false,
      'accountUsable': true,
      'total': 0,
      'list': <Object?>[],
    },
    '/app-api/user/queryUserLogout' => <String, Object?>{
      'canLogout': true,
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
      'providerStatus': 'VENDOR_BLOCKED',
      'reviewMode': 'FIRST_PARTY_MANUAL_REVIEW',
    },
    '/app-mini-api/mini/v1/account/sessions' => <String, Object?>{
      'total': 0,
      'list': <Object?>[],
    },
    _ => <String, Object?>{},
  };
  await _reply(request, data: data);
}

Future<HttpServer> _startServer(
  Future<void> Function(HttpRequest request) handler,
) async {
  final HttpServer server = await HttpServer.bind(
    InternetAddress.loopbackIPv4,
    0,
  );
  server.listen((HttpRequest request) async {
    await utf8.decoder.bind(request).join();
    await handler(request);
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
