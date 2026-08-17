import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/features/social/data/mock_social_repository.dart';
import 'package:voice_social_app/features/social/domain/social_models.dart';

void main() {
  test('social relations remain scoped to the selected user and action', () async {
    final MockSocialRepository repository = MockSocialRepository();

    SocialProfile profile = await repository.fetchPublicProfile(20003);
    expect(profile.user.isFollowing, isFalse);
    expect(profile.user.isFollower, isTrue);

    await repository.setFollowing(userId: 20003, following: true);
    profile = await repository.fetchPublicProfile(20003);
    expect(profile.user.isFollowing, isTrue);
    expect(profile.user.isFriend, isTrue);

    await repository.setBlocked(userId: 20003, blocked: true);
    profile = await repository.fetchPublicProfile(20003);
    expect(profile.user.isBlocked, isTrue);
    expect(profile.user.isFollowing, isFalse);
    expect(profile.user.isFriend, isFalse);
  });

  test('friend request, report, blacklist, and support ticket are deterministic', () async {
    final MockSocialRepository repository = MockSocialRepository();

    final List<FriendRequest> requests =
        await repository.fetchFriendRequests();
    expect(requests, hasLength(1));
    await repository.resolveFriendRequest(
      requestId: requests.single.id,
      accepted: true,
    );
    final SocialPage<SocialUser> friends = await repository.fetchRelations(
      type: SocialRelationList.friends,
      page: 1,
      pageSize: 20,
    );
    expect(
      friends.items.any((SocialUser user) => user.userId == 20004),
      isTrue,
    );

    final String receipt = await repository.submitReport(
      targetType: ReportTargetType.user,
      targetId: '20002',
      reasonCode: 2,
      description: '在房间公屏持续进行人身攻击，申请平台复核。',
      alsoBlock: true,
    );
    expect(receipt, startsWith('report-'));
    final SocialPage<SocialUser> blacklist = await repository.fetchBlacklist(
      page: 1,
      pageSize: 20,
    );
    expect(
      blacklist.items.any((SocialUser user) => user.userId == 20002),
      isTrue,
    );

    final SupportTicket ticket = await repository.submitFeedback(
      subject: '房间问题',
      content: '进入房间后成员列表刷新较慢，请协助排查。',
    );
    final SupportTicket restored =
        await repository.fetchSupportTicket(ticket.id);
    expect(restored.status, SupportTicketStatus.submitted);
    expect(restored.id, ticket.id);
  });
}
