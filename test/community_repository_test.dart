import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/community/data/mock_community_repository.dart';
import 'package:voice_social_app/features/community/domain/community_models.dart';

void main() {
  test(
    'mock owner is canonical; hosts cannot write guild management',
    () async {
      final owner = MockCommunityRepository();
      final guild = (await owner.fetchGuildHome()).currentGuild!;
      expect(guild.ownerUserId, 10001);
      expect(
        (await owner.fetchGuildMembers(
          guild.id,
        )).singleWhere((m) => m.userId == 10001).role,
        GuildRole.owner,
      );
      for (final role in [GuildRole.member, GuildRole.manager]) {
        final host = MockCommunityRepository(viewerRole: role);
        final before = await host.fetchGuildMembers('guild-1');
        await expectLater(
          host.fetchGuildApplications('guild-1'),
          throwsA(isA<ApiException>()),
        );
        await expectLater(
          host.resolveGuildApplication(
            applicationId: 'application-1',
            accepted: true,
          ),
          throwsA(isA<ApiException>()),
        );
        await expectLater(
          host.setGuildMemberMuted(
            guildId: 'guild-1',
            userId: 20002,
            muted: true,
          ),
          throwsA(isA<ApiException>()),
        );
        await expectLater(
          host.removeGuildMember(guildId: 'guild-1', userId: 20002),
          throwsA(isA<ApiException>()),
        );
        final after = await host.fetchGuildMembers('guild-1');
        expect(after.length, before.length);
        expect(after.singleWhere((m) => m.userId == 20002).isMuted, isFalse);
        await host.quitGuild('guild-1');
        expect((await host.fetchGuildHome()).currentGuild, isNull);
      }
    },
  );
  test('only canonical owner has guild management; legacy ADMIN is a host', () {
    expect(GuildRole.owner.canManage, isTrue);
    for (final role in [GuildRole.member, GuildRole.manager]) {
      expect(role.label, '主播');
      expect(role.canManage, isFalse);
    }
    expect(GuildRole.visitor.canManage, isFalse);
  });
  test(
    'guild operations target exact applications and member records',
    () async {
      final MockCommunityRepository repository = MockCommunityRepository();
      final GuildHomeSnapshot home = await repository.fetchGuildHome();
      expect(home.currentGuildAuthority, GuildCurrentAuthority.authoritative);
      final String guildId = home.currentGuild!.id;
      final List<GuildApplication> applications = await repository
          .fetchGuildApplications(guildId);
      final String secondId = applications[1].id;

      await repository.resolveGuildApplication(
        applicationId: secondId,
        accepted: true,
      );
      final List<GuildApplication> remaining = await repository
          .fetchGuildApplications(guildId);
      expect(
        remaining
            .firstWhere((GuildApplication item) => item.id == secondId)
            .status,
        GuildApplicationStatus.accepted,
      );
      expect(
        remaining.any(
          (GuildApplication item) => item.id == applications.first.id,
        ),
        isTrue,
      );

      final GuildMember target = (await repository.fetchGuildMembers(
        guildId,
      )).firstWhere((GuildMember item) => item.recordId == 'member-3');
      await repository.setGuildMemberMuted(
        guildId: guildId,
        userId: target.userId,
        muted: true,
      );
      expect(
        (await repository.fetchGuildMembers(guildId))
            .firstWhere((GuildMember item) => item.recordId == target.recordId)
            .isMuted,
        isTrue,
      );
    },
  );

  test(
    'duplicate or stale community actions fail instead of faking success',
    () async {
      final MockCommunityRepository repository = MockCommunityRepository();
      await repository.applyToJoinGuild('guild-2');
      expect(
        () => repository.applyToJoinGuild('guild-2'),
        throwsA(isA<ApiException>()),
      );
    },
  );
}
