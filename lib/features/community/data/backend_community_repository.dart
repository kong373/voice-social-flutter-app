import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/features/community/domain/community_models.dart';
import 'package:voice_social_app/features/community/domain/community_request_id.dart';
import 'package:voice_social_app/features/community/domain/community_repository.dart';

class BackendCommunityRepository implements CommunityRepository {
  static const int _guildPageSize = 50;
  static const int _cpPageSize = 20;
  static const int _activityPageSize = 50;
  static const int _maxPageRequests = 100;

  BackendCommunityRepository({
    required ApiClient apiClient,
    required BackendRouteCatalog routes,
    DateTime Function()? clock,
    String Function(DateTime)? businessDateProvider,
  }) : _apiClient = apiClient,
       _routes = routes,
       _clock = clock ?? DateTime.now,
       _businessDateProvider = businessDateProvider ?? _defaultBusinessDate;

  final ApiClient _apiClient;
  final BackendRouteCatalog _routes;
  final DateTime Function() _clock;
  final String Function(DateTime) _businessDateProvider;
  final _CommunityWriteCoordinator _writeCoordinator =
      _CommunityWriteCoordinator();
  @override
  bool get supportsInviteAttribution => true;

  @override
  bool get supportsActivityCatalog => true;

  @override
  Future<GuildHomeSnapshot> fetchGuildHome() async {
    final List<Map<String, Object?>> raw = await _fetchAllPages(
      pageSize: _guildPageSize,
      authoritativeId: (Map<String, Object?> item) =>
          _requiredNonEmptyStringField(item, 'guildId'),
      fetchPage: (int page, int pageSize) => _apiClient.post(
        _routes.recommendedGuilds,
        body: <String, Object?>{'pageNum': page, 'pageSize': pageSize},
      ),
    );
    final List<GuildSummary> recommended = raw
        .map(
          (Map<String, Object?> item) =>
              _guildFromMap(item, requireActive: true),
        )
        .where((GuildSummary value) => value.id.isNotEmpty)
        .toList(growable: false);
    return GuildHomeSnapshot(
      currentGuild: null,
      currentGuildAuthority: GuildCurrentAuthority.unavailable,
      recommended: recommended,
    );
  }

  @override
  Future<List<GuildSummary>> searchGuilds(String keyword) async {
    final List<Map<String, Object?>> raw = await _fetchAllPages(
      pageSize: _guildPageSize,
      authoritativeId: (Map<String, Object?> item) =>
          _requiredNonEmptyStringField(item, 'guildId'),
      fetchPage: (int page, int pageSize) => _apiClient.get(
        _routes.searchGuilds,
        query: <String, String>{
          'keyword': keyword.trim(),
          'pageNum': '$page',
          'pageSize': '$pageSize',
        },
      ),
    );
    return raw
        .map(
          (Map<String, Object?> item) =>
              _guildFromMap(item, requireActive: true),
        )
        .where((GuildSummary value) => value.id.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Future<GuildSummary> fetchGuild(String guildId) async {
    final ApiResponse response = await _apiClient.get(
      _routes.guildHomepage,
      query: <String, String>{'guildId': guildId},
    );
    final Map<String, Object?> data = _requiredMap(response.data);
    final GuildSummary guild = _guildFromMap(data);
    if (guild.id != guildId) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '服务端公会详情标识与请求不一致',
      );
    }
    if (guild.applicationPending == null || guild.hasSignedToday == null) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '服务端公会详情缺少申请或签到权威状态',
      );
    }
    return guild;
  }

  @override
  Future<void> applyToJoinGuild(String guildId) => _runCommunityWrite<void>(
    intentKey: _writeKey('guild-apply', <Object?>[guildId]),
    serialKey: _writeKey('guild', <Object?>[guildId]),
    requestIdPrefix: 'flutter-community-guild-apply',
    action: (Map<String, String> headers) async {
      final ApiResponse response = await _apiClient.post(
        _routes.applyGuildMembership,
        headers: headers,
        body: <String, Object?>{'guildId': guildId},
      );
      final Map<String, Object?> data = _requiredMap(response.data);
      _rejectProviderInvocation(data);
      if (!_hasNonEmptyString(data['applicationId']) ||
          data['guildId'] != guildId ||
          data['status'] != 'PENDING') {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '服务端未确认入会申请为待审核',
        );
      }
    },
  );

  @override
  Future<void> quitGuild(String guildId) => _runCommunityWrite<void>(
    intentKey: _writeKey('guild-quit', <Object?>[guildId]),
    serialKey: _writeKey('guild', <Object?>[guildId]),
    requestIdPrefix: 'flutter-community-guild-quit',
    action: (Map<String, String> headers) async {
      final ApiResponse response = await _apiClient.post(
        _routes.quitGuild,
        headers: headers,
        body: <String, Object?>{'guildId': guildId},
      );
      final Map<String, Object?> data = _requiredMap(response.data);
      _rejectProviderInvocation(data);
      if (data['guildId'] != guildId ||
          data['status'] != 'LEFT' ||
          data['left'] is! bool ||
          data['left'] != true) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '服务端未确认已退出公会',
        );
      }
    },
  );

  @override
  Future<void> signGuild(String guildId) {
    final String expectedBusinessDate = _currentBusinessDate();
    return _runCommunityWrite<void>(
      // A retained unknown-outcome key belongs to one business day only. A
      // new local day must never replay yesterday's sign intent.
      intentKey: _writeKey('guild-sign', <Object?>[
        guildId,
        expectedBusinessDate,
      ]),
      serialKey: _writeKey('guild', <Object?>[guildId]),
      requestIdPrefix: 'flutter-community-guild-sign',
      action: (Map<String, String> headers) async {
        final ApiResponse response = await _apiClient.post(
          _routes.guildSign,
          headers: headers,
          body: <String, Object?>{'guildId': guildId},
        );
        final Map<String, Object?> data = _requiredMap(response.data);
        _rejectProviderInvocation(data);
        if (data['guildId'] != guildId ||
            data['signed'] is! bool ||
            data['signed'] != true ||
            data['alreadySigned'] is! bool ||
            !_isIsoDate(data['signDate']) ||
            data['signDate'] != expectedBusinessDate ||
            data['rewardPoints'] is! int ||
            data['rewardPoints'] != 1) {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '服务端未返回当前业务日的有效公会签到确认',
          );
        }
      },
    );
  }

  @override
  Future<List<GuildMember>> fetchGuildMembers(String guildId) async {
    final List<Map<String, Object?>> records = await _fetchAllPages(
      pageSize: _guildPageSize,
      authoritativeId: (Map<String, Object?> item) =>
          '${_requiredPositiveIntField(item, 'userId')}',
      fetchPage: (int page, int pageSize) => _apiClient.post(
        _routes.guildMembers,
        body: <String, Object?>{
          'guildId': guildId,
          'pageNum': page,
          'pageSize': pageSize,
        },
      ),
    );
    return records
        .map(_memberFromMap)
        .where((GuildMember value) => value.recordId.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Future<List<GuildApplication>> fetchGuildApplications(String guildId) async {
    final List<Map<String, Object?>> records = await _fetchAllPages(
      pageSize: _guildPageSize,
      authoritativeId: (Map<String, Object?> item) =>
          _requiredNonEmptyStringField(item, 'applicationId'),
      fetchPage: (int page, int pageSize) => _apiClient.post(
        _routes.guildApplications,
        body: <String, Object?>{
          'guildId': guildId,
          'pageNum': page,
          'pageSize': pageSize,
        },
      ),
    );
    return records
        .map(_applicationFromMap)
        .where((GuildApplication value) => value.id.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Future<void> resolveGuildApplication({
    required String applicationId,
    required bool accepted,
  }) => _runCommunityWrite<void>(
    intentKey: _writeKey('guild-application-resolve', <Object?>[
      applicationId,
      accepted,
    ]),
    serialKey: _writeKey('guild-application', <Object?>[applicationId]),
    requestIdPrefix: 'flutter-community-guild-application',
    action: (Map<String, String> headers) async {
      final ApiResponse response = await _apiClient.post(
        _routes.resolveGuildApplication,
        headers: headers,
        body: <String, Object?>{
          'applicationId': applicationId,
          'approved': accepted,
        },
      );
      final Map<String, Object?> data = _requiredMap(response.data);
      _rejectProviderInvocation(data);
      final String expectedStatus = accepted ? 'APPROVED' : 'REJECTED';
      if (data['applicationId'] != applicationId ||
          !_hasNonEmptyString(data['guildId']) ||
          data['status'] != expectedStatus) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '服务端未确认入会申请审核结果',
        );
      }
    },
  );

  @override
  Future<void> setGuildMemberMuted({
    required String guildId,
    required int userId,
    required bool muted,
  }) => _runCommunityWrite<void>(
    intentKey: _writeKey('guild-member-mute', <Object?>[
      guildId,
      userId,
      muted,
    ]),
    serialKey: _writeKey('guild-member', <Object?>[guildId, userId]),
    requestIdPrefix: 'flutter-community-guild-member-mute',
    action: (Map<String, String> headers) async {
      final ApiResponse response = await _apiClient.post(
        _routes.guildMemberMute,
        headers: headers,
        body: <String, Object?>{
          'guildId': guildId,
          'userId': userId,
          'muted': muted,
        },
      );
      final Map<String, Object?> data = _requiredMap(response.data);
      _rejectProviderInvocation(data);
      if (data['guildId'] != guildId ||
          data['userId'] is! int ||
          data['userId'] != userId ||
          data['muted'] is! bool ||
          data['muted'] != muted) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '服务端未确认成员禁言状态',
        );
      }
    },
  );

  @override
  Future<void> removeGuildMember({
    required String guildId,
    required int userId,
  }) => _runCommunityWrite<void>(
    intentKey: _writeKey('guild-member-remove', <Object?>[guildId, userId]),
    serialKey: _writeKey('guild-member', <Object?>[guildId, userId]),
    requestIdPrefix: 'flutter-community-guild-member-remove',
    action: (Map<String, String> headers) async {
      final ApiResponse response = await _apiClient.post(
        _routes.removeGuildMember,
        headers: headers,
        body: <String, Object?>{'guildId': guildId, 'userId': userId},
      );
      final Map<String, Object?> data = _requiredMap(response.data);
      _rejectProviderInvocation(data);
      if (data['guildId'] != guildId ||
          data['userId'] is! int ||
          data['userId'] != userId ||
          data['removed'] is! bool ||
          data['removed'] != true) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '服务端未确认成员已移出',
        );
      }
    },
  );

  @override
  Future<InviteAttribution> fetchInviteAttribution() async {
    final ApiResponse response = await _apiClient.get(
      _routes.inviteAttribution,
    );
    final Map<String, Object?> data = _requiredMap(response.data);
    final bool available = _requiredBoolField(data, 'attributionAvailable');
    final String source = _requiredStringField(data, 'source');
    if (!available) {
      if (source != 'NOT_RECORDED' ||
          !_hasExactBool(data, 'fabricated', false)) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '邀请归属空状态缺少明确的非伪造标记',
        );
      }
      return const InviteAttribution(available: false, message: 'NOT_RECORDED');
    }
    final Object? inviterUserId = data['inviterUserId'];
    final String inviterName = _requiredStringField(data, 'inviterName');
    if (inviterUserId is int) {
      if (inviterUserId <= 0 || inviterName.isEmpty) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '邀请归属包含无效邀请人身份',
        );
      }
    } else if (inviterUserId != '' || inviterName.isNotEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '邀请归属邀请人身份类型无效',
      );
    }
    final String channelCode = _requiredNonEmptyStringField(
      data,
      'channelCode',
    );
    final String attributedAt = _requiredDateTimeField(data, 'attributedAt');
    if (source != 'FIRST_PARTY_RECORDED') {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '邀请归属来源不是第一方权威记录',
      );
    }
    return InviteAttribution(
      available: true,
      inviteCode: channelCode,
      channelName: inviterName,
      boundAt: attributedAt,
      // b709 does not expose an invited-user count.
      invitedUsers: null,
      message: source,
    );
  }

  @override
  Future<List<CpRelation>> fetchCpRelations() async {
    final List<Map<String, Object?>> records = await _fetchAllPages(
      pageSize: _cpPageSize,
      authoritativeId: (Map<String, Object?> item) =>
          _requiredNonEmptyStringField(item, 'cpRelationId'),
      fetchPage: (int page, int pageSize) => _apiClient.get(
        _routes.cpRelations,
        query: <String, String>{'pageNum': '$page', 'pageSize': '$pageSize'},
      ),
    );
    return records
        .map(_cpRelationFromMap)
        .where((CpRelation value) => value.relationId.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Future<List<CpInvitation>> fetchPendingCpInvitations() async {
    final List<Map<String, Object?>> records = await _fetchAllPages(
      pageSize: _cpPageSize,
      authoritativeId: (Map<String, Object?> item) =>
          _requiredNonEmptyStringField(item, 'cpRequestId'),
      fetchPage: (int page, int pageSize) => _apiClient.get(
        _routes.cpPendingInvitations,
        query: <String, String>{'pageNum': '$page', 'pageSize': '$pageSize'},
      ),
    );
    return records
        .map(_cpInvitationFromMap)
        .where((CpInvitation value) => value.invitationId.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Future<CpEligibility> checkCpEligibility(int targetUserId) async {
    final ApiResponse response = await _apiClient.get(
      _routes.cpEligibility,
      query: <String, String>{'userId': '$targetUserId'},
    );
    final Map<String, Object?> data = _requiredMap(response.data);
    if (_requiredPositiveIntField(data, 'targetUserId') != targetUserId) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: 'CP 资格响应用户与请求不一致',
      );
    }
    final bool eligible = _requiredBoolField(data, 'eligible');
    final String reason = _requiredNonEmptyStringField(data, 'reason');
    const Set<String> reasons = <String>{
      'SELF_NOT_ALLOWED',
      'TARGET_UNAVAILABLE',
      'BLOCK_RELATION',
      'ACTIVE_CP_EXISTS',
      'PENDING_REQUEST_EXISTS',
      'ELIGIBLE',
    };
    if (!reasons.contains(reason) || eligible != (reason == 'ELIGIBLE')) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: 'CP 资格状态与原因不一致',
      );
    }
    return CpEligibility(allowed: eligible, message: reason);
  }

  @override
  Future<String> requestCp(int targetUserId) => _runCommunityWrite<String>(
    intentKey: _writeKey('cp-request', <Object?>[targetUserId]),
    serialKey: _writeKey('cp-target', <Object?>[targetUserId]),
    requestIdPrefix: 'flutter-community-cp-request',
    action: (Map<String, String> headers) =>
        _requestCpOnce(targetUserId, headers),
  );

  Future<String> _requestCpOnce(
    int targetUserId,
    Map<String, String> headers,
  ) async {
    final ApiResponse response = await _apiClient.post(
      _routes.cpRequest,
      headers: headers,
      body: <String, Object?>{'targetUserId': targetUserId},
    );
    final Map<String, Object?> data = _requiredMap(response.data);
    _rejectProviderInvocation(data);
    final Object? requestId = data['cpRequestId'];
    if (!_hasNonEmptyString(requestId) ||
        data['targetUserId'] is! int ||
        data['targetUserId'] != targetUserId ||
        data['status'] != 'PENDING') {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '服务端未确认 CP 申请为待处理',
      );
    }
    return requestId! as String;
  }

  @override
  Future<void> resolveCpInvitation({
    required String invitationId,
    required bool accepted,
  }) => _runCommunityWrite<void>(
    intentKey: _writeKey('cp-resolve', <Object?>[invitationId, accepted]),
    serialKey: _writeKey('cp-invitation', <Object?>[invitationId]),
    requestIdPrefix: 'flutter-community-cp-resolve',
    action: (Map<String, String> headers) async {
      final ApiResponse response = await _apiClient.post(
        accepted ? _routes.cpAccept : _routes.cpReject,
        headers: headers,
        body: <String, Object?>{'cpRequestId': invitationId},
      );
      final Map<String, Object?> data = _requiredMap(response.data);
      _rejectProviderInvocation(data);
      final String expectedStatus = accepted ? 'ACCEPTED' : 'REJECTED';
      final Object? relationId = data['cpRelationId'];
      if (data['cpRequestId'] != invitationId ||
          data['status'] != expectedStatus ||
          relationId is! String ||
          (accepted ? relationId.trim().isEmpty : relationId.isNotEmpty)) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '服务端未确认 CP 邀请的终态',
        );
      }
    },
  );

  @override
  Future<void> endCpRelation(String relationId) async {
    final String normalized = relationId.trim();
    if (normalized.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: 'CP 关系编号不能为空',
      );
    }
    await _runCommunityWrite<void>(
      intentKey: _writeKey('cp-end', <Object?>[normalized]),
      serialKey: _writeKey('cp-relation', <Object?>[normalized]),
      requestIdPrefix: 'flutter-community-cp-end',
      action: (Map<String, String> headers) async {
        final ApiResponse response = await _apiClient.post(
          _routes.cpEnd,
          headers: headers,
          body: <String, Object?>{'cpRelationId': normalized},
        );
        final Map<String, Object?> data = _requiredMap(response.data);
        _rejectProviderInvocation(data);
        if (data['cpRelationId'] is! String ||
            data['cpRelationId'] != normalized ||
            data['status'] is! String ||
            data['status'] != 'ENDED' ||
            data['ended'] is! bool ||
            data['ended'] != true) {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '服务端未确认 CP 关系已解除',
          );
        }
      },
    );
  }

  @override
  Future<GuardianFanSnapshot> fetchGuardianFan(int anchorUserId) async {
    final List<Object?> results = await Future.wait<Object?>(<Future<Object?>>[
      _apiClient
          .get(_routes.guardianLevels)
          .then((ApiResponse value) => value.data),
      _apiClient
          .get(
            _routes.guardianInfo,
            query: <String, String>{'anchorUserId': '$anchorUserId'},
          )
          .then((ApiResponse value) => value.data),
      _apiClient
          .get(
            _routes.fansTeamRelation,
            query: <String, String>{'anchorUserId': '$anchorUserId'},
          )
          .then((ApiResponse value) => value.data),
      _apiClient
          .get(
            _routes.fansTeamTasks,
            query: <String, String>{'anchorUserId': '$anchorUserId'},
          )
          .then((ApiResponse value) => value.data),
    ]);
    final Map<String, Object?> levelData = _requiredMap(results[0]);
    _requireProviderNotInvoked(levelData);
    final List<Map<String, Object?>> levelRows = _requiredSingleListEnvelope(
      levelData,
      requireRecords: false,
    );
    final List<GuardianLevel> levels = levelRows
        .map(_guardianLevelFromMap)
        .toList(growable: false);

    final Map<String, Object?> guard = _requiredMap(results[1]);
    _requireProviderNotInvoked(guard);
    if (_requiredPositiveIntField(guard, 'anchorUserId') != anchorUserId) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '守护信息主播与请求不一致',
      );
    }
    final String anchorName = _requiredNonEmptyStringField(guard, 'anchorName');
    if (_requiredNonEmptyStringField(guard, 'nickName') != anchorName) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '守护信息主播名称别名不一致',
      );
    }
    final String roomId = _requiredNonEmptyStringField(guard, 'roomId');
    final bool active = _requiredBoolField(guard, 'active');
    final String guardianLevelId = _requiredStringField(
      guard,
      'guardianLevelId',
    );
    if (_requiredStringField(guard, 'levelId') != guardianLevelId) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '守护等级编号别名不一致',
      );
    }
    final String levelName = _requiredStringField(guard, 'levelName');
    final int guardPrice = _requiredNonNegativeIntField(guard, 'price');
    final int guardDuration = _requiredNonNegativeIntField(
      guard,
      'durationDays',
    );
    final String startedAt = _requiredStringField(guard, 'startedAt');
    final String expiresAt = _requiredStringField(guard, 'expiresAt');

    GuardianLevel? current;
    if (active) {
      if (guardianLevelId.isEmpty ||
          levelName.isEmpty ||
          guardDuration <= 0 ||
          !_isValidDateTime(startedAt) ||
          !_isValidDateTime(expiresAt) ||
          !DateTime.parse(expiresAt).isAfter(DateTime.parse(startedAt))) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '有效守护关系缺少完整等级或时间信息',
        );
      }
      for (final GuardianLevel level in levels) {
        if (level.id == guardianLevelId) {
          current = level;
          break;
        }
      }
      if (current == null ||
          current.name != levelName ||
          current.price != guardPrice ||
          current.durationDays != guardDuration) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '当前守护等级与等级目录不一致',
        );
      }
    } else if (guardianLevelId.isNotEmpty ||
        levelName.isNotEmpty ||
        guardPrice != 0 ||
        guardDuration != 0 ||
        startedAt.isNotEmpty ||
        expiresAt.isNotEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '无守护关系却返回了守护等级状态',
      );
    }

    final Map<String, Object?> relation = _requiredMap(results[2]);
    _requireProviderNotInvoked(relation);
    _validateFansRelation(
      relation,
      anchorUserId: anchorUserId,
      expectedRoomId: roomId,
    );
    final String fansTeamId = _requiredStringField(relation, 'fansTeamId');
    final String fansTeamName = _requiredStringField(relation, 'fansTeamName');
    final bool teamExists = _requiredBoolField(relation, 'teamExists');
    final bool joined = _requiredBoolField(relation, 'joined');
    final int fansLevel = _requiredNonNegativeIntField(relation, 'fansLevel');
    final int intimacy = _requiredNonNegativeIntField(relation, 'intimacy');

    final Map<String, Object?> taskData = _requiredMap(results[3]);
    _requireProviderNotInvoked(taskData);
    _validateFansTaskEnvelope(
      taskData,
      anchorUserId: anchorUserId,
      roomId: roomId,
      fansTeamId: fansTeamId,
      fansTeamName: fansTeamName,
      teamExists: teamExists,
      joined: joined,
    );
    final List<FansTask> tasks = _requiredSingleListEnvelope(
      taskData,
      requireRecords: true,
    ).map(_fansTaskFromMap).toList(growable: false);
    if (!joined && tasks.isNotEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '未加入粉丝团却返回了粉丝任务',
      );
    }

    return GuardianFanSnapshot(
      anchorUserId: anchorUserId,
      anchorName: anchorName,
      guardianLevels: levels,
      currentGuardianLevel: current,
      fansTeamName: fansTeamName,
      fansLevel: fansLevel,
      intimacy: intimacy,
      joinedFansTeam: joined,
      tasks: tasks,
    );
  }

  @override
  Future<void> becomeGuardian({
    required int anchorUserId,
    required String levelId,
  }) => _runCommunityWrite<void>(
    intentKey: _writeKey('guardian', <Object?>[anchorUserId, levelId]),
    serialKey: _writeKey('anchor', <Object?>[anchorUserId]),
    requestIdPrefix: 'flutter-community-guardian',
    action: (Map<String, String> headers) async {
      final ApiResponse response = await _apiClient.post(
        _routes.becomeGuardian,
        headers: headers,
        body: <String, Object?>{
          'anchorUserId': anchorUserId,
          'guardianLevelId': _numericId(levelId),
        },
      );
      final Map<String, Object?> data = _requiredMap(response.data);
      if (data['anchorUserId'] is! int ||
          data['anchorUserId'] != anchorUserId ||
          data['active'] is! bool ||
          data['active'] != true ||
          data['guardianLevelId'] is! String ||
          (data['guardianLevelId']! as String).toUpperCase() !=
              levelId.trim().toUpperCase() ||
          data['providerInvocation'] is! bool ||
          data['providerInvocation'] != false) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '服务端未确认守护关系已生效',
        );
      }
    },
  );

  @override
  Future<void> joinFansTeam(int anchorUserId) => _runCommunityWrite<void>(
    intentKey: _writeKey('fans-team-join', <Object?>[anchorUserId]),
    serialKey: _writeKey('anchor', <Object?>[anchorUserId]),
    requestIdPrefix: 'flutter-community-fans-team-join',
    action: (Map<String, String> headers) async {
      final ApiResponse response = await _apiClient.post(
        _routes.joinFansTeam,
        headers: headers,
        body: <String, Object?>{'anchorUserId': anchorUserId},
      );
      final Map<String, Object?> data = _requiredMap(response.data);
      if (data['anchorUserId'] is! int ||
          data['anchorUserId'] != anchorUserId ||
          data['joined'] is! bool ||
          data['joined'] != true ||
          !_hasNonEmptyString(data['fansTeamId']) ||
          data['status'] != 'ACTIVE' ||
          data['providerInvocation'] is! bool ||
          data['providerInvocation'] != false) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '服务端未确认已加入粉丝团',
        );
      }
    },
  );

  @override
  Future<TaskCenterSnapshot> fetchTaskCenter() async {
    final List<Object?> results = await Future.wait<Object?>(<Future<Object?>>[
      _apiClient
          .get(_routes.taskRecords, query: const <String, String>{'type': '1'})
          .then((ApiResponse value) => value.data),
      _apiClient
          .get(_routes.signRewards)
          .then((ApiResponse value) => value.data),
      _apiClient
          .get(_routes.todaySignStatus)
          .then((ApiResponse value) => value.data),
    ]);
    final Map<String, Object?> taskData = _requiredMap(results[0]);
    _requireProviderNotInvoked(taskData);
    if (_requiredIntField(taskData, 'type') != 1) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '任务中心返回了非日常任务类型',
      );
    }
    final List<TaskItem> tasks = _requiredSingleListEnvelope(
      taskData,
      requireRecords: true,
    ).map(_taskFromMap).toList(growable: false);

    final Map<String, Object?> rewardData = _requiredMap(results[1]);
    _requireProviderNotInvoked(rewardData);
    final String cycleStart = _requiredDateField(rewardData, 'cycleStart');
    final String cycleEnd = _requiredDateField(rewardData, 'cycleEnd');
    if (DateTime.parse(
          cycleEnd,
        ).difference(DateTime.parse(cycleStart)).inDays !=
        6) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '签到周期不是完整七天',
      );
    }
    final List<Map<String, Object?>> rewardRows = _requiredSingleListEnvelope(
      rewardData,
      requireRecords: true,
    );
    if (rewardRows.length != 7) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '签到奖励不是完整七天',
      );
    }
    final DateTime cycleStartDate = DateTime.parse(cycleStart);
    int todayRows = 0;
    for (int index = 0; index < rewardRows.length; index += 1) {
      final Map<String, Object?> row = rewardRows[index];
      if (_requiredPositiveIntField(row, 'day') != index + 1 ||
          _requiredDateField(row, 'date') !=
              cycleStartDate
                  .add(Duration(days: index))
                  .toIso8601String()
                  .split('T')
                  .first) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '签到奖励日期与签到周期不一致',
        );
      }
      if (_requiredBoolField(row, 'today')) {
        todayRows += 1;
      }
    }
    if (todayRows != 1) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '签到奖励没有唯一今日记录',
      );
    }
    final List<CheckInDay> days = rewardRows
        .map(_checkInFromMap)
        .toList(growable: false);

    final Map<String, Object?> status = _requiredMap(results[2]);
    _requireProviderNotInvoked(status);
    final bool signedToday = _requiredBoolField(status, 'signedToday');
    if (_requiredBoolField(status, 'isSign') != signedToday) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '今日签到状态别名不一致',
      );
    }
    final int continuousDays = _requiredNonNegativeIntField(
      status,
      'continuousDays',
    );
    if (continuousDays > 366) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '连续签到天数超过服务端上限',
      );
    }
    if (_requiredNonNegativeIntField(status, 'consecutiveDays') !=
        continuousDays) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '连续签到天数别名不一致',
      );
    }
    _requiredDateField(status, 'businessDate');
    return TaskCenterSnapshot(
      signedToday: signedToday,
      continuousDays: continuousDays,
      checkInDays: days,
      tasks: tasks,
    );
  }

  @override
  Future<TaskCenterSnapshot> completeDailyCheckIn() {
    final String expectedBusinessDate = _currentBusinessDate();
    return _runCommunityWrite<TaskCenterSnapshot>(
      // The daily task intent is scoped to the local business date so an
      // ambiguous response just before midnight cannot be replayed after
      // midnight with yesterday's idempotency key.
      intentKey: _writeKey('task-daily-check-in', <Object?>[
        expectedBusinessDate,
      ]),
      serialKey: 'task-center',
      requestIdPrefix: 'flutter-community-task-check-in',
      action: (Map<String, String> headers) async {
        final ApiResponse response = await _apiClient.post(
          _routes.completeSignIn,
          headers: headers,
          body: const <String, Object?>{},
        );
        final Map<String, Object?> data = _requiredMap(response.data);
        if (data['signed'] is! bool ||
            data['signed'] != true ||
            data['signedToday'] is! bool ||
            data['signedToday'] != true ||
            data['isSign'] is! bool ||
            data['isSign'] != true ||
            data['alreadySigned'] is! bool ||
            !_isIsoDate(data['businessDate']) ||
            data['businessDate'] != expectedBusinessDate ||
            data['taskId'] is! int ||
            (data['taskId']! as int) <= 0 ||
            data['providerInvocation'] is! bool ||
            data['providerInvocation'] != false) {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '服务端未返回有效签到确认',
          );
        }
        return fetchTaskCenter();
      },
    );
  }

  @override
  Future<TaskCenterSnapshot> claimTask(String taskId) async {
    final int? normalizedTaskId = int.tryParse(taskId.trim());
    if (normalizedTaskId == null || normalizedTaskId <= 0) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '任务编号无效',
      );
    }
    return _runCommunityWrite<TaskCenterSnapshot>(
      intentKey: _writeKey('task-claim', <Object?>[normalizedTaskId]),
      serialKey: 'task-center',
      requestIdPrefix: 'flutter-community-task-claim',
      action: (Map<String, String> headers) async {
        final ApiResponse response = await _apiClient.post(
          _routes.claimTaskReward,
          headers: headers,
          body: <String, Object?>{'taskId': normalizedTaskId},
        );
        final Map<String, Object?> data = _requiredMap(response.data);
        if (data['taskId'] is! int ||
            data['taskId'] != normalizedTaskId ||
            data['claimed'] is! bool ||
            data['claimed'] != true ||
            data['isReceive'] is! bool ||
            data['isReceive'] != true ||
            data['status'] is! int ||
            data['status'] != 2 ||
            data['providerInvocation'] is! bool ||
            data['providerInvocation'] != false) {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '服务端未确认任务奖励已领取',
          );
        }
        return fetchTaskCenter();
      },
    );
  }

  @override
  Future<List<ThemeActivity>> fetchActivities() async {
    final List<Map<String, Object?>> raw = await _fetchAllPages(
      pageSize: _activityPageSize,
      authoritativeId: (Map<String, Object?> item) =>
          _requiredNonEmptyStringField(item, 'activityId'),
      onPage: (Map<String, Object?> data, int _) {
        if (!_hasExactBool(data, 'fabricated', false)) {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '活动目录缺少明确的非伪造标记',
          );
        }
        final bool available = _requiredBoolField(data, 'catalogAvailable');
        final int total = _requiredNonNegativeIntField(data, 'total');
        if (available != (total > 0)) {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '活动目录可用状态与记录总数不一致',
          );
        }
      },
      fetchPage: (int page, int pageSize) => _apiClient.get(
        _routes.activityCatalog,
        query: <String, String>{'pageNum': '$page', 'pageSize': '$pageSize'},
      ),
    );
    return raw.map(_activityFromMap).toList(growable: false);
  }

  Future<T> _runCommunityWrite<T>({
    required String intentKey,
    required String serialKey,
    required String requestIdPrefix,
    required Future<T> Function(Map<String, String> headers) action,
  }) {
    return _writeCoordinator.run<T>(
      intentKey: intentKey,
      serialKey: serialKey,
      requestIdPrefix: requestIdPrefix,
      action: action,
    );
  }

  static String _writeKey(String operation, Iterable<Object?> values) {
    final StringBuffer key = StringBuffer(operation);
    for (final Object? value in values) {
      final String text = '$value';
      key
        ..write('|')
        ..write(text.length)
        ..write(':')
        ..write(text);
    }
    return key.toString();
  }

  Future<List<Map<String, Object?>>> _fetchAllPages({
    required int pageSize,
    required String Function(Map<String, Object?> item) authoritativeId,
    required Future<ApiResponse> Function(int page, int pageSize) fetchPage,
    void Function(Map<String, Object?> data, int page)? onPage,
  }) async {
    final List<Map<String, Object?>> records = <Map<String, Object?>>[];
    final Set<String> seenAuthoritativeIds = <String>{};
    int page = 1;
    int? expectedTotal;
    int? expectedPages;
    while (true) {
      if (page > _maxPageRequests) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '服务端分页超过安全上限',
        );
      }
      final Object? rawData = (await fetchPage(page, pageSize)).data;
      final Map<String, Object?> data = _requiredMap(rawData);
      onPage?.call(data, page);
      final _CommunityPageEnvelope envelope = _pageEnvelope(
        data,
        requestedPage: page,
        requestedPageSize: pageSize,
      );
      if (expectedTotal == null) {
        expectedTotal = envelope.total;
        expectedPages = envelope.pages;
        if (expectedPages > _maxPageRequests) {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '服务端分页超过安全上限',
          );
        }
      } else if (envelope.total != expectedTotal ||
          envelope.pages != expectedPages) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '服务端分页元数据在请求间发生变化',
        );
      }
      for (final Map<String, Object?> item in envelope.items) {
        final String id = authoritativeId(item).trim();
        if (id.isEmpty || !seenAuthoritativeIds.add(id)) {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '服务端分页跨页重复 authoritative ID',
          );
        }
      }
      records.addAll(envelope.items);
      if (envelope.pages == 0 || envelope.current >= envelope.pages) {
        if (expectedTotal != records.length) {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '服务端分页记录数量与 total 不一致',
          );
        }
        return records;
      }
      if (envelope.items.isEmpty) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '服务端分页仍有后续页但当前页为空',
        );
      }
      final int nextPage = envelope.current + 1;
      if (nextPage <= page) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '服务端分页未向前推进',
        );
      }
      page = nextPage;
    }
  }

  static _CommunityPageEnvelope _pageEnvelope(
    Object? value, {
    required int requestedPage,
    required int requestedPageSize,
  }) {
    final Map<String, Object?> data = _requiredMap(value);
    final List<Object?> list = _requiredList(data['list'], field: 'list');
    final List<Object?> records = _requiredList(
      data['records'],
      field: 'records',
    );
    if (!_sameValue(list, records)) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '服务端分页 list 与 records 不一致',
      );
    }
    final int current = _requiredPageInt(data['current'], allowZero: false);
    final int pageSize = _requiredPageInt(data['pageSize'], allowZero: false);
    final Object? rawSize = data['size'];
    if (rawSize != null &&
        _requiredPageInt(rawSize, allowZero: false) != pageSize) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '服务端分页 size 与 pageSize 不一致',
      );
    }
    final int total = _requiredPageInt(data['total'], allowZero: true);
    final int pages = _requiredPageInt(data['pages'], allowZero: true);
    if (current != requestedPage || pageSize != requestedPageSize) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '服务端分页 current 或 pageSize 与请求不一致',
      );
    }
    final int expectedPages = total == 0
        ? 0
        : (total + pageSize - 1) ~/ pageSize;
    if (pages != expectedPages || (pages > 0 && current > pages)) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '服务端分页 pages 与 total 不一致',
      );
    }
    final int expectedItemCount = total == 0
        ? 0
        : (total - ((current - 1) * pageSize)).clamp(0, pageSize).toInt();
    if (list.length != expectedItemCount) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '服务端分页记录数量与 total/pageSize 不一致',
      );
    }
    final List<Map<String, Object?>> items = <Map<String, Object?>>[];
    for (final Object? rawItem in list) {
      if (rawItem is! Map) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '服务端分页包含无效记录',
        );
      }
      items.add(_requiredMap(rawItem));
    }
    if (pages == 0 && items.isNotEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '服务端空分页包含记录',
      );
    }
    return _CommunityPageEnvelope(
      items: items,
      current: current,
      pageSize: pageSize,
      total: total,
      pages: pages,
    );
  }

  static int _requiredPageInt(Object? value, {required bool allowZero}) {
    if (value is! int || value < (allowZero ? 0 : 1)) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '服务端分页元数据不是有效数字',
      );
    }
    return value;
  }

  static GuildSummary _guildFromMap(
    Map<String, Object?> item, {
    bool requireActive = false,
  }) {
    final String id = _requiredNonEmptyStringField(item, 'guildId');
    final String name = _requiredNonEmptyStringField(item, 'guildName');
    if (_requiredNonEmptyStringField(item, 'name') != name) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '公会名称别名不一致',
      );
    }
    final String rawStatus = _requiredNonEmptyStringField(item, 'status');
    final GuildStatus status = switch (rawStatus) {
      'ACTIVE' => GuildStatus.active,
      'CLOSED' => GuildStatus.closed,
      _ => throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '公会包含未知状态 $rawStatus',
      ),
    };
    if (requireActive && status != GuildStatus.active) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '公会推荐或搜索包含非开放公会',
      );
    }
    final GuildRole role = _guildRoleFromValue(
      _requiredNonEmptyStringField(item, 'viewerRole'),
    );
    final bool joined = _requiredBoolField(item, 'joined');
    if (joined != (role != GuildRole.visitor)) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '公会成员身份与加入状态不一致',
      );
    }
    final String roomId = _requiredStringField(item, 'roomId');
    final String roomCode = _requiredStringField(item, 'roomCode');
    final String roomName = _requiredStringField(item, 'roomName');
    if (roomId.isEmpty && (roomCode.isNotEmpty || roomName.isNotEmpty)) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '公会房间编号缺失但返回了房间详情',
      );
    }
    final List<GuildRoom> rooms = roomId.isEmpty
        ? const <GuildRoom>[]
        : <GuildRoom>[
            GuildRoom(
              roomId: roomId,
              name: roomName,
              // b709 does not expose an online-member count.
              onlineUsers: null,
            ),
          ];
    _requiredStringField(item, 'ownerAvatar');
    _requiredDateTimeField(item, 'createdAt');
    _requiredDateTimeField(item, 'updatedAt');
    return GuildSummary(
      id: id,
      code: null,
      name: name,
      status: status,
      // The endpoint exposes the owner's avatar, not a guild avatar. Do not
      // relabel it as guild artwork.
      avatarUrl: null,
      description: _requiredStringField(item, 'introduction'),
      memberCount: _requiredNonNegativeIntField(item, 'memberCount'),
      ownerUserId: _requiredPositiveIntField(item, 'ownerUserId'),
      ownerName: _requiredNonEmptyStringField(item, 'ownerName'),
      role: role,
      joined: joined,
      applicationPending: item.containsKey('applicationPending')
          ? _requiredBoolField(item, 'applicationPending')
          : null,
      hasNewApplications: null,
      hasSignedToday: item.containsKey('signedToday')
          ? _requiredBoolField(item, 'signedToday')
          : null,
      rooms: rooms,
    );
  }

  static GuildMember _memberFromMap(Map<String, Object?> item) {
    final int userId = _requiredPositiveIntField(item, 'userId');
    final String avatarUrl = _requiredStringField(item, 'headImgUrl');
    _requiredStringField(item, 'signature');
    _requiredDateTimeField(item, 'joinedAt');
    return GuildMember(
      recordId: '$userId',
      userId: userId,
      nickname: _requiredNonEmptyStringField(item, 'nickName'),
      avatarUrl: avatarUrl.isEmpty ? null : avatarUrl,
      role: _memberRoleFromValue(_requiredNonEmptyStringField(item, 'role')),
      isMuted: _requiredBoolField(item, 'muted'),
      // Neither field exists in the frozen b709 member row.
      isSigned: null,
      roomId: null,
    );
  }

  static GuildApplication _applicationFromMap(Map<String, Object?> item) {
    // The current presentation model has no application-avatar slot, but the
    // exact field still has to be present and correctly typed.
    _requiredStringField(item, 'headImgUrl');
    final GuildApplicationStatus status = _applicationStatusFromValue(
      item['status'],
    );
    final String resolvedAt = _requiredStringField(item, 'resolvedAt');
    if (resolvedAt.isNotEmpty && !_isValidDateTime(resolvedAt)) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '入会申请处理时间无效',
      );
    }
    if ((status == GuildApplicationStatus.pending) != resolvedAt.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '入会申请状态与处理时间不一致',
      );
    }
    return GuildApplication(
      id: _requiredNonEmptyStringField(item, 'applicationId'),
      userId: _requiredPositiveIntField(item, 'userId'),
      nickname: _requiredNonEmptyStringField(item, 'nickName'),
      appliedAt: _requiredDateTimeField(item, 'createdAt'),
      message: _requiredStringField(item, 'message'),
      status: status,
    );
  }

  static CpRelation _cpRelationFromMap(Map<String, Object?> item) {
    final String status = _requiredNonEmptyStringField(item, 'status');
    if (status != 'ACTIVE') {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: 'CP 列表包含非有效关系',
      );
    }
    final String avatarUrl = _requiredStringField(item, 'headImgUrl');
    return CpRelation(
      relationId: _requiredNonEmptyStringField(item, 'cpRelationId'),
      userId: _requiredPositiveIntField(item, 'userId'),
      nickname: _requiredNonEmptyStringField(item, 'nickName'),
      avatarUrl: avatarUrl.isEmpty ? null : avatarUrl,
      // b709 exposes createdAt but no authoritative day count.
      days: null,
      boundAt: _requiredDateTimeField(item, 'createdAt'),
    );
  }

  static CpInvitation _cpInvitationFromMap(Map<String, Object?> item) {
    if (_requiredNonEmptyStringField(item, 'status') != 'PENDING') {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '待处理 CP 列表包含非待处理邀请',
      );
    }
    _requiredStringField(item, 'message');
    final String avatarUrl = _requiredStringField(item, 'headImgUrl');
    return CpInvitation(
      invitationId: _requiredNonEmptyStringField(item, 'cpRequestId'),
      userId: _requiredPositiveIntField(item, 'userId'),
      nickname: _requiredNonEmptyStringField(item, 'nickName'),
      avatarUrl: avatarUrl.isEmpty ? null : avatarUrl,
      createdAt: _requiredDateTimeField(item, 'createdAt'),
    );
  }

  static GuardianLevel _guardianLevelFromMap(Map<String, Object?> item) {
    return GuardianLevel(
      id: _requiredNonEmptyStringField(item, 'id'),
      name: _requiredNonEmptyStringField(item, 'name'),
      price: _requiredNonNegativeIntField(item, 'price'),
      durationDays: _requiredPositiveIntField(item, 'durationDays'),
      // b709 has no icon field.
      iconUrl: null,
    );
  }

  static FansTask _fansTaskFromMap(Map<String, Object?> item) {
    final _ParsedTask parsed = _parseTask(item);
    return FansTask(
      id: '${parsed.id}',
      title: parsed.title,
      progress: parsed.progress,
      target: parsed.target,
      reward: parsed.reward,
      claimed: parsed.claimed,
    );
  }

  static TaskItem _taskFromMap(Map<String, Object?> item) {
    final _ParsedTask parsed = _parseTask(item);
    return TaskItem(
      id: '${parsed.id}',
      title: parsed.title,
      description: parsed.description,
      progress: parsed.progress,
      target: parsed.target,
      reward: parsed.reward,
      state: switch (parsed.status) {
        1 => TaskState.claimable,
        2 => TaskState.claimed,
        _ => TaskState.inProgress,
      },
    );
  }

  static CheckInDay _checkInFromMap(Map<String, Object?> item) {
    final int day = _requiredPositiveIntField(item, 'day');
    if (_requiredPositiveIntField(item, 'signDay') != day || day > 7) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '签到奖励序号无效或别名不一致',
      );
    }
    _requiredDateField(item, 'date');
    final String reward = _requiredNonEmptyStringField(item, 'rewardDesc');
    if (_requiredNonEmptyStringField(item, 'reward') != reward) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '签到奖励描述别名不一致',
      );
    }
    final bool completed = _requiredBoolField(item, 'completed');
    final bool today = _requiredBoolField(item, 'today');
    if (_requiredBoolField(item, 'isSign') != completed ||
        _requiredBoolField(item, 'isToday') != today) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '签到奖励状态别名不一致',
      );
    }
    return CheckInDay(
      day: day,
      reward: reward,
      completed: completed,
      today: today,
    );
  }

  static ThemeActivity _activityFromMap(Map<String, Object?> item) {
    final String id = _requiredNonEmptyStringField(item, 'activityId');
    final String startsAt = _requiredDateTimeField(item, 'startsAt');
    final String endsAt = _requiredDateTimeField(item, 'endsAt');
    final DateTime start = DateTime.parse(startsAt);
    final DateTime end = DateTime.parse(endsAt);
    if (!end.isAfter(start)) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '活动响应缺少有效时间范围',
      );
    }
    final String rawStatus = item.containsKey('status')
        ? _requiredNonEmptyStringField(item, 'status').toUpperCase()
        : '';
    if (rawStatus.isNotEmpty && rawStatus != 'ACTIVE') {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '活动目录包含非进行中状态 $rawStatus',
      );
    }
    // The frozen b709 endpoint only returns rows inside the active time window
    // and omits a per-row status. Keep that endpoint invariant authoritative
    // instead of deriving state from the client clock.
    const ThemeActivityStatus status = ThemeActivityStatus.active;
    return ThemeActivity(
      id: id,
      title: _requiredNonEmptyStringField(item, 'title'),
      summary: _requiredStringField(item, 'description'),
      period: '$startsAt - $endsAt',
      status: status,
    );
  }

  static GuildRole _guildRoleFromValue(Object? value) {
    final String normalized = value?.toString().trim().toUpperCase() ?? '';
    return switch (normalized) {
      'OWNER' => GuildRole.owner,
      'ADMIN' => GuildRole.manager,
      'MEMBER' => GuildRole.member,
      'NONE' => GuildRole.visitor,
      _ => throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '公会包含未知角色 $normalized',
      ),
    };
  }

  static GuildRole _memberRoleFromValue(Object? value) {
    final GuildRole role = _guildRoleFromValue(value);
    if (role == GuildRole.visitor) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '公会成员列表包含访客角色',
      );
    }
    return role;
  }

  static GuildApplicationStatus _applicationStatusFromValue(Object? value) {
    if (value is! String || value.trim().isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '入会申请缺少有效状态',
      );
    }
    final String normalized = value.trim().toUpperCase();
    return switch (normalized) {
      'PENDING' => GuildApplicationStatus.pending,
      'APPROVED' => GuildApplicationStatus.accepted,
      'REJECTED' => GuildApplicationStatus.rejected,
      'CANCELLED' => GuildApplicationStatus.expired,
      _ => throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '入会申请包含未知状态 $normalized',
      ),
    };
  }

  static _ParsedTask _parseTask(Map<String, Object?> item) {
    final int id = _requiredPositiveIntField(item, 'taskId');
    if (_requiredPositiveIntField(item, 'id') != id) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '任务编号别名不一致',
      );
    }
    _requiredNonEmptyStringField(item, 'taskCode');
    final String title = _requiredNonEmptyStringField(item, 'taskName');
    final String titleAlias = _requiredNonEmptyStringField(item, 'title');
    final String description = _requiredNonEmptyStringField(
      item,
      'description',
    );
    final String descriptionAlias = _requiredNonEmptyStringField(
      item,
      'taskDesc',
    );
    if (titleAlias != title || descriptionAlias != description) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '任务名称或描述别名不一致',
      );
    }
    final int progress = _requiredNonNegativeIntField(item, 'progress');
    if (_requiredNonNegativeIntField(item, 'currentValue') != progress) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '任务进度别名不一致',
      );
    }
    final int target = _requiredPositiveIntField(item, 'target');
    if (_requiredPositiveIntField(item, 'targetValue') != target) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '任务目标别名不一致',
      );
    }
    final String reward = _requiredNonEmptyStringField(item, 'rewardDesc');
    if (_requiredNonEmptyStringField(item, 'reward') != reward) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '任务奖励描述别名不一致',
      );
    }
    final bool claimed = _requiredBoolField(item, 'claimed');
    if (_requiredBoolField(item, 'isReceive') != claimed) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '任务领取状态别名不一致',
      );
    }
    final int status = _requiredIntField(item, 'status');
    final int expectedStatus = claimed ? 2 : (progress >= target ? 1 : 0);
    if (status != expectedStatus) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '任务状态与进度或领取状态不一致',
      );
    }
    _requiredDateField(item, 'businessDate');
    return _ParsedTask(
      id: id,
      title: title,
      description: description,
      progress: progress,
      target: target,
      reward: reward,
      claimed: claimed,
      status: status,
    );
  }

  static List<Map<String, Object?>> _requiredSingleListEnvelope(
    Map<String, Object?> data, {
    required bool requireRecords,
  }) {
    final List<Object?> list = _requiredList(data['list'], field: 'list');
    if (requireRecords) {
      final List<Object?> records = _requiredList(
        data['records'],
        field: 'records',
      );
      if (!_sameValue(list, records)) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '服务端 list 与 records 不一致',
        );
      }
    }
    final int total = _requiredNonNegativeIntField(data, 'total');
    if (total != list.length) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '服务端列表记录数量与 total 不一致',
      );
    }
    final List<Map<String, Object?>> rows = <Map<String, Object?>>[];
    for (final Object? value in list) {
      rows.add(_requiredMap(value));
    }
    return rows;
  }

  static void _requireProviderNotInvoked(Map<String, Object?> data) {
    if (!_hasExactBool(data, 'providerInvocation', false)) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '第一方响应缺少明确的未调用厂商标记',
      );
    }
  }

  /// Guild and CP mutation envelopes predate the common provider boundary
  /// field. Preserve compatibility with responses omitting the field, but
  /// never accept an explicit vendor/provider invocation.
  static void _rejectProviderInvocation(Map<String, Object?> data) {
    if (data.containsKey('providerInvocation') &&
        (data['providerInvocation'] is! bool ||
            data['providerInvocation'] == true)) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '公会或 CP 写入响应禁止调用厂商',
      );
    }
  }

  static void _validateFansRelation(
    Map<String, Object?> relation, {
    required int anchorUserId,
    required String expectedRoomId,
  }) {
    if (_requiredPositiveIntField(relation, 'anchorUserId') != anchorUserId ||
        _requiredNonEmptyStringField(relation, 'roomId') != expectedRoomId) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '粉丝团关系主播或房间与请求不一致',
      );
    }
    final String teamId = _requiredStringField(relation, 'fansTeamId');
    final String teamName = _requiredStringField(relation, 'fansTeamName');
    if (_requiredStringField(relation, 'teamName') != teamName) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '粉丝团名称别名不一致',
      );
    }
    final bool teamExists = _requiredBoolField(relation, 'teamExists');
    final int level = _requiredNonNegativeIntField(relation, 'fansLevel');
    if (_requiredNonNegativeIntField(relation, 'level') != level) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '粉丝等级别名不一致',
      );
    }
    final int intimacy = _requiredNonNegativeIntField(relation, 'intimacy');
    final bool joined = _requiredBoolField(relation, 'joined');
    if (_requiredBoolField(relation, 'isJoin') != joined) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '粉丝团加入状态别名不一致',
      );
    }
    if (joined && (!teamExists || teamId.isEmpty || teamName.isEmpty)) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '已加入粉丝团但粉丝团身份不完整',
      );
    }
    if (!joined && (level != 0 || intimacy != 0)) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '未加入粉丝团却返回了粉丝等级或亲密度',
      );
    }
    if (teamId.isEmpty != teamName.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '粉丝团编号与名称可用性不一致',
      );
    }
  }

  static void _validateFansTaskEnvelope(
    Map<String, Object?> data, {
    required int anchorUserId,
    required String roomId,
    required String fansTeamId,
    required String fansTeamName,
    required bool teamExists,
    required bool joined,
  }) {
    if (_requiredPositiveIntField(data, 'anchorUserId') != anchorUserId ||
        _requiredNonEmptyStringField(data, 'roomId') != roomId ||
        _requiredStringField(data, 'fansTeamId') != fansTeamId ||
        _requiredStringField(data, 'fansTeamName') != fansTeamName ||
        _requiredBoolField(data, 'teamExists') != teamExists ||
        _requiredBoolField(data, 'joined') != joined ||
        _requiredBoolField(data, 'isJoin') != joined) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '粉丝任务上下文与粉丝团关系不一致',
      );
    }
  }

  static bool _hasExactBool(
    Map<String, Object?> data,
    String field,
    bool expected,
  ) => data[field] is bool && data[field] == expected;

  static bool _requiredBoolField(Map<String, Object?> data, String field) {
    final Object? value = data[field];
    if (value is! bool) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '服务端字段 $field 不是布尔值',
      );
    }
    return value;
  }

  static String _requiredStringField(Map<String, Object?> data, String field) {
    final Object? value = data[field];
    if (value is! String) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '服务端字段 $field 不是字符串',
      );
    }
    return value.trim();
  }

  static String _requiredNonEmptyStringField(
    Map<String, Object?> data,
    String field,
  ) {
    final String value = _requiredStringField(data, field);
    if (value.isEmpty) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '服务端字段 $field 不能为空',
      );
    }
    return value;
  }

  static int _requiredIntField(Map<String, Object?> data, String field) {
    final Object? value = data[field];
    if (value is! int) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '服务端字段 $field 不是整数',
      );
    }
    return value;
  }

  static int _requiredPositiveIntField(
    Map<String, Object?> data,
    String field,
  ) {
    final int value = _requiredIntField(data, field);
    if (value <= 0) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '服务端字段 $field 不是正整数',
      );
    }
    return value;
  }

  static int _requiredNonNegativeIntField(
    Map<String, Object?> data,
    String field,
  ) {
    final int value = _requiredIntField(data, field);
    if (value < 0) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '服务端字段 $field 不是非负整数',
      );
    }
    return value;
  }

  static String _requiredDateTimeField(
    Map<String, Object?> data,
    String field,
  ) {
    final String value = _requiredNonEmptyStringField(data, field);
    if (!_isValidDateTime(value)) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '服务端字段 $field 不是有效时间',
      );
    }
    return value;
  }

  static String _requiredDateField(Map<String, Object?> data, String field) {
    final String value = _requiredNonEmptyStringField(data, field);
    if (!_isIsoDate(value)) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '服务端字段 $field 不是有效日期',
      );
    }
    return value;
  }

  static bool _isValidDateTime(String value) {
    final DateTime? parsed = DateTime.tryParse(value);
    return parsed != null && value.contains('T');
  }

  static Object _numericId(String value) => int.tryParse(value) ?? value;

  static Map<String, Object?> _requiredMap(Object? value) {
    if (value is! Map) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '服务端响应不是对象',
      );
    }
    final Map<String, Object?> result = <String, Object?>{};
    for (final MapEntry<Object?, Object?> entry in value.entries) {
      if (entry.key is! String) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '服务端响应包含非字符串字段名',
        );
      }
      result[entry.key! as String] = entry.value;
    }
    return result;
  }

  static List<Object?> _requiredList(Object? value, {required String field}) {
    if (value is! List) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '服务端分页 $field 不是数组',
      );
    }
    return List<Object?>.from(value);
  }

  static bool _sameValue(Object? left, Object? right) {
    if (left is List && right is List) {
      if (left.length != right.length) {
        return false;
      }
      for (int index = 0; index < left.length; index += 1) {
        if (!_sameValue(left[index], right[index])) {
          return false;
        }
      }
      return true;
    }
    if (left is Map && right is Map) {
      if (left.length != right.length ||
          !left.keys.every((Object? key) => right.containsKey(key))) {
        return false;
      }
      return left.keys.every(
        (Object? key) => _sameValue(left[key], right[key]),
      );
    }
    return left == right;
  }

  static bool _isIsoDate(Object? value) {
    if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      return false;
    }
    final DateTime? parsed = DateTime.tryParse(value);
    return parsed != null && parsed.toIso8601String().startsWith(value);
  }

  String _currentBusinessDate() {
    final String date = _businessDateProvider(_clock()).trim();
    if (!_isIsoDate(date)) {
      throw const ApiException(
        kind: ApiFailureKind.configuration,
        message: '本地业务日期无效，已拒绝签到写入',
      );
    }
    return date;
  }

  static String _defaultBusinessDate(DateTime now) =>
      now.toIso8601String().split('T').first;

  static bool _hasNonEmptyString(Object? value) =>
      value is String && value.trim().isNotEmpty;
}

class _CommunityPageEnvelope {
  const _CommunityPageEnvelope({
    required this.items,
    required this.current,
    required this.pageSize,
    required this.total,
    required this.pages,
  });

  final List<Map<String, Object?>> items;
  final int current;
  final int pageSize;
  final int total;
  final int pages;
}

class _ParsedTask {
  const _ParsedTask({
    required this.id,
    required this.title,
    required this.description,
    required this.progress,
    required this.target,
    required this.reward,
    required this.claimed,
    required this.status,
  });

  final int id;
  final String title;
  final String description;
  final int progress;
  final int target;
  final String reward;
  final bool claimed;
  final int status;
}

/// Coordinates first-party community mutations.
///
/// A logical intent has one in-flight future and one retained idempotency key.
/// Mutations that touch the same entity are chained behind one another so an
/// older response cannot race a newer state transition. The chain is made
/// failure-proof so an error from one mutation never blocks an unrelated
/// later mutation for the same entity.
class _CommunityWriteCoordinator {
  final Map<String, Future<Object?>> _inFlight = <String, Future<Object?>>{};
  final Map<String, String> _retainedRequestIds = <String, String>{};
  final Map<String, Future<void>> _serialTails = <String, Future<void>>{};

  Future<T> run<T>({
    required String intentKey,
    required String serialKey,
    required String requestIdPrefix,
    required Future<T> Function(Map<String, String> headers) action,
  }) {
    final Future<Object?>? existing = _inFlight[intentKey];
    if (existing != null) {
      return existing.then<T>((Object? value) => value as T);
    }

    final String requestId = _retainedRequestIds[intentKey] ??=
        normalizeCommunityRequestId(newCommunityRequestId(requestIdPrefix));
    final Future<void> prior = _serialTails[serialKey] ?? Future<void>.value();
    final Future<T> operation = prior
        .then<T>((_) => action(<String, String>{'X-Request-Id': requestId}))
        .then<T>(
          (T value) {
            _retainedRequestIds.remove(intentKey);
            return value;
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!shouldRetainCommunityWriteRequest(error)) {
              _retainedRequestIds.remove(intentKey);
            }
            Error.throwWithStackTrace(error, stackTrace);
          },
        );
    final Future<Object?> tracked = operation.then<Object?>((T value) => value);
    _inFlight[intentKey] = tracked;
    tracked.then<void>(
      (_) => _removeInFlight(intentKey, tracked),
      onError: (Object _, StackTrace __) => _removeInFlight(intentKey, tracked),
    );

    // Normalize the tail's error so a rejected write cannot poison the next
    // mutation for the same entity.
    final Future<void> tail = tracked.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    _serialTails[serialKey] = tail;
    tail.then<void>((_) => _removeSerialTail(serialKey, tail));
    return operation;
  }

  void _removeInFlight(String intentKey, Future<Object?> tracked) {
    if (identical(_inFlight[intentKey], tracked)) {
      _inFlight.remove(intentKey);
    }
  }

  void _removeSerialTail(String serialKey, Future<void> tail) {
    if (identical(_serialTails[serialKey], tail)) {
      _serialTails.remove(serialKey);
    }
  }
}
