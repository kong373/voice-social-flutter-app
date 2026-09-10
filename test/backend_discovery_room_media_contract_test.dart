import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/media/media_models.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/features/discovery/data/backend_discovery_repository.dart';
import 'package:voice_social_app/features/discovery/domain/discovery_models.dart';

import 'support/media_http_fakes.dart';

void main() {
  for (final surface in _Surface.values) {
    test('${surface.name} preserves both room media descriptors', () async {
      final cover = _media(MediaPurpose.roomCover);
      final background = _media(MediaPurpose.roomBackground);
      final room = await _read(surface, {
        'coverMedia': cover,
        'backgroundMedia': background,
        // Asset versions are independent of the outer room version.
        'version': 91,
        'state': 'CLOSED',
        'accessMode': 'PASSWORD',
      });

      expect(room.coverMedia!.toJson(), cover);
      expect(room.backgroundMedia!.toJson(), background);
      expect(room.coverMedia!.assetId, cover['assetId']);
      expect(room.coverMedia!.version, 4);
      expect(room.backgroundMedia!.version, 8);
      expect(room.isClosed, isTrue);
      expect(room.isLocked, isTrue);
      expect(room.isFavorite, surface == _Surface.favorites);
    });

    for (final explicitNull in [false, true]) {
      test(
        '${surface.name} keeps ${explicitNull ? 'null' : 'absent'} media empty despite legacy URLs',
        () async {
          final room = await _read(surface, {
            if (explicitNull) 'coverMedia': null,
            if (explicitNull) 'backgroundMedia': null,
            'coverImage': 'https://legacy.example/cover.png',
            'coverImgUrl': 'https://legacy.example/other.png',
          });
          expect(room.coverMedia, isNull);
          expect(room.backgroundMedia, isNull);
          expect(room.coverUrl, 'https://legacy.example/cover.png');
        },
      );
    }

    for (final purpose in [
      MediaPurpose.roomCover,
      MediaPurpose.roomBackground,
    ]) {
      final slot = purpose == MediaPurpose.roomCover
          ? 'coverMedia'
          : 'backgroundMedia';
      test('${surface.name} parses $slot independently', () async {
        final descriptor = _media(purpose);
        final room = await _read(surface, {slot: descriptor});
        expect(
          (purpose == MediaPurpose.roomCover
                  ? room.coverMedia
                  : room.backgroundMedia)!
              .toJson(),
          descriptor,
        );
        expect(
          purpose == MediaPurpose.roomCover
              ? room.backgroundMedia
              : room.coverMedia,
          isNull,
        );
      });

      test(
        '${surface.name} rejects malformed $slot without fallback',
        () async {
          final valid = _media(purpose);
          final invalid = <String, Object?>{
            'URL instead of descriptor': 'https://external.example/cover.png',
            'asset UUID instead of descriptor': valid['assetId'],
            'array instead of descriptor': [valid],
            'wrong room slot purpose': {
              ...valid,
              'purpose': purpose == MediaPurpose.roomCover
                  ? 'ROOM_BACKGROUND'
                  : 'ROOM_COVER',
            },
            'other image purpose': {...valid, 'purpose': 'DYNAMIC_IMAGE'},
            'unknown purpose': {...valid, 'purpose': 'ROOM_IMAGE'},
            'noncanonical asset UUID': {...valid, 'assetId': 'asset-1'},
            'external URL field': {
              ...valid,
              'url': 'https://external.example/a',
            },
            'local path field': {...valid, 'path': '/tmp/image.png'},
            'missing version': {...valid}..remove('version'),
            'numeric string bytes': {...valid, 'bytes': '1024'},
            'fractional bytes': {...valid, 'bytes': 1024.5},
            'zero bytes': {...valid, 'bytes': 0},
            'over byte limit': {...valid, 'bytes': 10000001},
            'non-image MIME': {...valid, 'mediaType': 'video/mp4'},
            'nonzero duration': {...valid, 'durationMillis': 1},
            'numeric string duration': {...valid, 'durationMillis': '0'},
            'fractional duration': {...valid, 'durationMillis': 0.5},
            'numeric string version': {...valid, 'version': '4'},
            'fractional version': {...valid, 'version': 4.5},
            'negative version': {...valid, 'version': -1},
          };
          for (final entry in invalid.entries) {
            await expectLater(
              _read(surface, {
                'coverMedia': _media(MediaPurpose.roomCover),
                'backgroundMedia': _media(MediaPurpose.roomBackground),
                slot: entry.value,
                'coverImage': 'https://legacy.example/must-not-mask-error.png',
              }),
              throwsA(
                isA<ApiException>().having(
                  (error) => error.kind,
                  'kind',
                  ApiFailureKind.protocol,
                ),
              ),
              reason: entry.key,
            );
          }
        },
      );
    }
  }

  test('copyWith retains media when favorite and live fields change', () async {
    final original = await _read(_Surface.home, {
      'coverMedia': _media(MediaPurpose.roomCover),
      'backgroundMedia': _media(MediaPurpose.roomBackground),
      'coverImage': 'https://legacy.example/cover.png',
    });
    final changed = original.copyWith(
      title: '更新后的标题',
      topic: '更新后的话题',
      onlineCount: 7,
      occupiedSeats: 2,
      isSpeaking: true,
      isFavorite: true,
      relationReason: '已收藏',
      isLocked: true,
      isClosed: true,
    );
    expect(changed.coverMedia, same(original.coverMedia));
    expect(changed.backgroundMedia, same(original.backgroundMedia));
    expect(changed.coverUrl, original.coverUrl);
    expect(changed.id, original.id);
    expect(changed.title, '更新后的标题');
    expect(changed.onlineCount, 7);
    expect(changed.isFavorite, isTrue);
    expect(changed.isClosed, isTrue);
  });

  test('copyWith preserves nullable media on older room projections', () async {
    final original = await _read(_Surface.home, {});
    final changed = original.copyWith(isFavorite: true);
    expect(changed.coverMedia, isNull);
    expect(changed.backgroundMedia, isNull);
  });
}

enum _Surface { home, search, favorites, owned }

Map<String, Object?> _media(MediaPurpose purpose) => {
  'assetId': purpose == MediaPurpose.roomCover
      ? '11111111-1111-4111-8111-111111111111'
      : '22222222-2222-4222-8222-222222222222',
  'purpose': purpose.wire,
  'mediaType': 'image/png',
  'bytes': 1024,
  'durationMillis': 0,
  'version': purpose == MediaPurpose.roomCover ? 4 : 8,
};

Future<DiscoveryRoom> _read(
  _Surface surface,
  Map<String, Object?> fields,
) async {
  const routes = BackendRouteCatalog();
  final rows = [
    {
      'roomId': '33333333-3333-4333-8333-333333333333',
      'roomCode': '123456',
      'roomName': '封面契约房间',
      ...fields,
    },
  ];
  final identity = TestMediaIdentity();
  final http = MediaFakeHttp((request) {
    final path = request.uri.path;
    final search = path == routes.globalSearch;
    final collection =
        path == routes.favoriteRooms || path == routes.ownedRooms;
    final otherCollection =
        (surface == _Surface.favorites && path == routes.ownedRooms) ||
        (surface == _Surface.owned && path == routes.favoriteRooms);
    final responseRows = otherCollection ? <Object?>[] : rows;
    expect(
      path,
      isIn([
        routes.homeRecommendedRooms,
        routes.globalSearch,
        routes.favoriteRooms,
        routes.ownedRooms,
      ]),
    );
    expect(request.method, path == routes.ownedRooms ? 'GET' : 'POST');
    return MediaFakeResponse.json({
      if (search) ...{
        'roomsList': responseRows,
        'usersList': <Object?>[],
        'pageNo': 1,
      } else ...{
        'records': responseRows,
        'current': 1,
      },
      if (collection) ...{
        'list': responseRows,
        'size': 20,
        'pages': otherCollection ? 0 : 1,
      },
      'total': responseRows.length,
      'pageSize': 20,
    });
  });
  final repository = BackendDiscoveryRepository(
    apiClient: http.api(identity),
    clientType: 'Android',
  );
  try {
    return switch (surface) {
      _Surface.home => (await repository.fetchHomeRooms()).single,
      _Surface.search => (await repository.search(
        keyword: '房间',
        type: SearchEntityType.rooms,
      )).rooms.single,
      _Surface.favorites => (await repository.fetchRoomCollections(
        pageSize: 20,
      )).favorites.single,
      _Surface.owned => (await repository.fetchRoomCollections(
        pageSize: 20,
      )).ownedRooms.single,
    };
  } finally {
    identity.dispose();
  }
}
