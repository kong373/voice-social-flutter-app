import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/features/account/compliance/domain/account_compliance.dart';

class BackendAccountComplianceRepository
    implements AccountComplianceRepository {
  BackendAccountComplianceRepository({
    required ApiClient apiClient,
    BackendRouteCatalog routes = const BackendRouteCatalog(),
  }) : _apiClient = apiClient,
       _routes = routes;

  final ApiClient _apiClient;
  final BackendRouteCatalog _routes;

  @override
  bool get supportsDeviceSessionManagement => false;

  @override
  bool get supportsRealNameSubmission => false;

  @override
  Future<AccountComplianceSnapshot> fetchSnapshot({
    required String account,
    required int currentVersion,
    required int platformType,
  }) async {
    final Map<String, Object?> profile = await _bestEffortMap(
      () => _apiClient.get(_routes.personalData),
    );
    final Map<String, Object?> youth = await _bestEffortMap(
      () => _apiClient.get(_routes.youthModeStatus),
    );
    final CancellationEligibility cancellation =
        await queryCancellationEligibility();
    final VersionUpdateInfo versionInfo = await checkVersion(
      currentVersion: currentVersion,
      platformType: platformType,
    );

    final int verificationCode =
        _asInt(
          profile['realNameAuthStatus'] ??
              profile['certificationStatus'] ??
              profile['isRealName'],
        ) ??
        0;
    final int restrictionCode =
        _asInt(profile['forbiddenState'] ?? profile['restrictionType']) ?? 0;
    final String reason = _string(
      profile['forbiddenReason'] ?? profile['restrictionReason'],
    );

    return AccountComplianceSnapshot(
      account: _string(profile['loginName'], fallback: account),
      nickname: _string(profile['nickName'], fallback: '当前用户'),
      verificationState: switch (verificationCode) {
        1 => VerificationState.verified,
        2 => VerificationState.pending,
        3 => VerificationState.rejected,
        _ => VerificationState.unverified,
      },
      youthModeEnabled: _asInt(youth['isOpenMinorMode']) == 1,
      restriction: AccountRestriction(
        kind: switch (restrictionCode) {
          1 => RestrictionKind.account,
          2 => RestrictionKind.device,
          3 => RestrictionKind.chat,
          _ => RestrictionKind.none,
        },
        reason: reason,
      ),
      cancellation: cancellation,
      versionInfo: versionInfo,
      sessions: <DeviceSession>[
        DeviceSession(
          id: 'current',
          deviceName: '当前登录设备',
          location: '位置由系统隐私设置决定',
          lastActiveAt: DateTime.now(),
          isCurrent: true,
          canRevoke: false,
        ),
      ],
      permissions: const <PermissionSetting>[
        PermissionSetting(
          kind: PermissionKind.microphone,
          state: PermissionState.notDetermined,
          title: '麦克风',
          purpose: '上麦发言、音频诊断和房间语音互动。',
          managedByPlatform: false,
        ),
        PermissionSetting(
          kind: PermissionKind.notifications,
          state: PermissionState.notDetermined,
          title: '通知',
          purpose: '好友请求、系统通知和房间邀请提醒。',
          managedByPlatform: false,
        ),
        PermissionSetting(
          kind: PermissionKind.photos,
          state: PermissionState.notDetermined,
          title: '照片',
          purpose: '修改头像、举报凭证和发布动态图片。',
          managedByPlatform: false,
        ),
      ],
    );
  }

  @override
  Future<void> setPermissionState({
    required PermissionKind kind,
    required PermissionState state,
  }) async {
    throw const ApiException(
      kind: ApiFailureKind.configuration,
      message: '系统权限需要原生平台适配器，当前版本不会伪造授权结果',
    );
  }

  @override
  Future<void> submitRealName({
    required String realName,
    required String idNumber,
  }) async {
    throw const ApiException(
      kind: ApiFailureKind.configuration,
      message: '实名认证需要认证服务返回的 certifyId，当前客户端尚未接入认证适配器',
    );
  }

  @override
  Future<void> revokeDeviceSession(String sessionId) async {
    throw const ApiException(
      kind: ApiFailureKind.configuration,
      message: '后端尚未提供用户侧会话撤销接口',
    );
  }

  @override
  Future<AppealCase> queryAppeal({
    required String account,
    required String reasonType,
  }) async {
    final ApiResponse response = await _apiClient.post(
      _routes.queryAppealInfo,
      body: <String, Object?>{'account': account, 'reasonType': reasonType},
    );
    final Map<String, Object?> data = _asMap(response.data);
    final bool hasRecord = _string(data['hasAppealRecord']) == '1';
    return AppealCase(
      account: _string(data['account'], fallback: account),
      nickname: _string(data['nickname'], fallback: '当前用户'),
      reason: _string(data['reason']),
      reasonType: _string(data['reasonType'], fallback: reasonType),
      state: hasRecord ? AppealState.pending : AppealState.none,
      processText: hasRecord ? '已有申诉记录，可查看处理进度' : '尚未提交申诉',
      resultText: '',
    );
  }

  @override
  Future<AppealCase> submitAppeal({
    required String account,
    required String nickname,
    required String reason,
    required String reasonType,
    required String explanation,
  }) async {
    await _apiClient.post(
      _routes.submitAppeal,
      body: <String, Object?>{
        'account': account,
        'nickname': nickname,
        'reason': reason,
        'reasonType': reasonType,
        'illustrate': explanation,
        'cutPics': const <String>[],
      },
    );
    return queryAppealProgress(account);
  }

  @override
  Future<AppealCase> queryAppealProgress(String account) async {
    final ApiResponse response = await _apiClient.post(
      _routes.queryAppealProgress,
      body: <String, Object?>{'account': account},
    );
    final Map<String, Object?> data = _asMap(response.data);
    final String process = _string(data['process']);
    final String result = _string(data['result']);
    final String normalized = '$process$result';
    final AppealState state =
        normalized.contains('通过') || normalized.contains('成功')
        ? AppealState.approved
        : normalized.contains('拒绝') || normalized.contains('失败')
        ? AppealState.rejected
        : normalized.isEmpty
        ? AppealState.none
        : AppealState.pending;
    return AppealCase(
      account: _string(data['account'], fallback: account),
      nickname: _string(data['nickname'], fallback: '当前用户'),
      reason: _string(data['reason'] ?? data['punish']),
      reasonType: '1',
      state: state,
      processText: process.isEmpty ? '暂无进度信息' : process,
      resultText: result,
    );
  }

  @override
  Future<CancellationEligibility> queryCancellationEligibility() async {
    try {
      final ApiResponse response = await _apiClient.get(
        _routes.queryAccountCancellation,
      );
      final Map<String, Object?> data = _asMap(response.data);
      return CancellationEligibility(
        allowed: _asBool(data['flat'], fallback: false),
        message: _string(data['msg'], fallback: '请完成注销前检查'),
        mobile: _maskMobile(_string(data['phone'])),
        requiresSmsCode: true,
      );
    } on ApiException catch (error) {
      return CancellationEligibility(
        allowed: false,
        message: error.message,
        mobile: '',
        requiresSmsCode: true,
      );
    }
  }

  @override
  Future<void> requestCancellation({required String smsCode}) async {
    await _apiClient.delete(
      _routes.deleteAccount,
      query: <String, String>{'smsCode': smsCode},
    );
  }

  @override
  Future<VersionUpdateInfo> checkVersion({
    required int currentVersion,
    required int platformType,
  }) async {
    final Map<String, Object?> data = await _bestEffortMap(
      () => _apiClient.post(
        _routes.versionInformation,
        body: <String, Object?>{
          'innerVersion': currentVersion,
          'platformType': platformType,
        },
      ),
    );
    return VersionUpdateInfo(
      hasUpdate: _asBool(data['isUpdate'], fallback: false),
      forceUpdate: _asInt(data['isForceUpgrade']) == 1,
      versionName: _string(data['versionStr']),
      releaseNotes: _string(data['upgradeLog']),
      packageUrl: _string(data['upgradePackageUrl']),
    );
  }

  @override
  Future<bool> setYouthMode({
    required bool enabled,
    required String pin,
  }) async {
    await _apiClient.get(
      enabled ? _routes.enableYouthMode : _routes.disableYouthMode,
      query: <String, String>{'minorModePwd': pin},
    );
    return enabled;
  }

  Future<Map<String, Object?>> _bestEffortMap(
    Future<ApiResponse> Function() request,
  ) async {
    try {
      final ApiResponse response = await request();
      return _asMap(response.data);
    } on ApiException {
      return const <String, Object?>{};
    }
  }

  static Map<String, Object?> _asMap(Object? value) =>
      value is Map<String, Object?> ? value : const <String, Object?>{};

  static int? _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    return int.tryParse(value?.toString() ?? '');
  }

  static bool _asBool(Object? value, {required bool fallback}) {
    if (value is bool) {
      return value;
    }
    final int? parsed = _asInt(value);
    if (parsed != null) {
      return parsed == 1;
    }
    return fallback;
  }

  static String _string(Object? value, {String fallback = ''}) {
    final String result = value?.toString().trim() ?? '';
    return result.isEmpty ? fallback : result;
  }

  static String _maskMobile(String mobile) {
    if (mobile.length != 11) {
      return mobile;
    }
    return '${mobile.substring(0, 3)}****${mobile.substring(7)}';
  }
}
