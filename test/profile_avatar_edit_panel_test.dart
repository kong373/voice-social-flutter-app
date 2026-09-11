import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:voice_social_app/core/media/profile_avatar_transport.dart';
import 'package:voice_social_app/features/account/presentation/profile_avatar_edit_panel.dart';
import 'package:voice_social_app/features/account/profile_avatar/profile_avatar_editor.dart';
import 'package:voice_social_app/features/media/app_image_media_host.dart';
import 'package:voice_social_app/features/media/native_image_selection.dart';

import 'support/media_http_fakes.dart';

class _NoopPicker implements ImageSelection {
  @override
  Future<List<XFile>> pick(int remaining) async => const <XFile>[];
}

void main() {
  testWidgets(
    'actual avatar panel loads, selects, saves, and displays authoritative reread',
    (tester) async {
      final identity = TestMediaIdentity();
      var personalReads = 0;
      final http = MediaFakeHttp((request) {
        if (request.uri.path == '/app-api/user/getPersonalData') {
          personalReads++;
          return MediaFakeResponse.json(
            personalReads == 1
                ? {
                    'avatarRevision': 0,
                    'avatar': {
                      'kind': 'PRESET',
                      'reference': 'avatar-preset-moon',
                    },
                  }
                : {
                    'avatarRevision': 1,
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
          return MediaFakeResponse.json({
            'avatarRevision': 1,
            'avatar': {'kind': 'PRESET', 'reference': 'avatar-preset-sun'},
          });
        }
        throw StateError('unexpected ${request.method} ${request.uri}');
      });
      final client = http.api(identity);
      final host = AppImageMediaHost(
        api: client,
        userId: () => identity.user,
        generation: () => identity.generation,
        changes: identity,
        picker: _NoopPicker(),
        temporaryParent: () async => Directory.systemTemp,
        profileAvatarMediaTransport: ApiProfileAvatarMediaTransport(client),
      );
      final editor = ProfileAvatarEditor(
        api: ProfileAvatarApi(
          apiClient: client,
          mediaTransport: ApiProfileAvatarMediaTransport(client),
        ),
        imageHost: host,
      );
      addTearDown(() async {
        editor.dispose();
        host.dispose();
        await host.cleanup;
        identity.dispose();
      });

      final changed = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ProfileAvatarEditPanel(
                editor: editor,
                onAvatarChanged: (_) {
                  if (!changed.isCompleted) changed.complete();
                },
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(editor.load);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('公开预设'), findsOneWidget);
      expect(editor.current?.avatar?.reference, 'avatar-preset-moon');
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('profile-avatar-save')))
            .onPressed,
        isNotNull,
      );

      await tester.tap(
        find.byKey(
          const ValueKey<String>('preset-avatar-option:avatar-preset-sun'),
        ),
      );
      await tester.pump();
      expect(editor.selectedPresetId, 'avatar-preset-sun');
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('profile-avatar-save')))
            .onPressed,
        isNotNull,
      );

      final saveButton = tester.widget<FilledButton>(
        find.byKey(const Key('profile-avatar-save')),
      );
      await tester.runAsync(() async {
        saveButton.onPressed!();
        await Future.any<void>([
          changed.future,
          Future<void>.delayed(const Duration(seconds: 1)),
        ]);
      });
      await tester.pump();
      expect(
        changed.isCompleted,
        isTrue,
        reason:
            'state=${editor.uploadState} busy=${editor.busy} error=${editor.error} requests=${http.requests.length}',
      );

      expect(personalReads, 2);
      expect(editor.current?.avatarRevision, 1);
      expect(editor.current?.avatar?.reference, 'avatar-preset-sun');
      expect(editor.notice, isNull);
      expect(
        http.requests.map((request) => '${request.method} ${request.uri.path}'),
        [
          'GET /app-api/user/getPersonalData',
          'GET /app-register-api/media/v1/avatar-presets',
          'PUT /app-api/user/profile/avatar',
          'GET /app-api/user/getPersonalData',
        ],
      );
    },
  );
}
