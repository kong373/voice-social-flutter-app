import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/features/account/data/backend_auth_repository.dart';
import 'package:voice_social_app/features/account/domain/auth_models.dart';

void main() {
  test('public mobile client completes auth lifecycle without a secret', () async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(() => server.close(force: true));
    AuthSession? activeSession;
    final List<Map<String, Object?>> captured = <Map<String, Object?>>[];

    server.listen((HttpRequest request) async {
      final String rawBody = await utf8.decoder.bind(request).join();
      final Object? decodedBody = rawBody.isEmpty ? null : jsonDecode(rawBody);
      captured.add(<String, Object?>{
        'method': request.method,
        'path': request.uri.path,
        'clientId': request.headers.value('Client-Id'),
        'clientSecretHeader': request.headers.value('Client-Secret'),
        'authorization': request.headers.value(HttpHeaders.authorizationHeader),
        'deviceId': request.headers.value('X-Device-Id'),
        'developmentClientId': request.headers.value('X-Development-Client-Id'),
        'developmentOutboxKey': request.headers.value('X-Development-Outbox-Key'),
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
      developmentOutboxKey: 'development-outbox-key',
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
    expect(
      await repository.readDevelopmentSmsCode(challenge.challengeId),
      '123456',
    );

    final AuthOutcome outcome = await repository.signInWithSms(
      phone: '13800138000',
      smsCode: '123456',
      device: device,
    );
    activeSession = outcome.session;
    expect(activeSession?.accessToken, 'access-1');
    expect(activeSession?.refreshToken, 'refresh-1');
    expect(activeSession?.clientId, 'voice-social-mobile-public');

    final AuthSession refreshed = await repository.refreshSession(activeSession!);
    expect(refreshed.accessToken, 'access-2');
    expect(refreshed.refreshToken, 'refresh-2');
    activeSession = refreshed;
    await repository.logout(refreshed);

    expect(captured, hasLength(5));
    expect(
      captured.map((Map<String, Object?> item) => item['clientSecretHeader']),
      everyElement(isNull),
    );
    final String serialized = jsonEncode(captured);
    expect(serialized, isNot(contains('OAUTH_CLIENT_SECRET')));
    expect(serialized, isNot(contains('secret-value')));

    final Map<String, Object?> send = captured[0];
    expect(send['clientId'], 'voice-social-mobile-public');
    expect(send['deviceId'], 'install-device-1');
    expect(send['authorization'], isNull);

    final Map<String, Object?> outbox = captured[1];
    expect(outbox['developmentClientId'], 'voice-social-mobile-public');
    expect(outbox['developmentOutboxKey'], 'development-outbox-key');
    expect(outbox['authorization'], isNull);

    final Map<String, Object?> login = captured[2];
    expect(login['authorization'], isNull);
    final Map<String, Object?> loginBody =
        Map<String, Object?>.from(login['body']! as Map);
    expect(loginBody['clientId'], 'voice-social-mobile-public');
    expect(loginBody, isNot(contains('clientSecret')));

    final Map<String, Object?> refresh = captured[3];
    expect(refresh['authorization'], isNull);
    expect(refresh['clientId'], 'voice-social-mobile-public');

    final Map<String, Object?> logout = captured[4];
    expect(logout['authorization'], 'Bearer access-2');
  });
}

Object _authResponseFor(String path) => switch (path) {
      '/app-register-api/util/v1/sendSmsCode' => <String, Object?>{
          'challengeId': 'challenge-1',
          'expiresIn': 300,
          'retryAfter': 60,
        },
      '/internal/development/sms-outbox/challenge-1' => <String, Object?>{
          'challengeId': 'challenge-1',
          'code': '123456',
        },
      '/app-register-api/userAccount/v1/loginByMobileAndSmsCode' =>
        _token('access-1', 'refresh-1'),
      '/app-register-api/userAccount/v1/refreshSession' =>
        _token('access-2', 'refresh-2'),
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
