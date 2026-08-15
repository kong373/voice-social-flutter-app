import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/features/community/domain/community_models.dart';
import 'package:voice_social_app/features/community/domain/community_repository.dart';

class BackendCommunityRepository implements CommunityRepository {
  BackendCommunityRepository({
    required ApiClient apiClient,
    required BackendRouteCatalog routes,
  })  : _apiClient = apiClient,
        _routes = routes;

  final ApiClient _apiClient;
  final BackendRouteCatalog _routes;

  @override
  bool get supportsInviteAttribution => false;

  @override
  bool get supportsActivityCatalog => false;

  @override
  Future<GuildHomeSnapshot> fetchGuildHome() async {
    final List<Object?> results = await Future.wait<Object?>(<Future<Object?>>[
      _apiClient.get(_routes.guildHomepage).then((ApiResponse value) => value.data),
      _apiClient.post(
        _routes.recommendedGuilds,
        body: <String, Object?>{'pageNum': 1, 'pageSize': 20},
      ).then((ApiResponse value) => value.data),
    ]);
    final Map<String, Object?> currentData = _asMap(results[0]);
    final GuildSummary? current = currentData.isEmpty ||
            _string(currentData['id'] ?? currentData['guildId']).isEmpty
        ? null
        : _guildFromMap(currentData);
    final List<GuildSummary> recommended = _extractList(results[1])
        .map(_guildFromMap)
        .where((GuildSummary value) => value.id.isNotEmpty)
        .toList(growable: false);
    return GuildHomeSnapshot(currentGuild: current, recommended: recommended);
  }

  @override
  Future<List<GuildSummary>> searchGuilds(String keyword) async {
    final ApiResponse response = await _apiClient.get(
      _routes.searchGuilds,
      query: <String, String>{'searchParam': keyword.trim()},
    );
    return _extractList(response.data)
        .map(_guildFromMap)
        .where((GuildSummary value) => value.id.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Future<GuildSummary> fetchGuild(String guildId) async {
    final ApiResponse response = await _apiClient.get(
      _routes.guildHomepage,
      query: <String, String>{'guildId': guildId},
    );
    final Map<String, Object?> data = _asMap(response.data);
    if (data.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '服务端未返回公会详情',
      );
    }
    return _guildFromMap(data);
  }

  @override
  Future<void> applyToJoinGuild(String guildId) async {
    await _apiClient.get(
      _routes.applyGuildMembership,
      query: <String, String>{'guildId': guildId},
    );
  }

  @override
  Future<void> quitGuild(String guildId) async {
    await _apiClient.get(
      _routes.quitGuild,
      query: <String, String>{'guildId': guildId},
    );
  }

  @override
  Future<void> signGuild(String guildId) async {
    await _apiClient.post(
      _routes.guildSign,
      body: <String, Object?>{'guildId': _numericId(guildId)},
    );
  }

  @override
  Future<List<GuildMember>> fetchGuildMembers(String guildId) async {
    final ApiResponse response = await _apiClient.post(
      _routes.guildMembers,
      body: <String, Object?>{
        'guildId': _numericId(guildId),
        'pageNum': 1,
        'pageSize': 200,
      },
    );
    return _extractList(response.data)
        .map(_memberFromMap)
        .where((GuildMember value) => value.recordId.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Future<List<GuildApplication>> fetchGuildApplications(String guildId) async {
    final ApiResponse response = await _apiClient.post(
      _routes.guildApplications,
      body: <String, Object?>{
        'guildId': _numericId(guildId),
        'pageNum': 1,
        'pageSize': 100,
      },
    );
    return _extractList(response.data)
        .map(_applicationFromMap)
        .where((GuildApplication value) => value.id.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Future<void> resolveGuildApplication({
    required String applicationId,
    required bool accepted,
  }) async {
    await _apiClient.get(
      _routes.resolveGuildApplication,
      query: <String, String>{
        'id': applicationId,
        'type': accepted ? '1' : '2',
      },
    );
  }

  @override
  Future<void> setGuildMemberMuted({
    required String memberRecordId,
    required bool muted,
  }) async {
    await _apiClient.get(
      _routes.guildMemberMute,
      query: <String, String>{
        'id': memberRecordId,
        'isMuted': muted ? '1' : '0',
      },
    );
  }

  @override
  Future<void> removeGuildMember(String memberRecordId) async {
    await _apiClient.get(
      _routes.removeGuildMember,
      query: <String, String>{'id': memberRecordId},
    );
  }

  @override
  Future<InviteAttribution> fetchInviteAttribution() async {
    return const InviteAttribution(
      available: false,
      message: '当前后端未确认面向普通用户的渠道归属查询协议。',
    );
  }

  @override
  Future<List<CpRelation>> fetchCpRelations() async {
    final ApiResponse response = await _apiClient.get(_routes.cpRelations);
    return _extractList(response.data)
        .map(_cpRelationFromMap)
        .where((CpRelation value) => value.relationId.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Future<List<CpInvitation>> fetchPendingCpInvitations() async {
    final ApiResponse response = await _apiClient.get(_routes.cpPendingInvitations);
    return _extractList(response.data)
        .map(_cpInvitationFromMap)
        .where((CpInvitation value) => value.invitationId.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Future<CpEligibility> checkCpEligibility(int targetUserId) async {
    final ApiResponse response = await _apiClient.get(
      _routes.cpEligibility,
      query: <String, String>{'targetUserId': '$targetUserId'},
    );
    final Map<String, Object?> data = _asMap(response.data);
    return CpEligibility(
      allowed: _asBool(data['allowed'] ?? data['eligible'] ?? data['canInvite']),
      message: _string(
        data['message'] ?? data['reason'],
        fallback: '以服务端关系状态为准',
      ),
    );
  }

  @override
  Future<String> requestCp(int targetUserId) async {
    final ApiResponse response = await _apiClient.post(
      _routes.cpRequest,
      body: <String, Object?>{'targetUserId': targetUserId},
    );
    final Map<String, Object?> data = _asMap(response.data);
    return _string(
      data['invitationId'] ?? data['id'],
      fallback: 'submitted',
    );
  }

  @override
  Future<void> resolveCpInvitation({
    required String invitationId,
    required bool accepted,
  }) async {
    await _apiClient.post(
      accepted ? _routes.cpAccept : _routes.cpReject,
      body: <String, Object?>{'invitationId': _numericId(invitationId)},
    );
  }

  @override
  Future<GuardianFanSnapshot> fetchGuardianFan(int anchorUserId) async {
    final List<Object?> results = await Future.wait<Object?>(<Future<Object?>>[
      _apiClient.get(_routes.guardianLevels).then((ApiResponse value) => value.data),
      _apiClient.get(
        _routes.guardianInfo,
        query: <String, String>{'anchorUserId': '$anchorUserId'},
      ).then((ApiResponse value) => value.data),
      _apiClient.get(
        _routes.fansTeamRelation,
        query: <String, String>{'anchorUserId': '$anchorUserId'},
      ).then((ApiResponse value) => value.data),
      _apiClient.get(
        _routes.fansTeamTasks,
        query: <String, String>{'anchorUserId': '$anchorUserId'},
      ).then((ApiResponse value) => value.data),
    ]);
    final List<GuardianLevel> levels = _extractList(results[0])
        .map(_guardianLevelFromMap)
        .where((GuardianLevel value) => value.id.isNotEmpty)
        .toList(growable: false);
    final Map<String, Object?> guard = _asMap(results[1]);
    final Map<String, Object?> relation = _asMap(results[2]);
    final List<FansTask> tasks = _extractList(results[3])
        .map(_fansTaskFromMap)
        .where((FansTask value) => value.id.isNotEmpty)
        .toList(growable: false);
    GuardianLevel? current;
    final String currentId = _string(
      guard['guardianLevelId'] ?? guard['levelId'] ?? guard['id'],
    );
    for (final GuardianLevel level in levels) {
      if (level.id == currentId) {
        current = level;
        break;
      }
    }
    return GuardianFanSnapshot(
      anchorUserId: anchorUserId,
      anchorName: _string(
        guard['anchorName'] ?? guard['nickName'],
        fallback: '用户 $anchorUserId',
      ),
      guardianLevels: levels,
      currentGuardianLevel: current,
      fansTeamName: _string(
        relation['fansTeamName'] ?? relation['teamName'],
        fallback: '主播粉团',
      ),
      fansLevel: _asInt(relation['level'] ?? relation['fansLevel']) ?? 0,
      intimacy: _asInt(relation['intimacy'] ?? relation['intimacyValue']) ?? 0,
      joinedFansTeam: _asBool(
        relation['joined'] ?? relation['isJoin'] ?? relation['hasJoined'],
      ),
      tasks: tasks,
    );
  }

  @override
  Future<void> becomeGuardian({
    required int anchorUserId,
    required String levelId,
  }) async {
    await _apiClient.post(
      _routes.becomeGuardian,
      body: <String, Object?>{
        'anchorUserId': anchorUserId,
        'guardianLevelId': _numericId(levelId),
      },
    );
  }

  @override
  Future<void> joinFansTeam(int anchorUserId) async {
    await _apiClient.post(
      _routes.joinFansTeam,
      body: <String, Object?>{'anchorUserId': anchorUserId},
    );
  }

  @override
  Future<TaskCenterSnapshot> fetchTaskCenter() async {
    final List<Object?> results = await Future.wait<Object?>(<Future<Object?>>[
      _apiClient.get(
        _routes.taskRecords,
        query: const <String, String>{'type': '1'},
      ).then((ApiResponse value) => value.data),
      _apiClient.get(_routes.signRewards).then((ApiResponse value) => value.data),
      _apiClient.get(_routes.todaySignStatus).then((ApiResponse value) => value.data),
    ]);
    final List<TaskItem> tasks = _extractList(results[0])
        .map(_taskFromMap)
        .where((TaskItem value) => value.id.isNotEmpty)
        .toList(growable: false);
    final List<CheckInDay> days = _extractList(results[1])
        .map(_checkInFromMap)
        .toList(growable: false);
    final Map<String, Object?> status = _asMap(results[2]);
    return TaskCenterSnapshot(
      signedToday: _asBool(
        status['signedToday'] ?? status['isSign'] ?? status['status'],
      ),
      continuousDays: _asInt(
            status['continuousDays'] ?? status['consecutiveDays'],
          ) ??
          0,
      checkInDays: days,
      tasks: tasks,
    );
  }

  @override
  Future<TaskCenterSnapshot> completeDailyCheckIn() async {
    await _apiClient.get(_routes.completeSignIn);
    return fetchTaskCenter();
  }

  @override
  Future<TaskCenterSnapshot> claimTask(String taskId) async {
    await _apiClient.get(
      _routes.claimTaskReward,
      query: <String, String>{'taskId': taskId},
    );
    return fetchTaskCenter();
  }

  @override
  Future<List<ThemeActivity>> fetchActivities() async {
    throw const ApiException(
      kind: ApiFailureKind.configuration,
      message: '当前后端没有确认统一的主题活动目录接口',
    );
  }

  static GuildSummary _guildFromMap(Map<String, Object?> item) {
    final int roleValue = _asInt(item['guildRole']) ?? -1;
    final GuildRole role = switch (roleValue) {
      10 => GuildRole.owner,
      3 => GuildRole.manager,
      0 => GuildRole.member,
      _ => GuildRole.visitor,
    };
    return GuildSummary(
      id: _string(item['id'] ?? item['guildId']),
      code: _string(item['code'] ?? item['guildCode']),
      name: _string(item['name'] ?? item['guildName'], fallback: '公会'),
      avatarUrl: _optionalString(item['headImgUrl'] ?? item['avatarUrl']),
      description: _string(item['description'] ?? item['guildDesc']),
      memberCount: _asInt(item['memberNum'] ?? item['peopleNumber']) ?? 0,
      ownerUserId: _asInt(item['owner'] ?? item['ownerUserId']) ?? 0,
      ownerName: _string(item['presidentNickName'] ?? item['ownerName']),
      role: role,
      joined: _asBool(
        item['isJoinGuild'] ?? item['isJoinCurrentGuild'] ?? role != GuildRole.visitor,
      ),
      applicationPending: _asBool(item['isCurrentGuildApply']),
      hasNewApplications: _asBool(item['hasNewApplications'] ?? item['isHotPoint']),
      hasSignedToday: _asBool(item['hasSign']),
      rooms: _asMapList(item['playhouseList'])
          .map((Map<String, Object?> room) => GuildRoom(
                roomId: _string(room['roomId'] ?? room['id']),
                name: _string(room['roomName'] ?? room['name'], fallback: '公会房'),
                onlineUsers: _asInt(room['onlineUsers'] ?? room['onlineNum']) ?? 0,
              ))
          .where((GuildRoom room) => room.roomId.isNotEmpty)
          .toList(growable: false),
    );
  }

  static GuildMember _memberFromMap(Map<String, Object?> item) {
    final int roleValue = _asInt(item['guildRole']) ?? 0;
    return GuildMember(
      recordId: _string(item['id'] ?? item['recordId']),
      userId: _asInt(item['userId']) ?? 0,
      nickname: _string(item['nickName'] ?? item['nickname'], fallback: '公会成员'),
      avatarUrl: _optionalString(item['headImgUrl'] ?? item['avatarUrl']),
      role: switch (roleValue) {
        10 => GuildRole.owner,
        3 => GuildRole.manager,
        _ => GuildRole.member,
      },
      isMuted: _asBool(item['isMuted']),
      isSigned: _asBool(item['isSignUp']),
      roomId: _optionalString(item['roomId']),
    );
  }

  static GuildApplication _applicationFromMap(Map<String, Object?> item) {
    return GuildApplication(
      id: _string(item['id'] ?? item['applicationId']),
      userId: _asInt(item['userId']) ?? 0,
      nickname: _string(item['nickName'] ?? item['nickname'], fallback: '申请用户'),
      appliedAt: _string(item['createTime'] ?? item['appliedAt']),
      message: _string(item['remark'] ?? item['message']),
    );
  }

  static CpRelation _cpRelationFromMap(Map<String, Object?> item) {
    return CpRelation(
      relationId: _string(item['relationId'] ?? item['id']),
      userId: _asInt(item['targetUserId'] ?? item['userId']) ?? 0,
      nickname: _string(item['nickname'] ?? item['nickName'], fallback: 'CP 用户'),
      avatarUrl: _optionalString(item['avatarUrl'] ?? item['headImgUrl']),
      days: _asInt(item['days'] ?? item['relationDays']) ?? 0,
      boundAt: _string(item['boundAt'] ?? item['createTime']),
    );
  }

  static CpInvitation _cpInvitationFromMap(Map<String, Object?> item) {
    return CpInvitation(
      invitationId: _string(item['invitationId'] ?? item['id']),
      userId: _asInt(item['requestUserId'] ?? item['userId']) ?? 0,
      nickname: _string(item['nickname'] ?? item['nickName'], fallback: '邀请用户'),
      avatarUrl: _optionalString(item['avatarUrl'] ?? item['headImgUrl']),
      createdAt: _string(item['createdAt'] ?? item['createTime']),
    );
  }

  static GuardianLevel _guardianLevelFromMap(Map<String, Object?> item) {
    return GuardianLevel(
      id: _string(item['id'] ?? item['levelId']),
      name: _string(item['name'] ?? item['levelName'], fallback: '守护'),
      price: _asInt(item['price'] ?? item['diamond']) ?? 0,
      durationDays: _asInt(item['durationDays'] ?? item['days']) ?? 0,
      iconUrl: _optionalString(item['iconUrl'] ?? item['icon']),
    );
  }

  static FansTask _fansTaskFromMap(Map<String, Object?> item) {
    return FansTask(
      id: _string(item['id'] ?? item['taskId']),
      title: _string(item['title'] ?? item['taskName'], fallback: '粉团任务'),
      progress: _asInt(item['progress'] ?? item['currentValue']) ?? 0,
      target: _asInt(item['target'] ?? item['targetValue']) ?? 1,
      reward: _string(item['rewardDesc'] ?? item['reward']),
      claimed: _asBool(item['claimed'] ?? item['isReceive']),
    );
  }

  static TaskItem _taskFromMap(Map<String, Object?> item) {
    final int status = _asInt(item['status'] ?? item['taskStatus']) ?? 0;
    return TaskItem(
      id: _string(item['taskId'] ?? item['id']),
      title: _string(item['taskName'] ?? item['title'], fallback: '平台任务'),
      description: _string(item['description'] ?? item['taskDesc']),
      progress: _asInt(item['progress'] ?? item['currentValue']) ?? 0,
      target: _asInt(item['target'] ?? item['targetValue']) ?? 1,
      reward: _string(item['rewardDesc'] ?? item['reward']),
      state: switch (status) {
        1 => TaskState.claimable,
        2 => TaskState.claimed,
        3 => TaskState.expired,
        _ => TaskState.inProgress,
      },
    );
  }

  static CheckInDay _checkInFromMap(Map<String, Object?> item) {
    return CheckInDay(
      day: _asInt(item['day'] ?? item['signDay']) ?? 0,
      reward: _string(item['rewardDesc'] ?? item['reward']),
      completed: _asBool(item['completed'] ?? item['isSign']),
      today: _asBool(item['today'] ?? item['isToday']),
    );
  }

  static List<Map<String, Object?>> _extractList(Object? value) {
    final Map<String, Object?> map = _asMap(value);
    final Object? source = map['records'] ??
        map['list'] ??
        map['rows'] ??
        map['items'] ??
        map['data'] ??
        value;
    return _asMapList(source);
  }

  static Object _numericId(String value) => int.tryParse(value) ?? value;
  static Map<String, Object?> _asMap(Object? value) =>
      value is Map<String, Object?> ? value : const <String, Object?>{};
  static List<Map<String, Object?>> _asMapList(Object? value) => value is List
      ? value.whereType<Map<String, Object?>>().toList(growable: false)
      : const <Map<String, Object?>>[];
  static String _string(Object? value, {String fallback = ''}) {
    final String text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }
  static String? _optionalString(Object? value) {
    final String text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }
  static int? _asInt(Object? value) =>
      value is int ? value : int.tryParse(value?.toString() ?? '');
  static bool _asBool(Object? value) =>
      value == true || value == 1 || value?.toString() == '1';
}
