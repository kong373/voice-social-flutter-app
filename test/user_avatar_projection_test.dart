import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/features/account/domain/user_avatar_descriptor.dart';
import 'package:voice_social_app/features/social/data/backend_social_repository.dart';
import 'package:voice_social_app/features/room/data/backend_room_repository.dart';
import 'package:voice_social_app/features/room/data/backend_room_operations_repository.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/shell/live_read_only_repository.dart';
import 'package:voice_social_app/features/message/data/backend_message_repository.dart';
import 'package:voice_social_app/features/message/domain/message_models.dart';
import 'room_lease_contract_fixture.dart';
import 'support/media_http_fakes.dart';

const avatarProjection = {'kind': 'PRESET', 'reference': 'avatar-preset-moon'};
Map<String, Object?> avatarProfile() => {
  'id': 1,
  'userId': 1,
  'nickName': 'Avatar',
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
  'avatar': avatarProjection,
};
void main() {
  for (final send in [false, true]) {
    for (final invalid in [false, true]) {
      test(
        '${send ? "send response" : "history"} strict sender/receiver avatar metadata invalid=$invalid',
        () async {
          final actor = TestMediaIdentity();
          addTearDown(actor.dispose);
          final row = {
            'messageId': 'stored',
            'conversationId': 'conversation',
            'senderUserId': 1,
            'receiverUserId': 2,
            'direction': 'OUTGOING',
            'messageType': 'TEXT',
            'content': 'hello',
            'storageStatus': 'FIRST_PARTY_STORED',
            'deliveryStatus': 'VENDOR_BLOCKED',
            'imStatus': 'VENDOR_BLOCKED',
            'providerInvocation': false,
            'createdAt': '2026-09-10T00:00:00Z',
            'senderAvatar': avatarProjection,
            'receiverAvatar': invalid
                ? {'kind': 'PRESET', 'reference': 'https://bad.test/avatar'}
                : {'kind': 'PRESET', 'reference': 'avatar-preset-sun'},
          };
          const conversation = ConversationSummary.draft(
            kind: ConversationKind.privateChat,
            title: 'peer',
            lastMessage: '',
            unreadCount: 0,
            targetUserId: 2,
          );
          final http = MediaFakeHttp(
            (request) => MediaFakeResponse.json(
              send
                  ? row
                  : {
                      'conversationId': 'conversation',
                      'targetUserId': 2,
                      'list': [row],
                      'hasMore': false,
                      'nextCursor': '',
                      'unreadCount': 0,
                      'imStatus': 'VENDOR_BLOCKED',
                      'providerInvocation': false,
                    },
            ),
          );
          final repo = BackendMessageRepository(
            apiClient: http.api(actor),
            routes: const BackendRouteCatalog(),
            currentUserIdProvider: () => 1,
          );
          final future = send
              ? repo.sendPrivateMessage(
                  conversation: conversation,
                  content: 'hello',
                )
              : repo
                    .fetchVisiblePrivateMessagePage(
                      conversation,
                      isCurrent: () => true,
                    )
                    .then((batch) => batch.messages.single);
          if (invalid) {
            await expectLater(future, throwsA(anything));
          } else {
            final message = await future;
            expect(message.senderAvatar?.reference, 'avatar-preset-moon');
            expect(message.receiverAvatar?.reference, 'avatar-preset-sun');
            expect(
              message.copyWith(read: true).senderAvatar,
              same(message.senderAvatar),
            );
            expect(
              message.copyWith(read: true).receiverAvatar,
              same(message.receiverAvatar),
            );
          }
        },
      );
    }
  }
  for (final source in ['current', 'self', 'public']) {
    test(
      '$source strict avatar projection preserves preset; invalid non-null cannot fall back to URL',
      () async {
        final actor = TestMediaIdentity();
        addTearDown(actor.dispose);
        final data = avatarProfile();
        final http = MediaFakeHttp((_) => MediaFakeResponse.json(data));
        final api = http.api(actor);
        final social = BackendSocialRepository(
          apiClient: api,
          currentUserIdProvider: () => 1,
        );
        Future<UserAvatarDescriptor?> read() async => switch (source) {
          'current' => (await LiveReadOnlyRepository(
            api,
          ).fetchCurrentUser()).avatar,
          'self' => (await social.fetchMyProfile()).user.avatar,
          _ => (await social.fetchPublicProfile(1)).user.avatar,
        };
        expect((await read())?.reference, 'avatar-preset-moon');
        data['avatar'] = null;
        expect(await read(), isNull);
        data['avatar'] = {
          'kind': 'UPLOADED',
          'reference': 'https://bad.test/private',
          'version': 0,
        };
        data['headImgUrl'] = 'https://bad.test/legacy';
        await expectLater(read(), throwsA(anything));
      },
    );
  }
  test(
    'social copy retains exact descriptor; disabled projection cannot display metadata',
    () async {
      final actor = TestMediaIdentity();
      addTearDown(actor.dispose);
      final data = avatarProfile();
      final repo = BackendSocialRepository(
        apiClient: MediaFakeHttp(
          (_) => MediaFakeResponse.json(data),
        ).api(actor),
        currentUserIdProvider: () => 1,
      );
      final user = (await repo.fetchPublicProfile(1)).user;
      expect(user.copyWith(name: 'updated').avatar, same(user.avatar));
      data['status'] = 'DISABLED';
      expect((await repo.fetchPublicProfile(1)).user.avatar, isNull);
    },
  );
  test(
    'room seat metadata survives audio update but clears on occupant/availability loss',
    () async {
      final actor = TestMediaIdentity();
      addTearDown(actor.dispose);
      final http = MediaFakeHttp(
        (_) => MediaFakeResponse.json(
          withRoomLeaseFixture({
            'roomId': '9527',
            'roomName': 'test',
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
                'avatar': avatarProjection,
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
      expect(seat.avatar?.reference, 'avatar-preset-moon');
      expect(seat.copyWith(isSpeaking: true).avatar, same(seat.avatar));
      for (final empty in [
        seat.copyWith(userId: 2),
        seat.copyWith(clearUserId: true),
        seat.copyWith(isOnline: false),
        seat.copyWith(state: MicSeatState.available),
      ]) {
        expect(empty.avatar, isNull);
      }
    },
  );
  for (final source in ['online', 'offMic', 'managers', 'muted']) {
    test('$source member reads preserve descriptor and copies', () async {
      final actor = TestMediaIdentity();
      addTearDown(actor.dispose);
      final row = {
        'userId': 1,
        'nickName': 'member',
        'role': 'MEMBER',
        'presence': 'ONLINE',
        'joinedAt': '2026-09-10T00:00:00Z',
        'avatar': avatarProjection,
      };
      final http = MediaFakeHttp(
        (_) => MediaFakeResponse.json({
          'current': 1,
          'pageSize': 50,
          'size': 50,
          'total': 1,
          'pages': 1,
          'list': [row],
          'records': [row],
        }),
      );
      final repo = BackendRoomOperationsRepository(apiClient: http.api(actor));
      final members = await switch (source) {
        'online' =>
          repo
              .fetchOnlineMembers(roomId: '9527', page: 1, pageSize: 50)
              .then((r) => r.items),
        'offMic' => repo.fetchOffMicListeners('9527'),
        'managers' => repo.fetchManagers('9527'),
        _ => repo.fetchMutedUsers('9527'),
      };
      expect(members.single.avatar?.reference, 'avatar-preset-moon');
      expect(
        members.single.copyWith(isMuted: true).avatar,
        same(members.single.avatar),
      );
    });
  }
  test(
    'message conversation avatar read/copy uses descriptor, not legacy URL',
    () async {
      final actor = TestMediaIdentity();
      addTearDown(actor.dispose);
      final row = {
        'conversationId': 'conversation',
        'targetUserId': 2,
        'nickName': 'peer',
        'lastMessageAt': '2026-09-10T00:00:00Z',
        'unreadCount': 0,
        'content': 'text',
        'avatar': avatarProjection,
        'headImgUrl': '',
      };
      final http = MediaFakeHttp(
        (_) => MediaFakeResponse.json({
          'pageNum': 1,
          'pageSize': 100,
          'size': 100,
          'total': 1,
          'pages': 1,
          'hasMore': false,
          'list': [row],
          'records': [row],
        }),
      );
      final repo = BackendMessageRepository(
        apiClient: http.api(actor),
        routes: const BackendRouteCatalog(),
        currentUserIdProvider: () => 1,
      );
      final result = (await repo.fetchConversations()).single;
      expect(result.avatar?.reference, 'avatar-preset-moon');
      expect(result.copyWith(unreadCount: 2).avatar, same(result.avatar));
      expect(
        result
            .withServerIdentity(
              conversationId: 'next',
              serverUpdatedAt: DateTime.utc(2026),
            )
            .avatar,
        same(result.avatar),
      );
    },
  );
}
