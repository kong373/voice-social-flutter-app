import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/account/compliance/data/mock_account_compliance_repository.dart';
import 'package:voice_social_app/features/account/compliance/domain/account_compliance.dart';

void main() {
  test(
    'account compliance mock preserves authoritative account changes',
    () async {
      final MockAccountComplianceRepository repository =
          MockAccountComplianceRepository();

      AccountComplianceSnapshot snapshot = await repository.fetchSnapshot(
        account: '13800138000',
        currentVersion: 3,
        platformType: 1,
      );
      expect(snapshot.sessions, hasLength(2));
      expect(snapshot.verificationState, VerificationState.unverified);
      expect(snapshot.youthModeEnabled, isFalse);

      await repository.revokeDeviceSession('secondary');
      await repository.submitRealName(
        realName: '张三',
        idNumber: '420106200001010018',
      );
      final bool enabled = await repository.setYouthMode(
        enabled: true,
        pin: '2468',
      );

      snapshot = await repository.fetchSnapshot(
        account: '13800138000',
        currentVersion: 3,
        platformType: 1,
      );
      expect(enabled, isTrue);
      expect(snapshot.sessions, hasLength(1));
      expect(snapshot.sessions.single.isCurrent, isTrue);
      expect(snapshot.verificationState, VerificationState.verified);
      expect(snapshot.youthModeEnabled, isTrue);
    },
  );

  test(
    'account appeal and cancellation validate high-risk submissions',
    () async {
      final MockAccountComplianceRepository repository =
          MockAccountComplianceRepository();
      await repository.fetchSnapshot(
        account: '13800138000',
        currentVersion: 3,
        platformType: 1,
      );

      await expectLater(
        repository.submitAppeal(
          account: '13800138000',
          nickname: '晚星',
          reason: '账号安全策略命中',
          reasonType: '1',
          explanation: '太短',
        ),
        throwsA(isA<ApiException>()),
      );

      final AppealCase appeal = await repository.submitAppeal(
        account: '13800138000',
        nickname: '晚星',
        reason: '账号安全策略命中',
        reasonType: '1',
        explanation: '本人正常使用账号，希望平台核对具体处罚证据。',
      );
      expect(appeal.state, AppealState.pending);

      await expectLater(
        repository.requestCancellation(smsCode: '12'),
        throwsA(isA<ApiException>()),
      );
      await repository.requestCancellation(smsCode: '123456');
      final CancellationEligibility eligibility = await repository
          .queryCancellationEligibility();
      expect(eligibility.allowed, isFalse);
      expect(eligibility.status, 'COOLING_OFF');
      expect(eligibility.canCancel, isTrue);
      expect(eligibility.requiresSmsCode, isFalse);

      final CancellationEligibility restored = await repository
          .cancelDeletion();
      expect(restored.allowed, isTrue);
      expect(restored.status, 'NONE');
      expect(restored.canCancel, isFalse);

      await expectLater(
        repository.cancelDeletion(),
        throwsA(isA<ApiException>()),
      );
    },
  );
}
