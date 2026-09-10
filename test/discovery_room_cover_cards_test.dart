import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/design_system/runtime_surfaces.dart';
import 'package:voice_social_app/core/media/media_models.dart';
import 'package:voice_social_app/features/discovery/data/mock_discovery_repository.dart';
import 'package:voice_social_app/features/discovery/domain/discovery_models.dart';
import 'package:voice_social_app/features/discovery/home_page.dart';
import 'package:voice_social_app/features/discovery/presentation/saved_rooms_page.dart';
import 'package:voice_social_app/features/discovery/presentation/search_results_page.dart';
import 'package:voice_social_app/features/media/app_image_media_host.dart';
import 'package:voice_social_app/features/media/native_image_selection.dart';
import 'package:voice_social_app/features/room/presentation/room_cover_artwork.dart';
import 'package:voice_social_app/features/shell/video_runtime_pages.dart';

import 'support/media_http_fakes.dart';

void main() {
  for (final surface in _Surface.values) {
    for (final hasCover in [true, false]) {
      testWidgets(
        '${surface.name} passes room identity and ${hasCover ? 'cover' : 'null cover'} to controlled artwork',
        (tester) async {
          final rooms = [
            _room(1, hasCover: hasCover),
            _room(2, hasCover: hasCover, isClosed: true),
          ];
          final repository = _RoomsRepository(rooms);
          final opened = <DiscoveryRoom>[];
          await _pump(tester, surface, repository, onOpenRoom: opened.add);

          _expectRoomArt(tester, rooms);
          expect(find.text(rooms.first.title), findsWidgets);

          if (surface == _Surface.videoHome) {
            final hero = find.byWidgetPredicate(
              (widget) =>
                  widget is RoomCoverArtwork && widget.seed == 'hero-main',
            );
            expect(hero, findsOneWidget);
            final artwork = tester.widget<RoomCoverArtwork>(hero);
            expect(artwork.roomId, rooms.first.id);
            expect(artwork.height, 104);
            expect(artwork.borderRadius, BorderRadius.circular(19));

            // A separate room poster must not accidentally reuse hero media.
            final poster = find.descendant(
              of: find.byKey(Key('live-room-${rooms.last.id}')),
              matching: find.byType(RoomCoverArtwork),
            );
            expect(poster, findsOneWidget);
            expect(
              tester.widget<RoomCoverArtwork>(poster).roomId,
              rooms.last.id,
            );
            expect(
              tester.widget<RoomCoverArtwork>(poster).media,
              same(rooms.last.coverMedia),
            );
            await tester.tapAt(
              tester.getCenter(
                find.descendant(
                  of: hero,
                  matching: find.text(rooms.first.title),
                ),
              ),
            );
            expect(opened, [same(rooms.first)]);
            for (final seed in ['hero-date', 'hero-friends']) {
              expect(
                find.byWidgetPredicate(
                  (widget) =>
                      widget is OriginalRoomArtwork && widget.seed == seed,
                ),
                findsOneWidget,
              );
            }
          } else if (surface == _Surface.home) {
            final artwork = tester.widget<RoomCoverArtwork>(
              find.byType(RoomCoverArtwork),
            );
            expect(artwork.height, 280);
            expect(artwork.borderRadius, BorderRadius.circular(28));
          } else if (surface == _Surface.search) {
            expect(find.byType(RoomCoverArtwork), findsNWidgets(2));
            expect(find.text('已关闭'), findsOneWidget);
          } else {
            expect(find.byType(RoomCoverArtwork), findsOneWidget);
            expect(find.text('取消收藏'), findsOneWidget);
            await tester.tap(find.text('我的房间'));
            await tester.pumpAndSettle();
            _expectRoomArt(tester, [rooms.last]);
            expect(find.text(rooms.last.title), findsOneWidget);
            expect(find.text('已关闭'), findsOneWidget);
            expect(find.text('管理'), findsOneWidget);
            expect(find.text('进入房间'), findsOneWidget);
          }

          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('actual hero retries denied cover without entering room', (
    tester,
  ) async {
    final bytes = (await tester.runAsync(
      () => File('assets/runtime/room-cover-ruby.png').readAsBytes(),
    ))!;
    final temp = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('room-hero-retry-'),
    ))!;
    final identity = TestMediaIdentity();
    addTearDown(() async {
      identity.dispose();
      await tester.runAsync(() => temp.delete(recursive: true));
    });
    var denied = true;
    final http = MediaFakeHttp(
      (_) => denied
          ? MediaFakeResponse.json(null, status: 403, code: 40352)
          : MediaFakeResponse(
              200,
              Stream.value(bytes),
              type: 'image/png',
              contentLength: bytes.length,
            ),
    );
    final host = AppImageMediaHost(
      api: http.api(identity),
      userId: () => identity.user,
      generation: () => identity.generation,
      changes: identity,
      picker: _NoImageSelection(),
      temporaryParent: () async => temp,
    );
    final room = _room(1, mediaBytes: bytes.length);
    final opened = <DiscoveryRoom>[];
    await _pump(
      tester,
      _Surface.videoHome,
      _RoomsRepository([room]),
      imageMediaHost: host,
      onOpenRoom: opened.add,
    );
    final hero = find.byWidgetPredicate(
      (w) => w is RoomCoverArtwork && w.seed == 'hero-main',
    );
    final retry = find.descendant(of: hero, matching: find.text('重试图片'));
    await _until(tester, () => retry.evaluate().isNotEmpty);
    final previousGets = http.requests.length;
    denied = false;
    // Hit testing, not invoking the callback: the old overlay enters the room.
    await tester.tap(retry);
    await tester.pump();
    expect(opened, isEmpty, reason: 'image retry must not invoke room entry');
    final image = find.descendant(
      of: hero,
      matching: find.byWidgetPredicate(
        (w) => w is Image && w.image is FileImage,
      ),
    );
    await _until(tester, () => image.evaluate().isNotEmpty);
    expect(http.requests.length, previousGets + 1);
    expect(http.requests.every((r) => r.method == 'GET'), isTrue);
    // The title is deliberately IgnorePointer decoration. Touch its location
    // and assert that the outer card still receives the gesture.
    await tester.tapAt(
      tester.getCenter(
        find.descendant(of: hero, matching: find.text(room.title)),
      ),
    );
    expect(opened, [same(room)], reason: 'ordinary hero tap still opens room');
    expect(tester.takeException(), isNull);
  });

  testWidgets('saved-room refresh replaces and clears media on the same room', (
    tester,
  ) async {
    final initial = _room(1);
    final repository = _RoomsRepository([initial, _room(2)]);
    await _pump(tester, _Surface.saved, repository);
    _expectRoomArt(tester, [initial]);

    for (final room in [
      _room(1, coverRevision: 2),
      _room(1, hasCover: false),
    ]) {
      repository.favorites = [room];
      await tester.tap(find.byTooltip('刷新'));
      await tester.pumpAndSettle();
      expect(find.byType(RoomCoverArtwork), findsOneWidget);
      _expectRoomArt(tester, [room]);
      expect(find.text(room.title), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'card reads descriptor through authenticated content and clears on logout',
    (tester) async {
      final bytes = (await tester.runAsync(
        () => File('assets/runtime/room-cover-ruby.png').readAsBytes(),
      ))!;
      final temp = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('discovery-room-cover-test-'),
      ))!;
      final identity = TestMediaIdentity();
      addTearDown(() async {
        identity.dispose();
        await tester.runAsync(() => temp.delete(recursive: true));
      });
      final room = _room(1, mediaBytes: bytes.length);
      final http = MediaFakeHttp((_) {
        final response = MediaFakeResponse(
          200,
          Stream.value(bytes),
          type: 'image/png',
          contentLength: bytes.length,
        );
        response.headers.set('Cache-Control', 'private, no-store');
        return response;
      });
      final host = AppImageMediaHost(
        api: http.api(identity),
        userId: () => identity.user,
        generation: () => identity.generation,
        changes: identity,
        picker: _NoImageSelection(),
        temporaryParent: () async => temp,
      );
      await _pump(
        tester,
        _Surface.saved,
        _RoomsRepository([room, _room(2)]),
        imageMediaHost: host,
      );
      final fileImage = find.byWidgetPredicate(
        (widget) => widget is Image && widget.image is FileImage,
      );
      await _until(tester, () {
        if (fileImage.evaluate().length != 1) return false;
        return tester
            .widgetList<RawImage>(
              find.descendant(of: fileImage, matching: find.byType(RawImage)),
            )
            .any((image) => image.image != null);
      });
      _expectRoomArt(tester, [room]);
      expect(http.requests, hasLength(1));
      final request = http.requests.single;
      expect(request.method, 'GET');
      expect(request.uri.host, 'configured.backend.test');
      expect(
        request.uri.path,
        '/app-api/media/v1/assets/${room.coverMedia!.assetId}/content',
      );
      expect(request.uri.hasQuery, isFalse);
      expect(request.headers.value('Authorization'), identity.token);
      expect(request.followRedirects, isFalse);
      final provider = tester.widget<Image>(fileImage).image as FileImage;

      identity.change(0);
      await tester.pumpAndSettle();
      expect(fileImage, findsNothing);
      expect(find.text(room.title), findsOneWidget);
      expect(find.text('图片已清理'), findsOneWidget);
      expect(http.requests, hasLength(1));
      var removed = false;
      await _until(
        tester,
        () => removed,
        tick: () async {
          removed = await tester.runAsync(provider.file.exists) == false;
        },
      );
      expect(tester.takeException(), isNull);
    },
  );
}

enum _Surface { videoHome, home, search, saved }

void _expectRoomArt(WidgetTester tester, List<DiscoveryRoom> rooms) {
  final artwork = tester.widgetList<RoomCoverArtwork>(
    find.byType(RoomCoverArtwork),
  );
  expect(artwork, isNotEmpty);
  for (final widget in artwork) {
    final room = rooms.singleWhere((room) => room.id == widget.roomId);
    expect(widget.media, same(room.coverMedia));
    expect(widget.media, isNot(same(room.backgroundMedia)));
    expect(widget.child, isNotNull);
  }
  // Legacy external cover URLs must never become an image provider.
  expect(
    tester
        .widgetList<Image>(find.byType(Image))
        .where((image) => image.image is NetworkImage),
    isEmpty,
  );
}

Future<void> _pump(
  WidgetTester tester,
  _Surface surface,
  _RoomsRepository repository, {
  void Function(DiscoveryRoom)? onOpenRoom,
  AppImageMediaHost? imageMediaHost,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final dependencies = AppDependencies.forTestEnvironment(
    environment: AppEnvironment.mock(),
    discoveryRepository: repository,
    imageMediaHost: imageMediaHost,
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    dependencies.dispose();
    if (imageMediaHost != null) {
      var cleaned = false;
      final cleanup = imageMediaHost.cleanup.then((_) => cleaned = true);
      await _until(tester, () => cleaned);
      await cleanup;
    }
  });
  final Widget page = switch (surface) {
    _Surface.videoHome => VideoRuntimeHomePage(
      dependencies: dependencies,
      repository: repository,
      onOpenRoom: onOpenRoom ?? (_) {},
    ),
    _Surface.home => const HomePage(),
    _Surface.search => const SearchResultsPage(
      keyword: '封面',
      initialType: SearchEntityType.rooms,
    ),
    _Surface.saved => const SavedRoomsPage(),
  };
  await tester.pumpWidget(
    AppDependencyScope(
      dependencies: dependencies,
      child: MaterialApp(
        theme: AppTheme.social(),
        home: Scaffold(body: page),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

DiscoveryRoom _room(
  int index, {
  bool hasCover = true,
  bool isClosed = false,
  int coverRevision = 1,
  int mediaBytes = 1024,
}) => DiscoveryRoom(
  id: '33333333-3333-4333-8333-33333333333$index',
  code: '12345$index',
  title: '封面房间 $index',
  topic: '卡片描述 $index',
  onlineCount: 7,
  occupiedSeats: 2,
  isSpeaking: false,
  isFavorite: index == 1,
  isLocked: true,
  isClosed: isClosed,
  coverUrl: 'https://external.example/never-fetch.png',
  coverMedia: hasCover
      ? _media(MediaPurpose.roomCover, index, coverRevision, bytes: mediaBytes)
      : null,
  // A valid background must not be used as a missing cover's fallback.
  backgroundMedia: _media(MediaPurpose.roomBackground, index, 1),
);

MediaReference _media(
  MediaPurpose purpose,
  int index,
  int revision, {
  int bytes = 1024,
}) => MediaReference.fromJson({
  'assetId': purpose == MediaPurpose.roomCover
      ? '11111111-1111-4111-8111-1111111111$index$revision'
      : '22222222-2222-4222-8222-2222222222$index$revision',
  'purpose': purpose.wire,
  'mediaType': 'image/png',
  'bytes': bytes,
  'durationMillis': 0,
  'version': revision,
});

Future<void> _until(
  WidgetTester tester,
  bool Function() ready, {
  Future<void> Function()? tick,
}) async {
  for (var i = 0; !ready() && i < 100; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump();
    await tick?.call();
  }
  expect(ready(), isTrue, reason: 'Controlled room image did not settle');
}

class _NoImageSelection implements ImageSelection {
  @override
  Future<Never> pick(int remaining) async =>
      throw StateError('Room cards must not open an image picker');
}

class _RoomsRepository extends MockDiscoveryRepository {
  _RoomsRepository(this.rooms)
    : favorites = [rooms.first],
      owned = [rooms.last];

  final List<DiscoveryRoom> rooms;
  List<DiscoveryRoom> favorites;
  final List<DiscoveryRoom> owned;

  @override
  Future<List<DiscoveryRoom>> fetchHomeRooms({
    int page = 1,
    int pageSize = 20,
  }) async => rooms;

  @override
  Future<DiscoverySearchResult> search({
    required String keyword,
    required SearchEntityType type,
    int page = 1,
    int pageSize = 20,
  }) async => DiscoverySearchResult(
    rooms: rooms,
    users: const [],
    page: page,
    pageSize: pageSize,
    hasMore: false,
  );

  @override
  Future<RoomCollectionSnapshot> fetchRoomCollections({
    int page = 1,
    int pageSize = 30,
  }) async => RoomCollectionSnapshot(favorites: favorites, ownedRooms: owned);
}
