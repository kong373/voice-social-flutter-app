import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/room/data/backend_rtc_token_repository.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';

void main() {
  final DateTime now = DateTime.utc(2030, 1, 1, 12);

  test('parses the standard envelope payload and redacts token material', () {
    final RtcCredentials credentials = RtcCredentialsParser.fromBackendData(
      <String, Object?>{
        'provider': 'AGORA',
        'appId': 'public-app-id',
        'channelId': 'room-42',
        'token': 'ephemeral-token',
        'uid': '10042',
        'role': 'broadcaster',
        'expiresAt': '2030-01-01T13:00:00Z',
        'ttlSeconds': 3600,
        // Unknown provider-only values are ignored by the allow-list parser.
        'opaqueProviderValue': 'must-not-be-retained',
      },
      now: now,
    );

    expect(credentials.solution, RtcSolution.agora);
    expect(credentials.provider, 'agora');
    expect(credentials.appId, 'public-app-id');
    expect(credentials.channelId, 'room-42');
    expect(credentials.uid, 10042);
    expect(credentials.userId, 10042);
    expect(credentials.role, 'broadcaster');
    expect(credentials.expiresAt, DateTime.utc(2030, 1, 1, 13));
    expect(credentials.ttlSeconds, 3600);
    expect(credentials.toRedactedJson(), isNot(contains('token')));
    expect(
      credentials.toRedactedJson(),
      isNot(contains('opaqueProviderValue')),
    );

    final RtcCredentials enveloped = RtcCredentialsParser.fromBackendData(
      <String, Object?>{
        'code': 200,
        'message': 'ok',
        'data': <String, Object?>{
          'provider': 'agora',
          'appId': 'public-app-id',
          'channelId': 'room-42',
          'token': 'ephemeral-token',
          'uid': 10042,
          'role': 'broadcaster',
          'expiresAt': '2030-01-01T13:00:00Z',
        },
      },
      now: now,
    );
    expect(enveloped.uid, 10042);
  });

  test('accepts channelName and derives expiresAt from ttlSeconds', () {
    final RtcCredentials credentials =
        RtcCredentialsParser.fromBackendData(<String, Object?>{
          'provider': 'agora',
          'appId': 'public-app-id',
          'channelName': 'legacy-channel',
          'token': 'ephemeral-token',
          'uid': 7,
          'role': 'audience',
          'ttlSeconds': 120,
        }, now: now);

    expect(credentials.channelId, 'legacy-channel');
    expect(credentials.expiresAt, now.add(const Duration(seconds: 120)));
    expect(credentials.ttl, const Duration(seconds: 120));
  });

  test('rejects missing credential fields and expired credentials', () {
    final Map<String, Object?> complete = <String, Object?>{
      'provider': 'agora',
      'appId': 'public-app-id',
      'channelId': 'room-42',
      'token': 'ephemeral-token',
      'uid': 42,
      'role': 'audience',
      'ttlSeconds': 300,
    };
    for (final String field in <String>[
      'provider',
      'appId',
      'channelId',
      'token',
      'uid',
      'role',
      'ttlSeconds',
    ]) {
      final Map<String, Object?> malformed = Map<String, Object?>.of(complete)
        ..remove(field);
      expect(
        () => RtcCredentialsParser.fromBackendData(malformed, now: now),
        throwsA(isA<ApiException>()),
        reason: 'missing $field must fail closed',
      );
    }
    expect(
      () => RtcCredentialsParser.fromBackendData(<String, Object?>{
        ...complete,
        'expiresAt': '2030-01-01T11:59:59Z',
        'ttlSeconds': null,
      }, now: now),
      throwsA(
        isA<ApiException>().having(
          (ApiException error) => error.kind,
          'kind',
          ApiFailureKind.protocol,
        ),
      ),
    );
  });

  test('rejects a non-Agora provider', () {
    expect(
      () => RtcCredentialsParser.fromBackendData(<String, Object?>{
        'provider': 'zego',
        'appId': 'public-app-id',
        'channelId': 'room-42',
        'token': 'ephemeral-token',
        'uid': 42,
        'role': 'audience',
        'ttlSeconds': 300,
      }, now: now),
      throwsA(
        isA<ApiException>().having(
          (ApiException error) => error.kind,
          'kind',
          ApiFailureKind.protocol,
        ),
      ),
    );
  });

  test('rejects conflicting credential aliases and unknown roles', () {
    final Map<String, Object?> base = <String, Object?>{
      'provider': 'agora',
      'appId': 'public-app-id',
      'channelId': 'room-42',
      'token': 'ephemeral-token',
      'uid': 42,
      'role': 'audience',
      'ttlSeconds': 300,
    };
    expect(
      () => RtcCredentialsParser.fromBackendData(<String, Object?>{
        ...base,
        'channelName': 'other-room',
      }, now: now),
      throwsA(isA<ApiException>()),
    );
    expect(
      () => RtcCredentialsParser.fromBackendData(<String, Object?>{
        ...base,
        'userId': 43,
      }, now: now),
      throwsA(isA<ApiException>()),
    );
    expect(
      () => RtcCredentialsParser.fromBackendData(<String, Object?>{
        ...base,
        'role': 'administrator',
      }, now: now),
      throwsA(isA<ApiException>()),
    );
    expect(
      () => RtcCredentialsParser.roomIdFromBackendData(<String, Object?>{
        ...base,
        'roomId': 'room-42',
        'roomIdStr': 'other-room',
      }),
      throwsA(isA<ApiException>()),
    );
  });

  test('uses the positive signed Java uid boundary', () {
    final Map<String, Object?> base = <String, Object?>{
      'provider': 'agora',
      'appId': 'public-app-id',
      'channelId': 'room-42',
      'token': 'ephemeral-token',
      'role': 'audience',
      'ttlSeconds': 300,
    };
    expect(
      RtcCredentialsParser.fromBackendData(<String, Object?>{
        ...base,
        'uid': rtcUidMax,
      }, now: now).uid,
      rtcUidMax,
    );
    expect(
      () => RtcCredentialsParser.fromBackendData(<String, Object?>{
        ...base,
        'uid': rtcUidMax + 1,
      }, now: now),
      throwsA(isA<ApiException>()),
    );
  });

  test('buildRtcToken uses authenticated GET, query, and request id', () async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(() => server.close(force: true));
    final List<HttpRequest> requests = <HttpRequest>[];
    server.listen((HttpRequest request) async {
      requests.add(request);
      request.response
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode(<String, Object?>{
            'code': 200,
            'message': 'ok',
            'data': <String, Object?>{
              'provider': 'agora',
              'appId': 'public-app-id',
              'channelId': 'room-42',
              'token': 'ephemeral-token',
              'uid': 42,
              'role': 'audience',
              'expiresAt': '2030-01-01T13:00:00Z',
              'ttlSeconds': 3600,
            },
          }),
        );
      await request.response.close();
    });
    final ApiClient client = ApiClient(
      baseUri: Uri.parse('http://127.0.0.1:${server.port}/'),
      clientType: 'Android',
      clientInnerVersion: '6',
      authorizationProvider: () => 'Bearer first-party-test',
    );
    final BackendRtcTokenRepository repository = BackendRtcTokenRepository(
      apiClient: client,
      now: () => now,
    );

    final RtcCredentials credentials = await repository.buildRtcToken(
      roomId: ' room-42 ',
      currentUserId: 42,
      requestId: 'rtc-request-1',
    );

    expect(credentials.channelId, 'room-42');
    expect(requests, hasLength(1));
    expect(requests.single.method, 'GET');
    expect(
      requests.single.uri.path,
      '/app-room-api/room/com/v1/buildAgoraToken',
    );
    expect(requests.single.uri.queryParameters, <String, String>{
      'roomId': 'room-42',
    });
    expect(
      requests.single.headers.value('Authorization'),
      'Bearer first-party-test',
    );
    expect(requests.single.headers.value('X-Request-Id'), 'rtc-request-1');

    await repository.buildRtcToken(roomId: 'room-42', currentUserId: 42);
    expect(requests, hasLength(2));
    expect(requests[1].headers.value('X-Request-Id'), isNotEmpty);
  });

  test('repository rejects a token for another user or room', () async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(() => server.close(force: true));
    bool wrongUser = true;
    server.listen((HttpRequest request) async {
      request.response
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode(<String, Object?>{
            'code': 200,
            'message': 'ok',
            'data': <String, Object?>{
              'provider': 'agora',
              'appId': 'public-app-id',
              'channelId': 'room-42',
              'roomId': wrongUser ? 'room-42' : 'room-other',
              'token': 'ephemeral-token',
              'uid': wrongUser ? 43 : 42,
              'role': 'audience',
              'ttlSeconds': 300,
            },
          }),
        );
      await request.response.close();
    });
    final ApiClient client = ApiClient(
      baseUri: Uri.parse('http://127.0.0.1:${server.port}/'),
      clientType: 'Android',
      clientInnerVersion: '6',
      authorizationProvider: () => 'Bearer first-party-test',
    );
    final BackendRtcTokenRepository repository = BackendRtcTokenRepository(
      apiClient: client,
      now: () => now,
    );

    await expectLater(
      repository.buildRtcToken(roomId: 'room-42', currentUserId: 42),
      throwsA(isA<ApiException>()),
    );
    wrongUser = false;
    await expectLater(
      repository.buildRtcToken(roomId: 'room-42', currentUserId: 42),
      throwsA(isA<ApiException>()),
    );
  });
}
