import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/features/community/data/backend_community_repository.dart';
import 'package:voice_social_app/features/community/data/mock_community_repository.dart';
import 'package:voice_social_app/features/community/domain/community_repository.dart';
import 'package:voice_social_app/features/social/data/backend_social_repository.dart';
import 'package:voice_social_app/features/social/data/mock_social_repository.dart';
import 'package:voice_social_app/features/social/domain/social_models.dart';

void main() {
  final removed = throwsA(
    isA<UnsupportedError>().having(
      (error) => error.message,
      'product decision',
      'REMOVED_BY_PRODUCT',
    ),
  );
  for (final backend in [false, true]) {
    final client = _NoNetworkClient();
    final CommunityRepository community = backend
        ? BackendCommunityRepository(
            apiClient: client,
            routes: const BackendRouteCatalog(),
          )
        : MockCommunityRepository();
    final SocialRepository social = backend
        ? BackendSocialRepository(
            apiClient: client,
            currentUserIdProvider: () => 10001,
          )
        : MockSocialRepository();
    final operations = <String, Future<Object?> Function()>{
      'Q22-07 guild sign': () => community.signGuild('guild-1'),
      'Q23-01 CP list': community.fetchCpRelations,
      'Q23-01 CP pending': community.fetchPendingCpInvitations,
      'Q23-01 CP eligibility': () => community.checkCpEligibility(20003),
      'Q23-01 CP request': () => community.requestCp(20003),
      'Q23-01 CP accept': () =>
          community.resolveCpInvitation(invitationId: 'old', accepted: true),
      'Q23-01 CP reject': () =>
          community.resolveCpInvitation(invitationId: 'old', accepted: false),
      'Q23-01 CP end': () => community.endCpRelation('old'),
      'Q23-02 guardian and fans read': () => community.fetchGuardianFan(20003),
      'Q23-03 guardian purchase': () =>
          community.becomeGuardian(anchorUserId: 20003, levelId: 'old'),
      'Q23-04 fans join': () => community.joinFansTeam(20003),
      'Q23-05 task center': community.fetchTaskCenter,
      'Q23-05 daily sign': community.completeDailyCheckIn,
      'Q23-05 task reward': () => community.claimTask('old'),
      'Q23-06 activity catalog': community.fetchActivities,
      'Q16-02 friend send': () =>
          social.sendFriendRequest(userId: 20003, message: 'old'),
      'Q16-02 friend list': social.fetchFriendRequests,
      'Q16-02 friend accept': () =>
          social.resolveFriendRequest(requestId: 'old', accepted: true),
      'Q16-02 friend reject': () =>
          social.resolveFriendRequest(requestId: 'old', accepted: false),
    };
    for (final operation in operations.entries) {
      test(
        '${backend ? 'Backend' : 'Mock'} ${operation.key} rejects retries without requests',
        () async {
          for (var attempt = 0; attempt < 2; attempt++) {
            await expectLater(operation.value(), removed);
          }
          expect(client.calls, 0);
        },
      );
    }
    test(
      '${backend ? 'Backend' : 'Mock'} removed capabilities remain unavailable',
      () {
        expect(community.supportsActivityCatalog, isFalse);
        expect(social.supportsFriendRequestWorkflow, isFalse);
      },
    );
  }

  test(
    'retired friend writes cannot create mutual follow or change profile state',
    () async {
      final repository = MockSocialRepository();
      final before = (await repository.fetchPublicProfile(20003)).user;
      await expectLater(
        repository.resolveFriendRequest(requestId: 'request-1', accepted: true),
        removed,
      );
      final after = (await repository.fetchPublicProfile(20003)).user;
      expect(after.isFollowing, before.isFollowing);
      expect(after.isFollower, before.isFollower);
      expect(after.isFriend, before.isFriend);
      await repository.setFollowing(userId: 20003, following: true);
      expect(
        (await repository.fetchPublicProfile(20003)).user.isFriend,
        isTrue,
      );
      await repository.setFollowing(userId: 20003, following: false);
      expect(
        (await repository.fetchPublicProfile(20003)).user.isFriend,
        isFalse,
      );
    },
  );
}

/// Any transport interaction is a failure, including reads before a write.
class _NoNetworkClient implements ApiClient {
  int calls = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls++;
    throw StateError('Unexpected network access: ${invocation.memberName}');
  }
}
