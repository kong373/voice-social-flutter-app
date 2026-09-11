import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/media/profile_avatar_transport.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/account/profile_avatar/profile_avatar_editor.dart';

import 'support/media_http_fakes.dart';

const _assetId = '11111111-2222-4333-8444-555555555555';

Map<String, Object?> _status(
  String state,
  int version, {
  int? bytes,
  String? mediaType,
}) => {
  'assetId': _assetId,
  'purpose': 'AVATAR',
  'state': state,
  'version': version,
  'maximumBytes': 10000000,
  'expiresAt': '2099-09-12T00:00:00Z',
  'mediaType': mediaType,
  'bytes': bytes,
  'durationMillis': bytes == null ? null : 0,
};

void main() {
  test('profile request IDs follow the backend 80-character policy', () {
    expect(isProfileAvatarRequestId('a' * 80), isTrue);
    expect(isProfileAvatarRequestId('a' * 81), isFalse);
    expect(isProfileAvatarRequestId('profile.avatar-1'), isTrue);
    expect(isProfileAvatarRequestId('profile avatar'), isFalse);
  });

  test('profile avatar transport uses dedicated contract routes', () async {
    final actor = TestMediaIdentity();
    final scope = actor.scope();
    addTearDown(scope.dispose);
    final http = MediaFakeHttp((request) {
      if (request.uri.path == '/app-register-api/media/v1/avatar-presets') {
        return MediaFakeResponse.json({
          'presets': [
            'avatar-preset-moon',
            'avatar-preset-sun',
            'avatar-preset-cloud',
            'avatar-preset-star',
            'avatar-preset-sea',
            'avatar-preset-leaf',
          ],
        });
      }
      if (request.uri.path == '/app-api/user/profile/avatar-uploads' &&
          request.method == 'POST') {
        return MediaFakeResponse.json(_status('ALLOCATED', 0));
      }
      if (request.uri.path ==
              '/app-api/user/profile/avatar-uploads/$_assetId' &&
          request.method == 'GET') {
        return MediaFakeResponse.json(
          _status('READY', 2, bytes: 3, mediaType: 'image/png'),
        );
      }
      if (request.uri.path ==
              '/app-api/user/profile/avatar-uploads/$_assetId/content' &&
          request.method == 'PUT') {
        return MediaFakeResponse.json(
          _status('UPLOADING', 1, bytes: 3, mediaType: 'image/png'),
        );
      }
      if (request.uri.path ==
              '/app-api/user/profile/avatar-uploads/$_assetId/complete' &&
          request.method == 'POST') {
        return MediaFakeResponse.json(
          _status('READY', 2, bytes: 3, mediaType: 'image/png'),
        );
      }
      if (request.uri.path == '/app-api/user/profile/avatar' &&
          request.method == 'PUT') {
        return MediaFakeResponse.json({
          'avatarRevision': 1,
          'avatar': {'kind': 'PRESET', 'reference': 'avatar-preset-sun'},
        });
      }
      if (request.uri.path == '/app-api/user/getPersonalData' &&
          request.method == 'GET') {
        return MediaFakeResponse.json({
          'userId': 1,
          'avatarRevision': 1,
          'avatar': {'kind': 'PRESET', 'reference': 'avatar-preset-sun'},
          'headImageUrl': 'https://must-not-be-used.example/avatar.png',
        });
      }
      throw StateError('unexpected ${request.method} ${request.uri}');
    });
    final client = http.api(actor);
    final transport = ApiProfileAvatarMediaTransport(client);
    final api = ProfileAvatarApi(apiClient: client, mediaTransport: transport);

    expect(await api.fetchPresetIds(), contains('avatar-preset-sun'));
    await api.allocateUpload(
      identity: scope,
      requestId: 'profile-avatar-upload-1',
    );
    await api.statusUpload(identity: scope, assetId: _assetId);
    await api.putUploadContent(
      identity: scope,
      assetId: _assetId,
      expectedVersion: 0,
      bytes: 3,
      content: () => Stream.value([1, 2, 3]),
    );
    await api.completeUpload(
      identity: scope,
      assetId: _assetId,
      expectedVersion: 1,
    );
    final receipt = await api.bindAvatar(
      identity: scope,
      choice: ProfileAvatarChoice.preset('avatar-preset-sun'),
      expectedAvatarRevision: 0,
      requestId: 'profile-avatar-bind-1',
    );
    final current = await api.readCurrentAvatar(scope);

    expect(receipt.avatarRevision, 1);
    expect(current.avatarRevision, 1);
    expect(current.avatar?.reference, 'avatar-preset-sun');
    expect(
      http.requests
          .map((request) => '${request.method} ${request.uri.path}')
          .toList(),
      [
        'GET /app-register-api/media/v1/avatar-presets',
        'POST /app-api/user/profile/avatar-uploads',
        'GET /app-api/user/profile/avatar-uploads/$_assetId',
        'PUT /app-api/user/profile/avatar-uploads/$_assetId/content',
        'POST /app-api/user/profile/avatar-uploads/$_assetId/complete',
        'PUT /app-api/user/profile/avatar',
        'GET /app-api/user/getPersonalData',
      ],
    );
    final allocate = http.requests[1];
    expect(jsonDecode(utf8.decode(allocate.body)), {'purpose': 'AVATAR'});
    expect(allocate.headers.value('X-Request-Id'), 'profile-avatar-upload-1');
    final status = http.requests[2];
    expect(status.headers.value('X-Request-Id'), isNull);
    final content = http.requests[3];
    expect(content.uri.queryParameters, {'expectedVersion': '0'});
    expect(content.headers.value('Content-Type'), 'application/octet-stream');
    expect(content.headers.value('X-Request-Id'), isNull);
    expect(content.headers.value('Content-Encoding'), isNull);
    expect(content.body, [1, 2, 3]);
    final complete = http.requests[4];
    expect(jsonDecode(utf8.decode(complete.body)), {'expectedVersion': 1});
    expect(complete.headers.value('X-Request-Id'), isNull);
    final bind = http.requests[5];
    expect(bind.headers.value('X-Request-Id'), 'profile-avatar-bind-1');
    expect(jsonDecode(utf8.decode(bind.body)), {
      'kind': 'PRESET',
      'reference': 'avatar-preset-sun',
      'expectedAvatarRevision': 0,
    });
    expect(http.requests[0].headers.value('Authorization'), isNull);
    expect(http.requests[6].headers.value('Authorization'), actor.token);
  });

  test('no avatar is a strict null descriptor at revision zero', () async {
    final actor = TestMediaIdentity();
    final scope = actor.scope();
    addTearDown(scope.dispose);
    final http = MediaFakeHttp(
      (_) => MediaFakeResponse.json({
        'avatarRevision': 0,
        'avatar': null,
        'headImageUrl': 'https://must-not-be-used.example/legacy.png',
      }),
    );
    final client = http.api(actor);
    final api = ProfileAvatarApi(
      apiClient: client,
      mediaTransport: ApiProfileAvatarMediaTransport(client),
    );

    final snapshot = await api.readCurrentAvatar(scope);

    expect(snapshot.avatar, isNull);
    expect(snapshot.avatarRevision, 0);
  });

  test(
    'profile raw content PUT keeps explicit status recovery after 401',
    () async {
      final actor = TestMediaIdentity();
      final scope = actor.scope();
      addTearDown(scope.dispose);
      var refreshes = 0;
      final http = MediaFakeHttp((request) {
        expect(request.method, 'PUT');
        return MediaFakeResponse.json(null, status: 401, code: 40101);
      });
      final client = http.api(
        actor,
        refresh: () async {
          refreshes++;
          actor.refreshToken();
          return true;
        },
      );
      final api = ProfileAvatarApi(apiClient: client);

      await expectLater(
        api.putUploadContent(
          identity: scope,
          assetId: _assetId,
          expectedVersion: 0,
          bytes: 3,
          content: () => Stream.value([1, 2, 3]),
        ),
        throwsA(isA<ApiException>()),
      );
      expect(refreshes, 1);
      expect(http.requests, hasLength(1));
    },
  );

  test(
    'avatar parser rejects URL-shaped descriptors but keeps positive revision',
    () {
      expect(
        () => ProfileAvatarSnapshot.fromPersonalData({
          'avatarRevision': 1,
          'avatar': 'https://must-not-be-used.example/avatar.png',
        }),
        throwsA(isA<Exception>()),
      );
      expect(
        () => ProfileAvatarSnapshot.fromPersonalData({'avatar': null}),
        throwsA(isA<Exception>()),
      );
      final revoked = ProfileAvatarSnapshot.fromPersonalData({
        'avatarRevision': 1,
        'avatar': null,
      });
      expect(revoked.avatar, isNull);
      expect(revoked.avatarRevision, 1);
    },
  );
}
