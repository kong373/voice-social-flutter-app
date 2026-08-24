enum VerificationState { unverified, pending, verified, rejected, unavailable }

enum RestrictionKind { none, account, device, chat }

enum AppealState { none, pending, approved, rejected }

enum PermissionKind { microphone, notifications, photos }

/// State returned by the authoritative permission source.
///
/// `notDetermined` is only valid after a native platform adapter has actually
/// queried the OS. Live HTTP data cannot infer it. Until that adapter exists,
/// the backend repository must use [unavailable] and leave platform ownership
/// unknown.
enum PermissionState { notDetermined, granted, denied, restricted, unavailable }

class PermissionSetting {
  const PermissionSetting({
    required this.kind,
    required this.state,
    required this.title,
    required this.purpose,
    required this.managedByPlatform,
  });

  final PermissionKind kind;
  final PermissionState state;
  final String title;
  final String purpose;

  /// Whether the OS/native adapter owns this state. `null` means that no
  /// native authority is connected yet; it is intentionally different from
  /// `false`, which would claim that the platform does not manage the
  /// permission.
  final bool? managedByPlatform;

  PermissionSetting copyWith({
    PermissionState? state,
    bool? managedByPlatform,
  }) {
    return PermissionSetting(
      kind: kind,
      state: state ?? this.state,
      title: title,
      purpose: purpose,
      managedByPlatform: managedByPlatform ?? this.managedByPlatform,
    );
  }
}

class DeviceSession {
  const DeviceSession({
    required this.id,
    required this.deviceName,
    required this.location,
    required this.lastActiveAt,
    required this.isCurrent,
    required this.canRevoke,
  });

  final String id;
  final String deviceName;
  final String location;
  final DateTime lastActiveAt;
  final bool isCurrent;
  final bool canRevoke;
}

class AccountRestriction {
  const AccountRestriction({
    required this.kind,
    required this.reason,
    this.expiresAt,
  });

  final RestrictionKind kind;
  final String reason;
  final DateTime? expiresAt;

  bool get isRestricted => kind != RestrictionKind.none;
}

class AppealCase {
  const AppealCase({
    required this.account,
    required this.nickname,
    required this.reason,
    required this.reasonType,
    required this.state,
    required this.processText,
    required this.resultText,
  });

  final String account;
  final String nickname;
  final String reason;
  final String reasonType;
  final AppealState state;
  final String processText;
  final String resultText;
}

class CancellationEligibility {
  const CancellationEligibility({
    required this.allowed,
    required this.message,
    required this.mobile,
    required this.requiresSmsCode,
    this.status = 'NONE',
    this.canCancel = false,
    this.coolingEndsAt = '',
  });

  final bool allowed;
  final String message;
  final String mobile;
  final bool requiresSmsCode;

  /// The server-owned deletion request state, for example `NONE` or
  /// `COOLING_OFF`.
  final String status;

  /// Whether the server currently permits cancelling the deletion request.
  /// This is intentionally separate from [allowed], which means that a new
  /// deletion request may be submitted.
  final bool canCancel;

  /// The server-provided cooling-off deadline, if one exists.
  final String coolingEndsAt;
}

class VersionUpdateInfo {
  const VersionUpdateInfo({
    required this.hasUpdate,
    required this.forceUpdate,
    required this.versionName,
    required this.releaseNotes,
    required this.packageUrl,
  });

  final bool hasUpdate;
  final bool forceUpdate;
  final String versionName;
  final String releaseNotes;
  final String packageUrl;
}

class AccountComplianceSnapshot {
  const AccountComplianceSnapshot({
    required this.account,
    required this.nickname,
    required this.verificationState,
    required this.youthModeEnabled,
    required this.restriction,
    required this.cancellation,
    required this.versionInfo,
    required this.sessions,
    required this.permissions,
  });

  final String account;
  final String nickname;
  final VerificationState verificationState;
  final bool youthModeEnabled;
  final AccountRestriction restriction;
  final CancellationEligibility cancellation;
  final VersionUpdateInfo versionInfo;
  final List<DeviceSession> sessions;
  final List<PermissionSetting> permissions;

  AccountComplianceSnapshot copyWith({
    VerificationState? verificationState,
    bool? youthModeEnabled,
    AccountRestriction? restriction,
    CancellationEligibility? cancellation,
    VersionUpdateInfo? versionInfo,
    List<DeviceSession>? sessions,
    List<PermissionSetting>? permissions,
  }) {
    return AccountComplianceSnapshot(
      account: account,
      nickname: nickname,
      verificationState: verificationState ?? this.verificationState,
      youthModeEnabled: youthModeEnabled ?? this.youthModeEnabled,
      restriction: restriction ?? this.restriction,
      cancellation: cancellation ?? this.cancellation,
      versionInfo: versionInfo ?? this.versionInfo,
      sessions: sessions ?? this.sessions,
      permissions: permissions ?? this.permissions,
    );
  }
}

abstract interface class AccountComplianceRepository {
  bool get supportsDeviceSessionManagement;
  bool get supportsRealNameSubmission;

  Future<AccountComplianceSnapshot> fetchSnapshot({
    required String account,
    required int currentVersion,
    required int platformType,
  });

  Future<void> setPermissionState({
    required PermissionKind kind,
    required PermissionState state,
  });

  Future<void> submitRealName({
    required String realName,
    required String idNumber,
  });

  Future<void> revokeDeviceSession(String sessionId);

  Future<AppealCase> queryAppeal({
    required String account,
    required String reasonType,
  });

  Future<AppealCase> submitAppeal({
    required String account,
    required String nickname,
    required String reason,
    required String reasonType,
    required String explanation,
  });

  Future<AppealCase> queryAppealProgress(String account);

  Future<CancellationEligibility> queryCancellationEligibility();

  Future<void> requestCancellation({required String smsCode});

  Future<CancellationEligibility> cancelDeletion();

  Future<VersionUpdateInfo> checkVersion({
    required int currentVersion,
    required int platformType,
  });

  Future<bool> setYouthMode({required bool enabled, required String pin});
}
