import 'dart:async';

import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/community/domain/community_models.dart';
import 'package:voice_social_app/features/community/domain/community_repository.dart';

class MockCommunityRepository
    with RemovedCommunityOperations
    implements CommunityRepository {
  MockCommunityRepository()
    : _guilds = <String, GuildSummary>{
        'guild-1': const GuildSummary(
          id: 'guild-1',
          code: 'G10086',
          name: '晚风陪伴社',
          status: GuildStatus.active,
          description: '认真聊天、彼此尊重，不用热闹证明关系。',
          memberCount: 128,
          ownerUserId: 20001,
          ownerName: '晚星',
          role: GuildRole.manager,
          joined: true,
          applicationPending: false,
          hasNewApplications: true,
          hasSignedToday: false,
          rooms: <GuildRoom>[
            GuildRoom(roomId: '880217', name: '深夜温柔陪伴', onlineUsers: 36),
            GuildRoom(roomId: '520906', name: '安静音乐电台', onlineUsers: 18),
          ],
        ),
        'guild-2': const GuildSummary(
          id: 'guild-2',
          code: 'G20018',
          name: '松弛生活局',
          status: GuildStatus.active,
          description: '下班后慢一点，分享普通但真实的生活。',
          memberCount: 86,
          ownerUserId: 20003,
          ownerName: '阿岚',
          applicationPending: false,
          hasNewApplications: false,
          hasSignedToday: false,
        ),
        'guild-3': const GuildSummary(
          id: 'guild-3',
          code: 'G31007',
          name: '城市夜谈',
          status: GuildStatus.active,
          description: '从一座城市出发，聊工作、情绪与成长。',
          memberCount: 74,
          ownerUserId: 20006,
          ownerName: '十一',
          applicationPending: false,
          hasNewApplications: false,
          hasSignedToday: false,
        ),
      },
      _members = <GuildMember>[
        const GuildMember(
          recordId: 'member-1',
          userId: 20001,
          nickname: '晚星',
          role: GuildRole.owner,
          isSigned: true,
          roomId: '880217',
        ),
        const GuildMember(
          recordId: 'member-2',
          userId: 10001,
          nickname: '我',
          role: GuildRole.manager,
          isSigned: true,
        ),
        const GuildMember(
          recordId: 'member-3',
          userId: 20002,
          nickname: '南风',
          role: GuildRole.member,
          isMuted: false,
          roomId: '520906',
        ),
        const GuildMember(
          recordId: 'member-4',
          userId: 20004,
          nickname: '小满',
          role: GuildRole.member,
        ),
      ],
      _applications = <GuildApplication>[
        const GuildApplication(
          id: 'application-1',
          userId: 20007,
          nickname: '青禾',
          appliedAt: '今天 10:24',
          message: '希望加入一个认真聊天的公会。',
        ),
        const GuildApplication(
          id: 'application-2',
          userId: 20008,
          nickname: '弥生',
          appliedAt: '昨天 22:16',
          message: '经常参加陪伴主题房。',
        ),
        const GuildApplication(
          id: 'application-3',
          userId: 20013,
          nickname: '星野',
          appliedAt: '8 月 20 日',
          status: GuildApplicationStatus.accepted,
        ),
        const GuildApplication(
          id: 'application-4',
          userId: 20014,
          nickname: '青岚',
          appliedAt: '8 月 19 日',
          status: GuildApplicationStatus.rejected,
        ),
        const GuildApplication(
          id: 'application-5',
          userId: 20015,
          nickname: '冬青',
          appliedAt: '8 月 18 日',
          status: GuildApplicationStatus.expired,
        ),
      ];

  final Map<String, GuildSummary> _guilds;
  final List<GuildMember> _members;
  final List<GuildApplication> _applications;
  @override
  bool get supportsInviteAttribution => true;

  @override
  bool get supportsActivityCatalog => false;

  @override
  Future<GuildHomeSnapshot> fetchGuildHome() async {
    await _delay();
    final GuildSummary? current = _guilds.values
        .where((GuildSummary guild) => guild.joined)
        .firstOrNull;
    return GuildHomeSnapshot(
      currentGuild: current,
      currentGuildAuthority: GuildCurrentAuthority.authoritative,
      recommended: _guilds.values
          .where((GuildSummary guild) => !guild.joined)
          .toList(growable: false),
    );
  }

  @override
  Future<List<GuildSummary>> searchGuilds(String keyword) async {
    await _delay();
    final String query = keyword.trim().toLowerCase();
    if (query.isEmpty) {
      return _guilds.values.toList(growable: false);
    }
    return _guilds.values
        .where(
          (GuildSummary guild) =>
              guild.name.toLowerCase().contains(query) ||
              (guild.code?.toLowerCase().contains(query) ?? false),
        )
        .toList(growable: false);
  }

  @override
  Future<GuildSummary> fetchGuild(String guildId) async {
    await _delay();
    final GuildSummary? guild = _guilds[guildId];
    if (guild == null) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '公会不存在或已解散',
      );
    }
    return guild;
  }

  @override
  Future<void> applyToJoinGuild(String guildId) async {
    await _delay();
    final GuildSummary guild = await fetchGuild(guildId);
    _requireActiveGuild(guild);
    if (guild.joined || guild.applicationPending == true) {
      throw const ApiException(
        kind: ApiFailureKind.business,
        message: '当前公会申请状态已变化，请刷新后重试',
      );
    }
    _guilds[guildId] = guild.copyWith(applicationPending: true);
  }

  @override
  Future<void> quitGuild(String guildId) async {
    await _delay();
    final GuildSummary guild = await fetchGuild(guildId);
    _requireActiveGuild(guild);
    if (!guild.joined || guild.role == GuildRole.owner) {
      throw const ApiException(
        kind: ApiFailureKind.business,
        message: '当前身份不能退出该公会',
      );
    }
    _guilds[guildId] = guild.copyWith(
      joined: false,
      role: GuildRole.visitor,
      memberCount: (guild.memberCount - 1).clamp(0, 1 << 31).toInt(),
    );
  }

  @override
  Future<List<GuildMember>> fetchGuildMembers(String guildId) async {
    await _delay();
    await fetchGuild(guildId);
    return List<GuildMember>.unmodifiable(_members);
  }

  @override
  Future<List<GuildApplication>> fetchGuildApplications(String guildId) async {
    await _delay();
    final GuildSummary guild = await fetchGuild(guildId);
    if (!guild.role.canManage) {
      throw const ApiException(
        kind: ApiFailureKind.forbidden,
        message: '只有公会管理员可以查看申请',
      );
    }
    return List<GuildApplication>.unmodifiable(_applications);
  }

  @override
  Future<void> resolveGuildApplication({
    required String applicationId,
    required bool accepted,
  }) async {
    await _delay();
    final GuildSummary? managedGuild = _guilds.values
        .where((GuildSummary guild) => guild.role.canManage)
        .firstOrNull;
    if (managedGuild != null) {
      _requireActiveGuild(managedGuild);
    }
    final int index = _applications.indexWhere(
      (GuildApplication item) => item.id == applicationId,
    );
    if (index < 0 ||
        _applications[index].status != GuildApplicationStatus.pending) {
      throw const ApiException(
        kind: ApiFailureKind.business,
        message: '申请状态已变化，请刷新后重试',
      );
    }
    final GuildApplication request = _applications[index];
    _applications[index] = GuildApplication(
      id: request.id,
      userId: request.userId,
      nickname: request.nickname,
      appliedAt: request.appliedAt,
      message: request.message,
      status: accepted
          ? GuildApplicationStatus.accepted
          : GuildApplicationStatus.rejected,
    );
    if (accepted) {
      _members.add(
        GuildMember(
          recordId: 'member-${request.id}',
          userId: request.userId,
          nickname: request.nickname,
        ),
      );
    }
  }

  @override
  Future<void> setGuildMemberMuted({
    required String guildId,
    required int userId,
    required bool muted,
  }) async {
    await _delay();
    _requireActiveGuild(await fetchGuild(guildId));
    final int index = _members.indexWhere(
      (GuildMember member) => member.userId == userId,
    );
    if (index < 0) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '公会成员不存在',
      );
    }
    if (_members[index].role == GuildRole.owner) {
      throw const ApiException(
        kind: ApiFailureKind.forbidden,
        message: '不能对公会会长执行该操作',
      );
    }
    _members[index] = _members[index].copyWith(isMuted: muted);
  }

  @override
  Future<void> removeGuildMember({
    required String guildId,
    required int userId,
  }) async {
    await _delay();
    _requireActiveGuild(await fetchGuild(guildId));
    final int index = _members.indexWhere(
      (GuildMember member) => member.userId == userId,
    );
    if (index < 0) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '公会成员不存在',
      );
    }
    if (_members[index].role == GuildRole.owner) {
      throw const ApiException(
        kind: ApiFailureKind.forbidden,
        message: '不能移除公会会长',
      );
    }
    _members.removeAt(index);
  }

  @override
  Future<InviteAttribution> fetchInviteAttribution() async {
    await _delay();
    return const InviteAttribution(
      available: true,
      inviteCode: 'MELO8K2Q',
      channelName: '官方自然邀请',
      boundAt: '2026-08-01 14:20',
      invitedUsers: 7,
      message: '归属由服务端记录，客户端不能自行修改。',
    );
  }

  static void _requireActiveGuild(GuildSummary guild) {
    if (guild.status == GuildStatus.closed) {
      throw const ApiException(
        kind: ApiFailureKind.business,
        message: '公会已关闭，不能执行该操作',
      );
    }
  }

  static Future<void> _delay() =>
      Future<void>.delayed(const Duration(milliseconds: 35));
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final Iterator<T> iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
