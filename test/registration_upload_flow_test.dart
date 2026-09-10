import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/storage/key_value_store.dart';
import 'package:voice_social_app/features/account/application/auth_controller.dart';
import 'package:voice_social_app/features/account/data/auth_session_manager.dart';
import 'package:voice_social_app/features/account/data/device_identity_provider.dart';
import 'package:voice_social_app/features/account/data/mock_auth_repository.dart';
import 'package:voice_social_app/features/account/domain/auth_models.dart';
import 'package:voice_social_app/features/account/domain/registration_avatar.dart';
import 'package:voice_social_app/features/account/presentation/registration_page.dart';
import 'package:voice_social_app/features/account/registration_avatar/registration_avatar_host.dart';
import 'package:voice_social_app/features/account/registration_avatar/registration_avatar_transport_adapter.dart';
import 'support/registration_avatar_fakes.dart';

RegistrationProfile _uploaded() => RegistrationProfile(
  nickname: '小鲸',
  sex: 0,
  avatar: RegistrationAvatarChoice.uploaded(avatarTestId, 3),
);

void main() {
  final previewBinding = _PreviewTestBinding();
  for (final pending in [false, true]) {
    for (final exit in ['cancel', 'invalidate', 'unmount', 'replace']) {
      _flowWidgetTest(
        'preview cache ${pending ? 'pending' : 'decoded'} $exit evicts only its exact key',
        (tester, f) async {
          final cache = previewBinding.imageCache;
          final png = (await tester.runAsync(
            () => File(f.picker.files.single.path).readAsBytes(),
          ))!;
          final unrelated = MemoryImage(Uint8List.fromList(png));
          final unrelatedKey = await unrelated.obtainKey(
            ImageConfiguration.empty,
          );
          ImageProvider? previewProvider;
          ImageProvider? replacementProvider;
          final gate = pending ? _PreviewDecodeGate() : null;
          try {
            await tester.pumpWidget(MaterialApp(home: Image(image: unrelated)));
            await _pumpIoUntil(
              tester,
              () => cache.statusForKey(unrelatedKey).keepAlive,
              'unrelated image decoding',
            );
            await tester.pumpWidget(const SizedBox());
            expect(cache.statusForKey(unrelatedKey).live, false);
            await tester.runAsync(f.host.choose);
            previewBinding.nextDecode = gate;
            await tester.pumpWidget(
              MaterialApp(home: RegistrationPage(controller: f.controller)),
            );
            previewProvider = _previewProvider(tester);
            final key = await previewProvider.obtainKey(
              ImageConfiguration.empty,
            );
            expect(previewProvider, isA<ResizeImage>());
            await _pumpIoUntil(
              tester,
              () => pending ? gate!.entered : cache.statusForKey(key).keepAlive,
              'registration preview decoding',
            );
            expect(cache.statusForKey(key).live, true);
            expect(cache.statusForKey(key).pending, pending);
            expect(cache.statusForKey(key).keepAlive, !pending);

            switch (exit) {
              case 'cancel':
                f.controller.cancelRegistration();
              case 'invalidate':
                // The expiry timer uses this same context invalidation path.
                f.host.context.invalidate();
              case 'unmount':
                await tester.pumpWidget(const SizedBox());
              case 'replace':
                // Before allocation, choose is allowed to replace the image.
                await tester.runAsync(() async {
                  await File(
                    f.picker.files.single.path,
                  ).writeAsBytes(await _previewPng(Colors.blue));
                  await f.host.choose();
                });
            }
            await tester.pump();
            if (exit == 'replace') {
              replacementProvider = _previewProvider(tester);
              final nextKey = await replacementProvider.obtainKey(
                ImageConfiguration.empty,
              );
              expect(nextKey, isNot(key));
              await _pumpIoUntil(
                tester,
                () => cache.statusForKey(nextKey).keepAlive,
                'replacement preview decoding',
              );
            } else {
              expect(_previewImageFinder(), findsNothing);
              if (exit != 'unmount') expect(f.host.previewBytes, isNull);
            }
            _expectPreviewEvicted(cache, key);
            if (gate != null) {
              gate.release.complete();
              await _pumpIoUntil(
                tester,
                () => gate.completed,
                'late preview frame',
              );
              await tester.pumpAndSettle();
              _expectPreviewEvicted(cache, key);
            }
            expect(cache.statusForKey(unrelatedKey).keepAlive, true);
            expect(tester.takeException(), isNull);
            expect(f.server.allocations, 0);
          } finally {
            previewBinding.nextDecode = null;
            if (gate != null && !gate.release.isCompleted)
              gate.release.complete();
            await tester.pumpWidget(const SizedBox());
            if (gate?.entered == true) {
              await _pumpIoUntil(
                tester,
                () => gate!.completed,
                'decode cleanup',
              );
            }
            await previewProvider?.evict();
            await replacementProvider?.evict();
            await unrelated.evict();
          }
        },
      );
    }
  }

  test(
    'a claimed uploaded UUID without current READY never registers',
    () async {
      final f = await _FlowFixture.create();
      addTearDown(f.dispose);
      expect(await f.controller.completeRegistration(_uploaded()), false);
      expect(f.repository.proofs, isEmpty);
      expect(f.controller.session, isNull);
    },
  );

  test(
    'READY uses allocation binding; committed response loss requires fresh SMS login',
    () async {
      final f = await _FlowFixture.create();
      addTearDown(f.dispose);
      await f.host.choose();
      await f.host.upload();
      final ready = f.host.ready!;
      f.repository.failNext = true;
      expect(await f.controller.completeRegistration(_uploaded()), false);
      expect(f.controller.session, isNull);
      expect(f.controller.registrationOutcomeUnknown, true);
      expect(await f.controller.completeRegistration(_uploaded()), false);
      expect(f.repository.proofs, hasLength(1));
      for (final proof in f.repository.proofs) {
        expect(proof.requestId, ready.requestId);
        expect(proof.avatarCapability, ready.capability);
        expect(proof.challengeId, avatarChallenge);
      }
      expect(f.server.puts, 1);
      expect(f.server.allocations, 1);
      f.controller.cancelRegistration();
      await f.controller.sendSmsCode('13900000000');
      expect(
        await f.controller.signInWithSms(
          phone: '13900000000',
          smsCode: '123456',
        ),
        true,
      );
      expect(f.controller.session, isNotNull);
      expect(f.host.previewBytes, isNull);
      expect(f.controller.registrationAvatarHost, isNull);
    },
  );

  test(
    'preset can explicitly replace an uncertain upload without its capability',
    () async {
      final f = await _FlowFixture.create();
      addTearDown(f.dispose);
      f.server.losePut = true;
      await f.host.choose();
      await expectLater(f.host.upload(), throwsA(isA<ApiException>()));
      expect(f.host.ready, isNull);
      expect(
        await f.controller.completeRegistration(
          RegistrationProfile(
            nickname: '云',
            sex: 2,
            avatar: RegistrationAvatarChoice.preset('avatar-preset-cloud'),
          ),
        ),
        true,
      );
      expect(f.repository.proofs.single.avatarCapability, isNull);
      expect(f.server.puts, 1);
      expect(f.server.completes, 0);
    },
  );

  test(
    'resend invalidates same-phone upload context and cannot bind the old asset',
    () async {
      final f = await _FlowFixture.create();
      addTearDown(f.dispose);
      await f.host.choose();
      await f.host.upload();
      final old = f.host;
      await f.controller.sendSmsCode('13900000000');
      await f.controller.signInWithSms(phone: '13900000000', smsCode: '123456');
      expect(old.context.isCurrent, false);
      expect(old.previewBytes, isNull);
      expect(identical(old, f.controller.registrationAvatarHost), false);
      expect(await f.controller.completeRegistration(_uploaded()), false);
      expect(f.repository.proofs, isEmpty);
    },
  );

  test(
    'cancel during picker ignores late image and creates no upload',
    () async {
      final f = await _FlowFixture.create();
      addTearDown(f.dispose);
      f.picker.pause = Completer<void>();
      final picking = f.host.choose();
      final failed = expectLater(picking, throwsA(isA<ApiException>()));
      while (f.picker.calls == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      f.controller.cancelRegistration();
      f.picker.pause!.complete();
      await failed;
      expect(f.server.allocations, 0);
      expect(f.host.previewBytes, isNull);
      expect(f.controller.session, isNull);
    },
  );

  _flowWidgetTest(
    'page chooses previews uploads and submits the same READY avatar',
    (tester, f) async {
      await tester.pumpWidget(
        MaterialApp(home: RegistrationPage(controller: f.controller)),
      );
      await _waitUpload(tester, f.host);
      await tester.ensureVisible(
        find.byKey(const ValueKey('registration-pick-image')),
      );
      await tester.tap(find.byKey(const ValueKey('registration-pick-image')));
      await _waitUpload(tester, f.host);
      expect(f.host.ready, isNotNull);
      expect(find.text('已选择上传头像'), findsOneWidget);
      expect(find.text('头像已上传，可以完成注册'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('registration-upload-choice')),
          matching: find.byType(Image),
        ),
        findsOneWidget,
      );
      await tester.ensureVisible(find.widgetWithText(TextFormField, '昵称'));
      await tester.enterText(find.widgetWithText(TextFormField, '昵称'), '小鲸');
      await tester.ensureVisible(find.text('不公开'));
      await tester.tap(find.text('不公开'));
      await tester.tap(find.text('完成注册'));
      await tester.pumpAndSettle();
      expect(f.repository.profiles.single.avatar?.kind, 'UPLOADED');
      expect(f.repository.profiles.single.avatar?.reference, avatarTestId);
      expect(f.repository.profiles.single.birthday, isNull);
      expect(f.controller.session, isNotNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  _flowWidgetTest(
    'lost upload response recovers by explicit status check without a second PUT',
    (tester, f) async {
      f.server.losePut = true;
      await tester.pumpWidget(
        MaterialApp(home: RegistrationPage(controller: f.controller)),
      );
      await _waitUpload(tester, f.host);
      await tester.ensureVisible(
        find.byKey(const ValueKey('registration-pick-image')),
      );
      await tester.tap(find.byKey(const ValueKey('registration-pick-image')));
      await _waitUpload(tester, f.host);
      expect(f.host.ready, isNull);
      await tester.ensureVisible(find.widgetWithText(TextFormField, '昵称'));
      await tester.enterText(find.widgetWithText(TextFormField, '昵称'), '小鲸');
      await tester.ensureVisible(find.text('不公开'));
      await tester.tap(find.text('不公开'));
      await tester.tap(find.text('完成注册'));
      await tester.pump();
      expect(f.repository.proofs, isEmpty);
      expect(find.text('头像尚未确认上传完成，请先检查上传状态'), findsOneWidget);
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('检查上传状态'));
      await tester.pumpAndSettle();
      expect(find.text('检查上传状态').hitTestable(), findsOneWidget);
      final getsBeforeRecovery = f.server.gets;
      await tester.tap(find.text('检查上传状态'));
      await _waitUpload(tester, f.host);
      expect(f.server.gets, getsBeforeRecovery + 1);
      expect(f.host.ready, isNotNull);
      expect(f.server.puts, 1);
      expect(f.server.allocations, 1);
      await tester.tap(find.text('完成注册'));
      await tester.pumpAndSettle();
      expect(f.repository.proofs, hasLength(1));
      await tester.pumpWidget(const SizedBox());
    },
  );
  _flowWidgetTest(
    'invalidated challenge can remount registration without throwing',
    (tester, f) async {
      f.host.context.invalidate();
      await tester.pumpWidget(
        MaterialApp(home: RegistrationPage(controller: f.controller)),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('验证码已失效，请返回登录重新获取'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('registration-pick-image')),
        findsNothing,
      );
      expect(f.server.allocations, 0);
    },
  );

  _flowWidgetTest(
    'unknown final outcome shows login recovery instead of registering again',
    (tester, f) async {
      await tester.runAsync(() async {
        await f.host.choose();
        await f.host.upload();
        f.repository.failNext = true;
        expect(await f.controller.completeRegistration(_uploaded()), false);
      });
      await tester.pumpWidget(
        MaterialApp(home: RegistrationPage(controller: f.controller)),
      );
      await _waitUpload(tester, f.host);
      expect(find.text('完成注册'), findsNothing);
      expect(find.text('返回登录确认注册结果'), findsOneWidget);
      expect(find.text('头像已上传，可以完成注册'), findsNothing);
      await tester.tap(find.text('返回登录确认注册结果'));
      await tester.pump();
      expect(f.controller.stage, AuthFlowStage.signedOut);
      expect(f.controller.session, isNull);
      expect(f.repository.proofs, hasLength(1));
      expect(f.server.puts, 1);
    },
  );
}

Finder _previewImageFinder() => find.descendant(
  of: find.byKey(const ValueKey('registration-upload-choice')),
  matching: find.byType(Image),
);

Future<Uint8List> _previewPng(Color color) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(color, BlendMode.src);
  final picture = recorder.endRecording();
  final image = picture.toImageSync(8, 8);
  try {
    final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
    picture.dispose();
  }
}

ImageProvider _previewProvider(WidgetTester tester) =>
    tester.widget<Image>(_previewImageFinder()).image;

void _expectPreviewEvicted(ImageCache cache, Object key) {
  final status = cache.statusForKey(key);
  expect(status.pending, false, reason: 'preview must not remain pending');
  expect(status.live, false, reason: 'preview must not remain live');
  expect(status.keepAlive, false, reason: 'preview must not remain keepAlive');
}

class _PreviewDecodeGate {
  final release = Completer<void>();
  bool entered = false, completed = false;
}

class _PreviewTestBinding extends AutomatedTestWidgetsFlutterBinding {
  _PreviewDecodeGate? nextDecode;

  @override
  Future<ui.Codec> instantiateImageCodecWithSize(
    ui.ImmutableBuffer buffer, {
    ui.TargetImageSizeCallback? getTargetSize,
  }) async {
    final gate = nextDecode;
    nextDecode = null;
    final codec = await super.instantiateImageCodecWithSize(
      buffer,
      getTargetSize: getTargetSize,
    );
    return gate == null ? codec : _GatedPreviewCodec(codec, gate);
  }
}

class _GatedPreviewCodec implements ui.Codec {
  _GatedPreviewCodec(this.delegate, this.gate);
  final ui.Codec delegate;
  final _PreviewDecodeGate gate;

  @override
  int get frameCount => delegate.frameCount;
  @override
  int get repetitionCount => delegate.repetitionCount;
  @override
  void dispose() => delegate.dispose();
  @override
  Future<ui.FrameInfo> getNextFrame() async {
    // Start native decoding before pausing completion. Eviction may dispose
    // the codec while this operation is in flight; do not start native work
    // on an already disposed codec when the gate is released.
    final frame = delegate.getNextFrame();
    gate.entered = true;
    await gate.release.future;
    try {
      return await frame;
    } finally {
      gate.completed = true;
    }
  }
}

void _flowWidgetTest(
  String description,
  Future<void> Function(WidgetTester tester, _FlowFixture fixture) body,
) {
  testWidgets(description, (tester) async {
    final f = (await tester.runAsync(_FlowFixture.create))!;
    try {
      await body(tester, f);
    } finally {
      // Host cleanup futures originate in the widget's FakeAsync zone.
      // Finish them here, not in addTearDown/runAsync after that zone stops.
      await tester.pumpWidget(const SizedBox());
      var done = false;
      Object? failure;
      StackTrace? failureStack;
      final cleanup = f.dispose().then<void>(
        (_) => done = true,
        onError: (Object error, StackTrace stack) {
          failure = error;
          failureStack = stack;
          done = true;
        },
      );
      await _pumpIoUntil(tester, () => done, 'registration fixture cleanup');
      await cleanup;
      if (failure != null) {
        Error.throwWithStackTrace(failure!, failureStack!);
      }
      expect(
        await tester.runAsync(f.directory.exists),
        false,
        reason: 'real fixture directory must be removed before test completes',
      );
    }
  }, timeout: const Timeout(Duration(seconds: 30)));
}

Future<void> _pumpIoUntil(
  WidgetTester tester,
  bool Function() done,
  String phase,
) async {
  final watch = Stopwatch()..start();
  while (!done()) {
    if (watch.elapsed > const Duration(seconds: 10)) {
      fail('$phase did not finish within 10 real seconds');
    }
    // Only wait for real I/O here; resume/pump FakeAsync outside runAsync.
    // Do not fast-forward through the original SMS challenge expiry.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
}

Future<void> _waitUpload(
  WidgetTester tester,
  RegistrationAvatarHost host,
) async {
  await _pumpIoUntil(tester, () => !host.busy, 'registration avatar operation');
  await tester.pumpAndSettle();
}

class _FlowFixture {
  _FlowFixture(
    this.directory,
    this.repository,
    this.store,
    this.manager,
    this.picker,
  );
  final Directory directory;
  final _RegistrationRepository repository;
  final AvatarStore store;
  final AuthSessionManager manager;
  final AvatarPicker picker;
  late final AuthController controller;
  late final AvatarServer server;
  late final RegistrationAvatarHost host;
  final hosts = <RegistrationAvatarHost>[];
  static Future<_FlowFixture> create() async {
    final directory = await Directory.systemTemp.createTemp(
      'r01-registration-flow-',
    );
    final file = File('${directory.path}/source.png');
    // UI tests need a genuinely decodable image, not just protocol bytes.
    final png = await _previewPng(Colors.purple);
    await file.writeAsBytes(png);
    final f = _FlowFixture(
      directory,
      _RegistrationRepository(),
      AvatarStore(),
      AuthSessionManager(MemoryKeyValueStore()),
      AvatarPicker([XFile(file.path)]),
    );
    f.server = _FlowAvatarServer(f.repository.expiresAt, png.length);
    f.controller = AuthController(
      repository: f.repository,
      sessionManager: f.manager,
      deviceIdentityProvider: DeviceIdentityProvider(
        environment: AppEnvironment.mock(),
        sessionManager: f.manager,
      ),
      registrationAvatarClientId: 'public-client',
      registrationAvatarFactory: (context) {
        final host = RegistrationAvatarHost(
          context: context,
          transport: ApiRegistrationAvatarTransport(f.server.api()),
          store: f.store,
          picker: f.picker,
          temporaryParent: () async => directory,
        );
        f.hosts.add(host);
        return host;
      },
    );
    await f.controller.acceptConsent();
    await f.controller.sendSmsCode('13900000000');
    expect(
      await f.controller.signInWithSms(phone: '13900000000', smsCode: '123456'),
      true,
    );
    f.host = f.controller.registrationAvatarHost!;
    return f;
  }

  Future<void> dispose() async {
    controller.dispose();
    manager.dispose();
    for (final host in hosts) {
      await host.cleanup;
    }
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}

class _FlowAvatarServer extends AvatarServer {
  _FlowAvatarServer(super.expiresAt, this.imageBytes);
  final int imageBytes;

  @override
  Map<String, Object?> projection() {
    final data = super.projection();
    if (data['bytes'] != null) data['bytes'] = imageBytes;
    return data;
  }
}

class _RegistrationRepository extends MockAuthRepository {
  final expiresAt = DateTime.now().toUtc().add(const Duration(minutes: 4));
  final proofs = <RegistrationProof>[];
  final profiles = <RegistrationProfile>[];
  bool failNext = false;
  bool registered = false;
  @override
  Future<SmsChallenge> sendSmsCode({
    required String phone,
    required ClientDevice device,
  }) async => SmsChallenge(
    challengeId: avatarChallenge,
    expiresAt: expiresAt,
    retryAfter: 60,
  );
  @override
  Future<AuthOutcome> signInWithSms({
    required String phone,
    required String smsCode,
    required ClientDevice device,
  }) async => registered
      ? AuthOutcome.authenticated(_session(phone, device))
      : const AuthOutcome.registrationRequired();
  @override
  Future<AuthSession> registerWithSms({
    required String phone,
    required String smsCode,
    required ClientDevice device,
    required RegistrationProfile profile,
    RegistrationProof? proof,
  }) async {
    proof!.validate(profile.avatar!);
    proofs.add(proof);
    profiles.add(profile);
    if (failNext) {
      failNext = false;
      registered = true;
      throw const ApiException(
        kind: ApiFailureKind.timeout,
        message: 'unconfirmed',
      );
    }
    registered = true;
    return _session(phone, device);
  }

  AuthSession _session(String phone, ClientDevice device) => AuthSession(
    accessToken: 'test-access',
    tokenType: 'Bearer',
    expiresAt: DateTime.now().add(const Duration(hours: 1)),
    refreshToken: 'test-refresh',
    refreshExpiresAt: DateTime.now().add(const Duration(days: 1)),
    deviceId: device.deviceId,
    clientId: 'public-client',
    userId: 10001,
    mobile: phone,
    roles: 'USER',
  );
}
