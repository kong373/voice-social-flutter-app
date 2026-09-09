import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/commerce/data/mock_commerce_repository.dart';
import 'package:voice_social_app/features/commerce/domain/commerce_models.dart';
import 'package:voice_social_app/features/commerce/catalog/domain/commerce_catalog_models.dart';

void main() {
  test(
    'S07 recharge keeps fractional remainder and credits old whole units once',
    () async {
      final repository = MockCommerceRepository()
        ..giftCoins = GiftCoinAmount.fromTenths('5');
      final order = RechargeOrder(
        orderNo: 'precise-recharge',
        account: 'demo',
        product: const RechargeProduct(
          id: 'old-whole',
          giftCoins: 100,
          priceCny: 10,
        ),
        channel: PaymentChannelType.alipay,
        state: RechargeOrderState.succeeded,
        createdAt: DateTime.utc(2026, 9, 9),
      );
      repository.syncRechargeOrder(order);
      repository.syncRechargeOrder(order);
      expect((await repository.fetchWalletSummary()).giftCoinText, '100.5');
      expect(
        (await repository.fetchOrders(
          page: 1,
          pageSize: 10,
        )).items.first.giftCoinAmount,
        100,
      );
    },
  );
  test(
    'youth mode locks foreground features without deleting recovery data',
    () {
      const YouthModeCommercePolicy policy = YouthModeCommercePolicy();

      expect(policy.canCreateRechargeOrder(youthModeEnabled: true), isFalse);
      expect(policy.canCreateRechargeOrder(youthModeEnabled: false), isTrue);
      expect(policy.canUseNonRechargeFeature(youthModeEnabled: true), isFalse);
      expect(policy.canUseNonRechargeFeature(youthModeEnabled: false), isTrue);
      expect(
        policy.rechargeRestrictionReason(youthModeEnabled: true),
        contains('不能创建新的充值订单'),
      );
    },
  );

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

    for (final LedgerCurrency currency in LedgerCurrency.values) {
      for (final LedgerDirection direction in LedgerDirection.values) {
        final CommercePage<LedgerEntry> page = await repository.fetchLedger(
          currency: currency,
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
    }
    final LedgerEntry giftCoin = (await repository.fetchLedger(
      currency: LedgerCurrency.giftCoin,
      direction: LedgerDirection.income,
      page: 1,
      pageSize: 10,
    )).items.single;
    final LedgerEntry cash = (await repository.fetchLedger(
      currency: LedgerCurrency.cashCny,
      direction: LedgerDirection.income,
      page: 1,
      pageSize: 10,
    )).items.first;
    expect(giftCoin.coinAmount!.text, '300');
    expect(giftCoin.amount, isNull);
    expect(cash.amount, 68);
    expect(repository.supportsPaymentChannelInvocation, isFalse);
    expect(repository.refundScope, RefundScope.accountLegacy);
  });

  test(
    'orders, account-level refund, and withdrawal use authority checks',
    () async {
      final MockCommerceRepository repository = MockCommerceRepository();

      final CommercePage<PaymentOrder> orders = await repository.fetchOrders(
        page: 1,
        pageSize: 20,
      );
      final PaymentOrder confirming = orders.items.firstWhere(
        (PaymentOrder item) => item.status == PaymentOrderStatus.confirming,
      );
      final PaymentOrder refreshed = await repository.queryOrderStatus(
        confirming,
      );
      expect(refreshed.status, PaymentOrderStatus.succeeded);

      final RefundEligibility blocked = await repository.checkRefundEligibility(
        '13800138000',
      );
      expect(blocked.allowed, isFalse);
      expect(blocked.existingApplicationId, isNotNull);

      await expectLater(
        repository.applyWithdrawal(
          amount: 5,
          confirmedQuote: _confirmedQuote(5),
        ),
        throwsA(isA<ApiException>()),
      );
      final WithdrawalRecord withdrawal = await repository.applyWithdrawal(
        amount: 100,
        confirmedQuote: _confirmedQuote(100),
      );
      expect(withdrawal.status, WithdrawalStatus.pending);
      expect(withdrawal.receivedAmount, 100);
    },
  );
}

WithdrawalQuote _confirmedQuote(double amount) {
  final minor = WithdrawalAmountPolicy.isValid(amount)
      ? (amount * 100).round()
      : 0;
  final fee = WithdrawalQuote.ceilingFeeMinor(minor, 0);
  return WithdrawalQuote(
    quotedAmount: amount,
    feeAmount: fee / 100,
    receivedAmount: (minor - fee) / 100,
    feeRateBasisPoints: 0,
    feePolicyVersion: 0,
    feeRateText: '0%',
    minimumAmount: 100,
  );
}
