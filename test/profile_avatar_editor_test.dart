import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:voice_social_app/core/media/profile_avatar_transport.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/account/profile_avatar/profile_avatar_editor.dart';
import 'package:voice_social_app/features/media/app_image_media_host.dart';
import 'package:voice_social_app/features/media/native_image_selection.dart';

import 'support/media_http_fakes.dart';

const _assetId = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';

Map<String, Object?> _avatarStatus(String state, int version, {int? bytes}) => {
  'assetId': _assetId,
  'purpose': 'AVATAR',
  'state': state,
  'version': version,
  'maximumBytes': 10000000,
  'expiresAt': '2099-09-12T00:00:00Z',
  'mediaType': bytes == null ? null : 'image/png',
  'bytes': bytes,
  'durationMillis': bytes == null ? null : 0,
};

class _Picker implements ImageSelection {
  List<XFile> files = <XFile>[
    XFile.fromData(Uint8List.fromList([1, 2, 3])),
  ];

  @override
  Future<List<XFile>> pick(int remaining) async => files;
}

void main() {
  late TestMediaIdentity identity;
  late Directory temp;
  late _Picker picker;
  late MediaFakeHttp http;
  late AppImageMediaHost imageHost;

  setUp(() async {
    identity = TestMediaIdentity();
    temp = await Directory.systemTemp.createTemp('profile-avatar-editor-');
    picker = _Picker();
    var bound = false;
    http = MediaFakeHttp((request) {
      if (request.uri.path == '/app-api/user/getPersonalData') {
        return MediaFakeResponse.json({
          'userId': 1,
          'avatarRevision': bound ? 1 : 0,
          'avatar': bound
              ? {'kind': 'UPLOADED', 'reference': _assetId, 'version': 2}
              : {'kind': 'PRESET', 'reference': 'avatar-preset-moon'},
          'headImageUrl': 'https://must-not-be-used.example/old.png',
        });
      }
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
        return MediaFakeResponse.json(_avatarStatus('ALLOCATED', 0));
      }
      if (request.uri.path ==
              '/app-api/user/profile/avatar-uploads/$_assetId/content' &&
          request.method == 'PUT') {
        return MediaFakeResponse.json(_avatarStatus('UPLOADING', 1, bytes: 3));
      }
      if (request.uri.path ==
              '/app-api/user/profile/avatar-uploads/$_assetId/complete' &&
          request.method == 'POST') {
        return MediaFakeResponse.json(_avatarStatus('READY', 2, bytes: 3));
      }
      if (request.uri.path == '/app-api/user/profile/avatar' &&
          request.method == 'PUT') {
        bound = true;
        return MediaFakeResponse.json({
          'avatarRevision': 1,
          'avatar': {'kind': 'UPLOADED', 'reference': _assetId, 'version': 2},
        });
      }
      throw StateError('unexpected ${request.method} ${request.uri}');
    });
    final client = http.api(identity);
    imageHost = AppImageMediaHost(
      api: client,
      userId: () => identity.user,
      generation: () => identity.generation,
      changes: identity,
      picker: picker,
      temporaryParent: () async => temp,
      profileAvatarMediaTransport: ApiProfileAvatarMediaTransport(client),
    );
  });

  tearDown(() async {
    imageHost.dispose();
    await imageHost.cleanup;
    identity.dispose();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test(
    'image selection uploads through profile routes, binds, then rereads',
    () async {
      final client = http.api(identity);
      final editor = ProfileAvatarEditor(
        api: ProfileAvatarApi(
          apiClient: client,
          mediaTransport: ApiProfileAvatarMediaTransport(client),
        ),
        imageHost: imageHost,
      );
      addTearDown(editor.dispose);

      await editor.load();
      await editor.chooseImage();
      final result = await editor.save();

      expect(result.avatarRevision, 1);
      expect(result.avatar?.reference, _assetId);
      expect(editor.current?.avatar?.reference, _assetId);
      expect(
        http.requests
            .map((request) => '${request.method} ${request.uri.path}')
            .toList(),
        [
          'GET /app-api/user/getPersonalData',
          'GET /app-register-api/media/v1/avatar-presets',
          'POST /app-api/user/profile/avatar-uploads',
          'PUT /app-api/user/profile/avatar-uploads/$_assetId/content',
          'POST /app-api/user/profile/avatar-uploads/$_assetId/complete',
          'PUT /app-api/user/profile/avatar',
          'GET /app-api/user/getPersonalData',
        ],
      );
      expect(
        http.requests.where(
          (request) => request.uri.path.startsWith('/app-api/media/'),
        ),
        isEmpty,
      );
    },
  );

  test(
    'preset save skips upload and a bind failure preserves old avatar',
    () async {
      var bindCalls = 0;
      http = MediaFakeHttp((request) {
        if (request.uri.path == '/app-api/user/getPersonalData') {
          return MediaFakeResponse.json({
            'avatarRevision': 4,
            'avatar': {'kind': 'PRESET', 'reference': 'avatar-preset-moon'},
          });
        }
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
        if (request.uri.path == '/app-api/user/profile/avatar' &&
            request.method == 'PUT') {
          bindCalls++;
          return MediaFakeResponse.json(null, status: 409, code: 40990);
        }
        throw StateError('unexpected ${request.method} ${request.uri}');
      });
      final client = http.api(identity);
      imageHost.dispose();
      await imageHost.cleanup;
      imageHost = AppImageMediaHost(
        api: client,
        userId: () => identity.user,
        generation: () => identity.generation,
        changes: identity,
        picker: picker,
        temporaryParent: () async => temp,
        profileAvatarMediaTransport: ApiProfileAvatarMediaTransport(client),
      );
      final editor = ProfileAvatarEditor(
        api: ProfileAvatarApi(
          apiClient: client,
          mediaTransport: ApiProfileAvatarMediaTransport(client),
        ),
        imageHost: imageHost,
      );
      addTearDown(editor.dispose);

      await editor.load();
      editor.choosePreset('avatar-preset-sun');
      await expectLater(editor.save(), throwsA(isA<ApiException>()));

      expect(bindCalls, 1);
      expect(editor.current?.avatar?.reference, 'avatar-preset-moon');
      expect(editor.current?.avatarRevision, 4);
      expect(http.requests.map((request) => request.uri.path).toList(), [
        '/app-api/user/getPersonalData',
        '/app-register-api/media/v1/avatar-presets',
        '/app-api/user/profile/avatar',
      ]);
    },
  );

  test(
    'null avatar at a positive revision loads and binds with that revision',
    () async {
      var personalReads = 0;
      List<int>? bindBody;
      http = MediaFakeHttp((request) {
        if (request.uri.path == '/app-api/user/getPersonalData') {
          personalReads++;
          return MediaFakeResponse.json(
            personalReads == 1
                ? {'avatarRevision': 7, 'avatar': null}
                : {
                    'avatarRevision': 8,
                    'avatar': {
                      'kind': 'PRESET',
                      'reference': 'avatar-preset-sun',
                    },
                  },
          );
        }
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
        if (request.uri.path == '/app-api/user/profile/avatar' &&
            request.method == 'PUT') {
          bindBody = List<int>.from(request.body);
          return MediaFakeResponse.json({
            'avatarRevision': 8,
            'avatar': {'kind': 'PRESET', 'reference': 'avatar-preset-sun'},
          });
        }
        throw StateError('unexpected ${request.method} ${request.uri}');
      });
      final client = http.api(identity);
      imageHost.dispose();
      await imageHost.cleanup;
      imageHost = AppImageMediaHost(
        api: client,
        userId: () => identity.user,
        generation: () => identity.generation,
        changes: identity,
        picker: picker,
        temporaryParent: () async => temp,
        profileAvatarMediaTransport: ApiProfileAvatarMediaTransport(client),
      );
      final editor = ProfileAvatarEditor(
        api: ProfileAvatarApi(
          apiClient: client,
          mediaTransport: ApiProfileAvatarMediaTransport(client),
        ),
        imageHost: imageHost,
      );
      addTearDown(editor.dispose);

      await editor.load();
      expect(editor.hasCurrentSnapshot, isTrue);
      expect(editor.current?.avatarRevision, 7);
      expect(editor.current?.avatar, isNull);

      editor.choosePreset('avatar-preset-sun');
      final result = await editor.save();

      expect(
        jsonDecode(utf8.decode(bindBody!)),
        containsPair('expectedAvatarRevision', 7),
      );
      expect(result.avatarRevision, 8);
      expect(result.avatar?.reference, 'avatar-preset-sun');
    },
  );

  test(
    'authoritative reread wins over an old receipt and newer avatar revision',
    () async {
      var personalReads = 0;
      http = MediaFakeHttp((request) {
        if (request.uri.path == '/app-api/user/getPersonalData') {
          personalReads++;
          return MediaFakeResponse.json(
            personalReads == 1
                ? {
                    'avatarRevision': 4,
                    'avatar': {
                      'kind': 'PRESET',
                      'reference': 'avatar-preset-moon',
                    },
                  }
                : {
                    'avatarRevision': 6,
                    'avatar': {
                      'kind': 'PRESET',
                      'reference': 'avatar-preset-leaf',
                    },
                  },
          );
        }
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
        if (request.uri.path == '/app-api/user/profile/avatar' &&
            request.method == 'PUT') {
          // Historical receipt from the old idempotency key; it must not
          // overwrite the newer authoritative projection.
          return MediaFakeResponse.json({
            'avatarRevision': 5,
            'avatar': {'kind': 'PRESET', 'reference': 'avatar-preset-sun'},
          });
        }
        throw StateError('unexpected ${request.method} ${request.uri}');
      });
      final client = http.api(identity);
      imageHost.dispose();
      await imageHost.cleanup;
      imageHost = AppImageMediaHost(
        api: client,
        userId: () => identity.user,
        generation: () => identity.generation,
        changes: identity,
        picker: picker,
        temporaryParent: () async => temp,
        profileAvatarMediaTransport: ApiProfileAvatarMediaTransport(client),
      );
      final editor = ProfileAvatarEditor(
        api: ProfileAvatarApi(
          apiClient: client,
          mediaTransport: ApiProfileAvatarMediaTransport(client),
        ),
        imageHost: imageHost,
      );
      addTearDown(editor.dispose);

      await editor.load();
      editor.choosePreset('avatar-preset-sun');
      final result = await editor.save();

      expect(result.avatarRevision, 6);
      expect(result.avatar?.reference, 'avatar-preset-leaf');
      expect(editor.current?.avatarRevision, 6);
      expect(editor.current?.avatar?.reference, 'avatar-preset-leaf');
      expect(editor.notice, contains('最新头像'));
    },
  );

  test(
    'late old-identity save cannot replace the current editor state',
    () async {
      final bindGate = Completer<void>();
      http = MediaFakeHttp((request) async {
        if (request.uri.path == '/app-api/user/getPersonalData') {
          return MediaFakeResponse.json({'avatarRevision': 0, 'avatar': null});
        }
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
        if (request.uri.path == '/app-api/user/profile/avatar') {
          await bindGate.future;
          return MediaFakeResponse.json({
            'avatarRevision': 1,
            'avatar': {'kind': 'PRESET', 'reference': 'avatar-preset-sun'},
          });
        }
        throw StateError('unexpected ${request.method} ${request.uri}');
      });
      final client = http.api(identity);
      imageHost.dispose();
      await imageHost.cleanup;
      imageHost = AppImageMediaHost(
        api: client,
        userId: () => identity.user,
        generation: () => identity.generation,
        changes: identity,
        picker: picker,
        temporaryParent: () async => temp,
        profileAvatarMediaTransport: ApiProfileAvatarMediaTransport(client),
      );
      final editor = ProfileAvatarEditor(
        api: ProfileAvatarApi(
          apiClient: client,
          mediaTransport: ApiProfileAvatarMediaTransport(client),
        ),
        imageHost: imageHost,
      );
      addTearDown(editor.dispose);
      await editor.load();
      editor.choosePreset('avatar-preset-sun');
      final pending = editor.save();
      identity.change(2);
      bindGate.complete();

      await expectLater(pending, throwsA(isA<ApiException>()));
      expect(editor.current, isNotNull);
      expect(editor.current?.avatar, isNull);
    },
  );
}
