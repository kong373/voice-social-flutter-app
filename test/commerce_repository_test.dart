import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/commerce/data/mock_commerce_repository.dart';
import 'package:voice_social_app/features/commerce/domain/commerce_models.dart';

void main() {
  test('youth mode only blocks creation of new recharge orders', () {
    const YouthModeCommercePolicy policy = YouthModeCommercePolicy();

    expect(
      policy.canCreateRechargeOrder(youthModeEnabled: true),
      isFalse,
    );
    expect(
      policy.canCreateRechargeOrder(youthModeEnabled: false),
      isTrue,
    );
    expect(
      policy.canUseNonRechargeFeature(youthModeEnabled: true),
      isTrue,
    );
    expect(
      policy.rechargeRestrictionReason(youthModeEnabled: true),
      contains('不能创建新的充值订单'),
    );
  });

  test('wallet ledger excludes retired game and gift subtypes', () async {
    final MockCommerceRepository repository = MockCommerceRepository();
    const Set<String> retired = <String>{
      'blind_box',
      'red_packet',
      'magic_ball',
      'dango',
      'love_letter',
      'ktv',
    };

    for (final LedgerDirection direction in LedgerDirection.values) {
      final CommercePage<LedgerEntry> page = await repository.fetchLedger(
        direction: direction,
        page: 1,
        pageSize: 50,
      );
      expect(
        page.items.where(
          (LedgerEntry entry) => retired.contains(entry.rawSubtype),
        ),
        isEmpty,
      );
    }
    expect(repository.supportsPaymentChannelInvocation, isFalse);
    expect(repository.refundScope, RefundScope.accountLegacy);
  });

  test('orders, account-level refund, and withdrawal use authority checks', () async {
    final MockCommerceRepository repository = MockCommerceRepository();

    final CommercePage<PaymentOrder> orders = await repository.fetchOrders(
      page: 1,
      pageSize: 20,
    );
    final PaymentOrder confirming = orders.items.firstWhere(
      (PaymentOrder item) => item.status == PaymentOrderStatus.confirming,
    );
    final PaymentOrder refreshed =
        await repository.queryOrderStatus(confirming);
    expect(refreshed.status, PaymentOrderStatus.succeeded);

    final RefundEligibility blocked =
        await repository.checkRefundEligibility('13800138000');
    expect(blocked.allowed, isFalse);
    expect(blocked.existingApplicationId, isNotNull);

    await expectLater(
      repository.applyWithdrawal(amount: 50),
      throwsA(isA<ApiException>()),
    );
    final WithdrawalRecord withdrawal =
        await repository.applyWithdrawal(amount: 100);
    expect(withdrawal.status, WithdrawalStatus.pending);
    expect(withdrawal.receivedAmount, 99);
  });
}
