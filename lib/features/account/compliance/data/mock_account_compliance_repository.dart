import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/account/compliance/domain/account_compliance.dart';

class MockAccountComplianceRepository implements AccountComplianceRepository {
  AccountComplianceSnapshot? _snapshot;
  AppealCase? _appeal;

  @override
  bool get supportsDeviceSessionManagement => true;

  @override
  bool get supportsRealNameSubmission => true;

  @override
  Future<AccountComplianceSnapshot> fetchSnapshot({
    required String account,
    required int currentVersion,
    required int platformType,
  }) async {
    _snapshot ??= AccountComplianceSnapshot(
      account: account,
      nickname: '晚星',
      verificationState: VerificationState.unverified,
      youthModeEnabled: false,
      restriction: const AccountRestriction(
        kind: RestrictionKind.none,
        reason: '',
      ),
      cancellation: const CancellationEligibility(
        allowed: true,
        message: '账号满足注销条件。注销后资料、关系与钱包记录将按平台规则处理。',
        mobile: '138****8000',
        requiresSmsCode: true,
        status: 'NONE',
        canCancel: false,
      ),
      versionInfo: const VersionUpdateInfo(
        hasUpdate: true,
        forceUpdate: false,
        versionName: '0.2.3',
        releaseNotes: '优化房间发现、成员管理和账号安全体验。',
        packageUrl: '',
      ),
      sessions: <DeviceSession>[
        DeviceSession(
          id: 'current',
          deviceName: '当前设备 · Android',
          location: '东京',
          lastActiveAt: DateTime.now(),
          isCurrent: true,
          canRevoke: false,
        ),
        DeviceSession(
          id: 'secondary',
          deviceName: 'iPhone',
          location: '武汉',
          lastActiveAt: DateTime.now().subtract(const Duration(days: 2)),
          isCurrent: false,
          canRevoke: true,
        ),
      ],
      permissions: const <PermissionSetting>[
        PermissionSetting(
          kind: PermissionKind.microphone,
          state: PermissionState.granted,
          title: '麦克风',
          purpose: '上麦发言、音频诊断和房间语音互动。',
          managedByPlatform: true,
        ),
        PermissionSetting(
          kind: PermissionKind.notifications,
          state: PermissionState.notDetermined,
          title: '通知',
          purpose: '好友请求、系统通知和房间邀请提醒。',
          managedByPlatform: true,
        ),
        PermissionSetting(
          kind: PermissionKind.photos,
          state: PermissionState.denied,
          title: '照片',
          purpose: '修改头像、举报凭证和发布动态图片。',
          managedByPlatform: true,
        ),
      ],
    );
    return _snapshot!;
  }

  @override
  Future<void> setPermissionState({
    required PermissionKind kind,
    required PermissionState state,
  }) async {
    final AccountComplianceSnapshot snapshot = _requireSnapshot();
    _snapshot = snapshot.copyWith(
      permissions: <PermissionSetting>[
        for (final PermissionSetting item in snapshot.permissions)
          if (item.kind == kind) item.copyWith(state: state) else item,
      ],
    );
  }

  @override
  Future<void> openPermissionSettings() async {}

  @override
  Future<void> submitRealName({
    required String realName,
    required String idNumber,
  }) async {
    if (realName.trim().length < 2 || idNumber.trim().length != 18) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '请填写真实姓名和 18 位身份证号',
      );
    }
    _snapshot = _requireSnapshot().copyWith(
      verificationState: VerificationState.verified,
    );
  }

  @override
  Future<void> revokeDeviceSession(String sessionId) async {
    final AccountComplianceSnapshot snapshot = _requireSnapshot();
    DeviceSession? target;
    for (final DeviceSession item in snapshot.sessions) {
      if (item.id == sessionId) {
        target = item;
        break;
      }
    }
    if (target == null || !target.canRevoke) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '该会话不可移除',
      );
    }
    _snapshot = snapshot.copyWith(
      sessions: snapshot.sessions
          .where((DeviceSession item) => item.id != sessionId)
          .toList(growable: false),
    );
  }

  @override
  Future<AppealCase> queryAppeal({
    required String account,
    required String reasonType,
  }) async {
    return _appeal ??
        AppealCase(
          account: account,
          nickname: '晚星',
          reason: reasonType == '3' ? '公屏违规内容' : '账号安全策略命中',
          reasonType: reasonType,
          state: AppealState.none,
          processText: '尚未提交申诉',
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
    if (explanation.trim().length < 10) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '申诉说明至少填写 10 个字',
      );
    }
    _appeal = AppealCase(
      account: account,
      nickname: nickname,
      reason: reason,
      reasonType: reasonType,
      state: AppealState.pending,
      processText: '平台审核中',
      resultText: '',
    );
    return _appeal!;
  }

  @override
  Future<AppealCase> queryAppealProgress(String account) async {
    return _appeal ??
        AppealCase(
          account: account,
          nickname: '晚星',
          reason: '',
          reasonType: '1',
          state: AppealState.none,
          processText: '暂无申诉记录',
          resultText: '',
        );
  }

  @override
  Future<CancellationEligibility> queryCancellationEligibility() async =>
      _requireSnapshot().cancellation;

  @override
  Future<void> requestCancellation({required String smsCode}) async {
    if (smsCode.trim().length != 6) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '请输入 6 位短信验证码',
      );
    }
    final AccountComplianceSnapshot snapshot = _requireSnapshot();
    if (!snapshot.cancellation.allowed) {
      throw ApiException(
        kind: ApiFailureKind.business,
        message: snapshot.cancellation.message,
      );
    }
    _snapshot = snapshot.copyWith(
      cancellation: const CancellationEligibility(
        allowed: false,
        message: '注销申请已提交，当前处于 7 天冷静期。',
        mobile: '138****8000',
        requiresSmsCode: false,
        status: 'COOLING_OFF',
        canCancel: true,
        coolingEndsAt: '2026-08-29T00:00:00Z',
      ),
    );
  }

  @override
  Future<CancellationEligibility> cancelDeletion() async {
    final AccountComplianceSnapshot snapshot = _requireSnapshot();
    if (!snapshot.cancellation.canCancel) {
      throw const ApiException(
        kind: ApiFailureKind.conflict,
        message: '当前没有可撤销的注销申请',
      );
    }
    _snapshot = snapshot.copyWith(
      cancellation: const CancellationEligibility(
        allowed: true,
        message: '注销申请已撤销，账号恢复正常状态。',
        mobile: '138****8000',
        requiresSmsCode: false,
        status: 'NONE',
        canCancel: false,
      ),
    );
    return _snapshot!.cancellation;
  }

  @override
  Future<VersionUpdateInfo> checkVersion({
    required int currentVersion,
    required int platformType,
  }) async => _requireSnapshot().versionInfo;

  @override
  Future<bool> setYouthMode({
    required bool enabled,
    required String pin,
  }) async {
    if (!RegExp(r'^\d{4}$').hasMatch(pin)) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '请输入 4 位数字密码',
      );
    }
    _snapshot = _requireSnapshot().copyWith(youthModeEnabled: enabled);
    return enabled;
  }

  AccountComplianceSnapshot _requireSnapshot() {
    final AccountComplianceSnapshot? snapshot = _snapshot;
    if (snapshot == null) {
      throw StateError('请先加载账号合规状态');
    }
    return snapshot;
  }
}
