import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/features/account/data/auth_session_manager.dart';
import 'package:voice_social_app/features/account/domain/auth_models.dart';
import 'package:voice_social_app/features/account/domain/user_avatar_descriptor.dart';
import 'package:voice_social_app/features/account/presentation/preset_avatar_view.dart';
import 'package:voice_social_app/features/account/presentation/user_avatar_view.dart';
import 'package:voice_social_app/features/media/private_media_host.dart';
import 'support/media_http_fakes.dart';
import 'user_avatar_media_transport_test.dart' show avatarResponse, avatarAsset;

UserAvatarDescriptor uploaded([int version = 0]) =>
    UserAvatarDescriptor.fromBackendData({
      'kind': 'UPLOADED',
      'reference': avatarAsset,
      'version': version,
    });
UserAvatarDescriptor preset(String id) => UserAvatarDescriptor.fromBackendData({
  'kind': 'PRESET',
  'reference': 'avatar-preset-$id',
});
const legacy = Text('LEGACY');
const unavailable = Key('user-avatar-unavailable');
void main() {
  testWidgets(
    'same asset new version cancels old bytes and starts a fresh controlled read',
    (tester) async {
      final bytes = await tester.runAsync(avatarPng);
      final old = Completer<MediaFakeResponse>();
      var calls = 0;
      final deps = await AvatarDependencies.create(
        (_) => ++calls == 1 ? old.future : avatarResponse(bytes: bytes!),
      );
      await deps.show(tester, uploaded(0));
      await tester.pump();
      await deps.show(tester, uploaded(1));
      await decoded(tester);
      final image = tester.widget<RawImage>(find.byType(RawImage)).image;
      old.complete(avatarResponse());
      await tester.pump();
      expect(tester.widget<RawImage>(find.byType(RawImage)).image, same(image));
      expect(deps.http.requests, hasLength(2));
      expect(deps.http.requests.first.aborted, true);
      await deps.close(tester);
    },
  );
  testWidgets('legacy null alone preserves existing fallback', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: UserAvatarView(
          avatar: null,
          userId: 1,
          size: 44,
          fallback: legacy,
        ),
      ),
    );
    expect(find.text('LEGACY'), findsOneWidget);
  });
  testWidgets(
    'all six strict presets use exact artwork without HTTP, logout clears',
    (tester) async {
      final deps = await AvatarDependencies.create(
        (_) => throw StateError('NO HTTP'),
      );
      await deps.show(tester, null);
      for (final id in ['moon', 'sun', 'cloud', 'star', 'sea', 'leaf']) {
        await deps.show(tester, preset(id));
        expect(
          tester
              .widget<PresetAvatarView>(find.byType(PresetAvatarView))
              .presetId,
          'avatar-preset-$id',
        );
        expect(find.text('LEGACY'), findsNothing);
      }
      await deps.sessionManager.clear();
      await tester.pump();
      expect(find.byType(PresetAvatarView), findsNothing);
      expect(find.byKey(unavailable), findsOneWidget);
      expect(deps.http.opens, 0);
      await deps.close(tester);
    },
  );
  testWidgets(
    'uploaded bytes decode without ImageCache; logout disposes pixels and ABA does not reload old descriptor',
    (tester) async {
      final bytes = await tester.runAsync(avatarPng);
      final deps = await AvatarDependencies.create(
        (_) => avatarResponse(bytes: bytes!),
      );
      final cache = PaintingBinding.instance.imageCache.currentSize;
      await deps.show(tester, uploaded());
      await decoded(tester);
      final image = tester.widget<RawImage>(find.byType(RawImage)).image!;
      expect(image.width, 2);
      expect(PaintingBinding.instance.imageCache.currentSize, cache);
      await deps.sessionManager.save(avatarSession(2));
      await deps.sessionManager.save(avatarSession(1));
      await tester.pump();
      expect(find.byType(RawImage), findsNothing);
      expect(image.debugDisposed, true);
      await deps.show(tester, uploaded());
      expect(deps.http.requests, hasLength(1));
      await deps.close(tester);
    },
  );
  for (final lateError in [false, true]) {
    testWidgets('late ${lateError ? "error" : "bytes"} after ABA stays blank', (
      tester,
    ) async {
      final reply = Completer<MediaFakeResponse>();
      final deps = await AvatarDependencies.create((_) => reply.future);
      await deps.show(tester, uploaded());
      await tester.pump();
      await deps.sessionManager.save(avatarSession(2));
      await deps.sessionManager.save(avatarSession(1));
      if (lateError)
        reply.completeError(StateError('OLD SECRET'));
      else
        reply.complete(avatarResponse());
      await tester.pumpAndSettle();
      expect(find.byType(RawImage), findsNothing);
      expect(find.textContaining('OLD SECRET'), findsNothing);
      expect(tester.takeException(), isNull);
      expect(deps.http.requests, hasLength(1));
      await deps.close(tester);
    });
  }
  testWidgets(
    'new target/version rejects old bytes; invalid image never falls back to a URL or legacy image',
    (tester) async {
      final old = Completer<MediaFakeResponse>();
      final deps = await AvatarDependencies.create((_) => old.future);
      await deps.show(tester, uploaded());
      await tester.pump();
      await deps.show(tester, preset('sea'), userId: 2);
      old.complete(avatarResponse());
      await tester.pumpAndSettle();
      expect(find.byType(PresetAvatarView), findsOneWidget);
      expect(find.byType(RawImage), findsNothing);
      await deps.close(tester);
      final invalid = await AvatarDependencies.create((_) => avatarResponse());
      await invalid.show(tester, uploaded());
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await tester.pumpAndSettle();
      expect(find.byType(RawImage), findsNothing);
      expect(find.text('LEGACY'), findsNothing);
      expect(find.byKey(unavailable), findsOneWidget);
      await invalid.close(tester);
    },
  );
  testWidgets(
    'disabled display and unmounted pending read cannot expose pixels',
    (tester) async {
      final reply = Completer<MediaFakeResponse>();
      final deps = await AvatarDependencies.create((_) => reply.future);
      await deps.show(tester, uploaded());
      await tester.pump();
      await deps.show(tester, uploaded(), enabled: false);
      expect(find.byKey(unavailable), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      reply.complete(avatarResponse());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(deps.http.requests.single.aborted, true);
      await deps.close(tester);
    },
  );
}

Future<Uint8List> avatarPng() async {
  final recorder = ui.PictureRecorder();
  Canvas(
    recorder,
  ).drawRect(const Rect.fromLTWH(0, 0, 2, 2), Paint()..color = Colors.purple);
  final picture = recorder.endRecording();
  final image = await picture.toImage(2, 2);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return bytes!.buffer.asUint8List();
}

Future<void> decoded(WidgetTester tester) async {
  final images = find.descendant(
    of: find.byType(UserAvatarView),
    matching: find.byType(RawImage),
  );
  await tester.runAsync(() async {
    for (var attempt = 0; attempt < 100; attempt++) {
      await tester.pump();
      if (images.evaluate().any((e) => (e.widget as RawImage).image != null))
        return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  });
  await tester.pump();
  expect(images, findsOneWidget);
}

class AvatarDependencies extends Fake implements AppDependencies {
  final backing = AppDependencies.mock();
  late final MediaFakeHttp http;
  @override
  late final PrivateMediaHost privateMediaHost;
  @override
  AuthSessionManager get sessionManager => backing.sessionManager;
  static Future<AvatarDependencies> create(
    FutureOr<MediaFakeResponse> Function(MediaFakeRequest) respond,
  ) async {
    final deps = AvatarDependencies();
    await deps.sessionManager.save(avatarSession(1));
    deps.http = MediaFakeHttp(respond);
    final base = deps.backing.privateMediaHost;
    deps.privateMediaHost = PrivateMediaHost(
      api: ApiClient(
        baseUri: Uri.parse('https://backend.test'),
        clientType: 'test',
        clientInnerVersion: '1',
        authorizationProvider: () => deps.sessionManager.authorizationHeader,
        httpClient: deps.http,
      ),
      store: base.store,
      userId: base.userId,
      generation: base.generation,
      changes: base.changes,
      temporaryParent: base.temporaryParent,
      inputFactory: base.inputFactory,
      playerFactory: base.playerFactory,
    );
    return deps;
  }

  Future<void> show(
    WidgetTester tester,
    UserAvatarDescriptor? avatar, {
    int userId = 1,
    bool enabled = true,
  }) => tester.pumpWidget(
    AppDependencyScope(
      dependencies: this,
      child: MaterialApp(
        home: UserAvatarView(
          avatar: avatar,
          userId: userId,
          size: 44,
          fallback: legacy,
          enabled: enabled,
        ),
      ),
    ),
  );
  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    backing.dispose();
  }
}

AuthSession avatarSession(int user) => AuthSession(
  accessToken: 'test',
  tokenType: 'Bearer',
  expiresAt: DateTime(2099),
  userId: user,
  mobile: '',
  roles: 'USER',
);
