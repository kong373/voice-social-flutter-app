import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/features/social/domain/social_models.dart';

class BackendSocialRepository implements SocialRepository {
  static const int _friendRequestPageSize = 50;
  static const int _maxPageRequests = 100;
  static const int _maxRequestIdLength = 80;
  static const int _requestEntropyLength = 32;
  static final Random _requestIdRandom = Random.secure();
  static final RegExp _requestIdPattern = RegExp(r'^[A-Za-z0-9._:-]{1,80}$');
  static final RegExp _friendRequestPositiveIntegerPattern = RegExp(
    r'^[0-9]+$',
  );
  static const List<String> _friendRequestUserIdAliases = <String>[
    'userId',
    'user_id',
    'userID',
    'uid',
  ];
  static const List<String> _friendRequestRequesterIdAliases = <String>[
    'requesterUserId',
    'requester_user_id',
    'requesterUserID',
    'requesterId',
    'requester_id',
    'senderUserId',
    'sender_user_id',
    'senderUserID',
    'senderId',
    'sender_id',
    'fromUserId',
    'from_user_id',
    'fromUserID',
    'fromId',
    'from_id',
  ];
  static const List<String> _friendRequestTargetIdAliases = <String>[
    'targetUserId',
    'target_user_id',
    'targetUserID',
    'targetId',
    'target_id',
    'receiverUserId',
    'receiver_user_id',
    'receiverUserID',
    'receiverId',
    'receiver_id',
    'toUserId',
    'to_user_id',
    'toUserID',
    'toId',
    'to_id',
  ];
  static const List<String> _friendRequestCurrentViewIdAliases = <String>[
    'currentUserId',
    'current_user_id',
    'currentUserID',
    'currentId',
    'current_id',
    'viewerUserId',
    'viewer_user_id',
    'viewerUserID',
    'viewerId',
    'viewer_id',
  ];

  BackendSocialRepository({
    required ApiClient apiClient,
    required int Function() currentUserIdProvider,
    BackendRouteCatalog routes = const BackendRouteCatalog(),
  }) : _apiClient = apiClient,
       _currentUserIdProvider = currentUserIdProvider,
       _routes = routes;

  final ApiClient _apiClient;
  final int Function() _currentUserIdProvider;
  final BackendRouteCatalog _routes;
  final _SocialWriteCoordinator _writeCoordinator = _SocialWriteCoordinator();
  final Map<String, Future<String>> _pendingReportSubmissions =
      <String, Future<String>>{};
  final Map<String, String> _retainedReportRequestIds = <String, String>{};
  final Map<String, Future<SupportTicket>> _pendingFeedbackSubmissions =
      <String, Future<SupportTicket>>{};
  final Map<String, String> _retainedFeedbackRequestIds = <String, String>{};

  @override
  bool get supportsFriendRequestWorkflow => true;

  @override
  bool get supportsTicketProgress => true;

  @override
  Future<SocialProfile> fetchMyProfile() async {
    final ApiResponse personalResponse = await _apiClient.get(
      _routes.personalData,
    );
    final Map<String, Object?> personal = _requiredSocialMap(
      personalResponse.data,
    );
    _validatePersonalProfile(personal);
    Map<String, Object?> homepage = const <String, Object?>{};
    try {
      final ApiResponse homepageResponse = await _apiClient.get(
        _routes.personalHomepage,
      );
      homepage = _requiredSocialMap(homepageResponse.data);
      if (homepage.isEmpty) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '用户主页响应为空',
        );
      }
    } on ApiException catch (error) {
      // Only a documented missing homepage is recoverable. Propagate
      // authentication, authorization, conflict, validation, server, and
      // network failures instead of presenting a partial profile as healthy.
      if (error.httpStatus != 404) {
        rethrow;
      }
    }
    final int userId = _requiredPositiveInt(personal, 'userId');
    return _profileFromMaps(
      userId: userId,
      personal: personal,
      homepage: homepage,
      isSelf: true,
    );
  }

  @override
  Future<SocialProfile> updateMyProfile({
    required String nickname,
    required String signature,
    required int sex,
    required String birthday,
    required String city,
  }) async {
    final String normalizedName = nickname.trim();
    final String normalizedSignature = signature.trim();
    if (normalizedName.isEmpty || normalizedName.length > 64) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '昵称长度应为 1 至 64 个字符',
      );
    }
    if (normalizedSignature.length > 150) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '个性签名不能超过 150 个字符',
      );
    }
    final String normalizedBirthday = birthday.trim();
    final String normalizedCity = city.trim();
    final int currentUserId = _currentUserIdProvider();
    if (currentUserId <= 0) {
      throw const ApiException(
        kind: ApiFailureKind.unauthorized,
        message: '登录会话已失效',
      );
    }
    return _runSocialWrite<SocialProfile>(
      operation: 'profile-update',
      intentParts: <Object?>[
        currentUserId,
        normalizedName,
        normalizedSignature,
        sex,
        normalizedBirthday,
        normalizedCity,
      ],
      serialKey: 'profile:$currentUserId',
      requestIdPrefix: 'social-profile-update',
      action: (Map<String, String> headers) async {
        final ApiResponse response = await _apiClient.patch(
          _routes.updateUserProfile,
          headers: headers,
          body: <String, Object?>{
            'nickName': normalizedName,
            'signature': normalizedSignature,
            'sex': sex,
            'birthday': normalizedBirthday,
            'address': normalizedCity,
          },
        );
        final Map<String, Object?> homepage = _requiredSocialMap(response.data);
        final SocialProfile authoritative = _profileFromMaps(
          userId: currentUserId,
          personal: const <String, Object?>{},
          homepage: homepage,
          isSelf: true,
        );
        if (authoritative.user.name != normalizedName ||
            authoritative.user.signature != normalizedSignature ||
            authoritative.sex != sex ||
            authoritative.birthday != normalizedBirthday ||
            authoritative.city != normalizedCity) {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '资料更新响应与提交内容不一致',
          );
        }
        return authoritative;
      },
    );
  }

  @override
  Future<SocialProfile> fetchPublicProfile(int userId) async {
    final ApiResponse response = await _apiClient.get(
      _routes.personalHomepage,
      query: <String, String>{'userId': '$userId'},
    );
    final Map<String, Object?> homepage = _requiredSocialMap(response.data);
    if (homepage.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '用户主页响应为空',
      );
    }
    return _profileFromMaps(
      userId: userId,
      personal: const <String, Object?>{},
      homepage: homepage,
      isSelf: false,
    );
  }

  @override
  Future<SocialPage<SocialUser>> fetchRelations({
    required SocialRelationList type,
    required int page,
    required int pageSize,
  }) async {
    _validateSocialPageRequest(page: page, pageSize: pageSize);
    final String route = switch (type) {
      SocialRelationList.following => _routes.followingList,
      SocialRelationList.followers => _routes.followersList,
      SocialRelationList.friends => _routes.friendsList,
    };
    final ApiResponse response = await _apiClient.post(
      route,
      body: <String, Object?>{
        'pageNum': page,
        'pageSize': pageSize,
        'isSearchCount': true,
      },
    );
    return _socialPage(
      response.data,
      page: page,
      pageSize: pageSize,
      mapItem: (Map<String, Object?> raw) => _relationUser(raw, type),
    );
  }

  @override
  Future<void> setFollowing({required int userId, required bool following}) {
    final int actorUserId = _currentUserIdProvider();
    return _runSocialWrite<void>(
      operation: 'set-following',
      intentParts: <Object?>[actorUserId, userId, following],
      serialKey: 'relationship:$actorUserId:$userId',
      requestIdPrefix: 'social-following',
      action: (Map<String, String> headers) async {
        final ApiResponse response = await _apiClient.get(
          _routes.setFollowing,
          headers: headers,
          query: <String, String>{
            'userId': '$userId',
            'type': following ? '1' : '0',
          },
        );
        final Map<String, Object?> data = _requiredSocialMap(response.data);
        final int responseUserId = _requiredPositiveInt(data, 'userId');
        final bool responseFollowing = _requiredBool(data, 'following');
        _requiredBool(data, 'follower');
        _requiredBool(data, 'friend');
        _requiredBool(data, 'blocked');
        if (responseUserId != userId || responseFollowing != following) {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '关注关系响应与请求不一致',
          );
        }
      },
    );
  }

  @override
  Future<FriendRequestSendResult> sendFriendRequest({
    required int userId,
    required String message,
  }) async {
    if (userId <= 0) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '好友请求目标用户无效',
      );
    }
    final String normalizedMessage = message.trim();
    if (normalizedMessage.length > 160) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '好友申请留言不能超过 160 个字符',
      );
    }
    final int actorUserId = _currentUserIdProvider();
    return _runSocialWrite<FriendRequestSendResult>(
      operation: 'friend-request-send',
      intentParts: <Object?>[actorUserId, userId, normalizedMessage],
      serialKey: 'friend-target:$actorUserId:$userId',
      requestIdPrefix: 'social-friend-send',
      action: (Map<String, String> headers) async {
        final ApiResponse response = await _apiClient.post(
          _routes.friendRequestSend,
          headers: headers,
          body: <String, Object?>{
            'userId': userId,
            'message': normalizedMessage,
          },
        );
        final Map<String, Object?> data = _requiredSocialMap(response.data);
        final String requestId = _requiredExactNonEmptyString(
          data,
          'requestId',
        );
        final FriendRequestStatus status = _friendRequestStatus(data['status']);
        if (status != FriendRequestStatus.pending) {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '好友请求响应未进入 PENDING 状态',
          );
        }
        return FriendRequestSendResult(requestId: requestId, status: status);
      },
    );
  }

  @override
  Future<List<FriendRequest>> fetchFriendRequests() async {
    final int currentUserId = _requiredFriendRequestCurrentUserId();
    final List<Map<String, Object?>> records =
        await _fetchAllFriendRequestPages();
    return records
        .map(
          (Map<String, Object?> raw) =>
              _friendRequest(raw, currentUserId: currentUserId),
        )
        .toList(growable: false);
  }

  Future<List<Map<String, Object?>>> _fetchAllFriendRequestPages() async {
    final List<Map<String, Object?>> records = <Map<String, Object?>>[];
    int page = 1;
    int? expectedTotal;
    int? expectedPages;
    while (true) {
      if (page > _maxPageRequests) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '好友请求分页超过安全上限',
        );
      }
      final ApiResponse response = await _apiClient.get(
        _routes.friendRequestList,
        query: <String, String>{
          'sent': 'false',
          'pageNum': '$page',
          'pageSize': '$_friendRequestPageSize',
        },
      );
      final _FriendRequestPageEnvelope envelope = _friendRequestPageEnvelope(
        response.data,
        requestedPage: page,
        requestedPageSize: _friendRequestPageSize,
      );
      if (expectedTotal == null) {
        expectedTotal = envelope.total;
        expectedPages = envelope.pages;
        if (expectedPages > _maxPageRequests) {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '好友请求分页超过安全上限',
          );
        }
      } else if (envelope.total != expectedTotal ||
          envelope.pages != expectedPages) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '好友请求分页元数据在请求间发生变化',
        );
      }
      records.addAll(envelope.items);
      if (envelope.pages == 0 || envelope.current >= envelope.pages) {
        return records;
      }
      if (envelope.items.isEmpty) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '好友请求分页仍有后续页但当前页为空',
        );
      }
      final int nextPage = envelope.current + 1;
      if (nextPage <= page) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '好友请求分页未向前推进',
        );
      }
      page = nextPage;
    }
  }

  @override
  Future<void> resolveFriendRequest({
    required String requestId,
    required bool accepted,
  }) async {
    final String normalizedId = requestId.trim();
    if (normalizedId.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '好友请求 ID 不能为空',
      );
    }
    final int actorUserId = _currentUserIdProvider();
    return _runSocialWrite<void>(
      operation: 'friend-request-resolve',
      intentParts: <Object?>[actorUserId, normalizedId, accepted],
      serialKey: 'friend-request:$actorUserId:$normalizedId',
      requestIdPrefix: 'social-friend-resolve',
      action: (Map<String, String> headers) async {
        final ApiResponse response = await _apiClient.post(
          _routes.friendRequestResolve,
          headers: headers,
          body: <String, Object?>{
            'requestId': normalizedId,
            'accepted': accepted,
          },
        );
        final Map<String, Object?> data = _requiredSocialMap(response.data);
        final String responseId = _requiredExactNonEmptyString(
          data,
          'requestId',
        );
        final String responseStatus = _requiredNonEmptyString(data, 'status');
        final String expectedStatus = accepted ? 'ACCEPTED' : 'REJECTED';
        if (responseId != normalizedId || responseStatus != expectedStatus) {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '好友请求处理响应与请求不一致',
          );
        }
      },
    );
  }

  @override
  Future<SocialPage<SocialUser>> fetchVisitors({
    required VisitorRecordType type,
    required int page,
    required int pageSize,
  }) async {
    _validateSocialPageRequest(page: page, pageSize: pageSize);
    final ApiResponse response = await _apiClient.get(
      _routes.visitorRecords,
      query: <String, String>{
        'type': type == VisitorRecordType.viewedMe ? '1' : '2',
        'pageNum': '$page',
        'pageSize': '$pageSize',
        'isSearchCount': 'true',
      },
    );
    return _socialPage(
      response.data,
      page: page,
      pageSize: pageSize,
      mapItem: _visitorUser,
    );
  }

  @override
  Future<PrivacySettings> fetchPrivacySettings() async {
    final ApiResponse response = await _apiClient.get(
      _routes.onlyFollowedCanFollow,
    );
    return _privacyFromMap(_asMap(response.data));
  }

  @override
  Future<PrivacySettings> updatePrivacySettings({
    required bool onlyFollowedCanFollow,
  }) {
    final int actorUserId = _currentUserIdProvider();
    return _runSocialWrite<PrivacySettings>(
      operation: 'privacy-update',
      intentParts: <Object?>[actorUserId, onlyFollowedCanFollow],
      serialKey: 'privacy:$actorUserId',
      requestIdPrefix: 'social-privacy',
      action: (Map<String, String> headers) async {
        final ApiResponse response = await _apiClient.patch(
          _routes.socialPrivacy,
          headers: headers,
          body: <String, Object?>{
            'onlyFollowedCanFollow': onlyFollowedCanFollow,
          },
        );
        final PrivacySettings settings = _privacyFromMap(
          _requiredSocialMap(response.data),
        );
        if (settings.onlyFollowedCanFollow != onlyFollowedCanFollow) {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '隐私设置响应与请求不一致',
          );
        }
        return settings;
      },
    );
  }

  @override
  Future<SocialPage<SocialUser>> fetchBlacklist({
    required int page,
    required int pageSize,
  }) async {
    _validateSocialPageRequest(page: page, pageSize: pageSize);
    final ApiResponse response = await _apiClient.post(
      _routes.blacklist,
      body: <String, Object?>{
        'pageNum': page,
        'pageSize': pageSize,
        'isSearchCount': true,
      },
    );
    return _socialPage(
      response.data,
      page: page,
      pageSize: pageSize,
      mapItem: _blacklistUser,
    );
  }

  @override
  Future<void> setBlocked({required int userId, required bool blocked}) {
    final int actorUserId = _currentUserIdProvider();
    return _runSocialWrite<void>(
      operation: 'set-blocked',
      intentParts: <Object?>[actorUserId, userId, blocked],
      serialKey: 'relationship:$actorUserId:$userId',
      requestIdPrefix: 'social-blocked',
      action: (Map<String, String> headers) async {
        final ApiResponse response = await _apiClient.get(
          _routes.setBlocked,
          headers: headers,
          query: <String, String>{
            'userId': '$userId',
            'type': blocked ? '1' : '0',
          },
        );
        final Map<String, Object?> data = _requiredSocialMap(response.data);
        final int responseUserId = _requiredPositiveInt(data, 'userId');
        final bool responseBlocked = _requiredBool(data, 'blocked');
        if (responseUserId != userId || responseBlocked != blocked) {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '黑名单关系响应与请求不一致',
          );
        }
      },
    );
  }

  @override
  Future<String> submitReport({
    required ReportTargetType targetType,
    required String targetId,
    required int reasonCode,
    required String description,
    required bool alsoBlock,
  }) async {
    final String normalizedTargetId = targetId.trim();
    final int? numericTargetId = parseCanonicalReportEntityId(
      normalizedTargetId,
    );
    if (numericTargetId == null) {
      if (targetType == ReportTargetType.room) {
        throw const ApiException(
          kind: ApiFailureKind.configuration,
          message: '当前第一方举报接口只接受数字房间 ID；该房间使用 UUID/public_id，暂不能提交举报。',
        );
      }
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '用户举报目标 ID 必须是有效的正整数',
      );
    }
    final int currentUserId = _currentUserIdProvider();
    if (currentUserId <= 0) {
      throw const ApiException(
        kind: ApiFailureKind.unauthorized,
        message: '登录会话已失效',
      );
    }
    final String normalizedDescription = description.trim();
    final String intentKey = _reportIntentKey(
      currentUserId: currentUserId,
      targetType: targetType,
      targetId: normalizedTargetId,
      reasonCode: reasonCode,
      description: normalizedDescription,
      alsoBlock: alsoBlock,
    );
    final Future<String>? pending = _pendingReportSubmissions[intentKey];
    if (pending != null) {
      return pending;
    }
    final String requestId = _retainedReportRequestIds[intentKey] ??=
        _newSocialWriteRequestId('social-report');
    final Future<String> request =
        _submitReportOnce(
          currentUserId: currentUserId,
          targetType: targetType,
          targetId: numericTargetId,
          reasonCode: reasonCode,
          description: normalizedDescription,
          alsoBlock: alsoBlock,
          requestId: requestId,
        ).then<String>(
          (String value) {
            _pendingReportSubmissions.remove(intentKey);
            _retainedReportRequestIds.remove(intentKey);
            return value;
          },
          onError: (Object error, StackTrace stackTrace) {
            _pendingReportSubmissions.remove(intentKey);
            if (!_shouldRetainSocialWriteRequest(error)) {
              _retainedReportRequestIds.remove(intentKey);
            }
            Error.throwWithStackTrace(error, stackTrace);
          },
        );
    _pendingReportSubmissions[intentKey] = request;
    return request;
  }

  Future<String> _submitReportOnce({
    required int currentUserId,
    required ReportTargetType targetType,
    required int targetId,
    required int reasonCode,
    required String description,
    required bool alsoBlock,
    required String requestId,
  }) async {
    final ApiResponse response = await _apiClient.post(
      _routes.reportUserOrRoom,
      headers: <String, String>{'X-Request-Id': _normalizeRequestId(requestId)},
      body: <String, Object?>{
        'userId': currentUserId,
        'beTipUserId': targetType == ReportTargetType.user ? targetId : null,
        'beTipRoomId': targetType == ReportTargetType.room ? targetId : null,
        'tipType': reasonCode,
        'tipDescrib': description,
        'tipOffImages': const <String>[],
        'type': alsoBlock ? 1 : 2,
      },
    );
    final Map<String, Object?> data = _asMap(response.data);
    final String reportId = _string(data['reportId']);
    if (reportId.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '举报响应缺少 reportId',
      );
    }
    if (_string(data['status']).toUpperCase() != 'SUBMITTED') {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '举报响应缺少权威 SUBMITTED 状态',
      );
    }
    return reportId;
  }

  @override
  Future<SupportChannel> fetchCustomerService() async {
    final ApiResponse response = await _apiClient.get(_routes.customerService);
    final Map<String, Object?> data = _asMap(response.data);
    return SupportChannel(
      id: _string(data['accid'], fallback: 'customer-service'),
      name: '平台客服',
      description: '即时客服会话需要腾讯 IM；当前可以提交意见反馈。',
      liveConversationAvailable: false,
    );
  }

  @override
  Future<SupportTicket> submitFeedback({
    required String subject,
    required String content,
  }) async {
    final String normalizedContent = content.trim();
    final String normalizedSubject = subject.trim();
    if (normalizedContent.isEmpty || normalizedContent.length > 1000) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '反馈内容应为 1 至 1000 个字符',
      );
    }
    if (normalizedSubject.length > 120) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '反馈主题不能超过 120 个字符',
      );
    }
    final String intentKey = _feedbackIntentKey(
      currentUserId: _currentUserIdProvider(),
      subject: normalizedSubject,
      content: normalizedContent,
    );
    final Future<SupportTicket>? pending =
        _pendingFeedbackSubmissions[intentKey];
    if (pending != null) {
      return pending;
    }
    final String requestId = _retainedFeedbackRequestIds[intentKey] ??=
        _newSocialWriteRequestId('social-feedback');
    final Future<SupportTicket> request =
        _submitFeedbackOnce(
          subject: normalizedSubject,
          content: normalizedContent,
          requestId: requestId,
        ).then<SupportTicket>(
          (SupportTicket value) {
            _pendingFeedbackSubmissions.remove(intentKey);
            _retainedFeedbackRequestIds.remove(intentKey);
            return value;
          },
          onError: (Object error, StackTrace stackTrace) {
            _pendingFeedbackSubmissions.remove(intentKey);
            if (!_shouldRetainSocialWriteRequest(error)) {
              _retainedFeedbackRequestIds.remove(intentKey);
            }
            Error.throwWithStackTrace(error, stackTrace);
          },
        );
    _pendingFeedbackSubmissions[intentKey] = request;
    return request;
  }

  Future<SupportTicket> _submitFeedbackOnce({
    required String subject,
    required String content,
    required String requestId,
  }) async {
    final ApiResponse response = await _apiClient.post(
      _routes.submitFeedback,
      headers: <String, String>{'X-Request-Id': _normalizeRequestId(requestId)},
      body: <String, Object?>{'subject': subject, 'content': content},
    );
    return _supportTicketFromMap(_asMap(response.data));
  }

  @override
  Future<SupportTicket> fetchSupportTicket(String ticketId) async {
    final String normalizedId = ticketId.trim();
    if (normalizedId.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '工单 ID 不能为空',
      );
    }
    final ApiResponse response = await _apiClient.get(
      _routes.supportTicket,
      query: <String, String>{'ticketId': normalizedId},
    );
    return _supportTicketFromMap(_asMap(response.data));
  }

  static void _validatePersonalProfile(Map<String, Object?> data) {
    _requiredPositiveInt(data, 'userId');
    _requiredNonEmptyString(data, 'loginName');
    _requiredNonEmptyString(data, 'nickName');
    _requiredString(data, 'headImageUrl');
    _requiredProfileSex(data, 'sex');
    _requiredString(data, 'birthday');
  }

  static SocialProfile _profileFromMaps({
    required int userId,
    required Map<String, Object?> personal,
    required Map<String, Object?> homepage,
    required bool isSelf,
  }) {
    final bool hasHomepage = homepage.isNotEmpty;
    final int profileId;
    final String profileName;
    final String account;
    final String avatarUrl;
    final String signature;
    final int sex;
    final String birthday;
    final String city;
    final String coverUrl;
    final int followingCount;
    final int followerCount;
    final int friendCount;
    final int postCount;
    final int level;
    final bool isFollowing;
    final bool isFriend;
    final bool isBlocked;
    final bool isOnline;
    final String roomId;

    if (hasHomepage) {
      profileId = _requiredPositiveInt(homepage, 'id');
      if (profileId != userId) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '用户主页响应 userId 与请求不一致',
        );
      }
      profileName = _requiredNonEmptyString(homepage, 'nickName');
      account = _requiredNonEmptyString(homepage, 'loginName');
      avatarUrl = _requiredString(homepage, 'headImgUrl');
      signature = _requiredString(homepage, 'signature');
      sex = _requiredProfileSex(homepage, 'sex');
      birthday = _requiredString(homepage, 'birthday');
      city = _requiredString(homepage, 'piAddress');
      coverUrl = _requiredString(homepage, 'coverImgUrl');
      followingCount = _requiredNonNegativeInt(homepage, 'attentionNum');
      followerCount = _requiredNonNegativeInt(homepage, 'fansNum');
      friendCount = _requiredNonNegativeInt(homepage, 'playmateNum');
      postCount = _requiredNonNegativeInt(homepage, 'dynamicNum');
      level = _requiredNonNegativeInt(homepage, 'level');
      final int relationCode = _requiredInt(homepage, 'isAttention');
      if (relationCode < 0 || relationCode > 2) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '用户主页响应 isAttention 无效',
        );
      }
      isFriend = relationCode == 1;
      isFollowing = relationCode == 1 || relationCode == 2;
      isBlocked = _requiredBool(homepage, 'isBlacklist');
      isOnline = _requiredBinaryInt(homepage, 'isOnline') == 1;
      final int isInRoom = _requiredBinaryInt(homepage, 'isInRoom');
      roomId = _requiredString(homepage, 'roomId');
      if (isInRoom == 1 && roomId.isEmpty) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '用户主页响应 isInRoom 与 roomId 不一致',
        );
      }
    } else {
      profileId = _requiredPositiveInt(personal, 'userId');
      if (profileId != userId) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '个人资料响应 userId 与会话不一致',
        );
      }
      profileName = _requiredNonEmptyString(personal, 'nickName');
      account = _requiredNonEmptyString(personal, 'loginName');
      avatarUrl = _requiredString(personal, 'headImageUrl');
      signature = '';
      sex = _requiredProfileSex(personal, 'sex');
      birthday = _requiredString(personal, 'birthday');
      city = '';
      coverUrl = '';
      // A 404 homepage is the one documented partial-profile fallback. The
      // personal-data endpoint has no social counters, so these values are
      // intentionally absent rather than claims about the server state.
      followingCount = 0;
      followerCount = 0;
      friendCount = 0;
      postCount = 0;
      level = 0;
      isFollowing = false;
      isFriend = false;
      isBlocked = false;
      isOnline = false;
      roomId = '';
    }
    final SocialUser user = SocialUser(
      userId: profileId,
      name: profileName,
      signature: signature,
      avatarUrl: avatarUrl,
      isFollowing: isSelf ? false : isFollowing,
      isFollower: isSelf ? false : isFriend,
      isFriend: isSelf ? false : isFriend,
      isBlocked: isSelf ? false : isBlocked,
      isOnline: isSelf ? false : isOnline,
      roomId: roomId.isEmpty ? null : roomId,
    );
    return SocialProfile(
      user: user,
      account: account,
      sex: sex,
      birthday: birthday,
      city: city,
      coverUrl: coverUrl,
      followingCount: followingCount,
      followerCount: followerCount,
      friendCount: friendCount,
      postCount: postCount,
      level: level,
    );
  }

  static SocialUser _relationUser(
    Map<String, Object?> raw,
    SocialRelationList type,
  ) {
    final int userId = _requiredPositiveInt(raw, 'userId');
    final String name = _requiredNonEmptyString(raw, 'nickName');
    final String signature = _requiredString(raw, 'signature');
    final String avatarUrl = _requiredString(raw, 'headImgUrl');
    final int isOnline = _requiredBinaryInt(raw, 'isOnline');
    final int isInRoom = _requiredBinaryInt(raw, 'isInRoom');
    final String roomId = _requiredString(raw, 'roomId');
    final int mark = _requiredBinaryInt(raw, 'mark');
    final bool isFriend = type == SocialRelationList.friends || mark == 0;
    if (isInRoom == 1 && roomId.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '关系记录 isInRoom 与 roomId 不一致',
      );
    }
    return SocialUser(
      userId: userId,
      name: name,
      signature: signature,
      avatarUrl: avatarUrl,
      isFollowing: type != SocialRelationList.followers || isFriend,
      isFollower: type != SocialRelationList.following || isFriend,
      isFriend: isFriend,
      isBlocked: false,
      isOnline: isOnline == 1,
      roomId: roomId.isEmpty ? null : roomId,
    );
  }

  static SocialUser _visitorUser(Map<String, Object?> raw) {
    final int userId = _requiredPositiveInt(raw, 'userId');
    final String name = _requiredNonEmptyString(raw, 'nickname');
    final String avatarUrl = _requiredString(raw, 'headImgUrl');
    final DateTime visitedAt = _requiredDateTime(raw, 'visitedDate');
    final int visitCount = _requiredPositiveInt(raw, 'visitUserNum');
    return SocialUser(
      userId: userId,
      name: name,
      signature: '',
      avatarUrl: avatarUrl,
      isFollowing: false,
      isFollower: false,
      isFriend: false,
      isBlocked: false,
      isOnline: false,
      visitedAt: visitedAt,
      visitCount: visitCount,
    );
  }

  static SocialUser _blacklistUser(Map<String, Object?> raw) {
    final int userId = _requiredPositiveInt(raw, 'userId');
    final String name = _requiredNonEmptyString(raw, 'nickName');
    final String avatarUrl = _requiredString(raw, 'headImgUrl');
    return SocialUser(
      userId: userId,
      name: name,
      signature: '',
      avatarUrl: avatarUrl,
      isFollowing: false,
      isFollower: false,
      isFriend: false,
      isBlocked: true,
      isOnline: false,
    );
  }

  static _FriendRequestPageEnvelope _friendRequestPageEnvelope(
    Object? value, {
    required int requestedPage,
    required int requestedPageSize,
  }) {
    final Map<String, Object?> data = _requiredSocialMap(value);
    final List<Object?> rawList = _requiredSocialList(data['list'], 'list');
    final List<Object?> rawRecords = _requiredSocialList(
      data['records'],
      'records',
    );
    final int current = _requiredFriendPageInt(
      data['current'],
      allowZero: false,
    );
    final int pageSize = _requiredFriendPageInt(
      data['pageSize'],
      allowZero: false,
    );
    final int size = _requiredFriendPageInt(data['size'], allowZero: false);
    final int total = _requiredFriendPageInt(data['total'], allowZero: true);
    final int pages = _requiredFriendPageInt(data['pages'], allowZero: true);
    if (current != requestedPage ||
        pageSize != requestedPageSize ||
        size != requestedPageSize) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '好友请求分页 current、size 或 pageSize 与请求不一致',
      );
    }
    final int expectedPages = total == 0
        ? 0
        : (total + pageSize - 1) ~/ pageSize;
    if (pages != expectedPages || (pages > 0 && current > pages)) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '好友请求分页 pages 与 total 不一致',
      );
    }
    if (rawList.length != rawRecords.length || rawList.length > pageSize) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '好友请求 list/records 数量不一致或超过 pageSize',
      );
    }
    final List<Map<String, Object?>> items = <Map<String, Object?>>[];
    for (int index = 0; index < rawList.length; index += 1) {
      final Object? listed = rawList[index];
      final Object? recorded = rawRecords[index];
      if (listed is! Map || recorded is! Map) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '好友请求列表包含无效记录',
        );
      }
      final Map<String, Object?> listedMap = _requiredSocialMap(listed);
      final Map<String, Object?> recordedMap = _requiredSocialMap(recorded);
      if (!_sameSocialMap(listedMap, recordedMap)) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '好友请求 list 与 records 内容不一致',
        );
      }
      items.add(listedMap);
    }
    if (pages == 0 && items.isNotEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '好友请求空分页包含记录',
      );
    }
    return _FriendRequestPageEnvelope(
      items: items,
      current: current,
      pageSize: pageSize,
      total: total,
      pages: pages,
    );
  }

  static int _requiredFriendPageInt(Object? value, {required bool allowZero}) {
    final int? parsed = _asInt(value);
    if (parsed == null || parsed < (allowZero ? 0 : 1)) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '好友请求分页元数据不是有效数字',
      );
    }
    return parsed;
  }

  static SocialPage<SocialUser> _socialPage(
    Object? value, {
    required int page,
    required int pageSize,
    required SocialUser Function(Map<String, Object?> raw) mapItem,
  }) {
    final Map<String, Object?> data = _requiredSocialMap(value);
    final List<Object?> rawList = _requiredSocialList(data['list'], 'list');
    final List<Object?> rawRecords = _requiredSocialList(
      data['records'],
      'records',
    );
    final int current = _requiredSocialPageInt(data['current'], 'current');
    final int size = _requiredSocialPageInt(data['size'], 'size');
    final int responsePageSize = _requiredSocialPageInt(
      data['pageSize'],
      'pageSize',
    );
    final int total = _requiredSocialPageInt(data['total'], 'total');
    final int pages = _requiredSocialPageInt(data['pages'], 'pages');
    if (current != page || size != pageSize || responsePageSize != pageSize) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '社交分页 current、size 或 pageSize 与请求不一致',
      );
    }
    final int expectedPages = total == 0
        ? 0
        : (total + pageSize - 1) ~/ pageSize;
    if (pages != expectedPages) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '社交分页 pages 与 total/pageSize 不一致',
      );
    }
    final int expectedItemCount = _expectedSocialItemCount(
      page: page,
      pageSize: pageSize,
      total: total,
      pages: pages,
    );
    if (rawList.length != expectedItemCount ||
        rawRecords.length != expectedItemCount) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '社交分页 list/records 数量与 total/pageSize 不一致',
      );
    }
    final List<Map<String, Object?>> records = <Map<String, Object?>>[
      for (final Object? raw in rawRecords) _requiredSocialMap(raw),
    ];
    final List<Map<String, Object?>> listedItems = <Map<String, Object?>>[
      for (final Object? raw in rawList) _requiredSocialMap(raw),
    ];
    for (int index = 0; index < listedItems.length; index += 1) {
      if (!_sameSocialMap(listedItems[index], records[index])) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '社交分页 list 与 records 内容不一致',
        );
      }
    }
    final List<SocialUser> items = <SocialUser>[
      for (final Map<String, Object?> raw in listedItems) mapItem(raw),
    ];
    if (current < pages && items.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '社交分页仍有后续页但当前页为空',
      );
    }
    return SocialPage<SocialUser>(
      items: items,
      page: current,
      pageSize: size,
      total: total,
      hasMore: current < pages,
    );
  }

  static void _validateSocialPageRequest({
    required int page,
    required int pageSize,
  }) {
    if (page < 1 || pageSize < 1 || pageSize > 50) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '社交分页 page 必须为正数，pageSize 必须为 1 至 50',
      );
    }
  }

  static int _requiredSocialPageInt(Object? value, String field) {
    final int? parsed = _asInt(value);
    if (parsed == null ||
        parsed < 0 ||
        (field != 'total' && field != 'pages' && parsed < 1)) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '社交分页字段 $field 不是有效数字',
      );
    }
    return parsed;
  }

  static int _expectedSocialItemCount({
    required int page,
    required int pageSize,
    required int total,
    required int pages,
  }) {
    if (total == 0 || page > pages) {
      return 0;
    }
    final int remaining = total - ((page - 1) * pageSize);
    return remaining < pageSize ? remaining : pageSize;
  }

  static Map<String, Object?> _requiredSocialMap(Object? value) {
    if (value is! Map) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '社交分页响应不是对象',
      );
    }
    final Map<String, Object?> result = <String, Object?>{};
    for (final Object? key in value.keys) {
      if (key is! String) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '社交分页对象包含非字符串字段名',
        );
      }
      result[key] = value[key];
    }
    return result;
  }

  static List<Object?> _requiredSocialList(Object? value, String field) {
    if (value is! List) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '社交分页响应缺少有效 $field',
      );
    }
    return value.cast<Object?>();
  }

  static bool _sameSocialMap(
    Map<String, Object?> first,
    Map<String, Object?> second,
  ) {
    if (first.length != second.length) {
      return false;
    }
    for (final MapEntry<String, Object?> entry in first.entries) {
      if (!second.containsKey(entry.key) || second[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }

  static Map<String, Object?> _asMap(Object? value) =>
      value is Map<String, Object?> ? value : const <String, Object?>{};

  static int _requiredInt(Map<String, Object?> data, String field) {
    final Object? value = data[field];
    if (!data.containsKey(field) || value is! int) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '社交响应缺少有效 $field',
      );
    }
    return value;
  }

  static int _requiredPositiveInt(Map<String, Object?> data, String field) {
    final int value = _requiredInt(data, field);
    if (value <= 0) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '社交响应 $field 不是有效正数',
      );
    }
    return value;
  }

  static int _requiredNonNegativeInt(Map<String, Object?> data, String field) {
    final int value = _requiredInt(data, field);
    if (value < 0) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '社交响应 $field 不是有效非负数',
      );
    }
    return value;
  }

  static int _requiredBinaryInt(Map<String, Object?> data, String field) {
    final int value = _requiredInt(data, field);
    if (value != 0 && value != 1) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '社交响应 $field 不是有效布尔数字',
      );
    }
    return value;
  }

  static int _requiredProfileSex(Map<String, Object?> data, String field) {
    final int value = _requiredInt(data, field);
    if (value < 0 || value > 2) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '社交响应 $field 不是有效性别值',
      );
    }
    return value;
  }

  static bool _requiredBool(Map<String, Object?> data, String field) {
    final Object? value = data[field];
    if (!data.containsKey(field) || value is! bool) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '社交响应缺少明确布尔字段 $field',
      );
    }
    return value;
  }

  static String _requiredString(Map<String, Object?> data, String field) {
    final Object? value = data[field];
    if (!data.containsKey(field) || value is! String) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '社交响应缺少有效 $field',
      );
    }
    return value.trim();
  }

  static String _requiredNonEmptyString(
    Map<String, Object?> data,
    String field,
  ) {
    final String value = _requiredString(data, field);
    if (value.isEmpty) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '社交响应 $field 不能为空',
      );
    }
    return value;
  }

  static String _requiredExactNonEmptyString(
    Map<String, Object?> data,
    String field,
  ) {
    final Object? raw = data[field];
    if (!data.containsKey(field) || raw is! String || raw.isEmpty) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '社交响应 $field 不能为空',
      );
    }
    if (raw.trim() != raw) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '社交响应 $field 格式无效',
      );
    }
    return raw;
  }

  static DateTime _requiredDateTime(Map<String, Object?> data, String field) {
    final String value = _requiredNonEmptyString(data, field);
    final DateTime? parsed = DateTime.tryParse(value);
    if (parsed == null) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '社交响应 $field 不是有效时间',
      );
    }
    return parsed;
  }

  static int? _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    return int.tryParse(value?.toString() ?? '');
  }

  static bool _asBool(Object? value) {
    if (value is bool) {
      return value;
    }
    if (_asInt(value) == 1) {
      return true;
    }
    return value?.toString().trim().toLowerCase() == 'true';
  }

  static String _string(Object? value, {String fallback = ''}) {
    final String result = value?.toString().trim() ?? '';
    return result.isEmpty ? fallback : result;
  }

  static DateTime? _asDateTime(Object? value) =>
      DateTime.tryParse(value?.toString() ?? '');

  int _requiredFriendRequestCurrentUserId() {
    final int currentUserId = _currentUserIdProvider();
    if (currentUserId <= 0) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '好友请求当前视图用户 ID 不是有效正数',
      );
    }
    return currentUserId;
  }

  static int? _optionalFriendRequestIdentity(
    Map<String, Object?> raw, {
    required String role,
    required List<String> aliases,
  }) {
    int? resolved;
    String? resolvedAlias;
    for (final String alias in aliases) {
      if (!raw.containsKey(alias)) {
        continue;
      }
      final int value = _requiredFriendRequestIdentity(
        raw[alias],
        field: '$role.$alias',
      );
      if (resolved != null && resolved != value) {
        throw ApiException(
          kind: ApiFailureKind.protocol,
          message: '好友请求 $role 身份别名不一致: $resolvedAlias 与 $alias',
        );
      }
      resolved ??= value;
      resolvedAlias ??= alias;
    }
    return resolved;
  }

  static int _requiredFriendRequestIdentity(
    Object? value, {
    required String field,
  }) {
    final int? parsed;
    if (value is int) {
      parsed = value;
    } else if (value is String &&
        _friendRequestPositiveIntegerPattern.hasMatch(value)) {
      parsed = int.tryParse(value);
    } else {
      parsed = null;
    }
    if (parsed == null || parsed <= 0) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '好友请求 $field 不是有效正整数',
      );
    }
    return parsed;
  }

  static FriendRequest _friendRequest(
    Map<String, Object?> raw, {
    required int currentUserId,
  }) {
    final int? userId = _optionalFriendRequestIdentity(
      raw,
      role: 'user',
      aliases: _friendRequestUserIdAliases,
    );
    final int? requesterId = _optionalFriendRequestIdentity(
      raw,
      role: 'requester',
      aliases: _friendRequestRequesterIdAliases,
    );
    final int? targetId = _optionalFriendRequestIdentity(
      raw,
      role: 'target',
      aliases: _friendRequestTargetIdAliases,
    );
    final int? currentViewId = _optionalFriendRequestIdentity(
      raw,
      role: 'currentView',
      aliases: _friendRequestCurrentViewIdAliases,
    );
    if (userId != null && requesterId != null && userId != requesterId) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '好友请求 userId 与 requester 身份不一致',
      );
    }
    if (targetId != null && targetId != currentUserId) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '好友请求 target 身份与当前视图不一致',
      );
    }
    if (currentViewId != null && currentViewId != currentUserId) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '好友请求 currentView 身份与当前视图不一致',
      );
    }
    final int visibleUserId =
        requesterId ??
        userId ??
        (throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '好友请求记录缺少有效 userId',
        ));
    final String id = _string(raw['requestId']);
    if (id.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '好友请求记录缺少 requestId',
      );
    }
    final DateTime? createdAt = _asDateTime(raw['createdAt']);
    if (createdAt == null) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '好友请求记录缺少有效 createdAt',
      );
    }
    return FriendRequest(
      id: id,
      user: SocialUser(
        userId: visibleUserId,
        name: _string(raw['nickName'] ?? raw['nickname'], fallback: '用户'),
        signature: _string(raw['signature']),
        avatarUrl: _firstNonEmpty(<Object?>[
          raw['headImgUrl'],
          raw['headImageUrl'],
        ]),
        isFollowing: false,
        isFollower: false,
        isFriend: false,
        isBlocked: false,
        isOnline: _asInt(raw['isOnline']) == 1,
        roomId: _string(raw['roomId']).isEmpty ? null : _string(raw['roomId']),
      ),
      message: _string(raw['message']),
      createdAt: createdAt,
      status: _friendRequestStatus(raw['status']),
    );
  }

  static FriendRequestStatus _friendRequestStatus(Object? value) {
    switch (value?.toString().trim().toUpperCase()) {
      case 'ACCEPTED':
        return FriendRequestStatus.accepted;
      case 'REJECTED':
        return FriendRequestStatus.rejected;
      case 'EXPIRED':
      case 'CANCELLED':
        return FriendRequestStatus.expired;
      case 'PENDING':
        return FriendRequestStatus.pending;
      default:
        throw ApiException(
          kind: ApiFailureKind.protocol,
          message: '好友请求包含未知状态 ${value ?? ''}',
        );
    }
  }

  static PrivacySettings _privacyFromMap(Map<String, Object?> data) {
    return PrivacySettings(
      onlyFollowedCanFollow: _requiredBool(data, 'onlyFollowedCanFollow'),
      serverValueKnown: true,
    );
  }

  static SupportTicket _supportTicketFromMap(Map<String, Object?> data) {
    final SupportTicketStatus status = _supportTicketStatus(data['status']);
    final String statusText = _string(
      data['statusText'],
      fallback: _statusText(status),
    );
    final String id = _string(data['ticketId'] ?? data['id']);
    if (id.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '工单响应缺少 ticketId',
      );
    }
    final DateTime? createdAt = _asDateTime(data['createdAt']);
    if (createdAt == null) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '工单响应缺少有效 createdAt',
      );
    }
    return SupportTicket(
      id: id,
      subject: _string(data['subject'], fallback: '意见反馈'),
      content: _string(data['content']),
      status: status,
      statusText: statusText,
      createdAt: createdAt,
      progressAvailable:
          _asBool(data['progressAvailable']) || data.containsKey('events'),
    );
  }

  static SupportTicketStatus _supportTicketStatus(Object? value) {
    switch (value?.toString().trim().toUpperCase()) {
      case 'SUBMITTED':
        return SupportTicketStatus.submitted;
      case 'PROCESSING':
      case 'IN_PROGRESS':
        return SupportTicketStatus.processing;
      case 'RESOLVED':
      case 'CLOSED':
        return SupportTicketStatus.resolved;
      case 'REJECTED':
        return SupportTicketStatus.rejected;
      default:
        return SupportTicketStatus.unavailable;
    }
  }

  static String _statusText(SupportTicketStatus status) {
    return switch (status) {
      SupportTicketStatus.submitted => '已提交，等待客服处理',
      SupportTicketStatus.processing => '客服处理中',
      SupportTicketStatus.resolved => '问题已处理',
      SupportTicketStatus.rejected => '工单已驳回',
      SupportTicketStatus.unavailable => '工单状态暂不可用',
    };
  }

  Future<T> _runSocialWrite<T>({
    required String operation,
    required List<Object?> intentParts,
    required String serialKey,
    required String requestIdPrefix,
    required Future<T> Function(Map<String, String> headers) action,
  }) {
    return _writeCoordinator.run<T>(
      intentKey: '$operation:${_intentDigest(intentParts)}',
      serialKey: serialKey,
      requestIdPrefix: requestIdPrefix,
      action: action,
    );
  }

  static String _newSocialWriteRequestId(String prefix) {
    final String normalizedPrefix = prefix.trim();
    if (normalizedPrefix.isEmpty) {
      throw StateError('社交写入请求幂等 ID 前缀不能为空');
    }
    if (normalizedPrefix.length + 1 + _requestEntropyLength >
        _maxRequestIdLength) {
      throw StateError('社交写入请求幂等 ID 前缀过长');
    }
    final String entropy = List<String>.generate(
      _requestEntropyLength,
      (_) => _requestIdRandom.nextInt(16).toRadixString(16),
      growable: false,
    ).join();
    return '$normalizedPrefix-$entropy';
  }

  static String _normalizeRequestId(String requestId) {
    final String normalized = requestId.trim();
    if (!_requestIdPattern.hasMatch(normalized)) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '请求幂等 ID 格式无效',
      );
    }
    return normalized;
  }

  static bool _shouldRetainSocialWriteRequest(Object error) {
    if (error is! ApiException) {
      return true;
    }
    if (error.kind == ApiFailureKind.conflict) {
      return error.code == 40901 || error.code == 40902;
    }
    return switch (error.kind) {
      ApiFailureKind.timeout ||
      ApiFailureKind.network ||
      ApiFailureKind.protocol ||
      ApiFailureKind.server => true,
      ApiFailureKind.configuration ||
      ApiFailureKind.unauthorized ||
      ApiFailureKind.forbidden ||
      ApiFailureKind.validation ||
      ApiFailureKind.business => false,
      ApiFailureKind.conflict => false,
    };
  }

  static String _reportIntentKey({
    required int currentUserId,
    required ReportTargetType targetType,
    required String targetId,
    required int reasonCode,
    required String description,
    required bool alsoBlock,
  }) {
    return 'report:${_intentDigest(<Object?>[currentUserId, targetType.name, targetId, reasonCode, description, alsoBlock])}';
  }

  static String _feedbackIntentKey({
    required int currentUserId,
    required String subject,
    required String content,
  }) {
    return 'feedback:${_intentDigest(<Object?>[currentUserId, subject, content])}';
  }

  static String _intentDigest(List<Object?> parts) {
    final StringBuffer canonical = StringBuffer();
    for (final Object? part in parts) {
      final String value = part?.toString() ?? '';
      canonical
        ..write(value.length)
        ..write(':')
        ..write(value)
        ..write('|');
    }
    return sha256.convert(utf8.encode(canonical.toString())).toString();
  }

  static String _firstNonEmpty(Iterable<Object?> values) {
    for (final Object? value in values) {
      final String normalized = value?.toString().trim() ?? '';
      if (normalized.isNotEmpty) {
        return normalized;
      }
    }
    return '';
  }
}

class _FriendRequestPageEnvelope {
  const _FriendRequestPageEnvelope({
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

class _SocialWriteCoordinator {
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
        BackendSocialRepository._newSocialWriteRequestId(requestIdPrefix);
    final Future<void> prior = _serialTails[serialKey] ?? Future<void>.value();
    final Future<T> operation = prior
        .then<T>(
          (_) => action(<String, String>{
            'X-Request-Id': BackendSocialRepository._normalizeRequestId(
              requestId,
            ),
          }),
        )
        .then<T>(
          (T value) {
            _retainedRequestIds.remove(intentKey);
            return value;
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!BackendSocialRepository._shouldRetainSocialWriteRequest(
              error,
            )) {
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
