import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/account/compliance/data/backend_account_compliance_repository.dart';
import 'package:voice_social_app/features/account/compliance/domain/account_compliance.dart';
import 'package:voice_social_app/features/account/compliance/infrastructure/native_permission_adapter.dart';

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

      expect(snapshot.permissions, hasLength(4));
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

  test(
    'repository propagates native settings failure as an ApiException',
    () async {
      final HttpServer server = await _startServer(_validSnapshotHandler);
      addTearDown(() => server.close(force: true));
      final BackendAccountComplianceRepository repository =
          BackendAccountComplianceRepository(
            apiClient: _client(server),
            nativePermissionAdapter: MethodChannelNativePermissionAdapter(
              invoker: (String method, Map<String, Object?> arguments) async =>
                  false,
            ),
          );

      await expectLater(
        repository.openPermissionSettings(),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.configuration,
          ),
        ),
      );
    },
  );

  test(
    'live snapshot reads real native states and request refreshes through adapter',
    () async {
      final HttpServer server = await _startServer(_validSnapshotHandler);
      addTearDown(() => server.close(force: true));
      final _FakeNativePermissionAdapter adapter =
          _FakeNativePermissionAdapter(<PermissionKind, PermissionState>{
            PermissionKind.microphone: PermissionState.granted,
            PermissionKind.camera: PermissionState.notDetermined,
            PermissionKind.notifications: PermissionState.denied,
            PermissionKind.photos: PermissionState.restricted,
          });
      final BackendAccountComplianceRepository repository =
          BackendAccountComplianceRepository(
            apiClient: _client(server),
            nativePermissionAdapter: adapter,
          );

      final AccountComplianceSnapshot snapshot = await repository.fetchSnapshot(
        account: 'user-1',
        currentVersion: 6,
        platformType: 1,
      );

      expect(
        snapshot.permissions.map((PermissionSetting item) => item.state),
        <PermissionState>[
          PermissionState.granted,
          PermissionState.notDetermined,
          PermissionState.denied,
          PermissionState.restricted,
        ],
      );
      expect(
        snapshot.permissions.every(
          (PermissionSetting item) => item.managedByPlatform == true,
        ),
        isTrue,
      );

      adapter.states[PermissionKind.notifications] = PermissionState.granted;
      await repository.setPermissionState(
        kind: PermissionKind.notifications,
        state: PermissionState.granted,
      );
      expect(adapter.requested, <PermissionKind>[PermissionKind.notifications]);
      expect(
        (await repository.fetchSnapshot(
          account: 'user-1',
          currentVersion: 6,
          platformType: 1,
        )).permissions[2].state,
        PermissionState.granted,
      );
    },
  );

  test(
    'live real-name parser accepts the exact first-party review tuple',
    () async {
      final Map<String, Object?> realName = <String, Object?>{
        'status': 'PENDING',
        'statusCode': 1,
        'providerStatus': 'FIRST_PARTY_REVIEW',
        'reviewStatus': 'FIRST_PARTY_REVIEW',
        'reviewMode': 'FIRST_PARTY_MANUAL_REVIEW',
        'providerInvocation': false,
      };
      final HttpServer server = await _startServer(
        (HttpRequest request) =>
            _validSnapshotHandler(request, realNamePayload: realName),
      );
      addTearDown(() => server.close(force: true));
      final BackendAccountComplianceRepository repository =
          BackendAccountComplianceRepository(apiClient: _client(server));

      expect(
        (await repository.fetchSnapshot(
          account: 'user-1',
          currentVersion: 6,
          platformType: 1,
        )).verificationState,
        VerificationState.pending,
      );

      realName
        ..['status'] = 'APPROVED'
        ..['statusCode'] = 2;
      expect(
        (await repository.fetchSnapshot(
          account: 'user-1',
          currentVersion: 6,
          platformType: 1,
        )).verificationState,
        VerificationState.verified,
      );

      realName
        ..['status'] = 'REJECTED'
        ..['statusCode'] = 3;
      expect(
        (await repository.fetchSnapshot(
          account: 'user-1',
          currentVersion: 6,
          platformType: 1,
        )).verificationState,
        VerificationState.rejected,
      );
    },
  );

  test(
    'live real-name parser rejects vendor and legacy review tuples',
    () async {
      final List<Map<String, Object?>> invalidTuples = <Map<String, Object?>>[
        <String, Object?>{
          'providerStatus': 'VENDOR_BLOCKED',
          'reviewStatus': 'FIRST_PARTY_REVIEW',
          'reviewMode': 'FIRST_PARTY_MANUAL_REVIEW',
          'providerInvocation': false,
        },
        <String, Object?>{
          'providerStatus': 'FIRST_PARTY_REVIEWED',
          'reviewStatus': 'FIRST_PARTY_REVIEWED',
          'reviewMode': 'FIRST_PARTY_REVIEW',
          'providerInvocation': false,
        },
        <String, Object?>{
          'providerStatus': 'FIRST_PARTY_REVIEW',
          'reviewStatus': 'FIRST_PARTY_REVIEW',
          'reviewMode': 'FIRST_PARTY_MANUAL_REVIEW',
          'providerInvocation': true,
        },
        <String, Object?>{
          'providerStatus': ' FIRST_PARTY_REVIEW',
          'reviewStatus': 'FIRST_PARTY_REVIEW',
          'reviewMode': 'FIRST_PARTY_MANUAL_REVIEW',
          'providerInvocation': false,
        },
      ];

      for (final Map<String, Object?> tuple in invalidTuples) {
        final Map<String, Object?> realName = <String, Object?>{
          'status': 'PENDING',
          'statusCode': 1,
          ...tuple,
        };
        final HttpServer server = await _startServer(
          (HttpRequest request) =>
              _validSnapshotHandler(request, realNamePayload: realName),
        );
        addTearDown(() => server.close(force: true));
        final BackendAccountComplianceRepository repository =
            BackendAccountComplianceRepository(apiClient: _client(server));

        await expectLater(
          repository.fetchSnapshot(
            account: 'user-1',
            currentVersion: 6,
            platformType: 1,
          ),
          throwsA(
            isA<ApiException>().having(
              (ApiException error) => error.kind,
              'kind',
              ApiFailureKind.protocol,
            ),
          ),
        );
        await server.close(force: true);
      }
    },
  );
}

class _FakeNativePermissionAdapter implements NativePermissionAdapter {
  _FakeNativePermissionAdapter(this.states);

  final Map<PermissionKind, PermissionState> states;
  final List<PermissionKind> requested = <PermissionKind>[];

  @override
  Future<PermissionState> status(PermissionKind kind) async => states[kind]!;

  @override
  Future<PermissionState> request(PermissionKind kind) async {
    requested.add(kind);
    return states[kind]!;
  }

  @override
  Future<void> openAppSettings() async {}
}

Future<void> _validSnapshotHandler(
  HttpRequest request, {
  Map<String, Object?>? realNamePayload,
}) async {
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
    '/app-mini-api/mini/v1/account/real-name' =>
      realNamePayload ??
          <String, Object?>{
            'status': 'UNVERIFIED',
            'statusCode': 0,
            'providerStatus': 'FIRST_PARTY_REVIEW',
            'reviewStatus': 'FIRST_PARTY_REVIEW',
            'reviewMode': 'FIRST_PARTY_MANUAL_REVIEW',
            'providerInvocation': false,
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
