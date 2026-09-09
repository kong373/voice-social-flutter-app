import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/account/compliance/domain/account_compliance.dart';
import 'package:voice_social_app/features/account/data/auth_session_manager.dart';
import 'package:voice_social_app/features/commerce/catalog/domain/commerce_catalog_repository.dart';
import 'package:voice_social_app/features/commerce/data/backend_commerce_repository.dart';
import 'package:voice_social_app/features/commerce/domain/commerce_models.dart';
import 'package:voice_social_app/features/commerce/presentation/commerce_pages.dart';
import 'package:voice_social_app/features/room/presentation/gift_sheet.dart';

Finder get _send => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == '赠送礼物',
);

void main() {
  for (final fromInsufficientDialog in [true, false]) {
    for (final networkFailure in [false, true]) {
      testWidgets(
        'recharge return rejects unknown balance and recovers only by authoritative refresh '
        '(dialog=$fromInsufficientDialog, network=$networkFailure)',
        (tester) async {
          final h = _Harness();
          addTearDown(h.dispose);
          await h.mount(tester);
          expect(find.text('0.5'), findsOneWidget);
          await h.openRecharge(tester, fromInsufficientDialog);
          h.api.unknownPrecision = !networkFailure;
          h.api.networkFailure = networkFailure;
          await tester.pageBack();
          await tester.pumpAndSettle();
          expect(h.rechargeReturns, 1);
          await tester.tap(_send);
          await tester.pumpAndSettle();
          expect(h.requests, isEmpty);
          expect(tester.widget<Semantics>(_send).properties.enabled, isFalse);
          expect(find.text('余额待刷新，请重试'), findsOneWidget);
          expect(find.text('0.5'), findsNothing);

          h.api.unknownPrecision = false;
          h.api.networkFailure = false;
          h.api.availableTenths = '10000';
          await tester.tap(find.byTooltip('刷新余额'));
          await tester.pumpAndSettle();
          expect(find.text('1000'), findsOneWidget);
          expect(tester.widget<Semantics>(_send).properties.enabled, isTrue);
          await tester.tap(_send);
          await tester.pumpAndSettle();
          expect(h.requests, hasLength(1));
          expect(h.requests.single.target.userId, 20);
          expect(h.requests.single.quantity, 1);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }

    testWidgets(
      'late recharge balance cannot restore sending after identity ABA '
      '(dialog=$fromInsufficientDialog)',
      (tester) async {
        final h = _Harness();
        addTearDown(h.dispose);
        await h.mount(tester);
        await h.openRecharge(tester, fromInsufficientDialog);
        final oldBalance = Completer<ApiResponse>();
        h.api.nextBalance = oldBalance;
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(h.rechargeReturns, 1);
        expect(h.api.nextBalance, isNull);
        h.dependencies.switchIdentity('B');
        h.dependencies.switchIdentity('A');
        h.api.availableTenths = '10000';
        oldBalance.complete(h.api.balanceResponse());
        await tester.pumpAndSettle();
        expect(find.text('1000'), findsNothing);
        expect(find.text('身份已切换，请重新进入房间'), findsWidgets);
        expect(tester.widget<Semantics>(_send).properties.enabled, isFalse);
        await tester.tap(_send);
        await tester.pumpAndSettle();
        expect(h.requests, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}

class _Harness {
  final api = _WalletApi();
  late final dependencies = _Dependencies(api);
  final requests = <GiftSendRequest>[];
  int rechargeReturns = 0;

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: dependencies,
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 390,
                height: 490,
                child: GiftSheet(
                  balance: 1200,
                  account: 'A',
                  targets: const [GiftTarget(userId: 20, name: 'Alice')],
                  onSend: (request) async {
                    requests.add(request);
                    return false;
                  },
                  onRechargeReturn: () async {
                    rechargeReturns++;
                    // The legacy whole-coin room snapshot is not authoritative.
                    return 1200;
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openRecharge(WidgetTester tester, bool fromDialog) async {
    if (fromDialog) {
      await tester.tap(_send);
      await tester.pumpAndSettle();
      expect(find.text('礼物币不足'), findsOneWidget);
      expect(requests, isEmpty);
      await tester.tap(find.text('去充值'));
    } else {
      await tester.tap(find.text('充值'));
    }
    await tester.pumpAndSettle();
    expect(find.byType(RechargeCatalogPage), findsOneWidget);
    expect(find.text('充值商品目录'), findsOneWidget);
  }

  void dispose() {
    dependencies.changes.dispose();
    dependencies.backing.dispose();
  }
}

class _Dependencies extends Fake implements AppDependencies {
  _Dependencies(_WalletApi api) {
    commerceRepository = BackendCommerceRepository(
      apiClient: api,
      currentUserId: () => actor,
      identityGeneration: () => generation,
      withdrawalIdentityChanges: changes,
    );
  }
  final backing = AppDependencies.mock();
  final changes = ChangeNotifier();
  String actor = 'A';
  int generation = 1;
  void switchIdentity(String value) {
    actor = value;
    generation++;
    changes.notifyListeners();
  }

  @override
  late final CommerceRepository commerceRepository;
  @override
  CommerceCatalogRepository get commerceCatalogRepository =>
      backing.commerceCatalogRepository;
  @override
  AppEnvironment get environment => backing.environment;
  @override
  AuthSessionManager get sessionManager => backing.sessionManager;
  @override
  AccountComplianceRepository get accountComplianceRepository =>
      backing.accountComplianceRepository;
}

class _WalletApi extends Fake implements ApiClient {
  bool unknownPrecision = false;
  bool networkFailure = false;
  String availableTenths = '5';
  Completer<ApiResponse>? nextBalance;

  ApiResponse balanceResponse() => ApiResponse(
    code: 200,
    message: 'OK',
    data: {
      'currency': 'GIFT_COIN',
      'scale': 10,
      'precisionVersion': unknownPrecision ? 'UNKNOWN' : 'GIFT_COIN_TENTHS_V1',
      'availableTenths': availableTenths,
      'frozenTenths': '0',
      'integer': 1200,
    },
  );

  @override
  Future<ApiResponse> get(
    String path, {
    Map<String, String>? query,
    Map<String, String>? headers,
    bool authenticated = true,
  }) async {
    if (path == '/app-economy-api/ncoin') {
      final delayed = nextBalance;
      nextBalance = null;
      if (delayed != null) return delayed.future;
      if (networkFailure) {
        throw const ApiException(
          kind: ApiFailureKind.network,
          message: '测试网络失败',
        );
      }
      return balanceResponse();
    }
    expect(path, '/app-mini-api/mini/v1/wallet/overview');
    return const ApiResponse(
      code: 200,
      message: 'OK',
      data: {
        'balance': '0',
        'frozenBalance': '0',
        'totalEarnings': '0',
        'yesterdayEarnings': '0',
        'totalWithdraw': '0',
        'isRealName': 0,
        'defaultBankCard': <String, Object?>{},
        'agentEarnings': null,
        'agentEarningsStatus': 'UNAVAILABLE',
        'superAgentEarnings': null,
        'superAgentEarningsStatus': 'UNAVAILABLE',
        'incomeRole': 'ORDINARY',
        'incomeEligible': false,
        'canWithdraw': false,
      },
    );
  }
}
