import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:voice_social_app/core/media/profile_avatar_transport.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/account/presentation/profile_avatar_edit_panel.dart';
import 'package:voice_social_app/features/account/profile_avatar/profile_avatar_editor.dart';
import 'package:voice_social_app/features/media/app_image_media_host.dart';
import 'package:voice_social_app/features/media/native_image_selection.dart';

import 'support/media_http_fakes.dart';

const _asset = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';
const _upload = '/app-api/user/profile/avatar-uploads';

class _Picker implements ImageSelection {
  @override
  Future<List<XFile>> pick(int remaining) async => [
    XFile.fromData(Uint8List.fromList([1, 2, 3])),
  ];
}

Map<String, Object?> _status(String state, int version) => {
  'assetId': _asset,
  'purpose': 'AVATAR',
  'state': state,
  'version': version,
  'maximumBytes': 10000000,
  'expiresAt': '2099-09-12T00:00:00Z',
  'mediaType': version == 0 ? null : 'image/png',
  'bytes': version == 0 ? null : 3,
  'durationMillis': version == 0 ? null : 0,
};

void main() {
  late TestMediaIdentity identity;
  late Directory temporary;
  late MediaFakeHttp http;
  late AppImageMediaHost host;
  late ProfileAvatarEditor editor;
  late bool bound;
  Completer<HttpClientResponse>? delayedStatus;

  ProfileAvatarEditor newEditor() => ProfileAvatarEditor(
    api: ProfileAvatarApi(apiClient: http.api(identity)),
    imageHost: host,
  );

  int calls(String method, String path) => http.requests
      .where((request) => request.method == method && request.uri.path == path)
      .length;

  setUp(() async {
    identity = TestMediaIdentity();
    temporary = await Directory.systemTemp.createTemp('avatar-recovery-');
    bound = false;
    delayedStatus = null;
    http = MediaFakeHttp((request) {
      final path = request.uri.path;
      if (path == '/app-api/user/getPersonalData') {
        return MediaFakeResponse.json({
          'avatarRevision': bound ? 3 : 2,
          'avatar': bound
              ? {'kind': 'UPLOADED', 'reference': _asset, 'version': 3}
              : {'kind': 'PRESET', 'reference': 'avatar-preset-moon'},
        });
      }
      if (path == '/app-register-api/media/v1/avatar-presets') {
        return MediaFakeResponse.json({
          'presets': ['avatar-preset-moon', 'avatar-preset-sun'],
        });
      }
      if (path == _upload && request.method == 'POST') {
        return MediaFakeResponse.json(_status('ALLOCATED', 0));
      }
      if (path == '$_upload/$_asset/content' && request.method == 'PUT') {
        return MediaFakeResponse.json(_status('QUARANTINED', 2));
      }
      if (path == '$_upload/$_asset/complete' && request.method == 'POST') {
        // The server finished inspection, but its response missed the client
        // deadline. Its status endpoint can recover the same asset.
        throw TimeoutException('controlled response loss');
      }
      if (path == '$_upload/$_asset' && request.method == 'GET') {
        return delayedStatus?.future ??
            MediaFakeResponse.json(_status('READY', 3));
      }
      if (path == '/app-api/user/profile/avatar' && request.method == 'PUT') {
        bound = true;
        return MediaFakeResponse.json({
          'avatarRevision': 3,
          'avatar': {'kind': 'UPLOADED', 'reference': _asset, 'version': 3},
        });
      }
      throw StateError('unexpected ${request.method} $path');
    });
    final client = http.api(identity);
    host = AppImageMediaHost(
      api: client,
      userId: () => identity.user,
      generation: () => identity.generation,
      changes: identity,
      picker: _Picker(),
      temporaryParent: () async => temporary,
      profileAvatarMediaTransport: ApiProfileAvatarMediaTransport(client),
    );
    editor = newEditor();
    await editor.load();
    await editor.chooseImage();
    await expectLater(editor.save(), throwsA(isA<ApiException>()));
    expect(editor.current?.avatar?.reference, 'avatar-preset-moon');
  });

  tearDown(() async {
    editor.dispose();
    host.dispose();
    await host.cleanup;
    identity.dispose();
    await temporary.delete(recursive: true);
  });

  testWidgets(
    'visible recovery reads the original asset without replaying writes',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ProfileAvatarEditPanel(
                editor: editor,
                onAvatarChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      final retry = tester.widget<TextButton>(
        find.widgetWithText(TextButton, '重新读取头像设置'),
      );
      await tester.runAsync(() async {
        retry.onPressed!();
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await tester.pump();
      expect(calls('GET', '$_upload/$_asset'), 1);
      expect(calls('POST', _upload), 1);
      expect(calls('PUT', '$_upload/$_asset/content'), 1);
      expect(calls('POST', '$_upload/$_asset/complete'), 1);
      expect(calls('PUT', '/app-api/user/profile/avatar'), 0);
      expect(editor.current?.avatar?.reference, 'avatar-preset-moon');
      expect(editor.selectedPresetId, isNull);
      expect(editor.error, isNull);
      final result = await tester.runAsync(editor.save);
      expect(result?.avatar?.reference, _asset);
      expect(calls('PUT', '/app-api/user/profile/avatar'), 1);
      expect(calls('POST', _upload), 1);
      expect(calls('PUT', '$_upload/$_asset/content'), 1);
      expect(calls('POST', '$_upload/$_asset/complete'), 1);
    },
  );

  test(
    'reopening the editor preserves the pending image choice over the old preset',
    () async {
      editor.dispose();
      editor = newEditor();
      await editor.load();
      expect(editor.hasSelectedImage, isTrue);
      expect(editor.selectedPresetId, isNull);
      expect(editor.error, isNotNull);
      expect(editor.current?.avatar?.reference, 'avatar-preset-moon');
      expect(calls('POST', _upload), 1);
      expect(calls('GET', '$_upload/$_asset'), 0);
    },
  );

  test(
    'identity loss rejects a late original-asset status and never binds',
    () async {
      delayedStatus = Completer<HttpClientResponse>();
      final recovery = editor.reload();
      final rejected = expectLater(recovery, throwsA(isA<ApiException>()));
      for (
        var attempt = 0;
        attempt < 100 && calls('GET', '$_upload/$_asset') == 0;
        attempt++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      expect(calls('GET', '$_upload/$_asset'), 1);
      identity.change(2);
      delayedStatus!.complete(MediaFakeResponse.json(_status('READY', 3)));
      await rejected;
      expect(editor.current?.avatar?.reference, 'avatar-preset-moon');
      expect(calls('PUT', '/app-api/user/profile/avatar'), 0);
      expect(calls('POST', _upload), 1);
      expect(calls('PUT', '$_upload/$_asset/content'), 1);
    },
  );

  test(
    'authoritative read of an already bound image needs no second bind',
    () async {
      bound =
          true; // The previous bind response was lost, not the server write.
      await editor.reload();
      expect(editor.current?.avatar?.reference, _asset);
      expect(editor.current?.avatarRevision, 3);
      expect(editor.hasSelectedImage, isFalse);
      expect(editor.selectedPresetId, isNull);
      expect(calls('PUT', '/app-api/user/profile/avatar'), 0);
      expect(calls('POST', _upload), 1);
      expect(calls('PUT', '$_upload/$_asset/content'), 1);
    },
  );

  testWidgets('recovery notifies the containing profile of the reread avatar', (
    tester,
  ) async {
    bound = true;
    String? displayed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ProfileAvatarEditPanel(
              editor: editor,
              onAvatarChanged: (avatar) => displayed = avatar?.reference,
            ),
          ),
        ),
      ),
    );
    final retry = tester.widget<TextButton>(
      find.widgetWithText(TextButton, '重新读取头像设置'),
    );
    await tester.runAsync(() async {
      retry.onPressed!();
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pump();
    expect(editor.current?.avatar?.reference, _asset);
    expect(displayed, _asset);
    expect(calls('PUT', '/app-api/user/profile/avatar'), 0);
  });

  test(
    'reopening clears a known READY image already bound by authority',
    () async {
      await editor.reload();
      expect(editor.hasSelectedImage, isTrue);
      bound = true;
      editor.dispose();
      editor = newEditor();
      await editor.load();
      expect(editor.current?.avatar?.reference, _asset);
      expect(editor.hasSelectedImage, isFalse);
      expect(editor.selectedPresetId, isNull);
      expect(calls('GET', '$_upload/$_asset'), 1);
      expect(calls('PUT', '/app-api/user/profile/avatar'), 0);
    },
  );
}
