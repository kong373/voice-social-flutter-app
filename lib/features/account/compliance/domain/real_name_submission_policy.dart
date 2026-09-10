/// A strict projection of the backend real-name submission workflow.
///
/// These flags do not override account availability, youth-mode restrictions
/// or server-side permissions. No device date or editable birthday is used.
final class RealNameSubmissionPolicy {
  const RealNameSubmissionPolicy._({
    required this.needsAgeResubmission,
    required this.needsIdentityResubmission,
    required this.canSubmit,
  });

  final bool needsAgeResubmission;
  final bool needsIdentityResubmission;
  final bool canSubmit;

  factory RealNameSubmissionPolicy.fromBackendData(Map<String, Object?> data) {
    final status = data['status'];
    final statusCode = data['statusCode'];
    final needsAgeResubmission = data['needsAgeResubmission'];
    final needsIdentityResubmission =
        data.containsKey('needsIdentityResubmission')
        ? data['needsIdentityResubmission']
        : false;
    final canSubmit = data['canSubmit'];

    if (status is! String ||
        statusCode is! int ||
        needsAgeResubmission is! bool ||
        needsIdentityResubmission is! bool ||
        canSubmit is! bool) {
      throw const FormatException('INVALID_REAL_NAME_SUBMISSION_POLICY');
    }

    final expectedCode = switch (status) {
      'NOT_SUBMITTED' || 'UNVERIFIED' => 0,
      'PENDING' => 1,
      'VERIFIED' || 'APPROVED' => 2,
      'REJECTED' => 3,
      _ => throw const FormatException('INVALID_REAL_NAME_SUBMISSION_POLICY'),
    };

    if (statusCode != expectedCode ||
        ((needsAgeResubmission || needsIdentityResubmission) &&
            statusCode != 2)) {
      throw const FormatException('INVALID_REAL_NAME_SUBMISSION_POLICY');
    }

    final expectedCanSubmit =
        statusCode == 0 ||
        statusCode == 3 ||
        (statusCode == 2 &&
            (needsAgeResubmission || needsIdentityResubmission));

    if (canSubmit != expectedCanSubmit) {
      throw const FormatException('INVALID_REAL_NAME_SUBMISSION_POLICY');
    }

    return RealNameSubmissionPolicy._(
      needsAgeResubmission: needsAgeResubmission,
      needsIdentityResubmission: needsIdentityResubmission,
      canSubmit: canSubmit,
    );
  }
}
