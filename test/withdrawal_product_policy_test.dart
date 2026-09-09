import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/commerce/data/mock_commerce_repository.dart';
import 'package:voice_social_app/features/commerce/domain/commerce_models.dart';

void main() {
  test(
    '101.12 balance allows 101, preserves .12 and cannot withdraw remainder',
    () async {
      final repository = MockCommerceRepository(initialCashBalance: 101.12);
      await repository.applyWithdrawal(amount: 101);
      expect(
        (await repository.fetchWalletSummary()).cashBalance,
        closeTo(.12, .000001),
      );
      await expectLater(
        repository.applyWithdrawal(amount: .12),
        throwsA(isA<ApiException>()),
      );
    },
  );

  test(
    'Beijing midnight renews quota; rejection and imported history do not recalculate it',
    () async {
      var now = DateTime.utc(2026, 9, 9, 15, 59, 59);
      final repository = MockCommerceRepository(clock: () => now);
      final old = (await repository.fetchWithdrawalRecords(
        page: 1,
        pageSize: 20,
      )).items.first;
      WithdrawalRecord rejected(String id) => WithdrawalRecord(
        id: id,
        withdrawalNo: id,
        amount: old.amount,
        fee: old.fee,
        receivedAmount: old.receivedAmount,
        status: WithdrawalStatus.rejected,
        statusText: '已驳回',
        createdAt: now,
        rejectedReason: 'test',
        holderNameMasked: old.holderNameMasked,
        maskedCard: old.maskedCard,
      );
      repository.seedWithdrawalRecordForQa(rejected('imported-today'));
      final first = await repository.applyWithdrawal(amount: 100);
      repository.seedWithdrawalRecordForQa(rejected(first.id));
      await expectLater(
        repository.applyWithdrawal(amount: 101),
        throwsA(isA<ApiException>().having((e) => e.httpStatus, 'HTTP', 409)),
      );
      now = now.add(const Duration(seconds: 1));
      final next = await repository.applyWithdrawal(amount: 100);
      expect(next.id, isNot(first.id));
      expect(
        (await repository.fetchWithdrawalRecord(first.id)).status,
        WithdrawalStatus.rejected,
      );
    },
  );

  test(
    'concurrent applications consume only one daily slot and balance debit',
    () async {
      final repository = MockCommerceRepository();
      final results = await Future.wait(
        [100.0, 101.0].map((amount) async {
          try {
            return await repository.applyWithdrawal(amount: amount);
          } catch (error) {
            return error;
          }
        }),
      );
      expect(results.whereType<WithdrawalRecord>(), hasLength(1));
      expect(
        results.whereType<ApiException>().single.kind,
        ApiFailureKind.conflict,
      );
      expect((await repository.fetchWalletSummary()).cashBalance, 1188.5);
    },
  );

  test(
    'withdrawal rejects below minimum, fractional and unsafe amounts',
    () async {
      final repository = MockCommerceRepository();
      for (final amount in [
        99.0,
        100.01,
        double.nan,
        double.infinity,
        1e308,
        90071992547410.0,
      ]) {
        await expectLater(
          repository.fetchWithdrawalQuote(amount: amount),
          throwsA(isA<ApiException>()),
          reason: '$amount',
        );
        await expectLater(
          repository.applyWithdrawal(amount: amount),
          throwsA(isA<ApiException>()),
          reason: '$amount',
        );
      }
    },
  );

  test(
    'default quote is zero percent, minimum 100 and remainder is retained',
    () async {
      final repository = MockCommerceRepository();
      final quote = await repository.fetchWithdrawalQuote(amount: 100);
      expect(quote.minimumAmount, 100);
      expect(quote.feeRate, 0);
      expect(quote.feeAmount, 0);
      expect(quote.receivedAmount, 100);
      final before = await repository.fetchWalletSummary();
      final record = await repository.applyWithdrawal(
        amount: before.cashBalance.floorToDouble(),
      );
      expect(record.receivedAmount, 1288);
      final after = await repository.fetchWalletSummary();
      expect(after.cashBalance, 0.50);
    },
  );

  test(
    'only one successful application a day; client failures do not occupy it',
    () async {
      final repository = MockCommerceRepository(
        now: DateTime.utc(2026, 9, 9, 12),
      );
      await expectLater(
        repository.applyWithdrawal(amount: 100, payoutAccountId: 'invalid'),
        throwsA(isA<ApiException>()),
      );
      await repository.applyWithdrawal(amount: 100);
      await expectLater(
        repository.applyWithdrawal(amount: 100),
        throwsA(
          isA<ApiException>().having(
            (e) => e.kind,
            'kind',
            ApiFailureKind.conflict,
          ),
        ),
      );
    },
  );
}
