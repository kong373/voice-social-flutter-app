import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/social/data/mock_social_repository.dart';
import 'package:voice_social_app/features/social/domain/social_models.dart';

void main() {
  test(
    'nickname allowance resets at Beijing midnight rather than after 24 hours',
    () async {
      DateTime now = DateTime.utc(2026, 9, 9, 15, 59, 59);
      final MockSocialRepository repository = MockSocialRepository(
        now: () => now,
      );
      Future<SocialProfile> save(String name) => repository.updateMyProfile(
        nickname: name,
        signature: '',
        sex: 2,
        birthday: '',
        city: '',
      );
      await save('午夜前');
      await expectLater(save('当天第二次'), throwsA(isA<ApiException>()));
      now = DateTime.utc(2026, 9, 9, 16);
      expect((await save('午夜后')).user.name, '午夜后');
      await expectLater(save('次日第二次'), throwsA(isA<ApiException>()));
    },
  );

  test(
    'nickname can change once daily without blocking other profile edits',
    () async {
      final MockSocialRepository repository = MockSocialRepository();
      Future<SocialProfile> save(String name, String signature) =>
          repository.updateMyProfile(
            nickname: name,
            signature: signature,
            sex: 2,
            birthday: '2000-06-18',
            city: '武汉',
          );

      await save(' 晚星 ', '只改签名，不消耗昵称次数');
      await save('新晚星', '第一次改名');
      await expectLater(
        save('第二个昵称', '此签名也不能被写入'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 40929)),
      );
      final SocialProfile preserved = await repository.fetchMyProfile();
      expect(preserved.user.name, '新晚星');
      expect(preserved.user.signature, '第一次改名');
      final SocialProfile sameName = await save(' 新晚星 ', '允许继续改签名');
      expect(sameName.user.signature, '允许继续改签名');
    },
  );

  test(
    'social relations remain scoped to the selected user and action',
    () async {
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
    },
  );

  test('report, blacklist, and support ticket are deterministic', () async {
    final MockSocialRepository repository = MockSocialRepository();

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
    final SupportTicket restored = await repository.fetchSupportTicket(
      ticket.id,
    );
    expect(restored.status, SupportTicketStatus.submitted);
    expect(restored.id, ticket.id);
  });
}
