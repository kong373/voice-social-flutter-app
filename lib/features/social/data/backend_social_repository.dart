import 'dart:convert';
import '../../account/domain/user_avatar_descriptor.dart';
import 'dart:math';
import '../../../core/media/media_models.dart';
import '../../media/image_domain_contract.dart';
import '../../commerce/display/domain/equipped_decoration.dart';

import 'package:crypto/crypto.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/features/social/domain/social_models.dart';

class BackendSocialRepository
    with RemovedFriendRequestOperations
    implements SocialRepository {
  static const int _maxRequestIdLength = 80;
  static const int _requestEntropyLength = 32;
  static final Random _requestIdRandom = Random.secure();
  static final RegExp _requestIdPattern = RegExp(r'^[A-Za-z0-9._:-]{1,80}$');

  BackendSocialRepository({
    required ApiClient apiClient,
    required int Function() currentUserIdProvider,
    int Function()? identityGeneration,
    BackendRouteCatalog routes = const BackendRouteCatalog(),
  }) : _apiClient = apiClient,
       _currentUserIdProvider = currentUserIdProvider,
       _identityGeneration = identityGeneration ?? (() => 0),
       _routes = routes;

  final ApiClient _apiClient;
  final int Function() _currentUserIdProvider;
  final int Function() _identityGeneration;

  void Function() _supportIdentity() {
    final actor = _currentUserIdProvider();
    final generation = _identityGeneration();
    void check() {
      if (actor <= 0 ||
          actor != _currentUserIdProvider() ||
          generation != _identityGeneration()) {
        throw const ApiException(
          kind: ApiFailureKind.unauthorized,
          message: '账号已变化，请重新打开工单',
        );
      }
    }

    check();
    return check;
  }

  final BackendRouteCatalog _routes;
  final _SocialWriteCoordinator _writeCoordinator = _SocialWriteCoordinator();
  final Map<String, Future<String>> _pendingReportSubmissions =
      <String, Future<String>>{};
  final Map<String, String> _retainedReportRequestIds = <String, String>{};
  final Map<String, Future<SupportTicket>> _pendingFeedbackSubmissions =
      <String, Future<SupportTicket>>{};
  final Map<String, String> _retainedFeedbackRequestIds = <String, String>{};

  @override
  bool get supportsFriendRequestWorkflow => false;

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
    if (userId <= 0) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '关注目标用户无效',
      );
    }
    final int actorUserId = _currentUserIdProvider();
    return _runSocialWrite<void>(
      operation: 'set-following',
      intentParts: <Object?>[actorUserId, userId, following],
      serialKey: 'relationship:$actorUserId:$userId',
      requestIdPrefix: 'social-following',
      action: (Map<String, String> headers) async {
        final ApiResponse response = await _apiClient.post(
          _routes.setFollowing,
          headers: headers,
          body: <String, Object?>{'userId': userId, 'type': following ? 1 : 0},
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
          _routes.onlyFollowedCanFollow,
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
    if (userId <= 0) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '黑名单目标用户无效',
      );
    }
    final int actorUserId = _currentUserIdProvider();
    return _runSocialWrite<void>(
      operation: 'set-blocked',
      intentParts: <Object?>[actorUserId, userId, blocked],
      serialKey: 'relationship:$actorUserId:$userId',
      requestIdPrefix: 'social-blocked',
      action: (Map<String, String> headers) async {
        final ApiResponse response = await _apiClient.post(
          _routes.setBlocked,
          headers: headers,
          body: <String, Object?>{'userId': userId, 'type': blocked ? 1 : 0},
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
    late final Object authoritativeTargetId;
    if (targetType == ReportTargetType.room) {
      if (!isCanonicalReportRoomId(normalizedTargetId)) {
        throw const ApiException(
          kind: ApiFailureKind.validation,
          message: '房间举报目标必须是 lowercase canonical public UUID',
        );
      }
      authoritativeTargetId = normalizedTargetId;
    } else {
      final int? numericTargetId = parseCanonicalReportEntityId(
        normalizedTargetId,
      );
      if (numericTargetId == null) {
        throw const ApiException(
          kind: ApiFailureKind.validation,
          message: '用户举报目标 ID 必须是有效的正整数',
        );
      }
      authoritativeTargetId = numericTargetId;
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
          targetId: authoritativeTargetId,
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
    required Object targetId,
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
    if (data['providerInvocation'] is! bool ||
        data['providerInvocation'] != false) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '举报响应缺少第一方零厂商调用确认',
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
      description: '提交问题后，可在“我的反馈”查看处理状态。',
      liveConversationAvailable: false,
    );
  }

  @override
  Future<SupportTicket> submitFeedback({
    required String subject,
    required String content,
    List<MediaReference> media = const [],
    String? requestId,
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
    final images = List<MediaReference>.unmodifiable(media);
    imageAssetIds(images, MediaPurpose.supportImage);
    if (requestId != null || images.isNotEmpty) {
      return _submitFeedbackOnce(
        subject: normalizedSubject,
        content: normalizedContent,
        media: images,
        requestId: requestId ?? _newSocialWriteRequestId('support-media'),
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
    final String retainedId = _retainedFeedbackRequestIds[intentKey] ??=
        _newSocialWriteRequestId('social-feedback');
    final Future<SupportTicket> request =
        _submitFeedbackOnce(
          subject: normalizedSubject,
          content: normalizedContent,
          requestId: retainedId,
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
    List<MediaReference> media = const [],
  }) async {
    final checkIdentity = _supportIdentity();
    final ids = imageAssetIds(media, MediaPurpose.supportImage);
    final ApiResponse response = await _apiClient.postBoundToIdentity(
      _routes.submitFeedback,
      requireIdentity: checkIdentity,
      headers: <String, String>{'X-Request-Id': _normalizeRequestId(requestId)},
      body: <String, Object?>{
        'subject': subject,
        'content': content,
        if (ids.isNotEmpty) 'mediaAssetIds': ids,
      },
    );
    checkIdentity();
    final ticket = _supportTicketFromMap(_asMap(response.data));
    if (ticket.content != content ||
        (media.isNotEmpty &&
            !ticket.events.any(
              (event) =>
                  event.actorType == 'USER' &&
                  event.eventType == 'CREATED' &&
                  event.message == content &&
                  sameImageIds(event.media, media),
            )))
      throw mediaProtocol();
    return ticket;
  }

  @override
  Future<SupportTicket> fetchSupportTicket(String ticketId) async {
    final checkIdentity = _supportIdentity();
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
    final SupportTicket ticket = _supportTicketFromMap(_asMap(response.data));
    checkIdentity();
    if (ticket.id != normalizedId) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '工单响应与请求不一致',
      );
    }
    return ticket;
  }

  @override
  Future<SupportTicket> replyToSupportTicket({
    required String ticketId,
    required String message,
    List<MediaReference> media = const [],
    String? requestId,
  }) {
    final String id = ticketId.trim();
    final String text = message.trim();
    if (!RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(id) ||
        text.isEmpty ||
        text.length > 1000) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '补充内容应为 1 至 1000 个字符，工单编号须有效',
      );
    }
    final int userId = _currentUserIdProvider();
    final checkIdentity = _supportIdentity();
    final images = List<MediaReference>.unmodifiable(media);
    final ids = imageAssetIds(images, MediaPurpose.supportImage);
    checkIdentity();
    Future<SupportTicket> action(Map<String, String> headers) async {
      checkIdentity();
      final ApiResponse response = await _apiClient.postBoundToIdentity(
        '${_routes.supportTickets}/${Uri.encodeComponent(id)}/replies',
        requireIdentity: checkIdentity,
        headers: headers,
        body: <String, Object?>{
          'message': text,
          if (ids.isNotEmpty) 'mediaAssetIds': ids,
        },
      );
      checkIdentity();
      final Map<String, Object?> data = _requiredSocialMap(response.data);
      final SupportTicket ticket = _supportTicketFromMap(data);
      if (ticket.id != id ||
          ticket.version < 1 ||
          !ticket.events.any(
            (event) =>
                event.actorType == 'USER' &&
                event.eventType == 'MESSAGE' &&
                event.message == text &&
                sameImageIds(event.media, images),
          )) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '补充反馈尚未获得有效回执，请重试查询',
        );
      }
      return ticket;
    }

    if (requestId != null)
      return action({'X-Request-Id': _normalizeRequestId(requestId)});
    return _writeCoordinator.run<SupportTicket>(
      intentKey:
          'support-reply:${_intentDigest(<Object?>[userId, _identityGeneration(), id, text, ids])}',
      serialKey: 'support-reply:$userId:$id',
      requestIdPrefix: 'support-reply',
      action: action,
    );
  }

  @override
  Future<SocialPage<SupportTicket>> fetchSupportTickets({
    required int page,
    required int pageSize,
  }) async {
    _validateSocialPageRequest(page: page, pageSize: pageSize);
    if ((page - 1) * pageSize > 0x7fffffff) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '反馈列表页码超出范围',
      );
    }
    final ApiResponse response = await _apiClient.get(
      _routes.supportTickets,
      query: <String, String>{'page': '$page', 'pageSize': '$pageSize'},
    );
    return _socialPage<SupportTicket>(
      response.data,
      page: page,
      pageSize: pageSize,
      mapItem: _supportTicketFromMap,
    );
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
    final int? level;
    final bool levelAvailable;
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
      final Object? rawLevel = homepage['level'];
      if (!homepage.containsKey('level')) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '用户主页响应缺少 level 权威状态',
        );
      }
      if (rawLevel == null) {
        levelAvailable = _requiredBool(homepage, 'levelAvailable');
        final String levelStatus = _requiredNonEmptyString(
          homepage,
          'levelStatus',
        );
        if (levelAvailable || levelStatus != 'UNAVAILABLE') {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '用户主页响应 level 不可用状态不一致',
          );
        }
        level = null;
      } else {
        level = _requiredNonNegativeInt(homepage, 'level');
        levelAvailable = homepage.containsKey('levelAvailable')
            ? _requiredBool(homepage, 'levelAvailable')
            : true;
        if (!levelAvailable ||
            (homepage.containsKey('levelStatus') &&
                _requiredNonEmptyString(homepage, 'levelStatus') !=
                    'AVAILABLE')) {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '用户主页响应 level 可用状态不一致',
          );
        }
      }
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
      level = null;
      levelAvailable = false;
      isFollowing = false;
      isFriend = false;
      isBlocked = false;
      isOnline = false;
      roomId = '';
    }
    final display = hasHomepage ? homepage : personal;
    final SocialUser user = SocialUser(
      userId: profileId,
      avatar: display['status'] == 'ACTIVE'
          ? UserAvatarDescriptor.parseOptional(display['avatar'])
          : null,
      name: profileName,
      signature: signature,
      avatarUrl: avatarUrl,
      isFollowing: isSelf ? false : isFollowing,
      isFollower: isSelf ? false : isFriend,
      isFriend: isSelf ? false : isFriend,
      isBlocked: isSelf ? false : isBlocked,
      isOnline: isSelf ? false : isOnline,
      roomId: roomId.isEmpty ? null : roomId,
      equippedDecorations: display['status'] == 'ACTIVE'
          ? EquippedDecoration.parseList(display['equippedDecorations'])
          : const [],
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

  static SocialPage<T> _socialPage<T>(
    Object? value, {
    required int page,
    required int pageSize,
    required T Function(Map<String, Object?> raw) mapItem,
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
    final List<T> items = <T>[
      for (final Map<String, Object?> raw in listedItems) mapItem(raw),
    ];
    if (current < pages && items.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '社交分页仍有后续页但当前页为空',
      );
    }
    return SocialPage<T>(
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
      if (!second.containsKey(entry.key) ||
          !_sameSocialValue(entry.value, second[entry.key])) {
        return false;
      }
    }
    return true;
  }

  // JSON decoding creates distinct avatar maps for list and records. Compare
  // their values, retaining exact keys and ordered arrays for drift detection.
  static bool _sameSocialValue(Object? first, Object? second) {
    if (first is Map) {
      if (second is! Map || first.length != second.length) return false;
      for (final key in first.keys) {
        if (key is! String ||
            !second.containsKey(key) ||
            !_sameSocialValue(first[key], second[key])) {
          return false;
        }
      }
      return true;
    }
    if (first is List) {
      if (second is! List || first.length != second.length) return false;
      for (var index = 0; index < first.length; index++) {
        if (!_sameSocialValue(first[index], second[index])) return false;
      }
      return true;
    }
    return first == second;
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
      events: _supportEvents(data),
      version: _supportVersion(data),
    );
  }

  static int _supportVersion(Map<String, Object?> data) {
    if (!data.containsKey('version')) return 0;
    final Object? value = data['version'];
    if (value is! int || value < 0 || value > 9007199254740991) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '工单版本响应无效',
      );
    }
    return value;
  }

  static List<SupportTicketEvent> _supportEvents(Map<String, Object?> data) {
    if (!data.containsKey('events')) return const <SupportTicketEvent>[];
    final Object? raw = data['events'];
    if (raw is! List) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '工单处理记录响应无效',
      );
    }
    return List<SupportTicketEvent>.unmodifiable(
      raw.map((value) {
        final Map<String, Object?> event = _requiredSocialMap(value);
        final Object? actor = event['actorType'];
        final Object? type = event['eventType'];
        final Object? text = event['message'];
        final DateTime? time = _asDateTime(event['createdAt']);
        if (!const <String>{'USER', 'SYSTEM', 'AGENT'}.contains(actor) ||
            !const <String>{
              'CREATED',
              'STATUS_CHANGED',
              'MESSAGE',
              'RESOLVED',
            }.contains(type) ||
            text is! String ||
            text.trim().isEmpty ||
            text.length > 1000 ||
            time == null) {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '工单处理记录字段无效',
          );
        }
        return SupportTicketEvent(
          actorType: actor! as String,
          eventType: type! as String,
          message: text,
          createdAt: time,
          eventId: event['eventId'] == null
              ? null
              : requireMediaId(event['eventId']),
          media: _eventMedia(event),
        );
      }),
    );
  }

  static List<MediaReference> _eventMedia(Map<String, Object?> event) {
    final images = domainImages(
      event.containsKey('media') ? event['media'] : const [],
      MediaPurpose.supportImage,
    );
    if (images.isNotEmpty) requireMediaId(event['eventId']);
    return images;
  }

  static SupportTicketStatus _supportTicketStatus(Object? value) {
    switch (value?.toString().trim().toUpperCase()) {
      case 'SUBMITTED':
        return SupportTicketStatus.submitted;
      case 'ACCEPTED':
        return SupportTicketStatus.accepted;
      case 'PROCESSING':
      case 'IN_PROGRESS':
        return SupportTicketStatus.processing;
      case 'WAITING_USER':
        return SupportTicketStatus.waitingUser;
      case 'RESOLVED':
        return SupportTicketStatus.resolved;
      case 'CLOSED':
        return SupportTicketStatus.closed;
      case 'REJECTED':
        return SupportTicketStatus.rejected;
      default:
        return SupportTicketStatus.unavailable;
    }
  }

  static String _statusText(SupportTicketStatus status) {
    return switch (status) {
      SupportTicketStatus.submitted => '已提交，等待客服处理',
      SupportTicketStatus.accepted => '客服已受理',
      SupportTicketStatus.processing => '客服处理中',
      SupportTicketStatus.waitingUser => '等待补充信息',
      SupportTicketStatus.resolved => '问题已处理',
      SupportTicketStatus.closed => '工单已关闭',
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
