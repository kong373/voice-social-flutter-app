import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/features/community/domain/community_models.dart';
import 'package:voice_social_app/features/community/domain/community_request_id.dart';
import 'package:voice_social_app/features/community/domain/community_repository.dart';

class BackendCommunityRepository
    with RemovedCommunityOperations
    implements CommunityRepository {
  static const int _guildPageSize = 50;
  static const int _maxPageRequests = 100;

  BackendCommunityRepository({
    required ApiClient apiClient,
    required BackendRouteCatalog routes,
  }) : _apiClient = apiClient,
       _routes = routes;

  final ApiClient _apiClient;
  final BackendRouteCatalog _routes;
  final _CommunityWriteCoordinator _writeCoordinator =
      _CommunityWriteCoordinator();
  @override
  bool get supportsInviteAttribution => true;

  @override
  bool get supportsActivityCatalog => false;

  @override
  Future<GuildHomeSnapshot> fetchGuildHome() async {
    final List<Object?> results = await Future.wait<Object?>(<Future<Object?>>[
      _apiClient
          .get(_routes.currentGuild)
          .then((ApiResponse value) => value.data),
      _fetchAllPages(
        pageSize: _guildPageSize,
        authoritativeId: (Map<String, Object?> item) =>
            _requiredNonEmptyStringField(item, 'guildId'),
        fetchPage: (int page, int pageSize) => _apiClient.post(
          _routes.recommendedGuilds,
          body: <String, Object?>{'pageNum': page, 'pageSize': pageSize},
        ),
      ),
    ]);
    final _CurrentGuildResult current = _currentGuildFromMap(
      _requiredMap(results[0]),
    );
    final List<Map<String, Object?>> raw =
        results[1] as List<Map<String, Object?>>;
    final List<GuildSummary> recommended = raw
        .map(
          (Map<String, Object?> item) =>
              _guildFromMap(item, requireActive: true),
        )
        .where((GuildSummary value) => value.id.isNotEmpty)
        .toList(growable: false);
    return GuildHomeSnapshot(
      currentGuild: current.guild,
      currentGuildAuthority: current.authority,
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
    if (guild.applicationPending == null) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '服务端公会详情缺少申请权威状态',
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

  static _CurrentGuildResult _currentGuildFromMap(Map<String, Object?> data) {
    final String currentAuthority = _requiredNonEmptyStringField(
      data,
      'currentGuildAuthority',
    );
    final String authority = _requiredNonEmptyStringField(data, 'authority');
    final bool available = _requiredBoolField(data, 'available');
    final bool fabricated = _requiredBoolField(data, 'fabricated');
    final String membershipStatus = _requiredNonEmptyStringField(
      data,
      'membershipStatus',
    );
    final String currentGuildId = _requiredStringField(data, 'currentGuildId');
    if (!data.containsKey('currentGuild')) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '当前公会响应缺少 currentGuild 字段',
      );
    }
    final Object? rawGuild = data['currentGuild'];
    if (currentAuthority != authority || fabricated) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '当前公会权威标记不一致',
      );
    }
    if (membershipStatus == 'NONE') {
      if (currentAuthority != 'AUTHORITATIVE' ||
          !available ||
          currentGuildId.isNotEmpty ||
          rawGuild != null) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '当前公会无公会空态字段不一致',
        );
      }
      return const _CurrentGuildResult(
        guild: null,
        authority: GuildCurrentAuthority.authoritative,
      );
    }
    if (membershipStatus == 'UNAVAILABLE') {
      if (currentAuthority != 'UNAVAILABLE' ||
          available ||
          currentGuildId.isNotEmpty ||
          rawGuild != null) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '当前公会不可用空态字段不一致',
        );
      }
      return const _CurrentGuildResult(
        guild: null,
        authority: GuildCurrentAuthority.unavailable,
      );
    }
    if (membershipStatus != 'ACTIVE' ||
        currentAuthority != 'AUTHORITATIVE' ||
        !available ||
        rawGuild is! Map) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '当前公会会员状态结构无效',
      );
    }
    final GuildSummary guild = _guildFromMap(
      _requiredMap(rawGuild),
      requireActive: true,
    );
    if (currentGuildId != guild.id || !guild.joined) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '当前公会身份与会员状态不一致',
      );
    }
    return _CurrentGuildResult(
      guild: guild,
      authority: GuildCurrentAuthority.authoritative,
    );
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
    final int onlineUsers = _requiredNonNegativeIntField(item, 'onlineUsers');
    final String codeValue = _requiredStringField(item, 'code');
    final String artwork = _requiredStringField(item, 'artwork');
    final bool hasNewApplications = _requiredBoolField(
      item,
      'hasNewApplications',
    );
    if (roomId.isEmpty && (roomCode.isNotEmpty || roomName.isNotEmpty)) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '公会房间编号缺失但返回了房间详情',
      );
    }
    final List<GuildRoom> rooms = roomId.isEmpty
        ? const <GuildRoom>[]
        : <GuildRoom>[
            GuildRoom(roomId: roomId, name: roomName, onlineUsers: onlineUsers),
          ];
    _requiredStringField(item, 'ownerAvatar');
    _requiredDateTimeField(item, 'createdAt');
    _requiredDateTimeField(item, 'updatedAt');
    return GuildSummary(
      id: id,
      code: codeValue.isEmpty ? null : codeValue,
      name: name,
      status: status,
      avatarUrl: artwork.isEmpty ? null : artwork,
      description: _requiredStringField(item, 'introduction'),
      memberCount: _requiredNonNegativeIntField(item, 'memberCount'),
      ownerUserId: _requiredPositiveIntField(item, 'ownerUserId'),
      ownerName: _requiredNonEmptyStringField(item, 'ownerName'),
      role: role,
      joined: joined,
      applicationPending: item.containsKey('applicationPending')
          ? _requiredBoolField(item, 'applicationPending')
          : null,
      hasNewApplications: hasNewApplications,
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
      // Historical metadata is optional after Q22-07 removes guild sign-in.
      isSigned: item['isSigned'] is bool ? item['isSigned']! as bool : null,
      roomId: _nullableString(_requiredStringField(item, 'roomId')),
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

  /// Guild mutation envelopes predate the common provider boundary
  /// field. Preserve compatibility with responses omitting the field, but
  /// never accept an explicit vendor/provider invocation.
  static void _rejectProviderInvocation(Map<String, Object?> data) {
    if (data.containsKey('providerInvocation') &&
        (data['providerInvocation'] is! bool ||
            data['providerInvocation'] == true)) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '公会写入响应禁止调用厂商',
      );
    }
  }

  static bool _hasExactBool(
    Map<String, Object?> data,
    String field,
    bool expected,
  ) => data[field] is bool && data[field] == expected;

  static String? _nullableString(String value) =>
      value.trim().isEmpty ? null : value.trim();

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

  static bool _isValidDateTime(String value) {
    final DateTime? parsed = DateTime.tryParse(value);
    return parsed != null && value.contains('T');
  }

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

class _CurrentGuildResult {
  const _CurrentGuildResult({required this.guild, required this.authority});

  final GuildSummary? guild;
  final GuildCurrentAuthority authority;
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

  void discardRetained(String intentKey) {
    _retainedRequestIds.remove(intentKey);
  }

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
