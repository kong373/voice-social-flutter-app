import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/features/account/data/auth_session_manager.dart';
import 'package:voice_social_app/core/media/media_models.dart';
import 'package:voice_social_app/features/media/app_image_media_host.dart';
import 'package:voice_social_app/features/room/data/backend_room_lifecycle_repository.dart';
import 'package:voice_social_app/features/room/data/room_lease_binding.dart';
import 'package:voice_social_app/features/room/presentation/edit_room_page.dart';
import 'package:voice_social_app/features/room/presentation/room_cover_artwork.dart';
import 'package:voice_social_app/features/room/presentation/room_image_editor.dart';
import 'package:voice_social_app/features/room/application/room_controller.dart';
import 'package:voice_social_app/features/room/data/mock_room_repository.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/domain/room_operations_repository.dart';
import 'package:voice_social_app/features/room/infrastructure/rtc_adapter.dart';
import 'package:voice_social_app/features/room/infrastructure/room_realtime_gateway.dart';
import 'package:voice_social_app/features/room/presentation/video_runtime_room_page.dart';
import 'support/media_http_fakes.dart';
import 'manager_room_profile_test.dart' show profileWire, profileRoomId;
import 'room_lease_contract_fixture.dart';
import 's13_image_host_test.dart'
    show TestImageSelection, hostStatus, hostAsset;

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a/p8AAAAASUVORK5CYII=',
);
Map<String, Object?> _media(String purpose) => {
  'assetId': hostAsset,
  'purpose': purpose,
  'mediaType': 'image/png',
  'bytes': _png.length,
  'durationMillis': 0,
  'version': 2,
};

class _Dependencies implements AppDependencies {
  _Dependencies(this.base, this.imageMediaHost);
  final AppDependencies base;
  @override
  final AppImageMediaHost imageMediaHost;
  @override
  AuthSessionManager get sessionManager => base.sessionManager;
  @override
  RoomOperationsRepository get roomOperationsRepository =>
      base.roomOperationsRepository;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _BackgroundRoom extends MockRoomRepository {
  @override
  Future<RoomSnapshot> enterRoom({
    required String roomId,
    required String? password,
    required RoomEntrySource source,
    required int currentUserId,
  }) async => RoomSnapshot(
    roomId: roomId,
    roomCode: '12345',
    title: '关闭房间背景',
    topic: '',
    ownerId: currentUserId,
    role: RoomRole.owner,
    seats: const [],
    rtc: const RtcCredentials(token: '', channelId: ''),
    publicScreenEnabled: false,
    pictureMessagesAllowed: false,
    autoLockMic: false,
    giftCatalogAvailable: false,
    giftBalance: null,
    transportMode: RoomTransportMode.snapshotOnly,
    ownerClosedAccess: true,
    closedRoomAccess: true,
    canControlRoomLifecycle: true,
    version: 2,
    backgroundMedia: MediaReference.fromJson(_media('ROOM_BACKGROUND')),
  );
}

class _ReconnectingBackgroundRoom extends MockRoomRepository {
  final snapshot = RoomSnapshot(
    roomId: profileRoomId,
    roomCode: '12345',
    title: '可重连背景',
    topic: '',
    ownerId: 1,
    role: RoomRole.owner,
    seats: const [],
    rtc: const RtcCredentials(token: '', channelId: ''),
    publicScreenEnabled: false,
    pictureMessagesAllowed: false,
    autoLockMic: false,
    giftCatalogAvailable: false,
    giftBalance: null,
    transportMode: RoomTransportMode.snapshotOnly,
    sessionId: roomLeaseSessionId,
    roomLease: parseRoomLease(
      roomLeaseWireFixture(),
      sessionId: roomLeaseSessionId,
    ),
    backgroundMedia: MediaReference.fromJson(_media('ROOM_BACKGROUND')),
  );
  final reconnectResult = Completer<RoomSnapshot>();

  @override
  Future<RoomSnapshot> enterRoom({
    required String roomId,
    required String? password,
    required RoomEntrySource source,
    required int currentUserId,
  }) async => snapshot;

  @override
  Future<RoomSnapshot> reconnectRoom({
    required String roomId,
    required int currentUserId,
  }) => reconnectResult.future;

  @override
  Future<List<RoomMessage>> fetchPublicMessages(String roomId) async => [];

  @override
  Future<void> exitRoom(String roomId) async {}
}

void main() {
  late TestMediaIdentity identity;
  late Directory temp;
  late MediaFakeHttp http;
  late AppImageMediaHost host;
  late RoomLeaseBinding lease;
  late BackendRoomLifecycleRepository repo;
  late _Dependencies deps;
  late Map<String, Object?> profile;
  late FutureOr<HttpClientResponse> Function(MediaFakeRequest) readContent;
  int? patchFailure;
  String purpose = 'ROOM_COVER';
  final writes = <MediaFakeRequest>[];

  Future<void> setup(WidgetTester tester) async {
    identity = TestMediaIdentity();
    temp = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('room-image-pages-'),
    ))!;
    writes.clear();
    patchFailure = null;
    profile = {
      ...profileWire(owner: false),
      'coverMedia': null,
      'backgroundMedia': null,
    };
    readContent = (_) => MediaFakeResponse(
      200,
      Stream.value(_png),
      type: 'image/png',
      contentLength: _png.length,
    );
    http = MediaFakeHttp((r) {
      if (r.method == 'PATCH') {
        writes.add(r);
        if (patchFailure == 0)
          throw const SocketException('lost save response');
        if (patchFailure != null)
          return MediaFakeResponse.json(null, status: 409, code: patchFailure!);
        final body = jsonDecode(utf8.decode(r.body)) as Map<String, dynamic>;
        profile = {
          ...profile,
          ...body,
          'version': (body['expectedVersion'] as int) + 1,
        };
        for (final (input, output, p) in [
          ('coverAssetId', 'coverMedia', 'ROOM_COVER'),
          ('backgroundAssetId', 'backgroundMedia', 'ROOM_BACKGROUND'),
        ]) {
          if (body.containsKey(input))
            profile[output] = body[input] == null ? null : _media(p);
        }
        return MediaFakeResponse.json({
          ...profile,
          'rtcStatus': 'DISABLED',
          'imStatus': 'DISABLED',
          'providerInvocation': false,
        });
      }
      if (r.uri.path.endsWith('/editable-profile'))
        return MediaFakeResponse.json(profile);
      if (r.uri.path == '/app-api/media/v1/assets') {
        purpose = (jsonDecode(utf8.decode(r.body)) as Map)['purpose'] as String;
        return MediaFakeResponse.json(
          hostStatus('ALLOCATED', 0, purpose: purpose),
        );
      }
      if (r.method == 'PUT')
        return MediaFakeResponse.json(
          hostStatus('UPLOADING', 1, purpose: purpose, bytes: _png.length),
        );
      if (r.uri.path.endsWith('/complete'))
        return MediaFakeResponse.json(
          hostStatus('READY', 2, purpose: purpose, bytes: _png.length),
        );
      if (r.uri.path.endsWith('/content')) return readContent(r);
      throw StateError('Unexpected ${r.method} ${r.uri.path}');
    });
    final picker = TestImageSelection()
      ..files = [XFile.fromData(_png, name: 'photo.png')];
    host = AppImageMediaHost(
      api: http.api(identity),
      userId: () => identity.user,
      generation: () => identity.generation,
      changes: identity,
      picker: picker,
      temporaryParent: () async => temp,
    );
    lease = RoomLeaseBinding(
      authenticationGeneration: () => identity.generation,
    );
    lease.bind(
      lease.beginEntry('room'),
      profileRoomId,
      1,
      parseRoomLease(roomLeaseWireFixture(), sessionId: roomLeaseSessionId),
    );
    repo = BackendRoomLifecycleRepository(
      apiClient: http.api(identity),
      leaseBinding: lease,
    );
    deps = _Dependencies(AppDependencies.mock(), host);
  }

  Future<void> waitFor(
    WidgetTester tester,
    bool Function() reached,
    String reason,
  ) async {
    for (var i = 0; i < 150 && !reached(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(reached(), isTrue, reason: reason);
  }

  void imageTest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      await setup(tester);
      try {
        await body(tester);
      } finally {
        await tester.pumpWidget(const SizedBox());
        host.dispose();
        bool cleaned = false;
        final cleanup = host.cleanup.then((_) => cleaned = true);
        await waitFor(tester, () => cleaned, 'owned image cleanup terminates');
        await cleanup;
        await tester.runAsync(() async {
          if (await temp.exists()) await temp.delete(recursive: true);
        });
        deps.base.dispose();
        identity.dispose();
        lease.dispose();
      }
    });
  }

  Future<void> mount(WidgetTester tester, [Widget? page]) async {
    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: deps,
        child: MaterialApp(
          home:
              page ??
              EditRoomPage(roomId: profileRoomId, repositoryOverride: repo),
        ),
      ),
    );
    if (page == null)
      await waitFor(
        tester,
        () => find
            .byKey(const Key('edit-room-save-button'))
            .evaluate()
            .isNotEmpty,
        'HTTP profile loads editable form',
      );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    if (finder.evaluate().isEmpty)
      await tester.scrollUntilVisible(
        finder,
        280,
        scrollable: find.byType(Scrollable).first,
      );
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pump();
  }

  Future<void> chooseAndUpload(WidgetTester tester) async {
    await tap(tester, find.text('选择封面'));
    await waitFor(
      tester,
      () => host
          .draft('room:$profileRoomId:cover', MediaPurpose.roomCover)
          .images
          .isNotEmpty,
      'native selection captured',
    );
    final save = tester.widget<FilledButton>(
      find.byKey(const Key('edit-room-save-button')),
    );
    expect(save.onPressed, isNull, reason: 'non READY selection cannot save');
    await tap(tester, find.text('上传封面'));
    await waitFor(
      tester,
      () =>
          host
              .draft('room:$profileRoomId:cover', MediaPurpose.roomCover)
              .images
              .single
              .status
              ?.state ==
          MediaAssetState.ready,
      'upload completes READY',
    );
    await waitFor(
      tester,
      () => tester
          .widgetList<Image>(find.byType(Image))
          .any((w) => w.image is FileImage),
      'controlled preview displays file',
    );
  }

  imageTest(
    'real manager editor: picker -> READY -> ID-only PATCH, null clear, no lifecycle authority',
    (tester) async {
      profile['backgroundMedia'] = _media('ROOM_BACKGROUND');
      await mount(tester);
      await chooseAndUpload(tester);
      await tap(tester, find.text('清除背景'));
      expect(find.text('保存后清除背景'), findsOneWidget);
      expect(find.byKey(const Key('edit-room-close-button')), findsNothing);
      expect(find.byKey(const Key('edit-room-reopen-button')), findsNothing);
      await tap(tester, find.byKey(const Key('edit-room-save-button')));
      await waitFor(
        tester,
        () =>
            writes.length == 1 && repo.pendingImageSave(profileRoomId) == null,
        'save and authority reread finish',
      );
      await tester.pumpAndSettle();
      expect(writes, hasLength(1));
      final body = jsonDecode(utf8.decode(writes.single.body)) as Map;
      expect(body['coverAssetId'], hostAsset);
      expect(body.containsKey('backgroundAssetId'), isTrue);
      expect(body['backgroundAssetId'], isNull);
      expect(body['sessionId'], roomLeaseSessionId);
      expect(body['expectedVersion'], 2);
      expect(body.keys, isNot(contains('coverMedia')));
      expect(body.keys, isNot(contains('hallVisible')));
      expect(profile['status'], 'OPEN');
      expect(http.requests.where((r) => r.method == 'PUT'), hasLength(1));
      final allocation = http.requests.singleWhere(
        (r) => r.uri.path == '/app-api/media/v1/assets',
      );
      expect(jsonDecode(utf8.decode(allocation.body)), {
        'purpose': 'ROOM_COVER',
      });
      expect(writes.single.headers.value('X-Request-Id'), isNotEmpty);
    },
  );

  imageTest(
    'unknown PATCH remount retains exact key/body and READY asset without reupload',
    (tester) async {
      await mount(tester);
      await chooseAndUpload(tester);
      patchFailure = 0;
      await tap(tester, find.byKey(const Key('edit-room-save-button')));
      await waitFor(
        tester,
        () => find.text('重试原保存请求').evaluate().isNotEmpty,
        'unknown result exposed',
      );
      await tester.pumpAndSettle();
      expect(find.text('重试原保存请求'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await mount(tester);
      expect(find.text('重试原保存请求'), findsOneWidget);
      expect(
        writes,
        hasLength(1),
        reason: 'remount must not POST automatically',
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('room-ROOM_COVER-pick')),
        280,
        scrollable: find.byType(Scrollable).first,
      );
      final button = tester.widget<OutlinedButton>(
        find.byKey(const ValueKey('room-ROOM_COVER-pick')),
      );
      expect(button.onPressed, isNull);
      patchFailure = null;
      await tap(tester, find.byKey(const Key('edit-room-save-button')));
      await waitFor(
        tester,
        () =>
            writes.length == 2 && repo.pendingImageSave(profileRoomId) == null,
        'original save recovery finishes',
      );
      await tester.pumpAndSettle();
      expect(writes, hasLength(2));
      expect(writes[1].body, writes[0].body);
      expect(
        writes[1].headers.value('X-Request-Id'),
        writes[0].headers.value('X-Request-Id'),
      );
      expect(http.requests.where((r) => r.method == 'PUT'), hasLength(1));
      expect(repo.pendingImageSave(profileRoomId), isNull);
    },
  );

  imageTest(
    'version conflict refresh never automatically saves image or changes old lease',
    (tester) async {
      await mount(tester);
      await chooseAndUpload(tester);
      patchFailure = 40945;
      profile['version'] = 5;
      await tap(tester, find.byKey(const Key('edit-room-save-button')));
      await waitFor(
        tester,
        () =>
            tester
                .widget<FilledButton>(
                  find.byKey(const Key('edit-room-save-button')),
                )
                .onPressed !=
            null,
        'conflict authority reread restores explicit confirmation',
      );
      await tester.drag(find.byType(ListView).first, const Offset(0, 2000));
      await tester.pumpAndSettle();
      expect(writes, hasLength(1));
      expect(find.text('内容已更新，请重新确认后提交'), findsOneWidget);
      expect(find.text('最新版本 5'), findsOneWidget);
      patchFailure = null;
      await tap(tester, find.byKey(const Key('edit-room-save-button')));
      await waitFor(
        tester,
        () =>
            writes.length == 2 && repo.pendingImageSave(profileRoomId) == null,
        'confirmed new-version save finishes',
      );
      await tester.pumpAndSettle();
      expect(writes, hasLength(2));
      final second = jsonDecode(utf8.decode(writes[1].body)) as Map;
      expect(second['expectedVersion'], 5);
      expect(second['coverAssetId'], hostAsset);
      expect(second['sessionId'], roomLeaseSessionId);
      expect(
        writes[1].headers.value('X-Request-Id'),
        isNot(writes[0].headers.value('X-Request-Id')),
      );
      expect(http.requests.where((r) => r.method == 'PUT'), hasLength(1));
    },
  );

  for (final change in ['lease', 'ABA']) {
    imageTest(
      '$change removes visible controlled image and editor; late GET cannot restore it',
      (tester) async {
        final gate = Completer<HttpClientResponse>();
        int gets = 0;
        readContent = (_) {
          gets++;
          return gate.future;
        };
        profile['backgroundMedia'] = _media('ROOM_BACKGROUND');
        await mount(tester);
        await tester.scrollUntilVisible(
          find.text('清除背景'),
          280,
          scrollable: find.byType(Scrollable).first,
        );
        await waitFor(
          tester,
          () => gets == 1,
          'GET really reached transport before invalidation',
        );
        if (change == 'lease') {
          lease.beginEntry('different-room');
        } else {
          identity.change(2);
          identity.change(1);
        }
        await tester.pump();
        gate.complete(
          MediaFakeResponse(
            200,
            Stream.value(_png),
            type: 'image/png',
            contentLength: _png.length,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(RoomImageEditor), findsNothing);
        expect(find.byType(TextFormField), findsNothing);
        expect(
          tester
              .widgetList<Image>(find.byType(Image))
              .where((w) => w.image is FileImage),
          isEmpty,
        );
        expect(
          http.requests
              .singleWhere((r) => r.uri.path.endsWith('/content'))
              .aborted,
          isTrue,
        );
        expect(writes, isEmpty);
        await waitFor(
          tester,
          () => temp.listSync().isEmpty,
          'aborted controlled download cleans its owned directory',
        );
        expect(
          await tester.runAsync(
            () async => (await temp.list().toList()).isEmpty,
          ),
          isTrue,
        );
      },
    );
  }

  imageTest(
    'controlled cover uses fixed backend path, permission retry, cache eviction on ABA',
    (tester) async {
      bool denied = true;
      readContent = (_) => denied
          ? MediaFakeResponse.json(null, status: 403, code: 40352)
          : MediaFakeResponse(
              200,
              Stream.value(_png),
              type: 'image/png',
              contentLength: _png.length,
            );
      await mount(
        tester,
        Scaffold(
          body: RoomCoverArtwork(
            roomId: profileRoomId,
            media: MediaReference.fromJson(_media('ROOM_COVER')),
            seed: 'test',
            height: 200,
          ),
        ),
      );
      await waitFor(
        tester,
        () => find.text('重试图片').evaluate().isNotEmpty,
        '403 renders bounded retry',
      );
      denied = false;
      await tap(tester, find.text('重试图片'));
      await waitFor(
        tester,
        () => tester
            .widgetList<Image>(find.byType(Image))
            .any((w) => w.image is FileImage),
        '200 displays controlled cover',
      );
      final provider = tester
          .widgetList<Image>(find.byType(Image))
          .map((w) => w.image)
          .whereType<FileImage>()
          .single;
      final downloadedPath = provider.file.path;
      expect(File(downloadedPath).existsSync(), isTrue);
      expect(http.requests, hasLength(2));
      for (final request in http.requests) {
        expect(
          request.uri.toString(),
          'https://configured.backend.test/app-api/media/v1/assets/$hostAsset/content',
        );
        expect(request.headers.value('authorization'), 'Bearer contract-A-old');
        expect(request.followRedirects, isFalse);
      }
      identity.change(2);
      identity.change(1);
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<Image>(find.byType(Image))
            .where((w) => w.image is FileImage),
        isEmpty,
      );
      await waitFor(
        tester,
        () => !File(downloadedPath).existsSync(),
        'downloaded bytes removed on identity ABA',
      );
      expect(
        PaintingBinding.instance.imageCache.containsKey(provider),
        isFalse,
      );
      expect(
        http.requests,
        hasLength(2),
        reason: 'stale card must not fetch as B or renewed A',
      );
    },
  );

  for (final initialRead in ['displayed', 'pending']) {
    imageTest(
      'same-lease reconnect replaces $initialRead background scope and rejects old completion',
      (tester) async {
        final oldContent = Completer<HttpClientResponse>();
        var gets = 0;
        HttpClientResponse content() => MediaFakeResponse(
          200,
          Stream.value(_png),
          type: 'image/png',
          contentLength: _png.length,
        );
        readContent = (_) {
          gets++;
          return gets == 1 && initialRead == 'pending'
              ? oldContent.future
              : content();
        };
        final repository = _ReconnectingBackgroundRoom();
        final rtc = MockRtcAdapter();
        final realtime = MockRoomRealtimeGateway();
        final controller = RoomController(
          roomId: profileRoomId,
          title: '可重连背景',
          currentUserId: 1,
          accessToken: 'fixture',
          repository: repository,
          rtcAdapter: rtc,
          realtimeGateway: realtime,
          sessionChanges: identity,
          activeUserId: () => identity.user,
          identityGeneration: () => identity.generation,
        );
        final images = find.byWidgetPredicate(
          (widget) => widget is Image && widget.image is FileImage,
        );
        try {
          await mount(tester, VideoRuntimeRoomPage(controller: controller));
          await waitFor(tester, () => gets == 1, 'initial background GET');
          FileImage? previous;
          if (initialRead == 'displayed') {
            await waitFor(
              tester,
              () => images.evaluate().isNotEmpty,
              'first image',
            );
            previous = tester.widget<Image>(images).image as FileImage;
          }
          final reconnect = controller.reconnect();
          expect(controller.status, RoomSessionStatus.reconnecting);
          if (initialRead == 'displayed') {
            await tester.pump();
            expect(images, findsNothing);
            await waitFor(
              tester,
              () => !previous!.file.existsSync(),
              'old file removed',
            );
            expect(
              PaintingBinding.instance.imageCache.containsKey(previous!),
              isFalse,
            );
          }
          // The pending variant completes both status transitions before a
          // frame: rebuilding only on the final joined value is insufficient.
          repository.reconnectResult.complete(repository.snapshot);
          await reconnect;
          expect(controller.status, RoomSessionStatus.joined);
          expect(controller.snapshot!.sessionId, roomLeaseSessionId);
          await tester.pump();
          await waitFor(
            tester,
            () => gets == 2,
            'fresh background GET after reconnect',
          );
          await waitFor(
            tester,
            () => images.evaluate().isNotEmpty,
            'fresh background displayed',
          );
          final fresh = tester.widget<Image>(images).image as FileImage;
          if (previous != null)
            expect(fresh.file.path, isNot(previous.file.path));
          if (initialRead == 'pending') {
            expect(http.requests.first.aborted, isTrue);
            oldContent.complete(content());
            await tester.pumpAndSettle();
            expect(tester.widget<Image>(images).image, same(fresh));
          }
          expect(gets, 2);
          expect(http.requests.every((r) => r.method == 'GET'), isTrue);
          expect(writes, isEmpty);
          expect(rtc.joined, isFalse);
        } finally {
          if (!oldContent.isCompleted) oldContent.complete(content());
          await tester.pumpWidget(const SizedBox());
          controller.dispose();
          await realtime.dispose();
        }
      },
    );
  }

  for (final invalidation in ['ABA', 'lease', 'leave']) {
    imageTest(
      'background reconnect cannot recover across $invalidation or accept old GET',
      (tester) async {
        final oldContent = Completer<HttpClientResponse>();
        readContent = (_) => oldContent.future;
        final repository = _ReconnectingBackgroundRoom();
        final realtime = MockRoomRealtimeGateway();
        final controller = RoomController(
          roomId: profileRoomId,
          title: '可重连背景',
          currentUserId: 1,
          accessToken: 'fixture',
          repository: repository,
          rtcAdapter: MockRtcAdapter(),
          realtimeGateway: realtime,
          sessionChanges: identity,
          activeUserId: () => identity.user,
          identityGeneration: () => identity.generation,
        );
        try {
          await mount(tester, VideoRuntimeRoomPage(controller: controller));
          await waitFor(
            tester,
            () => http.requests.length == 1,
            'pending old GET',
          );
          final reconnect = controller.reconnect();
          expect(controller.status, RoomSessionStatus.reconnecting);
          var response = repository.snapshot;
          if (invalidation == 'ABA') {
            identity.change(2);
            identity.change(1);
          } else if (invalidation == 'leave') {
            await controller.leaveRoom();
          } else {
            const next = '11111111-1111-4111-8111-111111111112';
            response = response.copyWith(
              sessionId: next,
              roomLease: parseRoomLease(
                roomLeaseWireFixture(sessionId: next),
                sessionId: next,
              ),
            );
          }
          repository.reconnectResult.complete(response);
          await reconnect;
          oldContent.complete(
            MediaFakeResponse(
              200,
              Stream.value(_png),
              type: 'image/png',
              contentLength: _png.length,
            ),
          );
          await tester.pumpAndSettle();
          expect(controller.status, isNot(RoomSessionStatus.joined));
          expect(http.requests, hasLength(1));
          expect(http.requests.single.aborted, isTrue);
          expect(
            tester
                .widgetList<Image>(find.byType(Image))
                .where((w) => w.image is FileImage),
            isEmpty,
          );
          await waitFor(
            tester,
            () => temp.listSync().isEmpty,
            'old scope cleanup',
          );
          expect(writes, isEmpty);
        } finally {
          await tester.pumpWidget(const SizedBox());
          controller.dispose();
          await realtime.dispose();
        }
      },
    );
  }

  imageTest(
    'actual closed-owner room displays controlled background without membership, RTC, or IM; exit clears it',
    (tester) async {
      final rtc = MockRtcAdapter();
      final realtime = MockRoomRealtimeGateway();
      final controller = RoomController(
        roomId: profileRoomId,
        title: '关闭房间背景',
        currentUserId: 1,
        accessToken: 'fixture',
        repository: _BackgroundRoom(),
        rtcAdapter: rtc,
        realtimeGateway: realtime,
        sessionChanges: identity,
        activeUserId: () => identity.user,
        identityGeneration: () => identity.generation,
      );
      try {
        await mount(tester, VideoRuntimeRoomPage(controller: controller));
        await waitFor(
          tester,
          () => tester
              .widgetList<Image>(find.byType(Image))
              .any((w) => w.image is FileImage),
          'actual room background paints controlled file',
        );
        expect(controller.snapshot!.isClosedManagementView, isTrue);
        expect(controller.snapshot!.roomLease, isNull);
        expect(controller.snapshot!.sessionId, isNull);
        expect(rtc.joined, isFalse);
        expect(find.byKey(const Key('video-room-seat-grid')), findsNothing);
        expect(find.byKey(const Key('video-room-public-screen')), findsNothing);
        expect(http.requests.single.method, 'GET');
        final path = tester
            .widgetList<Image>(find.byType(Image))
            .map((w) => w.image)
            .whereType<FileImage>()
            .single
            .file
            .path;
        await controller.leaveRoom();
        await tester.pump();
        await waitFor(
          tester,
          () => !File(path).existsSync(),
          'room exit deletes background file',
        );
        expect(
          tester
              .widgetList<Image>(find.byType(Image))
              .where((w) => w.image is FileImage),
          isEmpty,
        );
        expect(writes, isEmpty);
      } finally {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        await realtime.dispose();
      }
    },
  );
}
