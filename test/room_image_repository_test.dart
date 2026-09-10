import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/media/media_models.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/room/data/backend_room_lifecycle_repository.dart';
import 'package:voice_social_app/features/room/domain/room_image_models.dart';
import 'manager_room_profile_test.dart'
    show ProfileApi, profileWire, profileRoomId;
import 'room_lease_contract_fixture.dart';

const roomCoverAsset = '11111111-2222-4333-8444-555555555501';
const roomBackgroundAsset = '11111111-2222-4333-8444-555555555502';
Map<String, Object?> roomImageWire(String purpose, {String? assetId}) => {
  'assetId':
      assetId ??
      (purpose == 'ROOM_COVER' ? roomCoverAsset : roomBackgroundAsset),
  'purpose': purpose,
  'mediaType': 'image/png',
  'bytes': 12,
  'durationMillis': 0,
  'version': 3,
};

class RoomImageProfileApi extends ProfileApi {
  bool malformedReceipt = false;
  @override
  Future<ApiResponse> patchBoundToIdentity(
    String path, {
    required void Function() requireIdentity,
    Map<String, String>? headers,
    Map<String, Object?>? body,
  }) async {
    requireIdentity();
    expect(path, '/app-api/rooms/updateRoomInformation');
    writes.add(Map.of(body!));
    requestIds.add(headers!['X-Request-Id']!);
    await saveGate?.future;
    requireIdentity();
    if (saveError != null) throw saveError!;
    wire = {...wire, ...body, 'version': (body['expectedVersion']! as int) + 1};
    for (final (field, output, purpose) in [
      ('coverAssetId', 'coverMedia', 'ROOM_COVER'),
      ('backgroundAssetId', 'backgroundMedia', 'ROOM_BACKGROUND'),
    ]) {
      if (body.containsKey(field))
        wire[output] = body[field] == null
            ? null
            : roomImageWire(purpose, assetId: body[field]! as String);
    }
    return ApiResponse(
      code: 200,
      message: 'OK',
      data: {
        ...wire,
        if (malformedReceipt) 'coverMedia': null,
        'rtcStatus': 'DISABLED',
        'imStatus': 'DISABLED',
        'providerInvocation': false,
      },
    );
  }
}

void main() {
  RoomImageProfileApi api() => RoomImageProfileApi()
    ..wire = {
      ...profileWire(owner: false),
      'coverMedia': roomImageWire('ROOM_COVER'),
      'backgroundMedia': roomImageWire('ROOM_BACKGROUND'),
    };
  BackendRoomLifecycleRepository repo(RoomImageProfileApi api) =>
      BackendRoomLifecycleRepository(
        apiClient: api,
        leaseBinding: admittedRoomFixture(roomId: profileRoomId),
      );

  test(
    'strict slot descriptors preserve asset version independently of room version',
    () async {
      final repository = repo(api());
      final room = await repository.fetchRoom(profileRoomId);
      expect(room.version, 2);
      expect(room.coverMedia!.toJson(), roomImageWire('ROOM_COVER'));
      expect(room.backgroundMedia!.version, 3);
      final draft = room.copyWith(title: '新名称');
      expect(draft.coverMedia, same(room.coverMedia));
      expect(draft.coverImageChange.changed, isFalse);
    },
  );

  test(
    'missing legacy/null descriptor does not authorize an external URL',
    () async {
      final transport = api()
        ..wire = {
          ...profileWire(owner: false),
          'coverImgUrl': 'https://untrusted.invalid/a.png',
        };
      final room = await repo(transport).fetchRoom(profileRoomId);
      expect(room.coverMedia, isNull);
      expect(room.backgroundMedia, isNull);
      expect(transport.paths, ['/app-api/rooms/editable-profile']);
    },
  );

  test(
    'malformed, swapped-purpose, noninteger, extra URL descriptors fail closed',
    () async {
      for (final invalid in [
        roomImageWire('ROOM_BACKGROUND'),
        {...roomImageWire('ROOM_COVER'), 'bytes': '12'},
        {...roomImageWire('ROOM_COVER'), 'bytes': 10000001},
        {...roomImageWire('ROOM_COVER'), 'mediaType': 'image/svg+xml'},
        {...roomImageWire('ROOM_COVER'), 'durationMillis': 1},
        {...roomImageWire('ROOM_COVER'), 'assetId': '$roomCoverAsset\n'},
        {
          ...roomImageWire('ROOM_COVER'),
          'url': 'https://untrusted.invalid/a.png',
        },
      ]) {
        final transport = api()..wire['coverMedia'] = invalid;
        await expectLater(
          repo(transport).fetchRoom(profileRoomId),
          throwsA(isA<ApiException>()),
        );
        expect(transport.writes, isEmpty);
      }
    },
  );

  test(
    'omit keeps both images and room state, manager sends exact original lease',
    () async {
      final transport = api();
      final repository = repo(transport);
      final room = await repository.fetchRoom(profileRoomId);
      await repository.saveRoom(room.copyWith(title: '只改房名'));
      final body = transport.writes.single;
      expect(body.containsKey('coverAssetId'), isFalse);
      expect(body.containsKey('backgroundAssetId'), isFalse);
      expect(body['sessionId'], roomLeaseSessionId);
      expect(body['expectedVersion'], 2);
      expect(body.containsKey('hallVisible'), isFalse);
      expect(transport.wire['status'], 'OPEN');
      expect(transport.wire['coverMedia'], roomImageWire('ROOM_COVER'));
    },
  );

  test(
    'replace and clear send only UUID/null atomically, no metadata or URL',
    () async {
      final transport = api();
      final repository = repo(transport);
      final room = await repository.fetchRoom(profileRoomId);
      final replacement = MediaReference.fromJson(
        roomImageWire(
          'ROOM_COVER',
          assetId: '11111111-2222-4333-8444-555555555503',
        ),
      );
      await repository.saveRoom(
        room.copyWith(
          coverImageChange: RoomImageChange.replace(replacement),
          backgroundImageChange: const RoomImageChange.clear(),
        ),
      );
      final body = transport.writes.single;
      expect(body['coverAssetId'], replacement.assetId);
      expect(body.containsKey('backgroundAssetId'), isTrue);
      expect(body['backgroundAssetId'], isNull);
      expect(body.keys, isNot(contains('coverMedia')));
      expect(body.keys, isNot(contains('backgroundMedia')));
      expect(body.keys, isNot(contains('coverUrl')));
      expect(transport.wire['status'], 'OPEN');
      expect(transport.wire['backgroundMedia'], isNull);
    },
  );

  test(
    'unknown image save survives editor reconstruction and freezes key/body; new lease cannot replay',
    () async {
      final transport = api();
      final repository = repo(transport);
      final room = await repository.fetchRoom(profileRoomId);
      final draft = room.copyWith(
        coverImageChange: const RoomImageChange.clear(),
      );
      transport.saveError = const ApiException(
        kind: ApiFailureKind.network,
        message: 'lost response',
      );
      await expectLater(
        repository.saveRoom(draft),
        throwsA(isA<ApiException>()),
      );
      expect(repository.pendingImageSave(profileRoomId), same(draft));
      await expectLater(
        repository.saveRoom(draft.copyWith(title: 'different')),
        throwsA(isA<ApiException>()),
      );
      expect(transport.writes, hasLength(1));
      transport.saveError = null;
      await repository.saveRoom(repository.pendingImageSave(profileRoomId)!);
      expect(transport.writes[0], transport.writes[1]);
      expect(transport.requestIds.toSet(), hasLength(1));
      expect(repository.pendingImageSave(profileRoomId), isNull);
      repository.leaseBinding.beginEntry('new session');
      await expectLater(
        repository.saveRoom(draft),
        throwsA(isA<ApiException>()),
      );
      expect(transport.writes, hasLength(2));
    },
  );

  test(
    'wrong READY purpose rejects before PATCH; wrong receipt is unknown not success',
    () async {
      final transport = api();
      final repository = repo(transport);
      final room = await repository.fetchRoom(profileRoomId);
      await expectLater(
        repository.saveRoom(
          room.copyWith(
            coverImageChange: RoomImageChange.replace(
              MediaReference.fromJson(roomImageWire('ROOM_BACKGROUND')),
            ),
          ),
        ),
        throwsA(isA<ApiException>()),
      );
      expect(transport.writes, isEmpty);
      transport.malformedReceipt = true;
      final draft = room.copyWith(
        coverImageChange: RoomImageChange.replace(
          MediaReference.fromJson(roomImageWire('ROOM_COVER')),
        ),
      );
      await expectLater(
        repository.saveRoom(draft),
        throwsA(isA<ApiException>()),
      );
      expect(repository.pendingImageSave(profileRoomId), same(draft));
    },
  );

  test(
    'closed owner clears cover without lease while retaining CLOSED state',
    () async {
      final transport = api()
        ..wire = {
          ...profileWire(),
          'status': 'CLOSED',
          'coverMedia': roomImageWire('ROOM_COVER'),
          'backgroundMedia': null,
        };
      final repository = BackendRoomLifecycleRepository(apiClient: transport);
      final room = await repository.fetchRoom(profileRoomId);
      await repository.saveRoom(
        room.copyWith(coverImageChange: const RoomImageChange.clear()),
      );
      expect(transport.writes.single.containsKey('sessionId'), isFalse);
      expect(transport.wire['status'], 'CLOSED');
    },
  );
}
