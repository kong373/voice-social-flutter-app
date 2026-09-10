import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/media/media_models.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/features/community/data/backend_community_repository.dart';
import 'package:voice_social_app/features/room/pk/data/backend_room_pk_repository.dart';

import 'support/media_http_fakes.dart';

const mediaCurrentRoomId = '33333333-3333-4333-8333-333333333333';
const mediaTargetRoomId = '44444444-4444-4444-8444-444444444444';
const mediaBattleId = '55555555-5555-4555-8555-555555555555';

Map<String, Object?> guildPkMediaFields() => {
  'coverMedia': {
    'assetId': '11111111-1111-4111-8111-111111111111',
    'purpose': 'ROOM_COVER',
    'mediaType': 'image/png',
    'bytes': 1024,
    'durationMillis': 0,
    'version': 4,
  },
  'backgroundMedia': {
    'assetId': '22222222-2222-4222-8222-222222222222',
    'purpose': 'ROOM_BACKGROUND',
    'mediaType': 'image/webp',
    'bytes': 2048,
    'durationMillis': 0,
    'version': 9,
  },
};

void main() {
  for (final surface in _Surface.values) {
    test(
      '${surface.name} reads independent cover/background descriptors',
      () async {
        final fields = guildPkMediaFields();
        final (cover, background) = await _read(surface, fields);
        expect(cover!.toJson(), fields['coverMedia']);
        expect(background!.toJson(), fields['backgroundMedia']);
      },
    );

    for (final explicitNull in [false, true]) {
      test(
        '${surface.name} accepts ${explicitNull ? 'null' : 'absent'} media without URL fallback',
        () async {
          final (cover, background) = await _read(surface, {
            if (explicitNull) 'coverMedia': null,
            if (explicitNull) 'backgroundMedia': null,
          });
          expect(cover, isNull);
          expect(background, isNull);
        },
      );
    }

    test('${surface.name} rejects invalid media in either slot', () async {
      for (final slot in ['coverMedia', 'backgroundMedia']) {
        final valid = guildPkMediaFields()[slot] as Map<String, Object?>;
        for (final invalid in <Object?>[
          'https://external.example/image.png',
          valid['assetId'],
          {
            ...valid,
            'purpose': slot == 'coverMedia' ? 'ROOM_BACKGROUND' : 'ROOM_COVER',
          },
          {...valid, 'url': 'https://external.example/image.png'},
          {...valid, 'bytes': '1024'},
          {...valid, 'durationMillis': 1},
          {...valid, 'version': 1.5},
        ]) {
          await expectLater(
            _read(surface, {...guildPkMediaFields(), slot: invalid}),
            throwsA(
              isA<ApiException>().having(
                (error) => error.kind,
                'kind',
                ApiFailureKind.protocol,
              ),
            ),
            reason: slot,
          );
        }
      }
    });
  }

  test('guild and PK copyWith retain room media references', () async {
    final fixture = GuildPkMediaFixture(guildPkMediaFields());
    addTearDown(fixture.dispose);
    final guild = await fixture.community.fetchGuild('guild-media');
    final copiedGuild = guild.copyWith(memberCount: 8);
    expect(
      copiedGuild.rooms.single.coverMedia,
      same(guild.rooms.single.coverMedia),
    );
    expect(
      copiedGuild.rooms.single.backgroundMedia,
      same(guild.rooms.single.backgroundMedia),
    );
    final battle = (await fixture.pk.fetchActiveBattle(
      roomId: mediaCurrentRoomId,
    ))!;
    final side = battle.opponentSide;
    final copiedSide = side.copyWith(score: 42);
    expect(copiedSide.score, 42);
    expect(copiedSide.coverMedia, same(side.coverMedia));
    expect(copiedSide.backgroundMedia, same(side.backgroundMedia));
    final invitation = (await fixture.pk.fetchIncomingInvitation(
      roomId: mediaCurrentRoomId,
    ))!;
    expect(
      invitation.copyWith().opponent.coverMedia,
      same(invitation.opponent.coverMedia),
    );
  });
}

enum _Surface {
  guildDetail,
  guildSearch,
  pkHot,
  pkSearch,
  pkIncoming,
  pkBattle,
  pkHistory,
}

Future<(MediaReference?, MediaReference?)> _read(
  _Surface surface,
  Map<String, Object?> fields,
) async {
  final fixture = GuildPkMediaFixture(fields);
  try {
    switch (surface) {
      case _Surface.guildDetail:
      case _Surface.guildSearch:
        final guild = surface == _Surface.guildDetail
            ? await fixture.community.fetchGuild('guild-media')
            : (await fixture.community.searchGuilds('公会')).single;
        return (
          guild.rooms.single.coverMedia,
          guild.rooms.single.backgroundMedia,
        );
      case _Surface.pkHot:
      case _Surface.pkSearch:
        final opponents = surface == _Surface.pkHot
            ? await fixture.pk.fetchHotOpponents(roomId: mediaCurrentRoomId)
            : await fixture.pk.searchOpponents(
                roomId: mediaCurrentRoomId,
                keyword: '房间',
              );
        return (opponents.single.coverMedia, opponents.single.backgroundMedia);
      case _Surface.pkIncoming:
        final invitation = (await fixture.pk.fetchIncomingInvitation(
          roomId: mediaCurrentRoomId,
        ))!;
        return (
          invitation.opponent.coverMedia,
          invitation.opponent.backgroundMedia,
        );
      case _Surface.pkBattle:
        final battle = (await fixture.pk.fetchActiveBattle(
          roomId: mediaCurrentRoomId,
        ))!;
        expect(battle.currentSide.coverMedia, isNull);
        return (
          battle.opponentSide.coverMedia,
          battle.opponentSide.backgroundMedia,
        );
      case _Surface.pkHistory:
        final record = (await fixture.pk.fetchHistory(
          roomId: mediaCurrentRoomId,
        )).single;
        expect(record.targetRoomId, mediaTargetRoomId);
        return (record.opponentCoverMedia, record.opponentBackgroundMedia);
    }
  } finally {
    fixture.dispose();
  }
}

/// Read-only fake transport; UI tests also consume its parsed repositories.
class GuildPkMediaFixture {
  GuildPkMediaFixture(this.fields) {
    http = MediaFakeHttp((request) {
      expect(request.method, 'GET');
      final path = request.uri.path;
      return MediaFakeResponse.json(switch (path) {
        '/app-api/guild/getGuildHomepageDetails' => _guild(),
        '/app-api/guild/searchGuild' => _page([_guild()], 50),
        '/app-api/activityPk/getRoomPkHotRoomList' ||
        '/app-api/activityPk/searchRoomPk' => _page([_opponent()], 20),
        '/app-api/activityPk/queryRoomPkProcess' => _process(),
        '/app-api/activityPk/queryRoomPkHistory' => _page([
          _process(completed: true),
        ], 20),
        _ => throw StateError('Unexpected room-card request $path'),
      });
    });
    final api = http.api(identity);
    community = BackendCommunityRepository(
      apiClient: api,
      routes: const BackendRouteCatalog(),
    );
    pk = BackendRoomPkRepository(
      apiClient: api,
      routes: const BackendRouteCatalog(),
    );
  }

  final Map<String, Object?> fields;
  final identity = TestMediaIdentity();
  late final MediaFakeHttp http;
  late final BackendCommunityRepository community;
  late final BackendRoomPkRepository pk;
  void dispose() => identity.dispose();

  Map<String, Object?> _guild() => {
    'guildId': 'guild-media',
    'code': 'G123',
    'guildName': '封面公会',
    'name': '封面公会',
    'introduction': '',
    'ownerUserId': 7,
    'ownerName': '会长',
    'ownerAvatar': '',
    'status': 'ACTIVE',
    'memberCount': 12,
    'onlineUsers': 3,
    'artwork': '',
    'hasNewApplications': false,
    'viewerRole': 'NONE',
    'joined': false,
    'applicationPending': false,
    'roomId': mediaTargetRoomId,
    'roomCode': 'R222',
    'roomName': '公会关联房间',
    'createdAt': '2026-08-01T00:00:00Z',
    'updatedAt': '2026-08-20T00:00:00Z',
    ...fields,
  };

  Map<String, Object?> _opponent() => {
    'roomId': mediaTargetRoomId,
    'roomCode': 'R222',
    'roomName': 'PK 对手房间',
    'coverImgUrl': 'https://legacy.example/never-load.png',
    'onlineNum': 3,
    'hasActivePk': false,
    ...fields,
  };

  Map<String, Object?> _process({bool completed = false}) => {
    'roomId': mediaCurrentRoomId,
    'targetRoomId': mediaTargetRoomId,
    'invitationId': '66666666-6666-4666-8666-666666666666',
    'invitationDirection': 'INCOMING',
    'invitationStatus': 'PENDING',
    'inviterRoomId': mediaTargetRoomId,
    'inviteeRoomId': mediaCurrentRoomId,
    'opponentRoom': _opponent(),
    'createdAt': '2030-08-21T11:59:00Z',
    'expiresAt': '2030-08-21T12:14:00Z',
    'punishmentTheme': '主题',
    'durationMinutes': 5,
    'battleId': mediaBattleId,
    'battleStatus': completed ? 'COMPLETED' : 'IN_PROGRESS',
    'resultCode': completed ? 'DRAW' : 'UNDECIDED',
    'startedAt': '2030-08-21T11:59:00Z',
    'endsAt': '2030-08-21T12:09:00Z',
    'completedAt': completed ? '2030-08-21T12:09:00Z' : null,
    'countdownSeconds': completed ? 0 : 120,
    'leftRoomId': mediaCurrentRoomId,
    'rightRoomId': mediaTargetRoomId,
    'leftRoom': _side(mediaCurrentRoomId, '当前房间', const {}),
    'rightRoom': _side(mediaTargetRoomId, 'PK 对手房间', fields),
  };

  Map<String, Object?> _side(
    String id,
    String name,
    Map<String, Object?> media,
  ) => {
    'roomId': id,
    'roomCode': id == mediaCurrentRoomId ? 'R111' : 'R222',
    'roomName': name,
    'coverUrl': 'https://legacy.example/never-load.png',
    'score': 10,
    'supporters': <Object?>[],
    ...media,
  };

  Map<String, Object?> _page(List<Object?> rows, int size) => {
    'records': rows,
    'list': rows,
    'current': 1,
    'size': size,
    'pageSize': size,
    'total': rows.length,
    'pages': rows.isEmpty ? 0 : 1,
  };
}
