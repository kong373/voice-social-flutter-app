import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/storage/key_value_store.dart';
import 'package:voice_social_app/features/account/data/backend_auth_repository.dart';
import 'package:voice_social_app/features/account/data/auth_session_manager.dart';
import 'package:voice_social_app/features/account/domain/auth_models.dart';

void main() {
  test(
    'public mobile client completes auth lifecycle without a secret',
    () async {
      final HttpServer server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => server.close(force: true));
      AuthSession? activeSession;
      final List<Map<String, Object?>> captured = <Map<String, Object?>>[];

      server.listen((HttpRequest request) async {
        final String rawBody = await utf8.decoder.bind(request).join();
        final Object? decodedBody = rawBody.isEmpty
            ? null
            : jsonDecode(rawBody);
        captured.add(<String, Object?>{
          'method': request.method,
          'path': request.uri.path,
          'clientId': request.headers.value('Client-Id'),
          'clientSecretHeader': request.headers.value('Client-Secret'),
          'authorization': request.headers.value(
            HttpHeaders.authorizationHeader,
          ),
          'deviceId': request.headers.value('X-Device-Id'),
          'requestId': request.headers.value('X-Request-Id'),
          'developmentClientId': request.headers.value(
            'X-Development-Client-Id',
          ),
          'developmentOutboxKey': request.headers.value(
            'X-Development-Outbox-Key',
          ),
          'body': decodedBody,
        });
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(<String, Object?>{
            'code': 200,
            'message': 'OK',
            'data': _authResponseFor(request.uri.path),
          }),
        );
        await request.response.close();
      });

      final AppEnvironment environment = AppEnvironment(
        backendMode: BackendMode.live,
        apiBaseUrl: 'http://${server.address.address}:${server.port}/',
        clientType: 'Android',
        clientInnerVersion: '6',
        oauthClientId: 'voice-social-mobile-public',
        realtimeEndpoint: '',
        deploymentEnvironment: DeploymentEnvironment.development,
        allowInsecureHttp: true,
      );
      final ApiClient client = ApiClient(
        baseUri: environment.apiBaseUri!,
        clientType: environment.clientType,
        clientInnerVersion: environment.clientInnerVersion,
        authorizationProvider: () => activeSession?.authorizationHeader,
      );
      final BackendAuthRepository repository = BackendAuthRepository(
        apiClient: client,
        environment: environment,
        sessionManager: AuthSessionManager(MemoryKeyValueStore()),
      );
      const ClientDevice device = ClientDevice(
        deviceType: 1,
        deviceId: 'install-device-1',
        mobileKind: 'Android emulator',
        appMarketType: 1,
        isEmulator: 1,
        smDeviceId: 'sm-device-1',
      );

      final SmsChallenge challenge = await repository.sendSmsCode(
        phone: '13800138000',
        device: device,
      );
      expect(challenge.challengeId, 'challenge-1');
      expect(challenge.developmentCode, '123456');

      final AuthOutcome outcome = await repository.signInWithSms(
        phone: '13800138000',
        smsCode: challenge.developmentCode!,
        device: device,
      );
      activeSession = outcome.session;
      expect(activeSession?.accessToken, 'access-1');
      expect(activeSession?.refreshToken, 'refresh-1');
      expect(activeSession?.clientId, 'voice-social-mobile-public');

      final AuthSession refreshed = await repository.refreshSession(
        activeSession!,
      );
      expect(refreshed.accessToken, 'access-2');
      expect(refreshed.refreshToken, 'refresh-2');
      activeSession = refreshed;
      await repository.logout(refreshed);

      expect(captured, hasLength(4));
      expect(
        captured.map((Map<String, Object?> item) => item['clientSecretHeader']),
        everyElement(isNull),
      );
      expect(
        captured.map(
          (Map<String, Object?> item) => item['developmentOutboxKey'],
        ),
        everyElement(isNull),
      );
      expect(
        captured.map((Map<String, Object?> item) => item['requestId']),
        everyElement(
          isA<String>().having((String value) => value, 'value', isNotEmpty),
        ),
      );
      final String serialized = jsonEncode(captured);
      expect(serialized, isNot(contains('OAUTH_CLIENT_SECRET')));
      expect(serialized, isNot(contains('secret-value')));
      expect(serialized, isNot(contains('Development-Outbox')));

      final Map<String, Object?> send = captured[0];
      expect(send['clientId'], 'voice-social-mobile-public');
      expect(send['deviceId'], 'install-device-1');
      expect(send['authorization'], isNull);

      final Map<String, Object?> login = captured[1];
      expect(login['authorization'], isNull);
      final Map<String, Object?> loginBody = Map<String, Object?>.from(
        login['body']! as Map,
      );
      expect(loginBody['clientId'], 'voice-social-mobile-public');
      expect(loginBody, isNot(contains('clientSecret')));

      final Map<String, Object?> refresh = captured[2];
      expect(refresh['authorization'], isNull);
      expect(refresh['clientId'], 'voice-social-mobile-public');

      final Map<String, Object?> logout = captured[3];
      expect(logout['authorization'], 'Bearer access-2');
    },
  );

  test(
    'ambiguous SMS response is surfaced once without unsafe automatic replay',
    () async {
      final HttpServer server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => server.close(force: true));
      var attempts = 0;
      server.listen((HttpRequest request) async {
        attempts += 1;
        request.response.headers.contentType = ContentType.json;
        await request.response.close();
      });

      final AppEnvironment environment = _testEnvironment(server);
      final ApiClient client = ApiClient(
        baseUri: environment.apiBaseUri!,
        clientType: environment.clientType,
        clientInnerVersion: environment.clientInnerVersion,
        authorizationProvider: () => null,
        timeout: const Duration(milliseconds: 50),
      );
      final BackendAuthRepository repository = BackendAuthRepository(
        apiClient: client,
        environment: environment,
        sessionManager: AuthSessionManager(MemoryKeyValueStore()),
      );

      ApiException? failure;
      try {
        await repository.sendSmsCode(phone: '13800138000', device: _testDevice);
      } on ApiException catch (error) {
        failure = error;
      }

      expect(failure?.kind, ApiFailureKind.protocol);
      expect(attempts, 1);
    },
  );

  test(
    'refresh rotation reuses one request id to recover a lost response',
    () async {
      final HttpServer server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => server.close(force: true));
      final List<String> requestIds = <String>[];
      var attempts = 0;
      server.listen((HttpRequest request) async {
        if (request.uri.path !=
            '/app-register-api/userAccount/v1/refreshSession') {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          return;
        }
        requestIds.add(request.headers.value('X-Request-Id') ?? '');
        attempts += 1;
        if (attempts == 1) {
          // Simulate a committed refresh whose response was lost in transit.
          await request.response.close();
          return;
        }
        request.response
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode(<String, Object?>{
              'code': 200,
              'message': 'OK',
              'data': _token('recovered-access', 'recovered-refresh'),
            }),
          );
        await request.response.close();
      });

      final BackendAuthRepository repository = _testRepository(
        _testEnvironment(server),
      );
      final AuthSession refreshed = await repository.refreshSession(
        AuthSession(
          accessToken: 'expired-access',
          tokenType: 'Bearer',
          expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
          refreshToken: 'one-time-refresh',
          refreshExpiresAt: DateTime.now().add(const Duration(days: 1)),
          deviceId: _testDevice.deviceId,
          userId: 10001,
          mobile: '13800138000',
          roles: 'USER',
        ),
      );

      expect(refreshed.accessToken, 'recovered-access');
      expect(refreshed.refreshToken, 'recovered-refresh');
      expect(requestIds, hasLength(2));
      expect(requestIds.first, isNotEmpty);
      expect(requestIds[1], requestIds.first);
    },
  );

  test(
    'refresh 401 and 409 fail closed without replaying the old token',
    () async {
      final HttpServer server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => server.close(force: true));
      final List<int> statuses = <int>[
        HttpStatus.unauthorized,
        HttpStatus.conflict,
      ];
      final List<String> requestIds = <String>[];
      server.listen((HttpRequest request) async {
        requestIds.add(request.headers.value('X-Request-Id') ?? '');
        final int status = statuses.removeAt(0);
        request.response
          ..statusCode = status
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode(<String, Object?>{
              'code': status,
              'message': 'refresh rejected',
              'data': null,
            }),
          );
        await request.response.close();
      });
      final BackendAuthRepository repository = _testRepository(
        _testEnvironment(server),
      );

      for (final ApiFailureKind expectedKind in <ApiFailureKind>[
        ApiFailureKind.unauthorized,
        ApiFailureKind.conflict,
      ]) {
        ApiException? failure;
        try {
          await repository.refreshSession(
            AuthSession(
              accessToken: 'expired-access',
              tokenType: 'Bearer',
              expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
              refreshToken: 'one-time-refresh',
              refreshExpiresAt: DateTime.now().add(const Duration(days: 1)),
              deviceId: _testDevice.deviceId,
              userId: 10001,
              mobile: '13800138000',
              roles: 'USER',
            ),
          );
        } on ApiException catch (error) {
          failure = error;
        }
        expect(failure?.kind, expectedKind);
      }
      expect(requestIds, hasLength(2));
      expect(requestIds.every((String value) => value.isNotEmpty), isTrue);
      expect(requestIds[0], isNot(requestIds[1]));
    },
  );

  test(
    'registerWithSms sends the canonical first-party request body',
    () async {
      final HttpServer server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => server.close(force: true));
      Map<String, Object?>? capturedBody;
      String? capturedClientId;
      String? capturedAuthorization;
      server.listen((HttpRequest request) async {
        capturedClientId = request.headers.value('Client-Id');
        capturedAuthorization = request.headers.value(
          HttpHeaders.authorizationHeader,
        );
        capturedBody = Map<String, Object?>.from(
          jsonDecode(await utf8.decoder.bind(request).join()) as Map,
        );
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(<String, Object?>{
            'code': 200,
            'message': 'OK',
            'data': _token('registered-access', 'registered-refresh'),
          }),
        );
        await request.response.close();
      });

      final AppEnvironment environment = _testEnvironment(server);
      final BackendAuthRepository repository = _testRepository(environment);
      const ClientDevice device = ClientDevice(
        deviceType: 1,
        deviceId: 'install-device-1',
        mobileKind: 'Android emulator',
        appMarketType: 1,
        isEmulator: 1,
        smDeviceId: 'sm-device-1',
      );

      final AuthSession session = await repository.registerWithSms(
        phone: '13800138000',
        smsCode: '123456',
        device: device,
        profile: const RegistrationProfile(
          nickname: '新用户',
          sex: 2,
          birthday: '2000-01-02',
          inviteCode: 'INV-001',
        ),
      );

      expect(capturedClientId, 'voice-social-mobile-public');
      expect(capturedAuthorization, isNull);
      expect(capturedBody, <String, Object?>{
        'phone': '13800138000',
        'smsCode': '123456',
        'sex': 2,
        'labelIds': <int>[],
        'inviteCode': 'INV-001',
        'appInviteCode': '',
        'deviceType': 1,
        'deviceId': 'install-device-1',
        'mobileKind': 'Android emulator',
        'appMarketType': 1,
        'clientId': 'voice-social-mobile-public',
        'isEmulator': 1,
        'nickname': '新用户',
        'birthday': '2000-01-02',
        'smDeviceId': 'sm-device-1',
        'sensorsAnonymousId': 'install-device-1',
      });
      expect(session.accessToken, 'registered-access');
      expect(session.refreshToken, 'registered-refresh');
      expect(session.tokenType, 'Bearer');
      expect(session.userId, 10001);
      expect(session.mobile, '13800138000');
      expect(session.roles, 'USER');
      expect(session.deviceId, 'install-device-1');
      expect(session.clientId, 'voice-social-mobile-public');
      expect(session.boundRoomId, isNull);
      expect(session.expiresAt.isAfter(DateTime.now()), isTrue);
      expect(session.refreshExpiresAt.isAfter(DateTime.now()), isTrue);
    },
  );

  test(
    'registerWithSms rejects malformed session payloads fail closed',
    () async {
      final HttpServer server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => server.close(force: true));
      Object? responseData;
      server.listen((HttpRequest request) async {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(<String, Object?>{
            'code': 200,
            'message': 'OK',
            'data': responseData,
          }),
        );
        await request.response.close();
      });

      final BackendAuthRepository repository = _testRepository(
        _testEnvironment(server),
      );
      const ClientDevice device = _testDevice;
      final List<Object?> malformedPayloads = <Object?>[
        null,
        <String, Object?>{},
        <String, Object?>{
          'access_token': 'access-only',
          'expires_in': 3600,
          'refresh_token': 'refresh',
          'refresh_expires_in': 3600,
        },
        <String, Object?>{
          'access_token': 'access',
          'expires_in': 0,
          'refresh_token': 'refresh',
          'refresh_expires_in': 3600,
          'userId': 10001,
        },
        <String, Object?>{
          'access_token': 'access',
          'expires_in': 3600,
          'refresh_token': 'refresh',
          'refresh_expires_in': 3600,
          'userId': 0,
        },
      ];

      for (final Object? malformed in malformedPayloads) {
        responseData = malformed;
        ApiException? failure;
        try {
          await repository.registerWithSms(
            phone: '13800138000',
            smsCode: '123456',
            device: device,
            profile: const RegistrationProfile(nickname: '新用户', sex: 2),
          );
        } on ApiException catch (error) {
          failure = error;
        }
        expect(failure?.kind, ApiFailureKind.protocol);
        expect(failure?.message, '登录响应中的会话字段不完整');
      }
    },
  );

  test(
    'registerWithSms preserves first-party auth HTTP failure classes',
    () async {
      final HttpServer server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => server.close(force: true));
      var responseStatus = HttpStatus.unauthorized;
      server.listen((HttpRequest request) async {
        request.response
          ..statusCode = responseStatus
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode(<String, Object?>{
              'code': responseStatus == HttpStatus.unprocessableEntity
                  ? 42201
                  : responseStatus,
              'message': 'registration rejected',
              'data': null,
            }),
          );
        await request.response.close();
      });

      final BackendAuthRepository repository = _testRepository(
        _testEnvironment(server),
      );
      const ClientDevice device = _testDevice;
      final List<(int, ApiFailureKind)> cases = <(int, ApiFailureKind)>[
        (HttpStatus.unauthorized, ApiFailureKind.unauthorized),
        (HttpStatus.forbidden, ApiFailureKind.forbidden),
        (HttpStatus.conflict, ApiFailureKind.conflict),
        (HttpStatus.unprocessableEntity, ApiFailureKind.validation),
        (HttpStatus.internalServerError, ApiFailureKind.server),
      ];

      for (final (int status, ApiFailureKind expectedKind) in cases) {
        responseStatus = status;
        ApiException? failure;
        try {
          await repository.registerWithSms(
            phone: '13800138000',
            smsCode: '123456',
            device: device,
            profile: const RegistrationProfile(nickname: '新用户', sex: 2),
          );
        } on ApiException catch (error) {
          failure = error;
        }
        expect(failure?.kind, expectedKind);
        expect(failure?.httpStatus, status);
        expect(
          failure?.code,
          status == HttpStatus.unprocessableEntity ? 42201 : status,
        );
      }
    },
  );
}

AppEnvironment _testEnvironment(HttpServer server) => AppEnvironment(
  backendMode: BackendMode.live,
  apiBaseUrl: 'http://${server.address.address}:${server.port}/',
  clientType: 'Android',
  clientInnerVersion: '6',
  oauthClientId: 'voice-social-mobile-public',
  realtimeEndpoint: '',
  deploymentEnvironment: DeploymentEnvironment.development,
  allowInsecureHttp: true,
);

BackendAuthRepository _testRepository(AppEnvironment environment) {
  final ApiClient client = ApiClient(
    baseUri: environment.apiBaseUri!,
    clientType: environment.clientType,
    clientInnerVersion: environment.clientInnerVersion,
    authorizationProvider: () => null,
  );
  return BackendAuthRepository(
    apiClient: client,
    environment: environment,
    sessionManager: AuthSessionManager(MemoryKeyValueStore()),
  );
}

const ClientDevice _testDevice = ClientDevice(
  deviceType: 1,
  deviceId: 'install-device-1',
  mobileKind: 'Android emulator',
  appMarketType: 1,
  isEmulator: 1,
  smDeviceId: 'sm-device-1',
);

Object? _authResponseFor(String path) => switch (path) {
  '/app-register-api/util/v1/sendSmsCode' => <String, Object?>{
    'challengeId': 'challenge-1',
    'expiresIn': 300,
    'retryAfter': 60,
    'developmentCode': '123456',
  },
  '/app-register-api/userAccount/v1/loginByMobileAndSmsCode' => _token(
    'access-1',
    'refresh-1',
  ),
  '/app-register-api/userAccount/v1/refreshSession' => _token(
    'access-2',
    'refresh-2',
  ),
  '/app-register-api/userAccount/v1/logout' => null,
  _ => <String, Object?>{},
};

Map<String, Object?> _token(String accessToken, String refreshToken) =>
    <String, Object?>{
      'access_token': accessToken,
      'token_type': 'Bearer',
      'expires_in': 3600,
      'refresh_token': refreshToken,
      'refresh_expires_in': 2592000,
      'userId': 10001,
      'mobile': '13800138000',
      'roles': 'USER',
    };
