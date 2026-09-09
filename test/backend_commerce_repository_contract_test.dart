import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'contract_test_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/features/commerce/data/backend_commerce_repository.dart';
import 'package:voice_social_app/features/commerce/domain/commerce_models.dart';

void main() {
  test(
    'U01 quote requires integer policy and exact CEILING_FEN amounts',
    () async {
      var payload = <String, Object?>{
        'amountMinor': 10100,
        'feeMinor': 51,
        'netAmountMinor': 10049,
        'minimumAmountMinor': 10000,
        'feeRateBasisPoints': 50,
        'feePolicyVersion': 7,
        'rounding': 'CEILING_FEN',
        'settlementMode': 'FIRST_PARTY_REVIEW_PROVIDER_BLOCKED',
      };
      final harness = await _Harness.start((_) => _Response.ok(payload));
      addTearDown(harness.close);
      final quote = await harness.repository.fetchWithdrawalQuote(amount: 101);
      expect(quote.feePolicyVersion, 7);
      expect(quote.feeAmount, .51);
      expect(quote.receivedAmount, 100.49);
      final valid = Map<String, Object?>.of(payload);
      for (final bad in <Map<String, Object?>>[
        {'feePolicyVersion': null},
        {'feePolicyVersion': '7'},
        {'feePolicyVersion': 7.0},
        {'feePolicyVersion': -1},
        {'feeRateBasisPoints': 50.0},
        {'feeRateBasisPoints': 10000},
        {'feeMinor': 50, 'netAmountMinor': 10050},
        {'feeMinor': 52, 'netAmountMinor': 10048},
        {'amountMinor': 10000},
        {'rounding': 'FLOOR'},
      ]) {
        payload = {...valid, ...bad};
        await expectLater(
          harness.repository.fetchWithdrawalQuote(amount: 101),
          throwsA(isA<ApiException>()),
        );
      }
    },
  );

  test(
    'U01 unknown retry retains confirmed version and byte-identical payload without requote',
    () async {
      var writes = 0;
      final harness = await _Harness.start((request) {
        if (request.path.endsWith('/withdrawal/accounts'))
          return _Response.ok({
            'list': [
              {
                'payoutAccountId': 'u01-account',
                'accountType': 'BANK_REFERENCE',
                'accountMasked': '****8001',
                'holderNameMasked': 'U*',
                'status': 'VERIFIED',
                'selectable': true,
              },
            ],
            'total': 1,
            'selectedPayoutAccountId': 'u01-account',
            'selectionRequired': false,
            'providerInvocation': false,
          });
        writes++;
        if (writes == 1)
          return const _Response(
            statusCode: 500,
            code: 500,
            message: 'unknown',
            data: null,
          );
        return _Response.ok({
          'withdrawalId': 'u01-result',
          'payoutAccountId': 'u01-account',
          'amountMinor': 10100,
          'feeMinor': 51,
          'netAmountMinor': 10049,
          'status': 'SUBMITTED',
          'payoutStatus': 'MANUAL_REVIEW_PENDING',
          'providerInvocation': false,
          'submittedAt': '2026-09-09T10:00:00Z',
          'accountMasked': '****8001',
          'holderNameMasked': 'U*',
        });
      });
      addTearDown(harness.close);
      const quote = WithdrawalQuote(
        quotedAmount: 101,
        feeAmount: .51,
        receivedAmount: 100.49,
        feeRateBasisPoints: 50,
        feeRateText: '0.50%',
        minimumAmount: 100,
        feePolicyVersion: 7,
      );
      await expectLater(
        harness.repository.applyWithdrawal(
          amount: 101,
          confirmedQuote: quote,
          payoutAccountId: 'u01-account',
        ),
        throwsA(isA<ApiException>()),
      );
      final recovered = harness.repository.pendingWithdrawal!;
      await expectLater(
        harness.repository.applyWithdrawal(
          amount: 100,
          confirmedQuote: _confirmedQuote(100),
          payoutAccountId: 'u01-account',
        ),
        throwsA(isA<ApiException>()),
      );
      final result = await harness.repository.applyWithdrawal(
        amount: recovered.amount,
        confirmedQuote: recovered.quote,
        payoutAccountId: recovered.payoutAccountId,
      );
      expect(result.receivedAmount, 100.49);
      expect(harness.repository.pendingWithdrawal, isNull);
      final posts = harness.requests.where((r) => r.method == 'POST').toList();
      expect(posts, hasLength(2));
      expect(posts[0].requestId, posts[1].requestId);
      expect(posts[0].rawBody, posts[1].rawBody);
      expect(posts[0].body, {
        'amountMinor': 10100,
        'payoutAccountId': 'u01-account',
        'expectedFeePolicyVersion': 7,
        'expectedFeeMinor': 51,
        'expectedNetAmountMinor': 10049,
      });
      expect(
        harness.requests.where((r) => r.path.endsWith('/withdrawal/accounts')),
        hasLength(1),
      );
      expect(
        harness.requests.where((r) => r.path.endsWith('/fee-rate')),
        isEmpty,
      );
    },
  );
  test(
    'withdrawal invalid product amounts never make any HTTP request',
    () async {
      final harness = await _Harness.start(
        (_) => _Response.ok(<String, Object?>{}),
      );
      addTearDown(harness.close);
      for (final amount in [
        99.0,
        100.01,
        double.nan,
        double.infinity,
        1e308,
        90071992547410.0,
      ]) {
        for (final request in [
          () => harness.repository.fetchWithdrawalQuote(amount: amount),
          () => harness.repository.applyWithdrawal(
            amount: amount,
            confirmedQuote: _confirmedQuote(amount),
            payoutAccountId: 'account',
          ),
        ]) {
          await expectLater(
            request(),
            throwsA(
              isA<ApiException>().having(
                (e) => e.kind,
                'kind',
                ApiFailureKind.validation,
              ),
            ),
          );
        }
      }
      expect(harness.requests, isEmpty);
    },
  );

  test(
    'guild gift share stays cash income and retains its own label',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        return _Response.ok(<String, Object?>{
          'currency': 'CASH_CNY',
          'list': <Object?>[
            <String, Object?>{
              'transactionId': 'guild-share-001',
              'type': 'CREDIT',
              'amountMinor': 148,
              'businessType': 'GUILD_GIFT_INCOME',
              'businessId': 'gift-transfer-001',
              'counterpartyUserId': 2002,
              'description': '公会礼物分成',
              'createdAt': '2026-09-08T10:00:00Z',
              'currency': 'CASH_CNY',
            },
          ],
          'pageNum': 1,
          'pageSize': 100,
          'total': 1,
          'pages': 1,
        });
      });
      addTearDown(harness.close);
      final CommercePage<LedgerEntry> result = await harness.repository
          .fetchLedger(
            currency: LedgerCurrency.cashCny,
            direction: LedgerDirection.income,
            page: 1,
            pageSize: 20,
          );
      final LedgerEntry entry = result.items.single;
      expect(entry.kind, LedgerKind.giftIncome);
      expect(entry.title, '公会礼物分成');
      expect(entry.amount, 1.48);
      expect(entry.currency, LedgerCurrency.cashCny);
      expect(entry.rawSubtype, 'guild_gift_income');
    },
  );

  test(
    'wallet and ledger use M4 currency/page contract and minor units',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        return switch (request.path) {
          '/app-economy-api/ncoin' => _Response.ok(<String, Object?>{
            'integer': 321,
          }),
          '/app-mini-api/mini/v1/wallet/overview' =>
            _Response.ok(<String, Object?>{
              'balance': 12.5,
              'frozenBalance': 1.25,
              'totalEarnings': 88,
              'yesterdayEarnings': 3,
              'totalWithdraw': 20,
              'isRealName': 1,
              'defaultBankCard': <String, Object?>{},
              'agentEarnings': 5,
              'superAgentEarnings': 6,
            }),
          '/app-mini-api/mini/v1/wallet/account-details' => _Response.ok(
            <String, Object?>{
              'currency': request.query['currency'],
              'list': <Object?>[
                <String, Object?>{
                  'transactionId': '00000000-0000-0000-0000-000000009001',
                  'type': 'CREDIT',
                  'amountMinor': request.query['currency'] == 'CASH_CNY'
                      ? 6600
                      : 66,
                  'businessType': request.query['currency'] == 'CASH_CNY'
                      ? 'GIFT_INCOME'
                      : 'RECHARGE_CREDIT',
                  'businessId': 'gift-transfer-1',
                  'counterpartyUserId': 2002,
                  'description': '礼物收益',
                  'createdAt': '2026-08-21T10:00:00Z',
                  'currency': request.query['currency'],
                },
                <String, Object?>{
                  'transactionId': '00000000-0000-0000-0000-000000009002',
                  'type': 'DEBIT',
                  'amountMinor': 10,
                  'businessType': 'GIFT_SEND',
                  'description': '送出礼物',
                  'createdAt': '2026-08-21T09:00:00Z',
                  'currency': request.query['currency'],
                },
                <String, Object?>{
                  'transactionId': 'retired',
                  'type': 'CREDIT',
                  'amountMinor': 999,
                  'businessType': 'BLIND_BOX',
                },
                <String, Object?>{
                  'transactionId': 'retired-vip-purchase',
                  'type': 'DEBIT',
                  'amountMinor': 999,
                  'businessType': 'VIP_PURCHASE',
                },
              ],
              'pageNum': 1,
              'pageSize': 100,
              'total': 4,
              'pages': 1,
            },
          ),
          _ => _Response.ok(<String, Object?>{}),
        };
      });
      addTearDown(harness.close);

      final WalletSummary wallet = await harness.repository
          .fetchWalletSummary();
      expect(wallet.giftCoinBalance, 321);
      expect(wallet.cashBalance, 12.5);
      final CommercePage<LedgerEntry> income = await harness.repository
          .fetchLedger(
            currency: LedgerCurrency.giftCoin,
            direction: LedgerDirection.income,
            page: 1,
            pageSize: 10,
          );
      expect(income.items, hasLength(1));
      expect(income.items.single.id, '00000000-0000-0000-0000-000000009001');
      expect(income.items.single.kind, LedgerKind.recharge);
      expect(income.items.single.amount, 66);
      expect(income.items.single.relatedUserName, '2002');
      expect(income.pageSize, 10);
      expect(income.hasMore, isFalse);
      expect(harness.requests[2].query, <String, String>{
        'currency': 'GIFT_COIN',
        'pageNum': '1',
        'pageSize': '100',
      });
      final CommercePage<LedgerEntry> cashIncome = await harness.repository
          .fetchLedger(
            currency: LedgerCurrency.cashCny,
            direction: LedgerDirection.income,
            page: 1,
            pageSize: 20,
          );
      expect(cashIncome.items.single.kind, LedgerKind.giftIncome);
      expect(cashIncome.items.single.amount, 66);
      expect(harness.requests[3].query, <String, String>{
        'currency': 'CASH_CNY',
        'pageNum': '1',
        'pageSize': '100',
      });
    },
  );

  test(
    'ledger filters direction after exhausting authoritative pages',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        final int backendPage = int.parse(request.query['pageNum']!);
        return _Response.ok(<String, Object?>{
          'currency': 'GIFT_COIN',
          'list': List<Object?>.generate(
            backendPage == 1 ? 100 : 1,
            (int index) => <String, Object?>{
              'transactionId': backendPage == 1
                  ? 'ledger-1-$index'
                  : 'ledger-2',
              'type': backendPage == 1 ? 'CREDIT' : 'DEBIT',
              'amountMinor': backendPage == 1 ? 30 : 12,
              'businessType': backendPage == 1
                  ? 'RECHARGE_CREDIT'
                  : 'GIFT_SEND',
              'description': backendPage == 1 ? '充值' : '送礼',
              'createdAt': '2026-08-21T10:00:00Z',
              'currency': 'GIFT_COIN',
            },
          ),
          'pageNum': backendPage,
          'pageSize': 100,
          'total': 101,
          'pages': 2,
        });
      });
      addTearDown(harness.close);

      final CommercePage<LedgerEntry> expense = await harness.repository
          .fetchLedger(
            currency: LedgerCurrency.giftCoin,
            direction: LedgerDirection.expense,
            page: 1,
            pageSize: 20,
          );

      expect(expense.items, hasLength(1));
      expect(expense.items.single.id, 'ledger-2');
      expect(expense.items.single.amount, 12);
      expect(expense.total, 1);
      expect(expense.hasMore, isFalse);
      expect(
        harness.requests.map(
          (RequestRecord request) => request.query['pageNum'],
        ),
        <String?>['1', '2'],
      );
    },
  );

  test('ledger rejects an underfilled non-final authoritative page', () async {
    final _Harness harness = await _Harness.start((RequestRecord request) {
      return _Response.ok(<String, Object?>{
        'currency': 'GIFT_COIN',
        'list': <Object?>[
          <String, Object?>{
            'transactionId': 'ledger-short',
            'type': 'CREDIT',
            'amountMinor': 30,
            'businessType': 'RECHARGE_CREDIT',
            'description': '充值',
            'createdAt': '2026-08-21T10:00:00Z',
            'currency': 'GIFT_COIN',
          },
        ],
        'pageNum': 1,
        'pageSize': 100,
        'total': 101,
        'pages': 2,
      });
    });
    addTearDown(harness.close);

    await expectLater(
      harness.repository.fetchLedger(
        currency: LedgerCurrency.giftCoin,
        direction: LedgerDirection.income,
        page: 1,
        pageSize: 20,
      ),
      throwsA(
        isA<ApiException>()
            .having(
              (ApiException error) => error.kind,
              'kind',
              ApiFailureKind.protocol,
            )
            .having(
              (ApiException error) => error.message,
              'message',
              contains('记录数'),
            ),
      ),
    );
  });

  test('b709 commerce DTOs use endpoint currency invariants', () async {
    final _Harness harness = await _Harness.start((RequestRecord request) {
      return switch (request.path) {
        '/app-mini-api/mini/v1/wallet/account-details' => _Response.ok(
          <String, Object?>{
            'currency': 'GIFT_COIN',
            'list': <Object?>[
              <String, Object?>{
                'transactionId': 'ledger-b709',
                'type': 'CREDIT',
                'amountMinor': 12,
                'businessType': 'RECHARGE_CREDIT',
                'description': '充值',
                'createdAt': '2026-08-22T10:00:00Z',
              },
            ],
            'pageNum': 1,
            'pageSize': 100,
            'total': 1,
            'pages': 1,
          },
        ),
        '/app-economy-api/pay/getOrders' => _Response.ok(<String, Object?>{
          'list': <Object?>[
            <String, Object?>{
              'orderNo': 'order-b709',
              'amount': 1,
              'ncoin': 10,
              'payType': 'WECHAT',
              'status': 'PENDING',
              'createDate': '2026-08-22T10:00:00Z',
            },
          ],
          'current': 1,
          'pageSize': 20,
          'total': 1,
        }),
        '/app-api/refund/check' => _Response.ok(<String, Object?>{
          'orderNo': 'order-b709',
          'eligible': true,
          'reason': 'ELIGIBLE',
          'amountMinor': 100,
          'giftCoinAmount': 10,
          'providerStatus': 'VENDOR_BLOCKED',
        }),
        '/app-api/refund/result' => _Response.ok(<String, Object?>{
          'refundId': 'refund-b709',
          'orderNo': 'order-b709',
          'amountMinor': 100,
          'reason': '重复充值',
          'status': 'SUBMITTED',
          'resultMessage': '',
          'submittedAt': '2026-08-22T10:01:00Z',
          'providerStatus': 'VENDOR_BLOCKED',
          'completed': false,
        }),
        '/app-mini-api/mini/v1/withdrawal/fee-rate' =>
          _Response.ok(<String, Object?>{
            'amountMinor': 10000,
            'feeMinor': 100,
            'netAmountMinor': 9900,
            'feePolicyVersion': 0,
            'feeRateBasisPoints': 100,
            'minimumAmountMinor': 10000,
            'settlementMode': 'FIRST_PARTY_REVIEW_PROVIDER_BLOCKED',
          }),
        '/app-mini-api/mini/v1/withdrawal/records' => _Response.ok(
          <String, Object?>{
            'list': <Object?>[
              <String, Object?>{
                'withdrawalId': 'withdrawal-b709',
                'payoutAccountId': 'account-b709',
                'amountMinor': 100,
                'feeMinor': 1,
                'netAmountMinor': 99,
                'status': 'SETTLED',
                'submittedAt': '2026-08-22T10:02:00Z',
              },
            ],
            'current': 1,
            'pageSize': 20,
            'total': 1,
            'pages': 1,
          },
        ),
        _ => _Response.ok(<String, Object?>{}),
      };
    });
    addTearDown(harness.close);

    final CommercePage<LedgerEntry> ledger = await harness.repository
        .fetchLedger(
          currency: LedgerCurrency.giftCoin,
          direction: LedgerDirection.income,
          page: 1,
          pageSize: 20,
        );
    expect(ledger.items.single.currency, LedgerCurrency.giftCoin);

    final CommercePage<PaymentOrder> orders = await harness.repository
        .fetchOrders(page: 1, pageSize: 20);
    expect(orders.items.single.currency, LedgerCurrency.cashCny);
    expect(orders.hasMore, isFalse);

    final RefundEligibility eligibility = await harness.repository
        .checkRefundEligibility('order-b709');
    expect(eligibility.allowed, isTrue);
    final RefundApplication refund = await harness.repository.fetchRefundResult(
      'refund-b709',
      expectedOrderNo: 'order-b709',
    );
    expect(refund.currency, LedgerCurrency.cashCny);

    final WithdrawalQuote quote = await harness.repository.fetchWithdrawalQuote(
      amount: 100,
    );
    expect(quote.currency, LedgerCurrency.cashCny);
    final CommercePage<WithdrawalRecord> withdrawals = await harness.repository
        .fetchWithdrawalRecords(page: 1, pageSize: 20);
    expect(withdrawals.items.single.currency, LedgerCurrency.cashCny);
  });

  test(
    'order list and detail parse authoritative status and pageSize',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        return switch (request.path) {
          '/app-economy-api/pay/getOrders' => _Response.ok(<String, Object?>{
            'list': <Object?>[
              <String, Object?>{
                'orderNo': 'order-1',
                'amount': 6,
                'ncoin': 60,
                'payType': 'WECHAT',
                'status': 'PENDING',
                'createDate': '2026-08-21T10:00:00Z',
                'currency': 'CASH_CNY',
              },
            ],
            'current': 1,
            'pageSize': 20,
            'total': 1,
            'pages': 1,
          }),
          '/app-economy-api/pay/isOrderSuccess' =>
            _Response.ok(<String, Object?>{
              'orderNo': 'order-1',
              'amount': 6,
              'ncoin': 60,
              'payType': 'WECHAT',
              'currency': 'CASH_CNY',
              'createDate': '2026-08-21T10:00:00Z',
              'bool': false,
              'status': 'FAILED',
            }),
          _ => _Response.ok(<String, Object?>{}),
        };
      });
      addTearDown(harness.close);

      final CommercePage<PaymentOrder> page = await harness.repository
          .fetchOrders(page: 1, pageSize: 20);
      expect(page.items.single.status, PaymentOrderStatus.pending);
      final PaymentOrder result = await harness.repository.queryOrderStatus(
        page.items.single,
      );
      expect(result.status, PaymentOrderStatus.failed);
      expect(harness.requests[0].method, 'POST');
      expect(harness.requests[0].body, <String, Object?>{
        'pageNum': 1,
        'pageSize': 20,
      });
      expect(harness.requests[1].query, <String, String>{'orderNo': 'order-1'});
    },
  );

  test(
    'order detail requires a strict bool that agrees with the authoritative status',
    () async {
      Map<String, Object?> payload({
        Object? boolValue = false,
        bool includeBool = true,
        required String status,
      }) => <String, Object?>{
        'orderNo': 'order-bool-authority',
        'amount': 6,
        'ncoin': 60,
        'payType': 'WECHAT',
        'currency': 'CASH_CNY',
        'createDate': '2026-08-21T10:00:00Z',
        if (includeBool) 'bool': boolValue,
        'status': status,
      };

      final List<Map<String, Object?>> malformed = <Map<String, Object?>>[
        payload(boolValue: true, status: 'FAILED'),
        payload(boolValue: false, status: 'SUCCEEDED'),
        payload(boolValue: true, status: 'CONFIRMING'),
        payload(includeBool: false, status: 'FAILED'),
        payload(boolValue: 'false', status: 'FAILED'),
      ];
      final PaymentOrder order = PaymentOrder(
        orderNo: 'order-bool-authority',
        amount: 6,
        giftCoinAmount: 60,
        channelName: 'WECHAT',
        createdAt: DateTime(2026),
        status: PaymentOrderStatus.pending,
      );

      for (final Map<String, Object?> responseData in malformed) {
        final _Harness harness = await _Harness.start(
          (RequestRecord request) => _Response.ok(responseData),
        );
        try {
          await expectLater(
            harness.repository.queryOrderStatus(order),
            throwsA(
              isA<ApiException>().having(
                (ApiException error) => error.kind,
                'kind',
                ApiFailureKind.protocol,
              ),
            ),
          );
        } finally {
          await harness.close();
        }
      }
    },
  );

  test(
    'refund check recovers the existing authoritative application UUID',
    () async {
      const String refundId = '00000000-0000-4000-8000-000000005001';
      final _Harness harness = await _Harness.start((RequestRecord request) {
        expect(request.path, '/app-api/refund/check');
        return _Response.ok(<String, Object?>{
          'orderNo': 'order-existing-refund',
          'eligible': false,
          'reason': 'REFUND_ALREADY_EXISTS',
          'amountMinor': 600,
          'giftCoinAmount': 60,
          'providerStatus': 'VENDOR_BLOCKED',
          'existingApplicationId': refundId,
        });
      });
      addTearDown(harness.close);

      final RefundEligibility eligibility = await harness.repository
          .checkRefundEligibility('order-existing-refund');

      expect(eligibility.allowed, isFalse);
      expect(eligibility.existingApplicationId, refundId);
    },
  );

  test(
    'refund check rejects an already-existing result without a canonical UUID',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        expect(request.path, '/app-api/refund/check');
        return _Response.ok(<String, Object?>{
          'orderNo': 'order-missing-refund-id',
          'eligible': false,
          'reason': 'REFUND_ALREADY_EXISTS',
          'amountMinor': 600,
          'giftCoinAmount': 60,
          'providerStatus': 'VENDOR_BLOCKED',
        });
      });
      addTearDown(harness.close);

      await expectLater(
        harness.repository.checkRefundEligibility('order-missing-refund-id'),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.protocol,
          ),
        ),
      );
    },
  );

  // REMOVED_BY_PRODUCT Q15-06: order-scoped refund uses exact check, submit, result, repeat contracts.

  // REMOVED_BY_PRODUCT Q15-06: concurrent duplicate refund submission sends one authoritative write.

  test(
    'refund history reads the complete account-scoped authoritative page',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        expect(request.path, '/app-api/refund/history');
        expect(request.query, <String, String>{
          'pageNum': '1',
          'pageSize': '100',
        });
        final List<Object?> records = <Object?>[
          <String, Object?>{
            'refundId': 'refund-history-2',
            'orderNo': 'order-history-2',
            'amountMinor': 200,
            'reason': '重复充值',
            'status': 'REJECTED',
            'resultMessage': '资料不足',
            'submittedAt': '2026-08-22T10:02:00Z',
            'providerStatus': 'REJECTED',
            'completed': false,
          },
          <String, Object?>{
            'refundId': 'refund-history-1',
            'orderNo': 'order-history-1',
            'amountMinor': 100,
            'reason': '误操作',
            'status': 'SUBMITTED',
            'resultMessage': '',
            'submittedAt': '2026-08-22T10:01:00Z',
            'providerStatus': 'VENDOR_BLOCKED',
            'completed': false,
          },
        ];
        return _Response.ok(<String, Object?>{
          'records': records,
          'list': records,
          'current': 1,
          'pageSize': 100,
          'total': 2,
          'pages': 1,
          'hasMore': false,
          'providerStatus': 'VENDOR_BLOCKED',
          'providerInvocation': false,
        });
      });
      addTearDown(harness.close);
      final List<RefundApplication> applications = await harness.repository
          .fetchRefundApplications('authenticated-account');
      expect(applications.map((RefundApplication item) => item.id), <String>[
        'refund-history-2',
        'refund-history-1',
      ]);
      expect(applications.first.account, 'order-history-2');
      expect(applications.first.status, RefundStatus.rejected);
      expect(harness.requests, hasLength(1));
    },
  );

  test(
    'Alipay refund provider observations map to authoritative business states',
    () async {
      final List<(String, String, bool, RefundStatus)> fixtures =
          <(String, String, bool, RefundStatus)>[
            ('SUBMITTED', 'READY', false, RefundStatus.reviewing),
            ('APPROVED', 'APPROVED', false, RefundStatus.approved),
            ('APPROVED', 'PROCESSING', false, RefundStatus.approved),
            ('APPROVED', 'PENDING', false, RefundStatus.approved),
            ('APPROVED', 'UNKNOWN', false, RefundStatus.approved),
            ('COMPLETED', 'REFUNDED', true, RefundStatus.completed),
            ('REJECTED', 'REJECTED', false, RefundStatus.rejected),
            ('CANCELLED', 'CANCELLED', false, RefundStatus.unavailable),
          ];
      int fixtureIndex = 0;
      final _Harness harness = await _Harness.start((RequestRecord request) {
        final (String status, String providerStatus, bool completed, _) =
            fixtures[fixtureIndex++];
        return _Response.ok(<String, Object?>{
          'refundId': 'refund-alipay-fixture',
          'orderNo': 'order-alipay-fixture',
          'amountMinor': 600,
          'reason': '重复充值',
          'status': status,
          'resultMessage': status == 'REJECTED' ? '资料不足' : '',
          'submittedAt': '2026-08-22T10:00:00Z',
          'providerStatus': providerStatus,
          'completed': completed,
          'currency': 'CASH_CNY',
        });
      });
      addTearDown(harness.close);

      for (final (String _, String _, bool _, RefundStatus expected)
          in fixtures) {
        final RefundApplication result = await harness.repository
            .fetchRefundResult('refund-alipay-fixture');
        expect(result.status, expected);
        expect(result.completed, expected == RefundStatus.completed);
      }
      expect(fixtureIndex, fixtures.length);
    },
  );

  test(
    'frozen F2 keeps first-party refund result and withdrawal quote reads reachable',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        return switch (request.path) {
          '/app-api/refund/result' => _Response.ok(<String, Object?>{
            'refundId': 'refund-capability',
            'orderNo': 'order-capability',
            'amountMinor': 100,
            'reason': '重复充值',
            'status': 'SUBMITTED',
            'resultMessage': '',
            'submittedAt': '2026-08-22T10:01:00Z',
            'providerStatus': 'VENDOR_BLOCKED',
            'completed': false,
          }),
          '/app-mini-api/mini/v1/withdrawal/fee-rate' =>
            _Response.ok(<String, Object?>{
              'amountMinor': 10000,
              'feeMinor': 200,
              'netAmountMinor': 9800,
              'feePolicyVersion': 0,
              'feeRateBasisPoints': 200,
              'minimumAmountMinor': 10000,
              'settlementMode': 'FIRST_PARTY_REVIEW_PROVIDER_BLOCKED',
            }),
          _ => _Response.ok(<String, Object?>{}),
        };
      });
      addTearDown(harness.close);

      expect(harness.repository.supportsRefundHistory, isTrue);
      expect(harness.repository.supportsWithdrawalApplication, isFalse);

      final RefundApplication result = await harness.repository
          .fetchRefundResult('refund-capability');
      expect(result.id, 'refund-capability');
      final WithdrawalQuote quote = await harness.repository
          .fetchWithdrawalQuote(amount: 100);
      expect(quote.receivedAmount, 98);
      expect(
        harness.requests.map((RequestRecord request) => request.path),
        <String>[
          '/app-api/refund/result',
          '/app-mini-api/mini/v1/withdrawal/fee-rate',
        ],
      );
    },
  );

  test(
    'withdrawal quote and records use minor units while apply fails closed',
    () async {
      const String withdrawalId = '00000000-0000-0000-0000-000000006001';
      final _Harness harness = await _Harness.start((RequestRecord request) {
        return switch (request.path) {
          '/app-mini-api/mini/v1/withdrawal/fee-rate' =>
            _Response.ok(<String, Object?>{
              'amountMinor': 10100,
              'feeMinor': 202,
              'netAmountMinor': 9898,
              'feePolicyVersion': 0,
              'feeRateBasisPoints': 200,
              'minimumAmountMinor': 10000,
              'currency': 'CASH_CNY',
              'availableMinor': 50000,
              'sufficient': true,
              'settlementMode': 'FIRST_PARTY_REVIEW_PROVIDER_BLOCKED',
            }),
          '/app-mini-api/mini/v1/withdrawal/records' => _Response.ok(
            <String, Object?>{
              'list': <Object?>[
                <String, Object?>{
                  'withdrawalId': withdrawalId,
                  'payoutAccountId': '00000000-0000-0000-0000-000000007001',
                  'amountMinor': 10000,
                  'feeMinor': 200,
                  'netAmountMinor': 9800,
                  'status': 'SETTLED',
                  'accountMasked': '****1234',
                  'holderNameMasked': '晚*',
                  'resultMessage': '',
                  'submittedAt': '2026-08-21T10:00:00Z',
                  'currency': 'CASH_CNY',
                  'settledAt': '2026-08-21T11:00:00Z',
                },
                <String, Object?>{
                  'withdrawalId': '00000000-0000-0000-0000-000000006002',
                  'payoutAccountId': '00000000-0000-0000-0000-000000007002',
                  'amountMinor': 2000,
                  'feeMinor': 40,
                  'netAmountMinor': 1960,
                  'status': 'REJECTED',
                  'resultMessage': '资料不完整',
                  'submittedAt': '2026-08-20T10:00:00Z',
                  'currency': 'CASH_CNY',
                },
              ],
              'current': 1,
              'pageSize': 100,
              'total': 2,
              'pages': 1,
            },
          ),
          _ => _Response.ok(<String, Object?>{}),
        };
      });
      addTearDown(harness.close);

      await expectLater(
        harness.repository.fetchWithdrawalQuote(amount: 101.345),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.validation,
          ),
        ),
      );
      expect(harness.requests, isEmpty);
      final WithdrawalQuote quote = await harness.repository
          .fetchWithdrawalQuote(amount: 101);
      expect(quote.feeRate, 0.02);
      expect(quote.feeRateText, '2.00%');
      expect(quote.minimumAmount, 100);
      expect(quote.quotedAmount, 101);
      expect(quote.feeAmount, 2.02);
      expect(quote.receivedAmount, 98.98);
      expect(quote.feeFor(101), 2.02);
      expect(quote.receivedFor(101), 98.98);
      expect(harness.requests.single.query, <String, String>{
        'amountMinor': '10100',
      });
      final CommercePage<WithdrawalRecord> settled = await harness.repository
          .fetchWithdrawalRecords(
            status: WithdrawalStatus.succeeded,
            page: 1,
            pageSize: 20,
          );
      expect(settled.items, hasLength(1));
      expect(settled.items.single.amount, 100);
      expect(settled.items.single.fee, 2);
      expect(settled.items.single.receivedAmount, 98);
      expect(
        settled.items.single.payoutAccountId,
        '00000000-0000-0000-0000-000000007001',
      );
      expect(settled.items.single.maskedCard, '****1234');
      expect(settled.items.single.holderNameMasked, '晚*');
      expect(harness.requests[1].query, <String, String>{
        'pageNum': '1',
        'pageSize': '100',
      });
      final WithdrawalRecord detail = await harness.repository
          .fetchWithdrawalRecord(withdrawalId);
      expect(detail.status, WithdrawalStatus.succeeded);
      expect(
        harness.requests[2].path,
        '/app-mini-api/mini/v1/withdrawal/records',
      );
      expect(harness.requests[2].query, <String, String>{
        'pageNum': '1',
        'pageSize': '100',
      });

      final int requestCount = harness.requests.length;
      await expectLater(
        harness.repository.applyWithdrawal(
          amount: 100,
          confirmedQuote: _confirmedQuote(100),
        ),
        throwsA(
          isA<ApiException>()
              .having(
                (ApiException error) => error.kind,
                'kind',
                ApiFailureKind.configuration,
              )
              .having(
                (ApiException error) => error.message,
                'message',
                contains('收款账户'),
              ),
        ),
      );
      expect(harness.requests, hasLength(requestCount));
    },
  );

  test(
    'withdrawal status filtering rejects an empty page that still has more',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        final int backendPage = int.parse(request.query['pageNum']!);
        if (backendPage > 2) {
          return const _Response(
            statusCode: 500,
            code: 500,
            message: 'unexpected extra request',
            data: null,
          );
        }
        return _Response.ok(<String, Object?>{
          'list': backendPage == 2
              ? <Object?>[]
              : List<Object?>.generate(
                  100,
                  (int index) => <String, Object?>{
                    'withdrawalId': 'withdrawal-$backendPage-$index',
                    'payoutAccountId': 'account-$backendPage-$index',
                    'amountMinor': 10000,
                    'feeMinor': 200,
                    'netAmountMinor': 9800,
                    'status': 'SETTLED',
                    'submittedAt': '2026-08-21T10:00:00Z',
                    'currency': 'CASH_CNY',
                  },
                ),
          'current': backendPage,
          'pageSize': 100,
          'total': 300,
          'pages': 3,
        });
      });
      addTearDown(harness.close);

      await expectLater(
        harness.repository.fetchWithdrawalRecords(
          status: WithdrawalStatus.succeeded,
          page: 1,
          pageSize: 20,
        ),
        throwsA(
          isA<ApiException>()
              .having(
                (ApiException error) => error.kind,
                'kind',
                ApiFailureKind.protocol,
              )
              .having(
                (ApiException error) => error.message,
                'message',
                contains('空'),
              ),
        ),
      );
      expect(
        harness.requests.map(
          (RequestRecord request) => request.query['pageNum'],
        ),
        <String?>['1', '2'],
      );
    },
  );

  test(
    'F3-B2 payout accounts expose only masked selectable authority and apply uses it',
    () async {
      const String selectedId = '00000000-0000-0000-0000-00000000a001';
      const String pendingId = '00000000-0000-0000-0000-00000000a002';
      int applyCalls = 0;
      final _Harness harness = await _Harness.start((RequestRecord request) {
        return switch (request.path) {
          '/app-mini-api/mini/v1/withdrawal/accounts' => _Response.ok(
            <String, Object?>{
              'list': <Object?>[
                <String, Object?>{
                  'payoutAccountId': selectedId,
                  'accountId': selectedId,
                  'accountType': 'MANUAL_SETTLEMENT',
                  'accountMasked': '****8002',
                  'holderNameMasked': 'F*2',
                  'status': 'VERIFIED',
                  'selectable': true,
                },
                <String, Object?>{
                  'payoutAccountId': pendingId,
                  'accountType': 'BANK_REFERENCE',
                  'accountMasked': '****8003',
                  'holderNameMasked': 'F*2',
                  'status': 'PENDING',
                  'selectable': false,
                },
              ],
              'current': 1,
              'pageSize': 2,
              'total': 2,
              'pages': 1,
              'selectedPayoutAccountId': selectedId,
              'defaultPayoutAccountId': selectedId,
              'selectionRequired': false,
              'providerInvocation': false,
            },
          ),
          '/app-mini-api/mini/v1/withdrawal/apply' => () {
            applyCalls += 1;
            expect(request.method, 'POST');
            expect(request.body, <String, Object?>{
              'amountMinor': 10000,
              'payoutAccountId': selectedId,
              'expectedFeePolicyVersion': 0,
              'expectedFeeMinor': 100,
              'expectedNetAmountMinor': 9900,
            });
            return _Response.ok(<String, Object?>{
              'withdrawalId': '00000000-0000-0000-0000-00000000a010',
              'payoutAccountId': selectedId,
              'amountMinor': 10000,
              'feeMinor': 100,
              'netAmountMinor': 9900,
              'status': 'SUBMITTED',
              'payoutStatus': 'MANUAL_REVIEW_PENDING',
              'providerInvocation': false,
              'submittedAt': '2026-08-24T10:00:00Z',
              'accountMasked': '****8002',
              'holderNameMasked': 'F*2',
            });
          }(),
          _ => _Response.ok(<String, Object?>{}),
        };
      });
      addTearDown(harness.close);

      final PayoutAccountSelection selection = await harness.repository
          .fetchPayoutAccounts();
      expect(selection.accounts, hasLength(2));
      expect(selection.selectedPayoutAccountId, selectedId);
      expect(selection.accounts.first.selectable, isTrue);
      expect(selection.accounts.last.selectable, isFalse);
      expect(selection.accounts.first.accountMasked, '****8002');
      expect(selection.accounts.first.holderNameMasked, 'F*2');

      final WithdrawalRecord record = await harness.repository.applyWithdrawal(
        amount: 100,
        confirmedQuote: _confirmedQuote(100),
        payoutAccountId: selectedId,
      );
      expect(record.payoutAccountId, selectedId);
      expect(record.amount, 100);
      expect(record.receivedAmount, 99);
      expect(applyCalls, 1);
    },
  );

  test(
    'F3-B2 withdrawal fails closed when selected payout account is stale',
    () async {
      const String staleId = '00000000-0000-0000-0000-00000000a101';
      int applyCalls = 0;
      int accountReads = 0;
      final _Harness harness = await _Harness.start((RequestRecord request) {
        if (request.path.endsWith('/withdrawal/accounts')) {
          accountReads += 1;
          final String id = accountReads == 1
              ? staleId
              : '00000000-0000-0000-0000-00000000a102';
          return _Response.ok(<String, Object?>{
            'list': <Object?>[
              <String, Object?>{
                'payoutAccountId': id,
                'accountType': 'BANK_REFERENCE',
                'accountMasked': '****8102',
                'holderNameMasked': 'F*2',
                'status': 'VERIFIED',
                'selectable': true,
              },
            ],
            'total': 1,
            'selectedPayoutAccountId': id,
            'selectionRequired': false,
            'providerInvocation': false,
          });
        }
        if (request.path.endsWith('/withdrawal/apply')) {
          applyCalls += 1;
        }
        return _Response.ok(<String, Object?>{});
      });
      addTearDown(harness.close);

      await harness.repository.fetchPayoutAccounts();
      await expectLater(
        harness.repository.applyWithdrawal(
          amount: 100,
          confirmedQuote: _confirmedQuote(100),
          payoutAccountId: staleId,
        ),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            anyOf(ApiFailureKind.conflict, ApiFailureKind.validation),
          ),
        ),
      );
      expect(applyCalls, 0);
    },
  );

  test(
    'F3-B2 payout accounts require an explicit no-provider marker',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        expect(request.path, '/app-mini-api/mini/v1/withdrawal/accounts');
        return _Response.ok(<String, Object?>{
          'list': <Object?>[],
          'total': 0,
          'selectedPayoutAccountId': '',
          'defaultPayoutAccountId': '',
          'selectionRequired': true,
        });
      });
      addTearDown(harness.close);

      await expectLater(
        harness.repository.fetchPayoutAccounts(),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.protocol,
          ),
        ),
      );
    },
  );

  test('F3-B2 withdrawal quote requires the blocked settlement mode', () async {
    final _Harness harness = await _Harness.start((RequestRecord request) {
      expect(request.path, '/app-mini-api/mini/v1/withdrawal/fee-rate');
      return _Response.ok(<String, Object?>{
        'amountMinor': 10000,
        'feeMinor': 100,
        'netAmountMinor': 9900,
        'feePolicyVersion': 0,
        'feeRateBasisPoints': 100,
        'minimumAmountMinor': 10000,
      });
    });
    addTearDown(harness.close);

    await expectLater(
      harness.repository.fetchWithdrawalQuote(amount: 100),
      throwsA(
        isA<ApiException>().having(
          (ApiException error) => error.kind,
          'kind',
          ApiFailureKind.protocol,
        ),
      ),
    );
  });

  test(
    'F3-B2 withdrawal apply rejects incomplete provider and record authority',
    () async {
      const String accountId = '00000000-0000-0000-0000-00000000a151';
      final _Harness harness = await _Harness.start((RequestRecord request) {
        if (request.path.endsWith('/withdrawal/accounts')) {
          return _Response.ok(<String, Object?>{
            'list': <Object?>[
              <String, Object?>{
                'payoutAccountId': accountId,
                'accountType': 'BANK_REFERENCE',
                'accountMasked': '****8151',
                'holderNameMasked': 'F*1',
                'status': 'VERIFIED',
                'selectable': true,
              },
            ],
            'total': 1,
            'selectedPayoutAccountId': accountId,
            'selectionRequired': false,
            'providerInvocation': false,
          });
        }
        expect(request.path, '/app-mini-api/mini/v1/withdrawal/apply');
        return _Response.ok(<String, Object?>{
          'withdrawalId': '00000000-0000-0000-0000-00000000a152',
          'amountMinor': 10000,
          'feeMinor': 100,
          'netAmountMinor': 9900,
          'status': 'SUBMITTED',
        });
      });
      addTearDown(harness.close);

      await expectLater(
        harness.repository.applyWithdrawal(
          amount: 100,
          confirmedQuote: _confirmedQuote(100),
          payoutAccountId: accountId,
        ),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.protocol,
          ),
        ),
      );
    },
  );

  test(
    'F3-B2 concurrent withdrawal submissions share one write and request id',
    () async {
      const String accountId = '00000000-0000-0000-0000-00000000a201';
      final List<String> requestIds = <String>[];
      int applyCalls = 0;
      final _Harness harness = await _Harness.start((RequestRecord request) {
        if (request.path.endsWith('/withdrawal/accounts')) {
          return _Response.ok(<String, Object?>{
            'list': <Object?>[
              <String, Object?>{
                'payoutAccountId': accountId,
                'accountType': 'BANK_REFERENCE',
                'accountMasked': '****8202',
                'holderNameMasked': 'F*2',
                'status': 'VERIFIED',
                'selectable': true,
              },
            ],
            'total': 1,
            'selectedPayoutAccountId': accountId,
            'selectionRequired': false,
            'providerInvocation': false,
          });
        }
        expect(request.path, '/app-mini-api/mini/v1/withdrawal/apply');
        applyCalls += 1;
        requestIds.add(request.requestId);
        return _Response.ok(<String, Object?>{
          'withdrawalId': '00000000-0000-0000-0000-00000000a210',
          'payoutAccountId': accountId,
          'amountMinor': 10000,
          'feeMinor': 100,
          'netAmountMinor': 9900,
          'status': 'SUBMITTED',
          'payoutStatus': 'MANUAL_REVIEW_PENDING',
          'providerInvocation': false,
          'submittedAt': '2026-08-24T10:00:00Z',
          'accountMasked': '****8202',
          'holderNameMasked': 'F*2',
        });
      });
      addTearDown(harness.close);

      final List<WithdrawalRecord> records =
          await Future.wait(<Future<WithdrawalRecord>>[
            harness.repository.applyWithdrawal(
              amount: 100,
              confirmedQuote: _confirmedQuote(100),
              payoutAccountId: accountId,
            ),
            harness.repository.applyWithdrawal(
              amount: 100,
              confirmedQuote: _confirmedQuote(100),
              payoutAccountId: accountId,
            ),
          ]);
      expect(records, hasLength(2));
      expect(records[0].id, records[1].id);
      expect(applyCalls, 1);
      expect(requestIds, hasLength(1));
    },
  );

  test(
    'F3-B2 pending withdrawal idempotency conflicts retain the request id',
    () async {
      const String accountId = '00000000-0000-0000-0000-00000000a251';
      final List<String> requestIds = <String>[];
      int applyCalls = 0;
      final _Harness harness = await _Harness.start((RequestRecord request) {
        if (request.path.endsWith('/withdrawal/accounts')) {
          return _Response.ok(<String, Object?>{
            'list': <Object?>[
              <String, Object?>{
                'payoutAccountId': accountId,
                'accountType': 'BANK_REFERENCE',
                'accountMasked': '****8252',
                'holderNameMasked': 'F*2',
                'status': 'VERIFIED',
                'selectable': true,
              },
            ],
            'total': 1,
            'selectedPayoutAccountId': accountId,
            'selectionRequired': false,
            'providerInvocation': false,
          });
        }
        expect(request.path, '/app-mini-api/mini/v1/withdrawal/apply');
        requestIds.add(request.requestId);
        applyCalls += 1;
        if (applyCalls == 1) {
          return const _Response(
            statusCode: 409,
            code: 40901,
            message: 'pending',
            data: null,
          );
        }
        return _Response.ok(<String, Object?>{
          'withdrawalId': '00000000-0000-0000-0000-00000000a260',
          'payoutAccountId': accountId,
          'amountMinor': 10000,
          'feeMinor': 100,
          'netAmountMinor': 9900,
          'status': 'SUBMITTED',
          'payoutStatus': 'MANUAL_REVIEW_PENDING',
          'providerInvocation': false,
          'submittedAt': '2026-08-24T10:00:00Z',
          'accountMasked': '****8252',
          'holderNameMasked': 'F*2',
        });
      });
      addTearDown(harness.close);

      await expectLater(
        harness.repository.applyWithdrawal(
          amount: 100,
          confirmedQuote: _confirmedQuote(100),
          payoutAccountId: accountId,
        ),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.code,
            'code',
            40901,
          ),
        ),
      );
      final WithdrawalRecord recovered = await harness.repository
          .applyWithdrawal(
            amount: 100,
            confirmedQuote: _confirmedQuote(100),
            payoutAccountId: accountId,
          );

      expect(recovered.payoutAccountId, accountId);
      expect(requestIds, hasLength(2));
      expect(requestIds[0], requestIds[1]);
    },
  );

  for (final (int, ApiFailureKind) failure in <(int, ApiFailureKind)>[
    (403, ApiFailureKind.forbidden),
    (409, ApiFailureKind.conflict),
    (422, ApiFailureKind.validation),
    (500, ApiFailureKind.server),
  ]) {
    test(
      'F3-B2 withdrawal apply preserves ${failure.$1} and does not fake success',
      () async {
        const String accountId = '00000000-0000-0000-0000-00000000a301';
        final _Harness harness = await _Harness.start((RequestRecord request) {
          if (request.path.endsWith('/withdrawal/accounts')) {
            return _Response.ok(<String, Object?>{
              'list': <Object?>[
                <String, Object?>{
                  'payoutAccountId': accountId,
                  'accountType': 'BANK_REFERENCE',
                  'accountMasked': '****8302',
                  'holderNameMasked': 'F*2',
                  'status': 'VERIFIED',
                  'selectable': true,
                },
              ],
              'total': 1,
              'selectedPayoutAccountId': accountId,
              'selectionRequired': false,
              'providerInvocation': false,
            });
          }
          expect(request.path, '/app-mini-api/mini/v1/withdrawal/apply');
          return _Response(
            statusCode: failure.$1,
            code: failure.$1,
            message: failure.$1 == 409
                ? '北京时间今日已提交提现申请，请次日重新申请'
                : 'withdrawal-${failure.$1}',
            data: null,
          );
        });
        addTearDown(harness.close);

        await expectLater(
          harness.repository.applyWithdrawal(
            amount: 100,
            confirmedQuote: _confirmedQuote(100),
            payoutAccountId: accountId,
          ),
          throwsA(
            isA<ApiException>()
                .having((ApiException error) => error.kind, 'kind', failure.$2)
                .having(
                  (ApiException error) => error.httpStatus,
                  'status',
                  failure.$1,
                )
                .having(
                  (ApiException error) => error.message,
                  'message',
                  failure.$1 == 409
                      ? '北京时间今日已提交提现申请，请次日重新申请'
                      : 'withdrawal-${failure.$1}',
                ),
          ),
        );
        expect(
          harness.requests.where(
            (RequestRecord request) =>
                request.path.endsWith('/withdrawal/apply'),
          ),
          hasLength(1),
        );
      },
    );
  }

  test(
    'F3-B2 withdrawal apply fails closed while offline before any write',
    () async {
      final _Harness harness = await _Harness.start(
        (RequestRecord request) => _Response.ok(<String, Object?>{}),
      );
      await harness.close();
      await expectLater(
        harness.repository.applyWithdrawal(
          amount: 100,
          confirmedQuote: _confirmedQuote(100),
          payoutAccountId: '00000000-0000-0000-0000-00000000a302',
        ),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.network,
          ),
        ),
      );
    },
  );

  test(
    'withdrawal status filtering rejects a page number that makes no progress',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        final int backendPage = int.parse(request.query['pageNum']!);
        if (backendPage > 2) {
          return const _Response(
            statusCode: 500,
            code: 500,
            message: 'unexpected extra request',
            data: null,
          );
        }
        return _Response.ok(<String, Object?>{
          'list': List<Object?>.generate(
            100,
            (int index) => <String, Object?>{
              'withdrawalId': 'withdrawal-$backendPage-$index',
              'payoutAccountId': 'account-$backendPage-$index',
              'amountMinor': 10000,
              'feeMinor': 200,
              'netAmountMinor': 9800,
              'status': 'SETTLED',
              'submittedAt': '2026-08-21T10:00:00Z',
              'currency': 'CASH_CNY',
            },
          ),
          'current': 1,
          'pageSize': 100,
          'total': 200,
          'pages': 2,
        });
      });
      addTearDown(harness.close);

      await expectLater(
        harness.repository.fetchWithdrawalRecords(
          status: WithdrawalStatus.succeeded,
          page: 1,
          pageSize: 20,
        ),
        throwsA(
          isA<ApiException>()
              .having(
                (ApiException error) => error.kind,
                'kind',
                ApiFailureKind.protocol,
              )
              .having(
                (ApiException error) => error.message,
                'message',
                contains('进展'),
              ),
        ),
      );
      expect(
        harness.requests.map(
          (RequestRecord request) => request.query['pageNum'],
        ),
        <String?>['1', '2'],
      );
    },
  );

  test(
    'withdrawal detail rejects a page number that makes no progress',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        final int backendPage = int.parse(request.query['pageNum']!);
        if (backendPage > 2) {
          return const _Response(
            statusCode: 500,
            code: 500,
            message: 'unexpected extra request',
            data: null,
          );
        }
        return _Response.ok(<String, Object?>{
          'list': List<Object?>.generate(
            100,
            (int index) => <String, Object?>{
              'withdrawalId': 'other-withdrawal-$backendPage-$index',
              'payoutAccountId': 'account-$backendPage-$index',
              'amountMinor': 10000,
              'feeMinor': 200,
              'netAmountMinor': 9800,
              'status': 'SETTLED',
              'submittedAt': '2026-08-21T10:00:00Z',
              'currency': 'CASH_CNY',
            },
          ),
          'current': 1,
          'pageSize': 100,
          'total': 200,
          'pages': 2,
        });
      });
      addTearDown(harness.close);

      await expectLater(
        harness.repository.fetchWithdrawalRecord('missing-withdrawal'),
        throwsA(
          isA<ApiException>()
              .having(
                (ApiException error) => error.kind,
                'kind',
                ApiFailureKind.protocol,
              )
              .having(
                (ApiException error) => error.message,
                'message',
                contains('进展'),
              ),
        ),
      );
      expect(
        harness.requests.map(
          (RequestRecord request) => request.query['pageNum'],
        ),
        <String?>['1', '2'],
      );
    },
  );

  test(
    'withdrawal filtering stops at the maximum backend page limit',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        final int backendPage = int.parse(request.query['pageNum']!);
        if (backendPage > 100) {
          return const _Response(
            statusCode: 500,
            code: 500,
            message: 'unexpected request past page limit',
            data: null,
          );
        }
        return _Response.ok(<String, Object?>{
          'list': List<Object?>.generate(
            100,
            (int index) => <String, Object?>{
              'withdrawalId': 'withdrawal-$backendPage-$index',
              'payoutAccountId': 'account-$backendPage-$index',
              'amountMinor': 10000,
              'feeMinor': 200,
              'netAmountMinor': 9800,
              'status': 'SETTLED',
              'submittedAt': '2026-08-21T10:00:00Z',
              'currency': 'CASH_CNY',
            },
          ),
          'current': backendPage,
          'pageSize': 100,
          'total': 10100,
          'pages': 101,
        });
      });
      addTearDown(harness.close);

      await expectLater(
        harness.repository.fetchWithdrawalRecords(
          status: WithdrawalStatus.succeeded,
          page: 1,
          pageSize: 20,
        ),
        throwsA(
          isA<ApiException>()
              .having(
                (ApiException error) => error.kind,
                'kind',
                ApiFailureKind.protocol,
              )
              .having(
                (ApiException error) => error.message,
                'message',
                contains('上限'),
              ),
        ),
      );
      expect(harness.requests, hasLength(100));
      expect(harness.requests.last.query['pageNum'], '100');
    },
  );

  test(
    'withdrawal status filtering preserves normal multi-page pagination',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        final int backendPage = int.parse(request.query['pageNum']!);
        return _Response.ok(<String, Object?>{
          'list': List<Object?>.generate(
            100,
            (int index) => <String, Object?>{
              'withdrawalId': backendPage == 2 && index == 99
                  ? 'withdrawal-2'
                  : 'withdrawal-$backendPage-$index',
              'payoutAccountId': 'account-$backendPage-$index',
              'amountMinor': backendPage == 2 && index == 99 ? 200 : 100,
              'feeMinor': backendPage == 2 && index == 99 ? 10 : 0,
              'netAmountMinor': backendPage == 2 && index == 99 ? 190 : 100,
              'status': backendPage == 2 && index == 99
                  ? 'SETTLED'
                  : 'REJECTED',
              'submittedAt': '2026-08-21T10:00:00Z',
              'currency': 'CASH_CNY',
            },
          ),
          'current': backendPage,
          'pageSize': 100,
          'total': 200,
          'pages': 2,
        });
      });
      addTearDown(harness.close);

      final CommercePage<WithdrawalRecord> result = await harness.repository
          .fetchWithdrawalRecords(
            status: WithdrawalStatus.succeeded,
            page: 1,
            pageSize: 20,
          );

      expect(result.items, hasLength(1));
      expect(result.items.single.id, 'withdrawal-2');
      expect(result.items.single.amount, 2);
      expect(result.total, 1);
      expect(result.hasMore, isFalse);
      expect(
        harness.requests.map(
          (RequestRecord request) => request.query['pageNum'],
        ),
        <String?>['1', '2'],
      );
    },
  );

  test(
    'empty commerce pages stay explicit and do not synthesize records',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        return _Response.ok(<String, Object?>{
          'list': <Object?>[],
          'current': 1,
          'pageSize': 20,
          'total': 0,
          'pages': 0,
        });
      });
      addTearDown(harness.close);
      final CommercePage<PaymentOrder> orders = await harness.repository
          .fetchOrders(page: 1, pageSize: 20);
      expect(orders.items, isEmpty);
      expect(orders.total, 0);
      expect(orders.hasMore, isFalse);
    },
  );

  test(
    'wallet rejects missing numeric authority but accepts legal zero values',
    () async {
      final _Harness missing = await _Harness.start((RequestRecord request) {
        return switch (request.path) {
          '/app-economy-api/ncoin' => _Response.ok(<String, Object?>{
            'integer': 0,
          }),
          '/app-mini-api/mini/v1/wallet/overview' =>
            _Response.ok(<String, Object?>{
              'frozenBalance': 0,
              'totalEarnings': 0,
              'yesterdayEarnings': 0,
              'totalWithdraw': 0,
              'isRealName': 0,
              'agentEarnings': 0,
              'superAgentEarnings': 0,
            }),
          _ => _Response.ok(<String, Object?>{}),
        };
      });
      addTearDown(missing.close);

      await expectLater(
        missing.repository.fetchWalletSummary(),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.protocol,
          ),
        ),
      );

      final _Harness zero = await _Harness.start((RequestRecord request) {
        return switch (request.path) {
          '/app-economy-api/ncoin' => _Response.ok(<String, Object?>{
            'integer': 0,
          }),
          '/app-mini-api/mini/v1/wallet/overview' =>
            _Response.ok(<String, Object?>{
              'balance': 0,
              'frozenBalance': 0,
              'totalEarnings': 0,
              'yesterdayEarnings': 0,
              'totalWithdraw': 0,
              'isRealName': 0,
              'agentEarnings': 0,
              'superAgentEarnings': 0,
            }),
          _ => _Response.ok(<String, Object?>{}),
        };
      });
      addTearDown(zero.close);
      final WalletSummary wallet = await zero.repository.fetchWalletSummary();
      expect(wallet.giftCoinBalance, 0);
      expect(wallet.cashBalance, 0);
      expect(wallet.frozenBalance, 0);
    },
  );

  test(
    'wallet accepts explicit unavailable commission authority and masked payout summary',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        return switch (request.path) {
          '/app-economy-api/ncoin' => _Response.ok(<String, Object?>{
            'integer': 0,
          }),
          '/app-mini-api/mini/v1/wallet/overview' => _Response.ok(
            <String, Object?>{
              'balance': 0,
              'frozenBalance': 0,
              'totalEarnings': 0,
              'yesterdayEarnings': 0,
              'totalWithdraw': 0,
              'isRealName': 1,
              'agentEarnings': null,
              'agentEarningsStatus': 'UNAVAILABLE',
              'superAgentEarnings': null,
              'superAgentEarningsStatus': 'UNAVAILABLE',
              'defaultBankCard': <String, Object?>{
                'payoutAccountId': 'account-authoritative-1',
                'accountId': 'account-authoritative-1',
                'accountType': 'BANK_CARD',
                'accountMasked': '**** 8812',
                'holderNameMasked': '晚*',
              },
            },
          ),
          _ => _Response.ok(<String, Object?>{}),
        };
      });
      addTearDown(harness.close);

      final WalletSummary wallet = await harness.repository
          .fetchWalletSummary();
      expect(wallet.agentEarnings, isNull);
      expect(wallet.superAgentEarnings, isNull);
      expect(wallet.bankCard?.id, 'account-authoritative-1');
      expect(wallet.bankCard?.accountType, 'BANK_CARD');
      expect(wallet.bankCard?.maskedAccount, '**** 8812');
      expect(wallet.bankCard?.holderNameMasked, '晚*');
    },
  );

  test(
    'ledger rejects missing currency, ID, amount, and time authority',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        return _Response.ok(<String, Object?>{
          'list': <Object?>[
            <String, Object?>{
              'type': 'CREDIT',
              'amountMinor': 1,
              'businessType': 'RECHARGE_CREDIT',
              'createdAt': '2026-08-22T10:00:00Z',
            },
          ],
          'pageNum': 1,
          'pageSize': 100,
          'total': 1,
          'pages': 1,
        });
      });
      addTearDown(harness.close);

      await expectLater(
        harness.repository.fetchLedger(
          currency: LedgerCurrency.giftCoin,
          direction: LedgerDirection.income,
          page: 1,
          pageSize: 20,
        ),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.protocol,
          ),
        ),
      );
    },
  );

  test('order rejects unknown status and incomplete page metadata', () async {
    final _Harness statusHarness = await _Harness.start(
      (RequestRecord request) => _Response.ok(<String, Object?>{
        'list': <Object?>[
          <String, Object?>{
            'orderNo': 'order-unknown',
            'amount': 1,
            'ncoin': 1,
            'payType': 'WECHAT',
            'status': 'NOT_A_STATUS',
            'createDate': '2026-08-22T10:00:00Z',
          },
        ],
        'current': 1,
        'pageSize': 20,
        'total': 1,
        'pages': 1,
      }),
    );
    addTearDown(statusHarness.close);
    await expectLater(
      statusHarness.repository.fetchOrders(page: 1, pageSize: 20),
      throwsA(isA<ApiException>()),
    );

    final _Harness pageHarness = await _Harness.start(
      (RequestRecord request) =>
          _Response.ok(<String, Object?>{'list': const <Object?>[]}),
    );
    addTearDown(pageHarness.close);
    await expectLater(
      pageHarness.repository.fetchOrders(page: 1, pageSize: 20),
      throwsA(isA<ApiException>()),
    );
  });

  test(
    'all commerce page reads reject returned page or page size drift',
    () async {
      final _Harness orderHarness = await _Harness.start(
        (RequestRecord request) => _Response.ok(<String, Object?>{
          'list': const <Object?>[],
          'current': 2,
          'pageSize': 20,
          'total': 0,
        }),
      );
      addTearDown(orderHarness.close);
      await expectLater(
        orderHarness.repository.fetchOrders(page: 1, pageSize: 20),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.protocol,
          ),
        ),
      );

      final _Harness ledgerHarness = await _Harness.start(
        (RequestRecord request) => _Response.ok(<String, Object?>{
          'currency': 'GIFT_COIN',
          'list': const <Object?>[],
          'pageNum': 1,
          'pageSize': 99,
          'total': 0,
          'pages': 0,
        }),
      );
      addTearDown(ledgerHarness.close);
      await expectLater(
        ledgerHarness.repository.fetchLedger(
          currency: LedgerCurrency.giftCoin,
          direction: LedgerDirection.income,
          page: 1,
          pageSize: 20,
        ),
        throwsA(isA<ApiException>()),
      );

      final _Harness withdrawalHarness = await _Harness.start(
        (RequestRecord request) => _Response.ok(<String, Object?>{
          'list': const <Object?>[],
          'current': 1,
          'pageSize': 99,
          'total': 0,
          'pages': 0,
        }),
      );
      addTearDown(withdrawalHarness.close);
      await expectLater(
        withdrawalHarness.repository.fetchWithdrawalRecords(
          page: 1,
          pageSize: 20,
        ),
        throwsA(isA<ApiException>()),
      );
    },
  );

  test(
    'ledger pagination rejects page jumps, backtracking, inconsistent metadata, and empty more pages',
    () async {
      Future<void> expectLedgerFailure({
        required FutureOr<_Response> Function(int page) response,
      }) async {
        final _Harness harness = await _Harness.start(
          (RequestRecord request) =>
              response(int.parse(request.query['pageNum'] ?? '1')),
        );
        addTearDown(harness.close);
        await expectLater(
          harness.repository.fetchLedger(
            currency: LedgerCurrency.giftCoin,
            direction: LedgerDirection.income,
            page: 1,
            pageSize: 20,
          ),
          throwsA(
            isA<ApiException>().having(
              (ApiException error) => error.kind,
              'kind',
              ApiFailureKind.protocol,
            ),
          ),
        );
      }

      await expectLedgerFailure(
        response: (int page) => _Response.ok(<String, Object?>{
          'currency': 'GIFT_COIN',
          'list': <Object?>[
            <String, Object?>{
              'transactionId': 'ledger-jump',
              'type': 'CREDIT',
              'amountMinor': 1,
              'businessType': 'RECHARGE_CREDIT',
              'createdAt': '2026-08-22T10:00:00Z',
            },
          ],
          'pageNum': page + 1,
          'pageSize': 100,
          'total': 1,
          'pages': 1,
        }),
      );

      await expectLedgerFailure(
        response: (int page) => _Response.ok(<String, Object?>{
          'currency': 'GIFT_COIN',
          'list': <Object?>[
            <String, Object?>{
              'transactionId': 'ledger-backtrack',
              'type': 'CREDIT',
              'amountMinor': 1,
              'businessType': 'RECHARGE_CREDIT',
              'createdAt': '2026-08-22T10:00:00Z',
            },
          ],
          'pageNum': page == 1 ? 1 : 1,
          'pageSize': 100,
          'total': 101,
          'pages': 2,
        }),
      );

      await expectLedgerFailure(
        response: (int page) => _Response.ok(<String, Object?>{
          'currency': 'GIFT_COIN',
          'list': <Object?>[
            <String, Object?>{
              'transactionId': 'ledger-inconsistent',
              'type': 'CREDIT',
              'amountMinor': 1,
              'businessType': 'RECHARGE_CREDIT',
              'createdAt': '2026-08-22T10:00:00Z',
            },
          ],
          'pageNum': 1,
          'pageSize': 100,
          'total': 101,
          'pages': 1,
        }),
      );

      await expectLedgerFailure(
        response: (int page) => _Response.ok(<String, Object?>{
          'currency': 'GIFT_COIN',
          'list': const <Object?>[],
          'pageNum': 1,
          'pageSize': 100,
          'total': 101,
          'pages': 2,
        }),
      );
    },
  );

  test(
    'withdrawal pagination rejects page jumps, backtracking, metadata drift, and empty more pages',
    () async {
      Future<void> expectWithdrawalFailure({
        required FutureOr<_Response> Function(int page) response,
      }) async {
        final _Harness harness = await _Harness.start(
          (RequestRecord request) =>
              response(int.parse(request.query['pageNum'] ?? '1')),
        );
        addTearDown(harness.close);
        await expectLater(
          harness.repository.fetchWithdrawalRecords(page: 1, pageSize: 20),
          throwsA(
            isA<ApiException>().having(
              (ApiException error) => error.kind,
              'kind',
              ApiFailureKind.protocol,
            ),
          ),
        );
      }

      await expectWithdrawalFailure(
        response: (int page) => _Response.ok(<String, Object?>{
          'list': const <Object?>[],
          'current': page + 1,
          'pageSize': 20,
          'total': 0,
          'pages': 0,
        }),
      );
      await expectWithdrawalFailure(
        response: (int page) => _Response.ok(<String, Object?>{
          'list': <Object?>[
            <String, Object?>{
              'withdrawalId': 'withdrawal-backtrack',
              'payoutAccountId': 'account-backtrack',
              'amountMinor': 100,
              'feeMinor': 1,
              'netAmountMinor': 99,
              'status': 'SETTLED',
              'submittedAt': '2026-08-22T10:00:00Z',
            },
          ],
          'current': 1,
          'pageSize': 100,
          'total': 101,
          'pages': 2,
        }),
      );
      await expectWithdrawalFailure(
        response: (int page) => _Response.ok(<String, Object?>{
          'list': const <Object?>[],
          'current': 1,
          'pageSize': 100,
          'total': 101,
          'pages': 1,
        }),
      );
      await expectWithdrawalFailure(
        response: (int page) => _Response.ok(<String, Object?>{
          'list': const <Object?>[],
          'current': 1,
          'pageSize': 100,
          'total': 101,
          'pages': 2,
        }),
      );
    },
  );

  test(
    'commerce list and page aliases must agree when multiple aliases are present',
    () async {
      Map<String, Object?> order({String id = 'order-alias'}) =>
          <String, Object?>{
            'orderNo': id,
            'amount': 1,
            'ncoin': 10,
            'payType': 'WECHAT',
            'status': 'PENDING',
            'createDate': '2026-08-22T10:00:00Z',
          };

      final List<Map<String, Object?>> malformed = <Map<String, Object?>>[
        <String, Object?>{
          'list': <Object?>[order(id: 'order-list')],
          'items': <Object?>[order(id: 'order-items')],
          'current': 1,
          'pageSize': 1,
          'total': 1,
        },
        <String, Object?>{
          'list': <Object?>[order()],
          'pageNum': 1,
          'current': 2,
          'pageSize': 1,
          'total': 1,
        },
        <String, Object?>{
          'list': <Object?>[order()],
          'current': 1,
          'pageSize': 1,
          'size': 2,
          'total': 1,
        },
        <String, Object?>{
          'list': <Object?>[order()],
          'current': 1,
          'pageSize': 1,
          'pages': 1,
          'totalPages': 2,
          'total': 1,
        },
      ];

      for (final Map<String, Object?> payload in malformed) {
        final _Harness harness = await _Harness.start(
          (RequestRecord request) => _Response.ok(payload),
        );
        try {
          await expectLater(
            harness.repository.fetchOrders(page: 1, pageSize: 1),
            throwsA(
              isA<ApiException>().having(
                (ApiException error) => error.kind,
                'kind',
                ApiFailureKind.protocol,
              ),
            ),
          );
        } finally {
          await harness.close();
        }
      }
    },
  );

  test(
    'multi-page ledger, order, and withdrawal results reject duplicate IDs',
    () async {
      final _Harness ledgerHarness = await _Harness.start((
        RequestRecord request,
      ) {
        final int page = int.parse(request.query['pageNum']!);
        return _Response.ok(<String, Object?>{
          'currency': 'GIFT_COIN',
          'list': List<Object?>.generate(100, (int index) {
            return <String, Object?>{
              'transactionId': index == 0
                  ? 'duplicate-ledger-id'
                  : 'ledger-$page-$index',
              'type': 'CREDIT',
              'amountMinor': 10,
              'businessType': 'RECHARGE_CREDIT',
              'createdAt': '2026-08-22T10:00:00Z',
            };
          }),
          'pageNum': page,
          'pageSize': 100,
          'total': 200,
          'pages': 2,
        });
      });
      addTearDown(ledgerHarness.close);
      await expectLater(
        ledgerHarness.repository.fetchLedger(
          currency: LedgerCurrency.giftCoin,
          direction: LedgerDirection.income,
          page: 1,
          pageSize: 20,
        ),
        throwsA(isA<ApiException>()),
      );

      final _Harness orderHarness = await _Harness.start((
        RequestRecord request,
      ) {
        final int page =
            (request.body! as Map<String, Object?>)['pageNum']! as int;
        return _Response.ok(<String, Object?>{
          'list': <Object?>[
            <String, Object?>{
              'orderNo': 'duplicate-order-id',
              'amount': 1,
              'ncoin': 10,
              'payType': 'WECHAT',
              'status': 'PENDING',
              'createDate': '2026-08-22T10:00:00Z',
            },
          ],
          'current': page,
          'pageSize': 1,
          'total': 2,
          'pages': 2,
        });
      });
      addTearDown(orderHarness.close);
      await expectLater(
        orderHarness.repository.fetchOrders(page: 1, pageSize: 1),
        throwsA(isA<ApiException>()),
      );

      final _Harness withdrawalHarness = await _Harness.start((
        RequestRecord request,
      ) {
        final int page = int.parse(request.query['pageNum']!);
        return _Response.ok(<String, Object?>{
          'list': List<Object?>.generate(100, (int index) {
            return <String, Object?>{
              'withdrawalId': index == 0
                  ? 'duplicate-withdrawal-id'
                  : 'withdrawal-$page-$index',
              'payoutAccountId': 'account-$page-$index',
              'amountMinor': 100,
              'feeMinor': 1,
              'netAmountMinor': 99,
              'status': 'SETTLED',
              'submittedAt': '2026-08-22T10:00:00Z',
            };
          }),
          'current': page,
          'pageSize': 100,
          'total': 200,
          'pages': 2,
        });
      });
      addTearDown(withdrawalHarness.close);
      await expectLater(
        withdrawalHarness.repository.fetchWithdrawalRecords(
          status: WithdrawalStatus.succeeded,
          page: 1,
          pageSize: 20,
        ),
        throwsA(isA<ApiException>()),
      );
    },
  );

  // REMOVED_BY_PRODUCT Q15-06: refund submit retries an ambiguous response with one bounded stable request ID.

  // REMOVED_BY_PRODUCT Q15-06: refund submit retains 40901/40902 and rotates after definitive 40903.

  // REMOVED_BY_PRODUCT Q15-06: refund retry keeps one request ID across an ambiguous response and prevents duplicate economic writes.

  // REMOVED_BY_PRODUCT Q15-06: refund retry reconciles a submitted state before applying the rejected gate.

  // REMOVED_BY_PRODUCT Q15-06: refund retry intent is refund-scoped when expected order is optional.

  test(
    'refund history reads reject mismatched refund IDs and selected orders',
    () async {
      const String refundId = 'refund-identity';
      const String orderNo = 'order-identity';

      Map<String, Object?> payload({
        required String responseRefundId,
        required String responseOrderNo,
        required String status,
      }) => <String, Object?>{
        'refundId': responseRefundId,
        'orderNo': responseOrderNo,
        'amountMinor': 100,
        'reason': '资料不足',
        'status': status,
        'resultMessage': status == 'REJECTED' ? '资料不足' : '',
        'submittedAt': '2026-08-22T10:00:00Z',
        'providerStatus': status == 'REJECTED' ? 'REJECTED' : 'SUBMITTED',
        'completed': status == 'COMPLETED',
        'currency': 'CASH_CNY',
      };

      Future<void> expectResultMismatch(Map<String, Object?> response) async {
        final _Harness harness = await _Harness.start(
          (RequestRecord request) => _Response.ok(response),
        );
        try {
          await expectLater(
            harness.repository.fetchRefundResult(
              refundId,
              expectedOrderNo: orderNo,
            ),
            throwsA(
              isA<ApiException>().having(
                (ApiException error) => error.kind,
                'kind',
                ApiFailureKind.protocol,
              ),
            ),
          );
        } finally {
          await harness.close();
        }
      }

      await expectResultMismatch(
        payload(
          responseRefundId: 'refund-other',
          responseOrderNo: orderNo,
          status: 'SUBMITTED',
        ),
      );
      await expectResultMismatch(
        payload(
          responseRefundId: refundId,
          responseOrderNo: 'order-other',
          status: 'SUBMITTED',
        ),
      );

      // REMOVED_BY_PRODUCT Q15-06: retry mismatch positives; read checks above remain.
    },
  );

  test('unknown order status cannot become success or confirming', () async {
    final _Harness harness = await _Harness.start(
      (RequestRecord request) => _Response.ok(<String, Object?>{
        'orderNo': 'order-1',
        'amount': 1,
        'ncoin': 1,
        'payType': 'WECHAT',
        'currency': 'CASH_CNY',
        'createDate': '2026-08-21T10:00:00Z',
        'bool': true,
      }),
    );
    addTearDown(harness.close);
    final PaymentOrder order = PaymentOrder(
      orderNo: 'order-1',
      amount: 1,
      giftCoinAmount: 1,
      channelName: 'WECHAT',
      createdAt: DateTime(2026),
      status: PaymentOrderStatus.pending,
    );
    await expectLater(
      harness.repository.queryOrderStatus(order),
      throwsA(isA<ApiException>()),
    );
  });

  test(
    'refund rejects missing server amount, status, currency, or time',
    () async {
      final _Harness harness = await _Harness.start(
        (RequestRecord request) => _Response.ok(<String, Object?>{
          'refundId': 'refund-1',
          'orderNo': 'order-1',
          'amountMinor': 100,
        }),
      );
      addTearDown(harness.close);
      await expectLater(
        harness.repository.fetchRefundResult('refund-1'),
        throwsA(isA<ApiException>()),
      );
    },
  );

  test(
    'refund fails closed on vendor-status and terminal-state contradictions',
    () async {
      final _Harness eligibilityHarness = await _Harness.start(
        (RequestRecord request) => _Response.ok(<String, Object?>{
          'orderNo': 'order-authority',
          'eligible': false,
          'reason': 'ELIGIBLE',
          'amountMinor': 100,
          'giftCoinAmount': 10,
          'providerStatus': 'READY',
        }),
      );
      try {
        await expectLater(
          eligibilityHarness.repository.checkRefundEligibility(
            'order-authority',
          ),
          throwsA(
            isA<ApiException>().having(
              (ApiException error) => error.kind,
              'kind',
              ApiFailureKind.protocol,
            ),
          ),
        );
      } finally {
        await eligibilityHarness.close();
      }

      final _Harness resultHarness = await _Harness.start(
        (RequestRecord request) => _Response.ok(<String, Object?>{
          'refundId': 'refund-authority',
          'orderNo': 'order-authority',
          'amountMinor': 100,
          'reason': '重复充值',
          'status': 'SUBMITTED',
          'resultMessage': '',
          'submittedAt': '2026-08-22T10:00:00Z',
          'providerStatus': 'VENDOR_BLOCKED',
          'completed': true,
        }),
      );
      try {
        await expectLater(
          resultHarness.repository.fetchRefundResult('refund-authority'),
          throwsA(
            isA<ApiException>().having(
              (ApiException error) => error.kind,
              'kind',
              ApiFailureKind.protocol,
            ),
          ),
        );
      } finally {
        await resultHarness.close();
      }

      final List<(String, String, bool)> contradictoryStates =
          <(String, String, bool)>[
            ('APPROVED', 'READY', false),
            ('APPROVED', 'VENDOR_BLOCKED', false),
            ('COMPLETED', 'PENDING', true),
            ('REJECTED', 'APPROVED', false),
            ('CANCELLED', 'REFUNDED', false),
          ];
      for (final (String status, String providerStatus, bool completed)
          in contradictoryStates) {
        final _Harness harness = await _Harness.start(
          (RequestRecord request) => _Response.ok(<String, Object?>{
            'refundId': 'refund-contradiction',
            'orderNo': 'order-authority',
            'amountMinor': 100,
            'reason': '重复充值',
            'status': status,
            'resultMessage': status == 'REJECTED' ? '资料不足' : '',
            'submittedAt': '2026-08-22T10:00:00Z',
            'providerStatus': providerStatus,
            'completed': completed,
          }),
        );
        await expectLater(
          harness.repository.fetchRefundResult('refund-contradiction'),
          throwsA(
            isA<ApiException>().having(
              (ApiException error) => error.kind,
              'kind',
              ApiFailureKind.protocol,
            ),
          ),
        );
        await harness.close();
      }
    },
  );

  test(
    'withdrawal quote and records reject missing authority fields',
    () async {
      final _Harness quoteHarness = await _Harness.start(
        (RequestRecord request) => _Response.ok(<String, Object?>{
          'feeMinor': 1,
          'netAmountMinor': 99,
          'feePolicyVersion': 0,
          'feeRateBasisPoints': 100,
          'minimumAmountMinor': 10000,
        }),
      );
      addTearDown(quoteHarness.close);
      await expectLater(
        quoteHarness.repository.fetchWithdrawalQuote(amount: 100),
        throwsA(
          isA<ApiException>().having(
            (e) => e.kind,
            'kind',
            ApiFailureKind.protocol,
          ),
        ),
      );

      final _Harness recordHarness = await _Harness.start(
        (RequestRecord request) => _Response.ok(<String, Object?>{
          'list': <Object?>[
            <String, Object?>{
              'amountMinor': 100,
              'feeMinor': 1,
              'netAmountMinor': 99,
              'status': 'SETTLED',
            },
          ],
          'current': 1,
          'pageSize': 100,
          'total': 1,
          'pages': 1,
        }),
      );
      addTearDown(recordHarness.close);
      await expectLater(
        recordHarness.repository.fetchWithdrawalRecords(page: 1, pageSize: 20),
        throwsA(isA<ApiException>()),
      );
    },
  );

  test(
    'withdrawal records reject a missing payout-account authority',
    () async {
      final _Harness harness = await _Harness.start(
        (RequestRecord request) => _Response.ok(<String, Object?>{
          'list': <Object?>[
            <String, Object?>{
              'withdrawalId': 'withdrawal-without-account',
              'amountMinor': 100,
              'feeMinor': 1,
              'netAmountMinor': 99,
              'status': 'SETTLED',
              'accountMasked': '****1234',
              'holderNameMasked': '晚*',
              'resultMessage': '',
              'submittedAt': '2026-08-21T10:00:00Z',
            },
          ],
          'current': 1,
          'pageSize': 100,
          'total': 1,
          'pages': 1,
        }),
      );
      addTearDown(harness.close);

      await expectLater(
        harness.repository.fetchWithdrawalRecords(page: 1, pageSize: 100),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.protocol,
          ),
        ),
      );
    },
  );

  for (final (int, ApiFailureKind) failure in <(int, ApiFailureKind)>[
    (400, ApiFailureKind.validation),
    (403, ApiFailureKind.forbidden),
    (409, ApiFailureKind.conflict),
    (422, ApiFailureKind.validation),
    (500, ApiFailureKind.server),
  ]) {
    test('commerce preserves ${failure.$1} error envelope', () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        return _Response(
          statusCode: failure.$1,
          code: failure.$1,
          message: 'commerce-${failure.$1}',
          data: null,
        );
      });
      addTearDown(harness.close);
      await expectLater(
        harness.repository.fetchOrders(page: 1, pageSize: 20),
        throwsA(
          isA<ApiException>()
              .having((ApiException error) => error.kind, 'kind', failure.$2)
              .having(
                (ApiException error) => error.httpStatus,
                'status',
                failure.$1,
              ),
        ),
      );
    });
  }
}

class _Harness {
  _Harness._(this.server, this.requests)
    : repository = BackendCommerceRepository(
        apiClient: ApiClient(
          baseUri: Uri.parse(
            'http://${server.address.address}:${server.port}/',
          ),
          clientType: 'Android',
          clientInnerVersion: '6',
          authorizationProvider: () => 'Bearer contract-test',
        ),
        routes: const BackendRouteCatalog(),
      );

  final HttpServer server;
  final List<RequestRecord> requests;
  final BackendCommerceRepository repository;

  static Future<_Harness> start(
    FutureOr<_Response> Function(RequestRecord) handler,
  ) async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final List<RequestRecord> requests = <RequestRecord>[];
    final _Harness harness = _Harness._(server, requests);
    server.listen((HttpRequest request) async {
      final String rawBody = await utf8.decoder.bind(request).join();
      final Object? decodedBody = rawBody.trim().isEmpty
          ? null
          : jsonDecode(rawBody);
      final RequestRecord record = RequestRecord(
        rawBody: rawBody,
        method: request.method,
        path: request.uri.path,
        query: request.uri.queryParameters,
        authorization: captureContractAuthorization(request),
        requestId: request.headers.value('X-Request-Id') ?? '',
        body: decodedBody is Map
            ? Map<String, Object?>.from(decodedBody)
            : decodedBody,
      );
      requests.add(record);
      final _Response response = await handler(record);
      request.response.statusCode = response.statusCode;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(<String, Object?>{
          'code': response.code,
          'message': response.message,
          'data': response.data,
        }),
      );
      await request.response.close();
    });
    return harness;
  }

  Future<void> close() => server.close(force: true);
}

class RequestRecord {
  const RequestRecord({
    this.rawBody = '',
    required this.method,
    required this.path,
    required this.query,
    required this.authorization,
    required this.requestId,
    required this.body,
  });

  final String method;
  final String rawBody;
  final String path;
  final Map<String, String> query;
  final String authorization;
  final String requestId;
  final Object? body;
}

class _Response {
  const _Response({
    required this.statusCode,
    required this.code,
    required this.message,
    required this.data,
  });

  const _Response.ok(Object? data)
    : statusCode = 200,
      code = 200,
      message = 'OK',
      data = data;

  final int statusCode;
  final int code;
  final String message;
  final Object? data;
}

WithdrawalQuote _confirmedQuote(double amount) {
  final minor = WithdrawalAmountPolicy.isValid(amount)
      ? (amount * 100).round()
      : 0;
  final fee = WithdrawalQuote.ceilingFeeMinor(minor, 100);
  return WithdrawalQuote(
    quotedAmount: amount,
    feeAmount: fee / 100,
    receivedAmount: (minor - fee) / 100,
    feeRateBasisPoints: 100,
    feePolicyVersion: 0,
    feeRateText: '1%',
    minimumAmount: 100,
  );
}
