import 'dart:async';

import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/community/domain/community_models.dart';
import 'package:voice_social_app/features/community/domain/community_repository.dart';

class MockCommunityRepository implements CommunityRepository {
  MockCommunityRepository()
      : _guilds = <String, GuildSummary>{
          'guild-1': const GuildSummary(
            id: 'guild-1',
            code: 'G10086',
            name: '晚风陪伴社',
            description: '认真聊天、彼此尊重，不用热闹证明关系。',
            memberCount: 128,
            ownerUserId: 20001,
            ownerName: '晚星',
            role: GuildRole.manager,
            joined: true,
            hasNewApplications: true,
            rooms: <GuildRoom>[
              GuildRoom(roomId: '880217', name: '深夜温柔陪伴', onlineUsers: 36),
              GuildRoom(roomId: '520906', name: '安静音乐电台', onlineUsers: 18),
            ],
          ),
          'guild-2': const GuildSummary(
            id: 'guild-2',
            code: 'G20018',
            name: '松弛生活局',
            description: '下班后慢一点，分享普通但真实的生活。',
            memberCount: 86,
            ownerUserId: 20003,
            ownerName: '阿岚',
          ),
          'guild-3': const GuildSummary(
            id: 'guild-3',
            code: 'G31007',
            name: '城市夜谈',
            description: '从一座城市出发，聊工作、情绪与成长。',
            memberCount: 74,
            ownerUserId: 20006,
            ownerName: '十一',
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
        ];

  final Map<String, GuildSummary> _guilds;
  final List<GuildMember> _members;
  final List<GuildApplication> _applications;
  final List<CpRelation> _cpRelations = <CpRelation>[
    const CpRelation(
      relationId: 'cp-1',
      userId: 20009,
      nickname: '林深',
      days: 46,
      boundAt: '2026-06-30',
    ),
  ];
  final List<CpInvitation> _cpInvitations = <CpInvitation>[
    const CpInvitation(
      invitationId: 'cp-invite-1',
      userId: 20010,
      nickname: '白露',
      createdAt: '今天 09:10',
    ),
  ];
  final Map<int, GuardianFanSnapshot> _guardian = <int, GuardianFanSnapshot>{
    20001: const GuardianFanSnapshot(
      anchorUserId: 20001,
      anchorName: '晚星',
      guardianLevels: <GuardianLevel>[
        GuardianLevel(id: 'guard-7', name: '七日守护', price: 660, durationDays: 7),
        GuardianLevel(id: 'guard-30', name: '月度守护', price: 1880, durationDays: 30),
      ],
      fansTeamName: '星光团',
      fansLevel: 3,
      intimacy: 1280,
      joinedFansTeam: true,
      tasks: <FansTask>[
        FansTask(id: 'fan-task-1', title: '今日进入主播房间', progress: 1, target: 1, reward: '亲密值 +10', claimed: true),
        FansTask(id: 'fan-task-2', title: '完成一次有效互动', progress: 0, target: 1, reward: '亲密值 +20'),
      ],
    ),
  };
  TaskCenterSnapshot _taskCenter = const TaskCenterSnapshot(
    signedToday: false,
    continuousDays: 3,
    checkInDays: <CheckInDay>[
      CheckInDay(day: 1, reward: '20 礼物币', completed: true),
      CheckInDay(day: 2, reward: '头像框体验卡', completed: true),
      CheckInDay(day: 3, reward: '30 礼物币', completed: true),
      CheckInDay(day: 4, reward: '进场装扮体验卡', completed: false, today: true),
      CheckInDay(day: 5, reward: '40 礼物币', completed: false),
      CheckInDay(day: 6, reward: '昵称色体验卡', completed: false),
      CheckInDay(day: 7, reward: '80 礼物币', completed: false),
    ],
    tasks: <TaskItem>[
      TaskItem(
        id: 'task-1',
        title: '进入一个正在发生的语音房',
        description: '进入有效房间并停留至少 1 分钟',
        progress: 1,
        target: 1,
        reward: '20 礼物币',
        state: TaskState.claimable,
      ),
      TaskItem(
        id: 'task-2',
        title: '发布一条真实动态',
        progress: 0,
        target: 1,
        reward: '30 经验',
        state: TaskState.inProgress,
      ),
      TaskItem(
        id: 'task-3',
        title: '完成一次每日签到',
        progress: 1,
        target: 1,
        reward: '成长值 +10',
        state: TaskState.claimed,
      ),
    ],
  );

  @override
  bool get supportsInviteAttribution => true;

  @override
  bool get supportsActivityCatalog => true;

  @override
  Future<GuildHomeSnapshot> fetchGuildHome() async {
    await _delay();
    final GuildSummary? current = _guilds.values
        .where((GuildSummary guild) => guild.joined)
        .firstOrNull;
    return GuildHomeSnapshot(
      currentGuild: current,
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
        .where((GuildSummary guild) =>
            guild.name.toLowerCase().contains(query) ||
            guild.code.toLowerCase().contains(query))
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
    if (guild.joined || guild.applicationPending) {
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
  Future<void> signGuild(String guildId) async {
    await _delay();
    final GuildSummary guild = await fetchGuild(guildId);
    if (!guild.joined) {
      throw const ApiException(
        kind: ApiFailureKind.forbidden,
        message: '加入公会后才能签到',
      );
    }
    if (guild.hasSignedToday) {
      throw const ApiException(
        kind: ApiFailureKind.business,
        message: '今天已经签到',
      );
    }
    _guilds[guildId] = guild.copyWith(hasSignedToday: true);
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
    return _applications
        .where((GuildApplication item) =>
            item.status == GuildApplicationStatus.pending)
        .toList(growable: false);
  }

  @override
  Future<void> resolveGuildApplication({
    required String applicationId,
    required bool accepted,
  }) async {
    await _delay();
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
      _members.add(GuildMember(
        recordId: 'member-${request.id}',
        userId: request.userId,
        nickname: request.nickname,
      ));
    }
  }

  @override
  Future<void> setGuildMemberMuted({
    required String memberRecordId,
    required bool muted,
  }) async {
    await _delay();
    final int index = _members.indexWhere(
      (GuildMember member) => member.recordId == memberRecordId,
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
  Future<void> removeGuildMember(String memberRecordId) async {
    await _delay();
    final int index = _members.indexWhere(
      (GuildMember member) => member.recordId == memberRecordId,
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

  @override
  Future<List<CpRelation>> fetchCpRelations() async {
    await _delay();
    return List<CpRelation>.unmodifiable(_cpRelations);
  }

  @override
  Future<List<CpInvitation>> fetchPendingCpInvitations() async {
    await _delay();
    return List<CpInvitation>.unmodifiable(_cpInvitations);
  }

  @override
  Future<CpEligibility> checkCpEligibility(int targetUserId) async {
    await _delay();
    if (targetUserId <= 0 || targetUserId == 10001) {
      return const CpEligibility(allowed: false, message: '请输入有效的其他用户 ID');
    }
    if (_cpRelations.any((CpRelation relation) => relation.userId == targetUserId)) {
      return const CpEligibility(allowed: false, message: '已经与该用户建立 CP 关系');
    }
    return const CpEligibility(
      allowed: true,
      message: '符合邀请条件，对方接受后关系才生效。',
    );
  }

  @override
  Future<String> requestCp(int targetUserId) async {
    final CpEligibility eligibility = await checkCpEligibility(targetUserId);
    if (!eligibility.allowed) {
      throw ApiException(
        kind: ApiFailureKind.business,
        message: eligibility.message,
      );
    }
    await _delay();
    return 'cp-outgoing-${DateTime.now().millisecondsSinceEpoch}';
  }

  @override
  Future<void> resolveCpInvitation({
    required String invitationId,
    required bool accepted,
  }) async {
    await _delay();
    final int index = _cpInvitations.indexWhere(
      (CpInvitation invitation) => invitation.invitationId == invitationId,
    );
    if (index < 0) {
      throw const ApiException(
        kind: ApiFailureKind.business,
        message: '邀请已处理或已过期',
      );
    }
    final CpInvitation invitation = _cpInvitations.removeAt(index);
    if (accepted) {
      _cpRelations.add(CpRelation(
        relationId: 'cp-${invitation.invitationId}',
        userId: invitation.userId,
        nickname: invitation.nickname,
        days: 1,
        boundAt: '今天',
      ));
    }
  }

  @override
  Future<GuardianFanSnapshot> fetchGuardianFan(int anchorUserId) async {
    await _delay();
    return _guardian.putIfAbsent(
      anchorUserId,
      () => GuardianFanSnapshot(
        anchorUserId: anchorUserId,
        anchorName: '用户 $anchorUserId',
        guardianLevels: const <GuardianLevel>[
          GuardianLevel(id: 'guard-7', name: '七日守护', price: 660, durationDays: 7),
          GuardianLevel(id: 'guard-30', name: '月度守护', price: 1880, durationDays: 30),
        ],
        fansTeamName: '陪伴粉团',
      ),
    );
  }

  @override
  Future<void> becomeGuardian({
    required int anchorUserId,
    required String levelId,
  }) async {
    await _delay();
    final GuardianFanSnapshot snapshot = await fetchGuardianFan(anchorUserId);
    GuardianLevel? selected;
    for (final GuardianLevel level in snapshot.guardianLevels) {
      if (level.id == levelId) {
        selected = level;
        break;
      }
    }
    if (selected == null) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '守护档位已失效',
      );
    }
    _guardian[anchorUserId] = snapshot.copyWith(currentGuardianLevel: selected);
  }

  @override
  Future<void> joinFansTeam(int anchorUserId) async {
    await _delay();
    final GuardianFanSnapshot snapshot = await fetchGuardianFan(anchorUserId);
    if (snapshot.joinedFansTeam) {
      throw const ApiException(
        kind: ApiFailureKind.business,
        message: '已经加入该粉团',
      );
    }
    _guardian[anchorUserId] = snapshot.copyWith(
      joinedFansTeam: true,
      fansLevel: 1,
      intimacy: 10,
    );
  }

  @override
  Future<TaskCenterSnapshot> fetchTaskCenter() async {
    await _delay();
    return _taskCenter;
  }

  @override
  Future<TaskCenterSnapshot> completeDailyCheckIn() async {
    await _delay();
    if (_taskCenter.signedToday) {
      throw const ApiException(
        kind: ApiFailureKind.business,
        message: '今天已经签到',
      );
    }
    _taskCenter = _taskCenter.copyWith(
      signedToday: true,
      continuousDays: _taskCenter.continuousDays + 1,
      checkInDays: <CheckInDay>[
        for (final CheckInDay day in _taskCenter.checkInDays)
          CheckInDay(
            day: day.day,
            reward: day.reward,
            completed: day.today ? true : day.completed,
            today: day.today,
          ),
      ],
    );
    return _taskCenter;
  }

  @override
  Future<TaskCenterSnapshot> claimTask(String taskId) async {
    await _delay();
    final int index = _taskCenter.tasks.indexWhere((TaskItem item) => item.id == taskId);
    if (index < 0 || _taskCenter.tasks[index].state != TaskState.claimable) {
      throw const ApiException(
        kind: ApiFailureKind.business,
        message: '任务状态已变化，请刷新后重试',
      );
    }
    final List<TaskItem> next = List<TaskItem>.of(_taskCenter.tasks);
    next[index] = next[index].copyWith(state: TaskState.claimed);
    _taskCenter = _taskCenter.copyWith(tasks: next);
    return _taskCenter;
  }

  @override
  Future<List<ThemeActivity>> fetchActivities() async {
    await _delay();
    return const <ThemeActivity>[
      ThemeActivity(
        id: 'activity-1',
        title: '周末陪伴主题房',
        summary: '围绕“这一周最想放下的事”进行真实聊天。',
        period: '8 月 15 日 20:00～23:00',
        status: ThemeActivityStatus.active,
        rules: <String>[
          '活动房仍为固定 8 麦普通语音房',
          '只保留普通礼物，不包含退役玩法',
          '有效房间入口直接进入语音房',
        ],
        routeTarget: '880217',
      ),
      ThemeActivity(
        id: 'activity-2',
        title: '城市夜谈计划',
        summary: '连续七天分享一条真实生活动态。',
        period: '8 月 18 日～8 月 24 日',
        status: ThemeActivityStatus.upcoming,
        rules: <String>['动态内容需由用户主动发布', '不使用随机匹配或附近的人'],
      ),
    ];
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
