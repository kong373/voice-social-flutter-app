import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/commerce/data/backend_commerce_repository.dart';
import 'package:voice_social_app/features/commerce/domain/commerce_models.dart';

Map<String, Object?> precision([String amount = '1148']) => {
  'currency': 'GIFT_COIN',
  'scale': 10,
  'precisionVersion': 'GIFT_COIN_TENTHS_V1',
  'availableTenths': amount,
  'frozenTenths': '20',
  'integer': 100,
  'value': 100,
};
Map<String, Object?> overview([String role = 'ANCHOR']) => {
  'balance': '120.00',
  'frozenBalance': '0.00',
  'totalEarnings': '0.00',
  'yesterdayEarnings': '0.00',
  'totalWithdraw': '0.00',
  'isRealName': 0,
  'defaultBankCard': <String, Object?>{},
  'agentEarnings': null,
  'agentEarningsStatus': 'UNAVAILABLE',
  'superAgentEarnings': null,
  'superAgentEarningsStatus': 'UNAVAILABLE',
  'incomeRole': role,
  'incomeEligible': role != 'ORDINARY',
  'canWithdraw': role != 'ORDINARY',
};

void main() {
  test(
    'S08 manual finance never accepts unknown or automatic provider state',
    () async {
      Object? invocation = false;
      final h = await Harness.start(
        (r, _) => {
          'amountMinor': 10100,
          'feeMinor': 51,
          'netAmountMinor': 10049,
          'minimumAmountMinor': 10000,
          'feeRateBasisPoints': 50,
          'feePolicyVersion': 7,
          'settlementMode': 'MANUAL_FINANCE',
          'providerInvocation': invocation,
        },
      );
      addTearDown(h.close);
      expect(
        (await h.repository.fetchWithdrawalQuote(amount: 101)).feeAmount,
        .51,
      );
      for (final invalid in [true, null, 'false', 0]) {
        invocation = invalid;
        await expectLater(
          h.repository.fetchWithdrawalQuote(amount: 101),
          throwsA(isA<ApiException>()),
        );
      }
      expect(h.writes, isEmpty);
    },
  );
  test(
    'S07 exact decimal strings beat stale whole fields without narrowing',
    () async {
      var coin = precision();
      final h = await Harness.start(
        (r, _) => r.uri.path.endsWith('/ncoin') ? coin : overview(),
      );
      addTearDown(h.close);
      var wallet = await h.repository.fetchWalletSummary();
      expect(wallet.giftCoinText, '114.8');
      expect(wallet.coinPrecision!.frozen.text, '2');
      coin = precision('92233720368547758079');
      wallet = await h.repository.fetchWalletSummary();
      expect(wallet.giftCoinText, '9223372036854775807.9');
      expect(wallet.giftCoins!.coversWholeCoins(100), isTrue);
      expect(GiftCoinAmount.fromTenths('9').coversWholeCoins(1), isFalse);
      expect(GiftCoinAmount.fromTenths('10').coversWholeCoins(1), isTrue);
      for (final bad in <Map<String, Object?>>[
        {'currency': 'CASH_CNY'},
        {'scale': 10.0},
        {'scale': 100},
        {'precisionVersion': 'V2'},
        {'availableTenths': 1148},
        {'availableTenths': 1148.0},
        {'availableTenths': '1e3'},
        {'availableTenths': '-1'},
        {'availableTenths': '1.5'},
        {'availableTenths': ' 10'},
        {'availableTenths': null},
        {'frozenTenths': '-1'},
      ]) {
        coin = {...precision(), ...bad};
        await expectLater(
          h.repository.fetchWalletSummary(),
          throwsA(isA<ApiException>()),
        );
      }
      coin = {'integer': 100};
      await expectLater(
        h.repository.fetchWalletSummary(),
        throwsA(isA<ApiException>()),
      );
    },
  );

  test(
    'S07 ledger keeps old whole debit and fractional income units separate',
    () async {
      var invalid = <String, Object?>{};
      final h = await Harness.start(
        (r, _) => {
          'currency': 'GIFT_COIN',
          'coinPrecision': precision(),
          'current': 1,
          'pageSize': 100,
          'total': 3,
          'pages': 1,
          'list': [
            {
              'transactionId': 'income',
              'type': 'CREDIT',
              'currency': 'GIFT_COIN_TENTH',
              'amountMinor': 148,
              'amountTenths': '148',
              'scale': 10,
              'precisionVersion': 'GIFT_COIN_TENTHS_V1',
              'businessType': 'GIFT_INCOME',
              'createdAt': '2026-09-09T00:00:00Z',
              ...invalid,
            },
            {
              'transactionId': 'debit',
              'type': 'DEBIT',
              'currency': 'GIFT_COIN',
              'amountMinor': 100,
              'amountTenths': '1000',
              'scale': 10,
              'precisionVersion': 'GIFT_COIN_TENTHS_V1',
              'businessType': 'GIFT_SEND',
              'createdAt': '2026-09-09T00:00:00Z',
            },
            {
              'transactionId': 'carry',
              'type': 'CREDIT',
              'businessType': 'COIN_PRECISION_CARRY',
            },
          ],
        },
      );
      addTearDown(h.close);
      Future<CommercePage<LedgerEntry>> read(LedgerDirection direction) =>
          h.repository.fetchLedger(
            currency: LedgerCurrency.giftCoin,
            direction: direction,
            page: 1,
            pageSize: 20,
          );
      final income = await read(LedgerDirection.income);
      expect(income.items.single.coinAmount!.text, '14.8');
      expect(income.items.single.amount, isNull);
      final expense = await read(LedgerDirection.expense);
      expect(expense.items.single.coinAmount!.text, '100');
      for (final bad in [
        {'currency': 'CASH_CNY'},
        {'scale': 1},
        {'amountTenths': 148},
        {'precisionVersion': 'unknown'},
      ]) {
        invalid = bad;
        await expectLater(
          read(LedgerDirection.income),
          throwsA(isA<ApiException>()),
        );
      }
    },
  );

  test(
    'S08 missing or contradictory capability never grants new withdrawal',
    () async {
      var authority = overview('ORDINARY');
      final h = await Harness.start(
        (r, _) => r.uri.path.endsWith('/ncoin') ? precision() : authority,
      );
      addTearDown(h.close);
      for (final role in ['ORDINARY', 'ANCHOR', 'GUILD_CHAIR']) {
        authority = overview(role);
        final wallet = await h.repository.fetchWalletSummary();
        expect(wallet.incomeEligible, role != 'ORDINARY');
        expect(wallet.canWithdraw, role != 'ORDINARY');
      }
      authority = overview()
        ..remove('incomeRole')
        ..remove('incomeEligible')
        ..remove('canWithdraw');
      expect((await h.repository.fetchWalletSummary()).canWithdraw, isFalse);
      for (final invalid in [
        {'incomeRole': 'ADMIN'},
        {'incomeEligible': 1},
        {'incomeRole': 'ORDINARY'},
        {'canWithdraw': false},
      ]) {
        authority = {...overview(), ...invalid};
        await expectLater(
          h.repository.fetchWalletSummary(),
          throwsA(isA<ApiException>()),
        );
      }
      authority = overview();
      expect((await h.repository.fetchWalletSummary()).canWithdraw, isTrue);
      authority = overview(
        'ORDINARY',
      ); // Role lost after a valid cached UI read.
      await expectLater(
        h.repository.applyWithdrawal(
          amount: 101,
          confirmedQuote: quote,
          payoutAccountId: 'account-A',
        ),
        throwsA(
          isA<ApiException>().having(
            (e) => e.kind,
            'kind',
            ApiFailureKind.forbidden,
          ),
        ),
      );
      expect(h.writes, isEmpty);
      expect(h.repository.pendingWithdrawal, isNull);
    },
  );

  test(
    'S07 wallet A-B-A late read rejected and next GET never mixes accounts',
    () async {
      String? user = 'A';
      var generation = 1;
      final started = Completer<void>();
      final release = Completer<void>();
      var first = true;
      final auths = <String?>[];
      final h = await Harness.start(
        (r, _) async {
          auths.add(r.headers.value('Authorization'));
          if (first) {
            first = false;
            started.complete();
            await release.future;
          }
          return r.uri.path.endsWith('/ncoin') ? precision() : overview();
        },
        user: () => user,
        generation: () => generation,
      );
      addTearDown(h.close);
      final old = h.repository.fetchWalletSummary().then<Object>(
        (v) => v,
        onError: (Object e) => e,
      );
      await started.future;
      user = 'B';
      generation++;
      await h.repository.fetchWalletSummary();
      user = 'A';
      generation++;
      release.complete();
      expect(await old, isA<ApiException>());
      expect(auths, ['Bearer A', 'Bearer B', 'Bearer B']);
      expect((await h.repository.fetchWalletSummary()).giftCoinText, '114.8');
    },
  );

  test(
    'S08 lost income role keeps unknown key/body recovery but blocks next new write',
    () async {
      var role = 'ANCHOR';
      var postCount = 0;
      final h = await Harness.start((r, _) {
        if (r.uri.path.endsWith('/overview')) return overview(role);
        if (r.uri.path.endsWith('/accounts'))
          return {
            'list': [
              {
                'payoutAccountId': 'account-A',
                'accountType': 'BANK_REFERENCE',
                'accountMasked': '****8001',
                'holderNameMasked': 'A*',
                'status': 'VERIFIED',
                'selectable': true,
              },
            ],
            'total': 1,
            'selectedPayoutAccountId': 'account-A',
            'selectionRequired': false,
            'providerInvocation': false,
          };
        if (++postCount == 1) {
          r.response.statusCode = 500;
          return null;
        }
        return {
          'withdrawalId': 'original-receipt',
          'payoutAccountId': 'account-A',
          'amountMinor': 10100,
          'feeMinor': 51,
          'netAmountMinor': 10049,
          'status': 'SUBMITTED',
          'payoutStatus': 'MANUAL_REVIEW_PENDING',
          'providerInvocation': false,
          'submittedAt': '2026-09-09T00:00:00Z',
          'accountMasked': '****8001',
          'holderNameMasked': 'A*',
        };
      });
      addTearDown(h.close);
      Future<WithdrawalRecord> apply() => h.repository.applyWithdrawal(
        amount: 101,
        confirmedQuote: quote,
        payoutAccountId: 'account-A',
      );
      await expectLater(apply(), throwsA(isA<ApiException>()));
      expect(h.repository.pendingWithdrawal, isNotNull);
      role = 'ORDINARY';
      expect((await apply()).id, 'original-receipt');
      expect(h.writes, hasLength(2));
      expect(h.writes[0], h.writes[1]);
      expect(h.repository.pendingWithdrawal, isNull);
      await expectLater(apply(), throwsA(isA<ApiException>()));
      expect(h.writes, hasLength(2));
    },
  );
}

const quote = WithdrawalQuote(
  quotedAmount: 101,
  feeAmount: .51,
  receivedAmount: 100.49,
  feeRateBasisPoints: 50,
  feePolicyVersion: 7,
  feeRateText: '0.50%',
  minimumAmount: 100,
);

class Harness {
  Harness(this.server, this.repository, this.writes);
  final HttpServer server;
  final BackendCommerceRepository repository;
  final List<(String?, String)> writes;
  static Future<Harness> start(
    FutureOr<Object?> Function(HttpRequest, String) handler, {
    String? Function()? user,
    int Function()? generation,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final writes = <(String?, String)>[];
    final repository = BackendCommerceRepository(
      apiClient: ApiClient(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}/'),
        clientType: 'Android',
        clientInnerVersion: '6',
        authorizationProvider: () => 'Bearer ${user?.call() ?? 'A'}',
      ),
      currentUserId: user ?? () => 'A',
      identityGeneration: generation ?? () => 1,
    );
    server.listen((r) async {
      final body = await utf8.decoder.bind(r).join();
      if (r.method == 'POST')
        writes.add((r.headers.value('X-Request-Id'), body));
      final data = await handler(r, body);
      r.response.headers.contentType = ContentType.json;
      r.response.write(
        jsonEncode({
          'code': r.response.statusCode,
          'message': 'fixture',
          'data': data,
        }),
      );
      await r.response.close();
    });
    return Harness(server, repository, writes);
  }

  Future<void> close() => server.close(force: true);
}
