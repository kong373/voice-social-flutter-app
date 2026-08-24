import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/features/account/compliance/domain/account_compliance.dart';
import 'package:voice_social_app/features/account/compliance/domain/account_compliance_request_id.dart';
import 'package:voice_social_app/features/account/compliance/infrastructure/native_permission_adapter.dart';

/// First-party HTTP adapter for account safety and compliance.
///
/// This repository deliberately does not hide request failures. A missing
/// snapshot, an unavailable session list, or an unavailable version service
/// is a real state that the presentation layer must surface to the user; it
/// must not be converted into an apparently healthy empty snapshot.
class BackendAccountComplianceRepository
    implements AccountComplianceRepository {
  BackendAccountComplianceRepository({
    required ApiClient apiClient,
    BackendRouteCatalog routes = const BackendRouteCatalog(),
    String Function()? currentDeviceIdProvider,
    NativePermissionAdapter? nativePermissionAdapter,
    bool supportsRealNameSubmission = true,
  }) : _apiClient = apiClient,
       _routes = routes,
       _currentDeviceIdProvider = currentDeviceIdProvider ?? (() => ''),
       _nativePermissionAdapter =
           nativePermissionAdapter ?? MethodChannelNativePermissionAdapter(),
       _supportsRealNameSubmission = supportsRealNameSubmission;

  final ApiClient _apiClient;
  final BackendRouteCatalog _routes;
  final String Function() _currentDeviceIdProvider;
  final NativePermissionAdapter _nativePermissionAdapter;
  final bool _supportsRealNameSubmission;
  final Map<String, Future<void>> _pendingRealNameSubmissions =
      <String, Future<void>>{};
  final Map<String, String> _retainedRealNameRequestIds = <String, String>{};
  final Map<String, Future<void>> _pendingSessionRevocations =
      <String, Future<void>>{};
  final Map<String, String> _retainedSessionRevocationRequestIds =
      <String, String>{};
  final Map<String, Future<AppealCase>> _pendingAppealSubmissions =
      <String, Future<AppealCase>>{};
  final Map<String, String> _retainedAppealRequestIds = <String, String>{};
  final Map<String, Future<void>> _pendingDeletionRequests =
      <String, Future<void>>{};
  final Map<String, String> _retainedDeletionRequestIds = <String, String>{};
  final Map<String, Future<bool>> _pendingYouthModeChanges =
      <String, Future<bool>>{};
  final Map<String, String> _retainedYouthModeRequestIds = <String, String>{};
  Future<CancellationEligibility>? _pendingCancellation;
  String? _retainedCancellationRequestId;

  @override
  bool get supportsDeviceSessionManagement => true;

  @override
  bool get supportsRealNameSubmission => _supportsRealNameSubmission;

  @override
  Future<AccountComplianceSnapshot> fetchSnapshot({
    required String account,
    int? expectedUserId,
    required int currentVersion,
    required int platformType,
  }) async {
    final ApiResponse profileResponse = await _apiClient.get(
      _routes.personalData,
    );
    final Map<String, Object?> profile = _requireMap(
      profileResponse.data,
      '个人资料',
    );
    final String loginName = _requiredString(profile, 'loginName', '个人资料');
    final String nickName = _requiredString(profile, 'nickName', '个人资料');
    if (expectedUserId != null) {
      final int responseUserId = _requiredPositiveInt(
        profile,
        'userId',
        '个人资料',
      );
      if (responseUserId != expectedUserId) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '个人资料响应主体与当前会话不一致',
        );
      }
    }
    // These authorities are independent once the authenticated principal has
    // been confirmed by the profile response. Fetch them concurrently so the
    // live entry gate is bounded by the slowest request instead of the sum of
    // six network round trips. Future.wait still fails closed if any authority
    // is unavailable or violates its contract.
    final List<Object?> authorities =
        await Future.wait<Object?>(<Future<Object?>>[
          _apiClient.get(_routes.youthModeStatus),
          _apiClient.get(_routes.accountRestrictions),
          queryCancellationEligibility(),
          checkVersion(
            currentVersion: currentVersion,
            platformType: platformType,
          ),
          _apiClient.get(_routes.accountRealName),
          _apiClient.get(_routes.accountSessions),
        ]);
    final ApiResponse youthResponse = authorities[0] as ApiResponse;
    final ApiResponse restrictionsResponse = authorities[1] as ApiResponse;
    final CancellationEligibility cancellation =
        authorities[2] as CancellationEligibility;
    final VersionUpdateInfo versionInfo = authorities[3] as VersionUpdateInfo;
    final ApiResponse realNameResponse = authorities[4] as ApiResponse;
    final ApiResponse sessionsResponse = authorities[5] as ApiResponse;

    final Map<String, Object?> youth = _requireMap(youthResponse.data, '青少年模式');
    final Map<String, Object?> restrictions = _requireMap(
      restrictionsResponse.data,
      '账户限制',
    );
    final Map<String, Object?> realName = _requireMap(
      realNameResponse.data,
      '实名认证',
    );
    final Map<String, Object?> sessions = _requireMap(
      sessionsResponse.data,
      '设备会话',
    );
    final int verificationCode = _parseVerificationCode(realName);
    final bool youthModeEnabled = _requiredBool(
      youth,
      'youthModeEnabled',
      '青少年模式',
    );
    final Object? legacyYouthMode = youth['isYouthMode'];
    if (legacyYouthMode != null &&
        _strictBinaryInt(legacyYouthMode, '青少年模式 isYouthMode') !=
            (youthModeEnabled ? 1 : 0)) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '青少年模式响应中的状态字段互相矛盾',
      );
    }
    final List<Object?> restrictionList = _requireList(
      restrictions['list'],
      '账户限制 list',
    );
    final int restrictionTotal = _requiredNonNegativeInt(
      restrictions,
      'total',
      '账户限制',
    );
    if (restrictionTotal != restrictionList.length) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '账户限制响应中的 total 与 list 数量不一致',
      );
    }
    final bool isRestricted = _requiredBool(restrictions, 'restricted', '账户限制');
    final bool accountUsable = _requiredBool(
      restrictions,
      'accountUsable',
      '账户限制',
    );
    if (isRestricted != restrictionList.isNotEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '账户限制响应中的 restricted 与 list 不一致',
      );
    }
    final Map<String, Object?> latestRestriction = restrictionList.isEmpty
        ? const <String, Object?>{}
        : _parseRestriction(restrictionList.first);
    final List<Object?> sessionList = _requireList(
      sessions['list'],
      '设备会话 list',
    );
    final int sessionTotal = _requiredNonNegativeInt(sessions, 'total', '设备会话');
    if (sessionTotal != sessionList.length) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '设备会话响应中的 total 与 list 数量不一致',
      );
    }
    final List<DeviceSession> deviceSessions = _parseSessions(sessionList);
    final List<PermissionSetting> permissions = await _permissionSettings();

    return AccountComplianceSnapshot(
      account: loginName,
      nickname: nickName,
      accountUsable: accountUsable,
      verificationState: _verificationState(verificationCode),
      youthModeEnabled: youthModeEnabled,
      restriction: AccountRestriction(
        kind: _restrictionKind(
          _string(latestRestriction['type']),
          restricted: isRestricted,
        ),
        reason: _string(latestRestriction['reason']),
        expiresAt: _nullableDateTime(latestRestriction['endsAt']),
      ),
      cancellation: cancellation,
      versionInfo: versionInfo,
      sessions: deviceSessions,
      permissions: permissions,
    );
  }

  @override
  Future<void> setPermissionState({
    required PermissionKind kind,
    required PermissionState state,
  }) async {
    if (state != PermissionState.granted) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '系统权限请求只允许请求授权，不接受客户端写入状态',
      );
    }
    final PermissionState result = await _requestPermission(kind);
    if (result == PermissionState.unavailable) {
      throw const ApiException(
        kind: ApiFailureKind.configuration,
        message: '系统权限需要原生平台适配器，当前适配器不可用，不会伪造授权结果',
      );
    }
  }

  @override
  Future<void> openPermissionSettings() =>
      _nativePermissionAdapter.openAppSettings();

  Future<List<PermissionSetting>> _permissionSettings() async {
    const List<PermissionKind> kinds = <PermissionKind>[
      PermissionKind.microphone,
      PermissionKind.notifications,
      PermissionKind.photos,
    ];
    final List<PermissionSetting> permissions = <PermissionSetting>[];
    for (final PermissionKind kind in kinds) {
      final PermissionState state = await _readPermission(kind);
      permissions.add(
        PermissionSetting(
          kind: kind,
          state: state,
          title: _permissionTitle(kind),
          purpose: _permissionPurpose(kind),
          managedByPlatform: state == PermissionState.unavailable ? null : true,
        ),
      );
    }
    return permissions;
  }

  Future<PermissionState> _readPermission(PermissionKind kind) async {
    try {
      return await _nativePermissionAdapter.status(kind);
    } on Object {
      return PermissionState.unavailable;
    }
  }

  Future<PermissionState> _requestPermission(PermissionKind kind) async {
    try {
      return await _nativePermissionAdapter.request(kind);
    } on Object {
      return PermissionState.unavailable;
    }
  }

  static String _permissionTitle(PermissionKind kind) => switch (kind) {
    PermissionKind.microphone => '麦克风',
    PermissionKind.notifications => '通知',
    PermissionKind.photos => '照片',
  };

  static String _permissionPurpose(PermissionKind kind) => switch (kind) {
    PermissionKind.microphone => '上麦发言、音频诊断和房间语音互动。',
    PermissionKind.notifications => '好友请求、系统通知和房间邀请提醒。',
    PermissionKind.photos => '修改头像、举报凭证和发布动态图片。',
  };

  @override
  Future<void> submitRealName({
    required String realName,
    required String idNumber,
  }) {
    if (!supportsRealNameSubmission) {
      return Future<void>.error(
        const ApiException(
          kind: ApiFailureKind.business,
          message: 'VENDOR_BLOCKED：正式实名厂商尚未接入，当前不会提交身份证号',
        ),
      );
    }
    final String normalizedName = realName.trim();
    final String normalizedId = idNumber
        .replaceAll(' ', '')
        .trim()
        .toUpperCase();
    if (normalizedName.isEmpty || normalizedId.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '真实姓名和证件号码不能为空',
      );
    }
    final String intentKey = _writeKey('real-name', <Object?>[
      normalizedName,
      normalizedId,
    ]);
    final Future<void>? pending = _pendingRealNameSubmissions[intentKey];
    if (pending != null) {
      return pending;
    }
    final String requestId = _retainedRealNameRequestIds[intentKey] ??=
        _newRequestId('flutter-account-real-name');
    late final Future<void> operation;
    operation =
        _submitRealNameOnce(
          realName: normalizedName,
          idNumber: normalizedId,
          requestId: requestId,
        ).then<void>(
          (_) {
            _removePending(_pendingRealNameSubmissions, intentKey, operation);
            _retainedRealNameRequestIds.remove(intentKey);
          },
          onError: (Object error, StackTrace stackTrace) {
            _removePending(_pendingRealNameSubmissions, intentKey, operation);
            if (!shouldRetainAccountComplianceRequest(error)) {
              _retainedRealNameRequestIds.remove(intentKey);
            }
            Error.throwWithStackTrace(error, stackTrace);
          },
        );
    _pendingRealNameSubmissions[intentKey] = operation;
    return operation;
  }

  Future<void> _submitRealNameOnce({
    required String realName,
    required String idNumber,
    required String requestId,
  }) async {
    final ApiResponse response = await _apiClient.post(
      _routes.accountRealName,
      headers: <String, String>{
        'X-Request-Id': normalizeAccountComplianceRequestId(requestId),
      },
      body: <String, Object?>{
        'legalName': realName,
        'identityNumber': idNumber,
      },
    );
    final Map<String, Object?> submitted = _requireMap(response.data, '实名认证提交');
    if (_parseVerificationCode(submitted) != 1) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '实名认证提交响应未进入待审核状态',
      );
    }
  }

  @override
  Future<void> revokeDeviceSession(String sessionId) {
    final String normalizedSessionId = sessionId.trim();
    if (normalizedSessionId.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '设备会话 ID 不能为空',
      );
    }
    final String intentKey = _writeKey('revoke-session', <Object?>[
      normalizedSessionId,
    ]);
    final Future<void>? pending = _pendingSessionRevocations[intentKey];
    if (pending != null) {
      return pending;
    }
    final String requestId = _retainedSessionRevocationRequestIds[intentKey] ??=
        _newRequestId('flutter-account-revoke-session');
    late final Future<void> operation;
    operation =
        _revokeDeviceSessionOnce(
          sessionId: normalizedSessionId,
          requestId: requestId,
        ).then<void>(
          (_) {
            _removePending(_pendingSessionRevocations, intentKey, operation);
            _retainedSessionRevocationRequestIds.remove(intentKey);
          },
          onError: (Object error, StackTrace stackTrace) {
            _removePending(_pendingSessionRevocations, intentKey, operation);
            if (!shouldRetainAccountComplianceRequest(error)) {
              _retainedSessionRevocationRequestIds.remove(intentKey);
            }
            Error.throwWithStackTrace(error, stackTrace);
          },
        );
    _pendingSessionRevocations[intentKey] = operation;
    return operation;
  }

  Future<void> _revokeDeviceSessionOnce({
    required String sessionId,
    required String requestId,
  }) async {
    final ApiResponse response = await _apiClient.delete(
      '${_routes.accountSessions}/${Uri.encodeComponent(sessionId)}',
      headers: <String, String>{
        'X-Request-Id': normalizeAccountComplianceRequestId(requestId),
      },
    );
    final Map<String, Object?> data = _requireMap(response.data, '设备会话撤销');
    if (_requiredString(data, 'sessionId', '设备会话撤销') != sessionId ||
        _requiredString(data, 'status', '设备会话撤销') != 'REVOKED' ||
        !_requiredBool(data, 'revoked', '设备会话撤销')) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '设备会话撤销响应与请求不一致',
      );
    }
  }

  @override
  Future<AppealCase> queryAppeal({
    required String account,
    required String reasonType,
  }) async {
    final Map<String, Object?> data = await _appealInfo();
    return _parseAppealEnvelope(data, account: account, reasonType: reasonType);
  }

  @override
  Future<AppealCase> submitAppeal({
    required String account,
    required String nickname,
    required String reason,
    required String reasonType,
    required String explanation,
  }) {
    final String normalizedAccount = account.trim();
    final String normalizedNickname = nickname.trim();
    final String normalizedReason = reason.trim();
    final String normalizedReasonType = reasonType.trim();
    final String normalizedExplanation = explanation.trim();
    final String intentKey = _writeKey('submit-appeal', <Object?>[
      normalizedAccount,
      normalizedNickname,
      normalizedReason,
      normalizedReasonType,
      normalizedExplanation,
    ]);
    final Future<AppealCase>? pending = _pendingAppealSubmissions[intentKey];
    if (pending != null) {
      return pending;
    }
    final String requestId = _retainedAppealRequestIds[intentKey] ??=
        _newRequestId('flutter-account-submit-appeal');
    late final Future<AppealCase> operation;
    operation =
        _submitAppealOnce(
          account: normalizedAccount,
          nickname: normalizedNickname,
          reason: normalizedReason,
          reasonType: normalizedReasonType,
          explanation: normalizedExplanation,
          requestId: requestId,
        ).then<AppealCase>(
          (AppealCase value) {
            _removePending(_pendingAppealSubmissions, intentKey, operation);
            _retainedAppealRequestIds.remove(intentKey);
            return value;
          },
          onError: (Object error, StackTrace stackTrace) {
            _removePending(_pendingAppealSubmissions, intentKey, operation);
            if (!shouldRetainAccountComplianceRequest(error)) {
              _retainedAppealRequestIds.remove(intentKey);
            }
            Error.throwWithStackTrace(error, stackTrace);
          },
        );
    _pendingAppealSubmissions[intentKey] = operation;
    return operation;
  }

  Future<AppealCase> _submitAppealOnce({
    required String account,
    required String nickname,
    required String reason,
    required String reasonType,
    required String explanation,
    required String requestId,
  }) async {
    final Map<String, Object?> current = await _appealInfo();
    final Map<String, Object?> penalty = _asMap(current['penalty']);
    final ApiResponse response = await _apiClient.post(
      _routes.submitAppeal,
      headers: <String, String>{
        'X-Request-Id': normalizeAccountComplianceRequestId(requestId),
      },
      body: <String, Object?>{
        'penaltyId': _string(penalty['penaltyId']),
        'reason': reason.isEmpty ? explanation : reason,
        'evidence': <String, Object?>{
          'explanation': explanation,
          'reasonType': reasonType,
          'account': account,
          'nickname': nickname,
        },
      },
    );
    final Map<String, Object?> submitted = _requireMap(response.data, '申诉提交');
    return _parseAppeal(
      submitted,
      account: account,
      reasonType: reasonType,
      penalty: penalty,
    );
  }

  @override
  Future<AppealCase> queryAppealProgress(String account) async {
    final Map<String, Object?> envelope = await _appealInfo();
    final Map<String, Object?> appeal = _asMap(envelope['appeal']);
    if (appeal.isEmpty) {
      return _parseAppealEnvelope(envelope, account: account, reasonType: '');
    }
    final String appealId = _string(appeal['appealId']);
    if (appealId.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '申诉记录缺少 appealId，无法查询处理进度',
      );
    }
    final ApiResponse response = await _apiClient.get(
      _routes.queryAppealProgress,
      query: <String, String>{'appealId': appealId},
    );
    final Map<String, Object?> progress = _requireMap(response.data, '申诉进度');
    if (_requiredString(progress, 'appealId', '申诉进度') != appealId) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '申诉进度 appealId 与请求不一致',
      );
    }
    return _parseAppeal(
      progress,
      account: account,
      reasonType: '',
      penalty: _asMap(envelope['penalty']),
    );
  }

  @override
  Future<CancellationEligibility> queryCancellationEligibility() async {
    final ApiResponse response = await _apiClient.get(
      _routes.queryAccountCancellation,
    );
    return _parseCancellation(_asMap(response.data));
  }

  @override
  Future<void> requestCancellation({required String smsCode}) {
    const String intentKey = 'request-account-deletion';
    final Future<void>? pending = _pendingDeletionRequests[intentKey];
    if (pending != null) {
      return pending;
    }
    final String requestId = _retainedDeletionRequestIds[intentKey] ??=
        _newRequestId('flutter-account-request-deletion');
    late final Future<void> operation;
    operation = _requestCancellationOnce(requestId: requestId).then<void>(
      (_) {
        _removePending(_pendingDeletionRequests, intentKey, operation);
        _retainedDeletionRequestIds.remove(intentKey);
      },
      onError: (Object error, StackTrace stackTrace) {
        _removePending(_pendingDeletionRequests, intentKey, operation);
        if (!shouldRetainAccountComplianceRequest(error)) {
          _retainedDeletionRequestIds.remove(intentKey);
        }
        Error.throwWithStackTrace(error, stackTrace);
      },
    );
    _pendingDeletionRequests[intentKey] = operation;
    return operation;
  }

  Future<void> _requestCancellationOnce({required String requestId}) async {
    // Keep the domain method for compatibility with the existing page, but
    // do not send the value as a fake SMS credential. The backend contract is
    // an explicit confirmation body and enforces the cooling-period policy.
    final ApiResponse response = await _apiClient.delete(
      _routes.deleteAccount,
      headers: <String, String>{
        'X-Request-Id': normalizeAccountComplianceRequestId(requestId),
      },
      body: const <String, Object?>{'confirmation': 'CONFIRM_DELETE'},
    );
    final CancellationEligibility result = _parseCancellation(
      _requireMap(response.data, '注销申请'),
    );
    if (result.status != 'COOLING_OFF' ||
        result.allowed ||
        !result.canCancel ||
        result.requiresSmsCode) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '注销申请响应未进入服务端冷静期状态',
      );
    }
  }

  @override
  Future<CancellationEligibility> cancelDeletion() {
    final Future<CancellationEligibility>? pending = _pendingCancellation;
    if (pending != null) {
      return pending;
    }
    final String requestId = _retainedCancellationRequestId ??= _newRequestId(
      'flutter-account-cancel-deletion',
    );
    late final Future<CancellationEligibility> operation;
    operation = _cancelDeletionOnce(requestId: requestId)
        .then<CancellationEligibility>(
          (CancellationEligibility value) {
            if (identical(_pendingCancellation, operation)) {
              _pendingCancellation = null;
            }
            _retainedCancellationRequestId = null;
            return value;
          },
          onError: (Object error, StackTrace stackTrace) {
            if (identical(_pendingCancellation, operation)) {
              _pendingCancellation = null;
            }
            if (!shouldRetainAccountComplianceRequest(error)) {
              _retainedCancellationRequestId = null;
            }
            Error.throwWithStackTrace(error, stackTrace);
          },
        );
    _pendingCancellation = operation;
    return operation;
  }

  Future<CancellationEligibility> _cancelDeletionOnce({
    required String requestId,
  }) async {
    final ApiResponse response = await _apiClient.post(
      _routes.cancelAccountDeletion,
      headers: <String, String>{
        'X-Request-Id': normalizeAccountComplianceRequestId(requestId),
      },
    );
    final Map<String, Object?> data = _requireMap(response.data, '撤销注销');
    final Map<String, Object?> latestRequest = _asMap(data['latestRequest']);
    final String status = _string(
      data['status'] ?? latestRequest['status'],
    ).trim();
    if (status.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '撤销注销响应缺少服务端状态',
      );
    }
    return _parseCancellation(data);
  }

  @override
  Future<VersionUpdateInfo> checkVersion({
    required int currentVersion,
    required int platformType,
  }) async {
    final ApiResponse response = await _apiClient.get(
      _routes.versionInformation,
      query: <String, String>{
        'type': platformType.toString(),
        'versionCode': currentVersion.toString(),
      },
    );
    final Map<String, Object?> data = _requireMap(response.data, '版本信息');
    if (_requiredBool(data, 'providerInvocation', '版本信息')) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '版本信息响应不得触发第三方能力',
      );
    }
    final int isUpdate = _strictBinaryInt(data['isUpdate'], '版本信息 isUpdate');
    final Map<String, Object?> latest = _requireMap(
      data['latest'],
      '版本信息 latest',
      allowEmpty: isUpdate == 0,
    );
    if (isUpdate == 0 && latest.isNotEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '版本信息响应中的 isUpdate 与 latest 不一致',
      );
    }
    final int forceUpdate = isUpdate == 0
        ? 0
        : _strictBinaryInt(latest['isForce'], '版本信息 isForce');
    final String versionName = isUpdate == 0
        ? ''
        : _requiredString(latest, 'versionName', '版本信息 latest');
    return VersionUpdateInfo(
      hasUpdate: isUpdate == 1,
      forceUpdate: forceUpdate == 1,
      versionName: versionName,
      releaseNotes: _string(latest['versionInfo']),
      packageUrl: _string(latest['packageUrl']),
    );
  }

  @override
  Future<bool> setYouthMode({required bool enabled, required String pin}) {
    final String normalizedPin = pin.trim();
    final String intentKey = _writeKey('youth-mode', <Object?>[
      enabled,
      normalizedPin,
    ]);
    final Future<bool>? pending = _pendingYouthModeChanges[intentKey];
    if (pending != null) {
      return pending;
    }
    final String requestId = _retainedYouthModeRequestIds[intentKey] ??=
        _newRequestId(
          enabled
              ? 'flutter-account-youth-enable'
              : 'flutter-account-youth-disable',
        );
    late final Future<bool> operation;
    operation =
        _setYouthModeOnce(
          enabled: enabled,
          pin: normalizedPin,
          requestId: requestId,
        ).then<bool>(
          (bool value) {
            _removePending(_pendingYouthModeChanges, intentKey, operation);
            _retainedYouthModeRequestIds.remove(intentKey);
            return value;
          },
          onError: (Object error, StackTrace stackTrace) {
            _removePending(_pendingYouthModeChanges, intentKey, operation);
            if (!shouldRetainAccountComplianceRequest(error)) {
              _retainedYouthModeRequestIds.remove(intentKey);
            }
            Error.throwWithStackTrace(error, stackTrace);
          },
        );
    _pendingYouthModeChanges[intentKey] = operation;
    return operation;
  }

  Future<bool> _setYouthModeOnce({
    required bool enabled,
    required String pin,
    required String requestId,
  }) async {
    final ApiResponse response = await _apiClient.post(
      enabled ? _routes.enableYouthMode : _routes.disableYouthMode,
      headers: <String, String>{
        'X-Request-Id': normalizeAccountComplianceRequestId(requestId),
      },
      body: <String, Object?>{'password': pin},
    );
    final Map<String, Object?> data = _requireMap(response.data, '青少年模式更新');
    final bool serverEnabled = _requiredBool(
      data,
      'youthModeEnabled',
      '青少年模式更新',
    );
    if (serverEnabled != enabled) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '青少年模式更新响应与请求状态不一致',
      );
    }
    return serverEnabled;
  }

  String _newRequestId(String prefix) => normalizeAccountComplianceRequestId(
    newAccountComplianceRequestId(prefix),
  );

  static String _writeKey(String operation, Iterable<Object?> values) {
    final StringBuffer canonical = StringBuffer();
    for (final Object? value in values) {
      final String text = '$value';
      canonical
        ..write(text.length)
        ..write(':')
        ..write(text)
        ..write('|');
    }
    // The intent may contain identity data or a youth-mode PIN. Keep only a
    // one-way digest in the coordinator maps; plaintext remains scoped to the
    // active method call and is never embedded in a request ID or log key.
    final String digest = sha256
        .convert(utf8.encode(canonical.toString()))
        .toString();
    return '$operation:$digest';
  }

  static void _removePending<T>(
    Map<String, Future<T>> pending,
    String intentKey,
    Future<T> operation,
  ) {
    if (identical(pending[intentKey], operation)) {
      pending.remove(intentKey);
    }
  }

  Future<Map<String, Object?>> _appealInfo() async {
    final ApiResponse response = await _apiClient.get(_routes.queryAppealInfo);
    final Map<String, Object?> data = _requireMap(response.data, '申诉信息');
    _requireMap(data['penalty'], '申诉信息 penalty', allowEmpty: true);
    _requireMap(data['appeal'], '申诉信息 appeal', allowEmpty: true);
    return data;
  }

  static AppealCase _parseAppealEnvelope(
    Map<String, Object?> data, {
    required String account,
    required String reasonType,
  }) {
    final Map<String, Object?> appeal = _requireMap(
      data['appeal'],
      '申诉信息 appeal',
      allowEmpty: true,
    );
    final Map<String, Object?> penalty = _requireMap(
      data['penalty'],
      '申诉信息 penalty',
      allowEmpty: true,
    );
    if (appeal.isEmpty) {
      return AppealCase(
        account: account,
        nickname: '当前用户',
        reason: _string(penalty['reason']),
        reasonType: _string(penalty['type'], fallback: reasonType),
        state: AppealState.none,
        processText: '尚未提交申诉',
        resultText: '',
      );
    }
    return _parseAppeal(
      appeal,
      account: account,
      reasonType: _string(penalty['type'], fallback: reasonType),
      penalty: penalty,
    );
  }

  static AppealCase _parseAppeal(
    Map<String, Object?> data, {
    required String account,
    required String reasonType,
    Map<String, Object?>? penalty,
  }) {
    _requiredString(data, 'appealId', '申诉记录');
    final String status = _requiredString(data, 'status', '申诉记录').toUpperCase();
    final AppealState state = switch (status) {
      'APPROVED' => AppealState.approved,
      'REJECTED' => AppealState.rejected,
      'SUBMITTED' || 'REVIEWING' || 'PENDING' => AppealState.pending,
      'CANCELLED' => AppealState.none,
      _ => throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '申诉记录包含未知状态',
      ),
    };
    final String result = _string(data['resultMessage'] ?? data['result']);
    final String process = _string(data['process']);
    return AppealCase(
      account: account,
      nickname: '当前用户',
      reason: _string(data['reason'] ?? penalty?['reason'] ?? data['punish']),
      reasonType: _string(
        data['reasonType'] ?? penalty?['type'],
        fallback: reasonType,
      ),
      state: state,
      processText: process.isNotEmpty
          ? process
          : status == 'CANCELLED'
          ? '申诉已取消'
          : _appealProcessText(state),
      resultText: result,
    );
  }

  List<DeviceSession> _parseSessions(Object? value) {
    if (value is! List) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '设备会话响应缺少有效 list',
      );
    }
    final String currentDeviceId = _currentDeviceIdProvider().trim();
    final List<DeviceSession> sessions = <DeviceSession>[];
    for (int index = 0; index < value.length; index++) {
      final Map<String, Object?> item = _asMap(value[index]);
      if (item.isEmpty) {
        throw ApiException(
          kind: ApiFailureKind.protocol,
          message: '设备会话第 ${index + 1} 项不是有效对象',
        );
      }
      final String sessionId = _string(item['sessionId'] ?? item['id']);
      final String deviceId = _string(item['deviceId']);
      if (sessionId.isEmpty || deviceId.isEmpty) {
        throw ApiException(
          kind: ApiFailureKind.protocol,
          message: '设备会话第 ${index + 1} 项缺少 sessionId 或 deviceId',
        );
      }
      final DateTime? lastActiveAt = DateTime.tryParse(
        _string(item['lastUsedAt'] ?? item['createdAt']),
      );
      if (lastActiveAt == null) {
        throw ApiException(
          kind: ApiFailureKind.protocol,
          message: '设备会话第 ${index + 1} 项缺少有效服务时间',
        );
      }
      final Object? rawActive = item['active'];
      if (rawActive is! bool) {
        throw ApiException(
          kind: ApiFailureKind.protocol,
          message: '设备会话第 ${index + 1} 项缺少有效 active 布尔值',
        );
      }
      final bool active = rawActive;
      final bool isCurrent =
          currentDeviceId.isNotEmpty && deviceId == currentDeviceId;
      sessions.add(
        DeviceSession(
          id: sessionId,
          deviceName: _string(item['deviceName'] ?? deviceId, fallback: '登录设备'),
          location: _string(item['location'], fallback: '位置由系统隐私设置决定'),
          lastActiveAt: lastActiveAt,
          isCurrent: isCurrent,
          // Fail closed when the session manager has no device id. In
          // particular, never expose the current session as revocable.
          canRevoke: active && currentDeviceId.isNotEmpty && !isCurrent,
        ),
      );
    }
    return sessions;
  }

  static VerificationState _verificationState(int code) => switch (code) {
    1 => VerificationState.pending,
    2 => VerificationState.verified,
    3 => VerificationState.rejected,
    _ => VerificationState.unverified,
  };

  static RestrictionKind _restrictionKind(
    String type, {
    required bool restricted,
  }) {
    if (!restricted) {
      return RestrictionKind.none;
    }
    final String normalized = type.toUpperCase();
    if (normalized.contains('DEVICE')) {
      return RestrictionKind.device;
    }
    if (normalized.contains('CHAT') ||
        normalized.contains('MUTE') ||
        normalized.contains('MESSAGE')) {
      return RestrictionKind.chat;
    }
    return RestrictionKind.account;
  }

  static String _cancellationMessage(String status, bool eligible) {
    if (status == 'COOLING_OFF') {
      return '账户已进入注销冷静期';
    }
    return eligible ? '账号满足注销条件' : '当前暂不满足注销条件';
  }

  static CancellationEligibility _parseCancellation(Map<String, Object?> data) {
    if (data.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '账户注销资格响应缺少有效对象',
      );
    }
    final Map<String, Object?> latestRequest = _requireMap(
      data['latestRequest'],
      '账户注销资格 latestRequest',
      allowEmpty: true,
    );
    final String status = _requiredString(
      data,
      'status',
      '账户注销资格',
    ).toUpperCase();
    if (status != 'NONE' && status != 'COOLING_OFF') {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '账户注销资格响应包含未知状态',
      );
    }
    final bool eligible = _requiredBool(data, 'eligible', '账户注销资格');
    final bool canLogout = _requiredBool(data, 'canLogout', '账户注销资格');
    if (eligible != canLogout || eligible != (status == 'NONE')) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '账户注销资格响应中的资格字段互相矛盾',
      );
    }
    if (!_requiredBool(data, 'requiresConfirmation', '账户注销资格') ||
        _requiredBool(data, 'immediateDeletion', '账户注销资格')) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '账户注销资格响应违反冷静期确认契约',
      );
    }
    if (status == 'COOLING_OFF') {
      if (_requiredString(
            latestRequest,
            'status',
            '账户注销资格 latestRequest',
          ).toUpperCase() !=
          'COOLING_OFF') {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '账户注销资格响应缺少有效冷静期申请',
        );
      }
      if (DateTime.tryParse(_string(latestRequest['coolingEndsAt'])) == null) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '账户注销资格响应缺少有效冷静期截止时间',
        );
      }
    } else if (latestRequest.isNotEmpty &&
        _string(latestRequest['status']).toUpperCase() == 'COOLING_OFF') {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '账户注销资格响应中的当前状态与申请记录矛盾',
      );
    }
    return CancellationEligibility(
      allowed: eligible,
      canCancel: status == 'COOLING_OFF',
      status: status,
      coolingEndsAt: _string(
        data['coolingEndsAt'] ?? latestRequest['coolingEndsAt'],
      ),
      message: _cancellationMessage(status, eligible),
      mobile: _maskMobile(_string(data['phone'] ?? data['mobile'])),
      // The first-party endpoint requires an explicit confirmation body. It
      // does not use or pretend to validate a provider SMS code.
      requiresSmsCode: false,
    );
  }

  static String _appealProcessText(AppealState state) => switch (state) {
    AppealState.pending => '平台审核中',
    AppealState.approved => '申诉已通过',
    AppealState.rejected => '申诉未通过',
    AppealState.none => '暂无申诉记录',
  };

  static int _parseVerificationCode(Map<String, Object?> data) {
    final String status = _requiredString(data, 'status', '实名认证').toUpperCase();
    final int code = _requiredNonNegativeInt(data, 'statusCode', '实名认证');
    final int expected = switch (status) {
      'NOT_SUBMITTED' || 'UNVERIFIED' => 0,
      'PENDING' => 1,
      'VERIFIED' || 'APPROVED' => 2,
      'REJECTED' => 3,
      _ => -1,
    };
    if (expected < 0 || code != expected) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '实名认证响应中的状态字段无效或互相矛盾',
      );
    }
    final String providerStatus = _requiredExactString(
      data,
      'providerStatus',
      '实名认证',
    );
    final String reviewStatus = _requiredExactString(
      data,
      'reviewStatus',
      '实名认证',
    );
    final String reviewMode = _requiredExactString(data, 'reviewMode', '实名认证');
    final bool providerInvocation = _requiredBool(
      data,
      'providerInvocation',
      '实名认证',
    );
    if (providerStatus != 'FIRST_PARTY_REVIEW' ||
        reviewStatus != 'FIRST_PARTY_REVIEW' ||
        reviewMode != 'FIRST_PARTY_MANUAL_REVIEW' ||
        providerInvocation) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '实名认证响应必须满足第一方人工审核契约',
      );
    }
    return code;
  }

  static Map<String, Object?> _parseRestriction(Object? value) {
    final Map<String, Object?> item = _requireMap(value, '账户限制记录');
    _requiredString(item, 'penaltyId', '账户限制记录');
    _requiredString(item, 'type', '账户限制记录');
    if (_requiredString(item, 'status', '账户限制记录') != 'ACTIVE') {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '账户限制响应包含非 ACTIVE 记录',
      );
    }
    _requiredString(item, 'reason', '账户限制记录');
    final String endsAt = _string(item['endsAt']);
    if (endsAt.isNotEmpty && DateTime.tryParse(endsAt) == null) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '账户限制记录包含无效 endsAt',
      );
    }
    return item;
  }

  static Map<String, Object?> _requireMap(
    Object? value,
    String field, {
    bool allowEmpty = false,
  }) {
    if (value is! Map) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$field 响应不是有效对象',
      );
    }
    final Map<String, Object?> result = <String, Object?>{};
    for (final MapEntry<Object?, Object?> entry in value.entries) {
      if (entry.key is! String) {
        throw ApiException(
          kind: ApiFailureKind.protocol,
          message: '$field 响应包含非字符串字段名',
        );
      }
      result[entry.key as String] = entry.value;
    }
    if (!allowEmpty && result.isEmpty) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$field 响应缺少有效字段',
      );
    }
    return result;
  }

  static List<Object?> _requireList(Object? value, String field) {
    if (value is! List) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$field 不是有效列表',
      );
    }
    return value.cast<Object?>();
  }

  static String _requiredString(
    Map<String, Object?> data,
    String key,
    String field,
  ) {
    final Object? raw = data[key];
    if (raw is! String || raw.trim().isEmpty) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$field 响应缺少有效 $key',
      );
    }
    return raw.trim();
  }

  static String _requiredExactString(
    Map<String, Object?> data,
    String key,
    String field,
  ) {
    final Object? raw = data[key];
    if (raw is! String || raw.isEmpty || raw.trim() != raw) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$field 响应缺少有效 $key',
      );
    }
    return raw;
  }

  static bool _requiredBool(
    Map<String, Object?> data,
    String key,
    String field,
  ) {
    final Object? raw = data[key];
    if (raw is! bool) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$field 响应缺少有效 $key 布尔值',
      );
    }
    return raw;
  }

  static int _requiredNonNegativeInt(
    Map<String, Object?> data,
    String key,
    String field,
  ) {
    final Object? raw = data[key];
    if (raw is! int || raw < 0) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$field 响应缺少有效 $key 整数',
      );
    }
    return raw;
  }

  static int _requiredPositiveInt(
    Map<String, Object?> data,
    String key,
    String field,
  ) {
    final Object? raw = data[key];
    if (raw is! int || raw <= 0) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$field 响应缺少有效 $key 正整数',
      );
    }
    return raw;
  }

  static int _strictBinaryInt(Object? value, String field) {
    if (value is! int || (value != 0 && value != 1)) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$field 必须是 0 或 1',
      );
    }
    return value;
  }

  static Map<String, Object?> _asMap(Object? value) {
    if (value is! Map) {
      return const <String, Object?>{};
    }
    return <String, Object?>{
      for (final MapEntry<Object?, Object?> entry in value.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }

  static String _string(Object? value, {String fallback = ''}) {
    final String result = value?.toString().trim() ?? '';
    return result.isEmpty ? fallback : result;
  }

  static DateTime? _nullableDateTime(Object? value) {
    return DateTime.tryParse(_string(value));
  }

  static String _maskMobile(String mobile) {
    if (mobile.length != 11) {
      return mobile;
    }
    return '${mobile.substring(0, 3)}****${mobile.substring(7)}';
  }
}
