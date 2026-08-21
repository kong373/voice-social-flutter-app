import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/features/commerce/data/backend_commerce_repository.dart';
import 'package:voice_social_app/features/commerce/domain/commerce_models.dart';

void main() {
  test(
    'commerce wallet and ledger contracts parse balances and pagination',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        return switch (request.path) {
          '/app-economy-api/ncoin' => _Response.ok(<String, Object?>{
            'integer': 321,
          }),
          '/app-mini-api/mini/v1/wallet/overview' => _Response.ok(
            <String, Object?>{
              'balance': 12.5,
              'frozenBalance': 1.25,
              'totalEarnings': 88.0,
              'yesterdayEarnings': 3.0,
              'totalWithdraw': 20.0,
              'isRealName': 1,
              'defaultBankCard': <String, Object?>{
                'id': 'card-1',
                'bankName': '测试银行',
                'cardNumberMasked': '****1234',
                'cardHolderName': '晚星',
              },
              'agentEarnings': 5,
              'superAgentEarnings': 6,
            },
          ),
          '/app-mini-api/mini/v1/wallet/account-details' => _Response.ok(
            <String, Object?>{
              'records': <Object?>[
                <String, Object?>{
                  'id': 'ledger-1',
                  'subType': 'gift_income',
                  'subTypeName': '礼物收入',
                  'amount': 6.5,
                  'createTime': '2026-08-21T10:00:00Z',
                },
                <String, Object?>{
                  'id': 'retired-1',
                  'subType': 'blind_box',
                  'amount': 99,
                },
              ],
              'current': 2,
              'size': 1,
              'total': 3,
              'pages': 3,
            },
          ),
          _ => _Response.ok(<String, Object?>{}),
        };
      });
      addTearDown(harness.close);
      final BackendCommerceRepository repository = harness.repository;

      final WalletSummary wallet = await repository.fetchWalletSummary();
      expect(wallet.giftCoinBalance, 321);
      expect(wallet.cashBalance, 12.5);
      expect(wallet.realNameVerified, isTrue);
      expect(wallet.bankCard?.maskedNumber, '****1234');
      final CommercePage<LedgerEntry> ledger = await repository.fetchLedger(
        direction: LedgerDirection.income,
        page: 2,
        pageSize: 1,
      );
      expect(ledger.items.single.id, 'ledger-1');
      expect(ledger.items.single.kind, LedgerKind.giftIncome);
      expect(ledger.page, 2);
      expect(ledger.total, 3);
      expect(ledger.hasMore, isTrue);

      expect(harness.requests[0].method, 'GET');
      expect(harness.requests[1].path, '/app-mini-api/mini/v1/wallet/overview');
      expect(harness.requests[2].query, <String, String>{
        'type': '1',
        'page': '2',
        'size': '1',
      });
    },
  );

  test(
    'commerce orders and order status preserve post/get contracts',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        return switch (request.path) {
          '/app-economy-api/pay/getOrders' => _Response.ok(<String, Object?>{
            'list': <Object?>[
              <String, Object?>{
                'orderNo': 'order-1',
                'amount': 6.0,
                'ncoin': 60,
                'payType': '微信支付',
                'createDate': '2026-08-21T10:00:00Z',
              },
            ],
            'current': 1,
            'size': 20,
            'total': 1,
          }),
          '/app-economy-api/pay/isOrderSuccess' => _Response.ok(
            <String, Object?>{'bool': true},
          ),
          _ => _Response.ok(<String, Object?>{}),
        };
      });
      addTearDown(harness.close);
      final BackendCommerceRepository repository = harness.repository;
      final CommercePage<PaymentOrder> page = await repository.fetchOrders(
        page: 1,
        pageSize: 20,
      );
      expect(page.items.single.orderNo, 'order-1');
      expect(page.items.single.giftCoinAmount, 60);
      final PaymentOrder succeeded = await repository.queryOrderStatus(
        page.items.single,
      );
      expect(succeeded.status, PaymentOrderStatus.succeeded);
      expect(harness.requests[0].method, 'POST');
      expect(harness.requests[0].body, <String, Object?>{
        'pageNum': 1,
        'pageSize': 20,
        'isSearchCount': true,
      });
      expect(harness.requests[1].query, <String, String>{'orderNo': 'order-1'});
    },
  );

  test(
    'commerce refund flow preserves eligibility, submit, result, and repeat',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        return switch (request.path) {
          '/app-api/refund/check' => _Response.ok(<String, Object?>{
            'string': null,
          }),
          '/app-api/refund/application' => _Response.ok(<String, Object?>{
            'string': 'refund-1',
          }),
          '/app-api/refund/result' => _Response.ok(<String, Object?>{
            'status': 2,
            'rejectedReason': '资料不足',
          }),
          '/app-api/refund/repeat' => _Response.ok(<String, Object?>{}),
          _ => _Response.ok(<String, Object?>{}),
        };
      });
      addTearDown(harness.close);
      final BackendCommerceRepository repository = harness.repository;
      final RefundEligibility eligibility = await repository
          .checkRefundEligibility('user@example.com');
      expect(eligibility.allowed, isTrue);
      final RefundApplication submitted = await repository.submitRefund(
        const RefundRequest(
          account: 'user@example.com',
          realName: '晚星',
          age: 20,
          amount: 12.5,
          reason: '测试申请',
          receivingAccount: 'pay@example.com',
          receivingName: '晚星',
          guardianName: '监护人',
          guardianPhone: '13800138000',
        ),
      );
      expect(submitted.id, 'refund-1');
      expect(submitted.status, RefundStatus.reviewing);
      final RefundApplication result = await repository.fetchRefundResult(
        'refund-1',
      );
      expect(result.status, RefundStatus.rejected);
      expect(result.rejectedReason, '资料不足');
      final RefundApplication resubmitted = await repository.resubmitRefund(
        'refund-1',
      );
      expect(resubmitted.status, RefundStatus.resubmitted);

      expect(harness.requests[0].query, <String, String>{
        'loginName': 'user@example.com',
      });
      expect(harness.requests[2].method, 'POST');
      expect(harness.requests[2].body, <String, Object?>{
        'loginName': 'user@example.com',
        'realName': '晚星',
        'age': 20,
        'refundAmount': 12.5,
        'refundReason': '测试申请',
        'alipayAccount': 'pay@example.com',
        'alipayRealName': '晚星',
        'payEvidenceImgUrls': '',
        'custodianName': '监护人',
        'custodianPhone': '13800138000',
        'custodianIdcardNo': '',
        'custodianCertificateImgUrls': '',
        'rechargeNotCustodianEvidenceImgUrls': '',
      });
      expect(harness.requests[3].query, <String, String>{'id': 'refund-1'});
      expect(harness.requests[4].query, <String, String>{'id': 'refund-1'});
      expect(harness.requests[5].query, <String, String>{'id': 'refund-1'});
    },
  );

  test(
    'commerce refund existing application is returned without duplicate submit',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        return switch (request.path) {
          '/app-api/refund/check' => _Response.ok(<String, Object?>{
            'string': 'refund-existing',
          }),
          '/app-api/refund/result' => _Response.ok(<String, Object?>{
            'status': 1,
          }),
          _ => _Response.ok(<String, Object?>{}),
        };
      });
      addTearDown(harness.close);
      final BackendCommerceRepository repository = harness.repository;
      final List<RefundApplication> applications = await repository
          .fetchRefundApplications('account-1');
      expect(applications.single.id, 'refund-existing');
      expect(applications.single.account, 'account-1');
      expect(applications.single.status, RefundStatus.approved);
      expect(harness.requests, hasLength(2));
      expect(harness.requests[0].path, '/app-api/refund/check');
      expect(harness.requests[1].path, '/app-api/refund/result');
      expect(
        harness.requests.any(
          (RequestRecord item) => item.path == '/app-api/refund/application',
        ),
        isFalse,
      );
    },
  );

  test(
    'commerce withdrawal quote, application, list, and detail preserve contracts',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        return switch (request.path) {
          '/app-mini-api/mini/v1/withdrawal/fee-rate' => _Response.ok(
            <String, Object?>{'feeRate': 0.1, 'feeRateDisplay': '10%'},
          ),
          '/app-mini-api/mini/v1/withdrawal/apply' => _Response.ok('wd-1'),
          '/app-mini-api/mini/v1/withdrawal/records/wd-1' =>
            _Response.ok(<String, Object?>{
              'id': 'wd-1',
              'withdrawalNo': 'WD001',
              'amount': 100,
              'fee': 10,
              'actualAmount': 90,
              'status': 4,
              'statusName': '打款成功',
              'createTime': '2026-08-21T10:00:00Z',
              'bankCardName': '测试银行',
              'bankCardId': '****1234',
            }),
          '/app-mini-api/mini/v1/withdrawal/records' => _Response.ok(
            <String, Object?>{
              'records': <Object?>[],
              'current': 1,
              'size': 20,
              'total': 0,
            },
          ),
          _ => _Response.ok(<String, Object?>{}),
        };
      });
      addTearDown(harness.close);
      final BackendCommerceRepository repository = harness.repository;
      final WithdrawalQuote quote = await repository.fetchWithdrawalQuote();
      expect(quote.feeRate, 0.1);
      expect(quote.feeRateText, '10%');
      expect(quote.feeFor(100), 10);
      final WithdrawalRecord applied = await repository.applyWithdrawal(
        amount: 100,
      );
      expect(applied.status, WithdrawalStatus.succeeded);
      final CommercePage<WithdrawalRecord> records = await repository
          .fetchWithdrawalRecords(
            status: WithdrawalStatus.succeeded,
            page: 1,
            pageSize: 20,
          );
      expect(records.items, isEmpty);
      final WithdrawalRecord detail = await repository.fetchWithdrawalRecord(
        'wd-1',
      );
      expect(detail.withdrawalNo, 'WD001');
      expect(detail.receivedAmount, 90);
      expect(harness.requests[1].method, 'POST');
      expect(harness.requests[1].body, <String, Object?>{'amount': 100});
      expect(harness.requests[3].query, <String, String>{
        'page': '1',
        'size': '20',
        'status': '4',
      });
      expect(
        harness.requests[4].path,
        '/app-mini-api/mini/v1/withdrawal/records/wd-1',
      );
    },
  );

  test('commerce error envelope preserves status and message', () async {
    final _Harness harness = await _Harness.start((RequestRecord request) {
      return const _Response(
        statusCode: 503,
        code: 503,
        message: '钱包服务暂不可用',
        data: null,
      );
    });
    addTearDown(harness.close);
    await expectLater(
      harness.repository.fetchWalletSummary(),
      throwsA(
        isA<ApiException>()
            .having((ApiException e) => e.kind, 'kind', ApiFailureKind.server)
            .having((ApiException e) => e.httpStatus, 'httpStatus', 503)
            .having((ApiException e) => e.message, 'message', '钱包服务暂不可用'),
      ),
    );
  });
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
        method: request.method,
        path: request.uri.path,
        query: request.uri.queryParameters,
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
    required this.method,
    required this.path,
    required this.query,
    required this.body,
  });

  final String method;
  final String path;
  final Map<String, String> query;
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
