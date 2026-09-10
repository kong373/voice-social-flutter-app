import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/features/commerce/display/domain/equipped_decoration.dart';
import 'package:voice_social_app/features/social/data/backend_social_repository.dart';
import 'package:voice_social_app/features/room/data/backend_room_repository.dart';
import 'package:voice_social_app/features/room/data/backend_room_operations_repository.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/shell/live_read_only_repository.dart';
import 'room_lease_contract_fixture.dart';
import 'support/media_http_fakes.dart';

Map<String, Object?> decorationDisplayRow() => {
  'decorationId': '00000000-0000-0000-0000-000000000001',
  'type': 'AVATAR_FRAME',
  'assetKey': 'decoration/star-ring-frame',
  'expiresAt': '2099-01-01T00:00:00Z',
};

Map<String, Object?> _profile() => {
  'id': 1,
  'userId': 1,
  'nickName': '测试',
  'loginName': 'test',
  'headImgUrl': '',
  'headImageUrl': '',
  'signature': '',
  'sex': 1,
  'birthday': '',
  'piAddress': '',
  'coverImgUrl': '',
  'attentionNum': 0,
  'fansNum': 0,
  'playmateNum': 0,
  'dynamicNum': 0,
  'level': null,
  'levelAvailable': false,
  'levelStatus': 'UNAVAILABLE',
  'isAttention': 0,
  'isBlacklist': false,
  'isOnline': 1,
  'isInRoom': 0,
  'roomId': '',
  'status': 'ACTIVE',
  'equippedDecorations': [decorationDisplayRow()],
};

void main() {
  for (final self in [false, true]) {
    test(
      '${self ? 'self' : 'public'} profile parses equipped display without losing it on copy',
      () async {
        final actor = TestMediaIdentity();
        addTearDown(actor.dispose);
        final http = MediaFakeHttp((_) => MediaFakeResponse.json(_profile()));
        final repo = BackendSocialRepository(
          apiClient: http.api(actor),
          currentUserIdProvider: () => 1,
        );
        final profile = self
            ? await repo.fetchMyProfile()
            : await repo.fetchPublicProfile(1);
        expect(
          profile.user.equippedDecorations.single.product,
          DecorationProduct.starRingFrame,
        );
        expect(
          profile.user.copyWith(name: '新昵称').equippedDecorations,
          profile.user.equippedDecorations,
        );
      },
    );
  }
  test(
    'disabled profile discards decorated metadata and legacy absence stays empty',
    () async {
      final actor = TestMediaIdentity();
      addTearDown(actor.dispose);
      for (final raw in [
        _profile()..remove('equippedDecorations'),
        {..._profile(), 'status': 'DISABLED'},
      ]) {
        final http = MediaFakeHttp((_) => MediaFakeResponse.json(raw));
        final repo = BackendSocialRepository(
          apiClient: http.api(actor),
          currentUserIdProvider: () => 1,
        );
        expect(
          (await repo.fetchPublicProfile(1)).user.equippedDecorations,
          isEmpty,
        );
      }
    },
  );
  test('current-user read includes display metadata only for ACTIVE', () async {
    final actor = TestMediaIdentity();
    addTearDown(actor.dispose);
    for (final status in ['ACTIVE', 'DISABLED', null]) {
      final http = MediaFakeHttp(
        (_) => MediaFakeResponse.json({..._profile(), 'status': status}),
      );
      final user = await LiveReadOnlyRepository(
        http.api(actor),
      ).fetchCurrentUser();
      if (status == 'ACTIVE') {
        expect(
          user.equippedDecorations.single.product,
          DecorationProduct.starRingFrame,
        );
      } else {
        expect(user.equippedDecorations, isEmpty);
      }
    }
  });
  test(
    'documented homepage 404 uses personal display, not arbitrary failed reads',
    () async {
      final actor = TestMediaIdentity();
      addTearDown(actor.dispose);
      final http = MediaFakeHttp(
        (request) => request.uri.path.contains('personalHomepage')
            ? MediaFakeResponse.json(null, status: 404, code: 40402)
            : MediaFakeResponse.json(_profile()),
      );
      final profile = await BackendSocialRepository(
        apiClient: http.api(actor),
        currentUserIdProvider: () => 1,
      ).fetchMyProfile();
      expect(
        profile.user.equippedDecorations.single.product,
        DecorationProduct.starRingFrame,
      );
      expect(http.requests, hasLength(2));
    },
  );
  test(
    'enter seat adapts equipped display and changing occupant clears it',
    () async {
      final actor = TestMediaIdentity();
      addTearDown(actor.dispose);
      final http = MediaFakeHttp(
        (_) => MediaFakeResponse.json(
          withRoomLeaseFixture({
            'roomId': '9527',
            'roomName': '测试',
            'ownerId': 1,
            'seats': [
              {
                'index': 1,
                'occupied': true,
                'online': true,
                'muted': false,
                'userId': 1,
                'selfMuted': false,
                'forcedMuted': false,
                'legacyMuted': false,
                'joinedAt': '2026-09-10T00:00:00Z',
                'equippedDecorations': [decorationDisplayRow()],
              },
            ],
          }),
        ),
      );
      final room = await BackendRoomRepository(apiClient: http.api(actor))
          .enterRoom(
            roomId: '9527',
            password: null,
            source: RoomEntrySource.home,
            currentUserId: 1,
          );
      final seat = room.seats.first;
      expect(
        seat.equippedDecorations.single.product,
        DecorationProduct.starRingFrame,
      );
      expect(
        seat.copyWith(isSpeaking: true).equippedDecorations,
        seat.equippedDecorations,
      );
      expect(seat.copyWith(userId: 2).equippedDecorations, isEmpty);
      expect(seat.copyWith(clearUserId: true).equippedDecorations, isEmpty);
      expect(seat.copyWith(isOnline: false).equippedDecorations, isEmpty);
      expect(
        seat.copyWith(state: MicSeatState.available).equippedDecorations,
        isEmpty,
      );
    },
  );
  test(
    'member read preserves membership joinedAt separately from seat time',
    () async {
      final actor = TestMediaIdentity();
      addTearDown(actor.dispose);
      final memberRow = <String, Object?>{
        'userId': 1,
        'nickName': '测试',
        'role': 'MEMBER',
        'presence': 'ONLINE',
        'onMic': false,
        'seatNumber': 0,
        'joinedAt': '2026-09-10T00:00:00Z',
        'equippedDecorations': [decorationDisplayRow()],
      };
      final http = MediaFakeHttp(
        (_) => MediaFakeResponse.json({
          'current': 1,
          'pageSize': 20,
          'size': 20,
          'pages': 1,
          'total': 1,
          'list': [memberRow],
          'records': [memberRow],
        }),
      );
      final member = (await BackendRoomOperationsRepository(
        apiClient: http.api(actor),
      ).fetchOnlineMembers(roomId: '9527', page: 1)).items.single;
      expect(
        member.equippedDecorations.single.product,
        DecorationProduct.starRingFrame,
      );
      expect(member.joinedAt, DateTime.utc(2026, 9, 10));
      expect(member.copyWith(isMuted: true).joinedAt, member.joinedAt);
      expect(
        member.copyWith(isMuted: true).equippedDecorations,
        member.equippedDecorations,
      );
    },
  );

  test(
    'strict display metadata never treats malformed or extra fields as wear',
    () {
      for (final input in [
        null,
        'bad',
        [null],
        [decorationDisplayRow()..remove('expiresAt')],
        [
          {...decorationDisplayRow(), 'url': 'https://bad.test'},
        ],
        [
          {...decorationDisplayRow(), 'decorationId': '1'},
        ],
        [
          {...decorationDisplayRow(), 'type': 'VOICE_WAVE'},
        ],
        [
          {...decorationDisplayRow(), 'assetKey': 'https://bad.test'},
        ],
        [
          {...decorationDisplayRow(), 'expiresAt': '2099-02-30T00:00:00Z'},
        ],
        [
          {...decorationDisplayRow(), 'expiresAt': '2099-01-01'},
        ],
        [
          {...decorationDisplayRow(), 'expiresAt': 1},
        ],
        [decorationDisplayRow(), decorationDisplayRow()],
      ]) {
        expect(EquippedDecoration.parseList(input), isEmpty);
      }
    },
  );
  test(
    'retired permanent and finite expiry stay exact while unknown keys do not render',
    () {
      final permanent = EquippedDecoration.parseList([
        {...decorationDisplayRow(), 'expiresAt': null},
      ]).single;
      expect(permanent.isActiveAt(DateTime.utc(2200)), true);
      final finite = EquippedDecoration.parseList([
        decorationDisplayRow(),
      ]).single;
      expect(finite.isActiveAt(DateTime.utc(2099)), false);
      expect(finite.isActiveAt(DateTime.utc(2098)), true);
      expect(
        EquippedDecoration.parseList([
          {...decorationDisplayRow(), 'assetKey': 'decoration/unknown'},
        ]).single.product,
        isNull,
      );
      expect(
        EquippedDecoration.parseList([
          {...decorationDisplayRow(), 'type': 'ROOM_ENTRY'},
        ]).single.product,
        isNull,
      );
    },
  );
  test('conflicting same-type records cannot select an arbitrary frame', () {
    final items = EquippedDecoration.parseList([
      decorationDisplayRow(),
      {
        ...decorationDisplayRow(),
        'decorationId': '00000000-0000-0000-0000-000000000002',
      },
      {
        ...decorationDisplayRow(),
        'decorationId': '00000000-0000-0000-0000-000000000003',
        'type': 'PROFILE_BADGE',
        'assetKey': 'decoration/companion-badge',
      },
    ]);
    expect(items.single.product, DecorationProduct.companionBadge);
  });
}
