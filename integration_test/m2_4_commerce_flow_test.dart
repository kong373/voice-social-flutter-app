import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:voice_social_app/debug/qa_console/qa_fixtures.dart';
import 'package:voice_social_app/features/commerce/catalog/domain/commerce_catalog_models.dart';
import 'package:voice_social_app/features/commerce/domain/commerce_models.dart';
import 'package:voice_social_app/features/commerce/presentation/commerce_pages.dart';

import 'm2_4_test_support.dart';

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  _installLinuxSecureStorageTestStub();

  testWidgets(
    'FLOW-012 ordinary commerce entry keeps server-authoritative state',
    (WidgetTester tester) async {
      final dependencies = await launchAndAuthenticate(tester);
      final String account = dependencies.sessionManager.session!.mobile;

      // Enter every commerce surface through the ordinary signed-in route.
      await tester.tap(find.text('我的'));
      await tester.pumpAndSettle();
      await pumpUntilVisible(tester, find.text('个人与关系'));
      await _scrollToAndTap(tester, find.text('钱包、订单与收益'));
      await pumpUntilVisible(tester, find.byType(CommerceHubPage));
      expect(find.text('钱包与商业化'), findsOneWidget);

      // Wallet: the visible balances must exactly match the repository result.
      await _scrollToAndTap(tester, find.text('钱包与流水'));
      await pumpUntilVisible(tester, find.text('普通礼物收益'));
      final WalletSummary walletBefore = await dependencies.commerceRepository
          .fetchWalletSummary();
      expect(walletBefore.giftCoinBalance, 1680);
      expect(walletBefore.cashBalance, 1288.50);
      expect(walletBefore.frozenBalance, 200);
      expect(find.text('${walletBefore.giftCoinBalance}'), findsOneWidget);
      expect(
        find.text('¥${walletBefore.cashBalance.toStringAsFixed(2)}'),
        findsOneWidget,
      );
      expect(find.text('普通礼物收益'), findsOneWidget);
      await _captureFlowStep(tester, binding, 'FLOW-012-01-wallet-$qaAvdId');
      await _pageBackTo(tester, find.byType(CommerceHubPage));

      // Catalog and Android payment: only the two approved channels may be
      // exposed. Submit the recommended 700-coin product through Alipay.
      await _scrollToAndTap(tester, find.text('充值商品目录'));
      await pumpUntilVisible(tester, find.text('700 礼物币'));
      expect(find.text('Android'), findsOneWidget);
      expect(find.text('1680'), findsOneWidget);
      await _scrollToAndTap(tester, find.text('选择支付方式'));
      await pumpUntilVisible(tester, find.byType(PaymentSubmissionPage));
      final List<RadioListTile<PaymentChannelType>> channelTiles = tester
          .widgetList<RadioListTile<PaymentChannelType>>(
            find.byType(RadioListTile<PaymentChannelType>),
          )
          .toList(growable: false);
      expect(channelTiles, hasLength(2));
      expect(
        channelTiles.map(
          (RadioListTile<PaymentChannelType> tile) => tile.value,
        ),
        unorderedEquals(<PaymentChannelType>[
          PaymentChannelType.wechat,
          PaymentChannelType.alipay,
        ]),
      );
      expect(find.text('微信支付'), findsOneWidget);
      expect(find.text('支付宝'), findsOneWidget);
      expect(find.text('Apple IAP'), findsNothing);
      expect(find.text('易票联'), findsNothing);
      await tester.tap(find.text('支付宝'));
      await tester.pumpAndSettle();
      await _captureFlowStep(
        tester,
        binding,
        'FLOW-012-02-android-channels-$qaAvdId',
      );

      await tester.tap(find.text('提交充值订单'));
      await tester.pumpAndSettle();
      expect(find.text('确认充值信息'), findsOneWidget);
      expect(find.text('充值 700 礼物币，实付 ¥68.00，支付方式为 支付宝。'), findsOneWidget);
      await tester.tap(find.text('确认提交'));
      await pumpUntilVisible(tester, find.byType(PaymentResultPage));
      await pumpUntilVisible(tester, find.text('刷新订单状态'));
      final RechargeOrder submittedOrder = tester
          .widget<PaymentResultPage>(find.byType(PaymentResultPage))
          .order;
      expect(submittedOrder.account, account);
      expect(submittedOrder.product.id, 'recharge-68');
      expect(submittedOrder.product.totalGiftCoins, 700);
      expect(submittedOrder.product.priceCny, 68);
      expect(submittedOrder.channel, PaymentChannelType.alipay);
      expect(submittedOrder.state, RechargeOrderState.confirming);
      expect(find.text('服务端确认中'), findsOneWidget);
      expect(find.text(submittedOrder.orderNo), findsOneWidget);
      await _captureFlowStep(
        tester,
        binding,
        'FLOW-012-03-payment-confirming-$qaAvdId',
      );

      await tester.tap(find.text('刷新订单状态'));
      await pumpUntilVisible(tester, find.text('充值成功'));
      final RechargeOrder serverRechargeOrder = await dependencies
          .commerceCatalogRepository
          .queryRechargeOrder(submittedOrder);
      expect(serverRechargeOrder.orderNo, submittedOrder.orderNo);
      expect(serverRechargeOrder.state, RechargeOrderState.succeeded);
      expect(serverRechargeOrder.message, '服务端已确认到账');
      expect(find.text('服务端已确认到账'), findsOneWidget);
      await _captureFlowStep(
        tester,
        binding,
        'FLOW-012-04-payment-server-success-$qaAvdId',
      );

      await tester.tap(find.text('返回钱包'));
      await tester.pumpAndSettle();
      await pumpUntilVisible(tester, find.byType(RechargeCatalogPage));
      await _pageBackTo(tester, find.byType(CommerceHubPage));

      // The same RC order must naturally appear in the ordinary order center.
      // Refreshing its detail is a server query and must preserve succeeded.
      await _scrollToAndTap(tester, find.text('充值订单'));
      await pumpUntilVisible(tester, find.byType(OrdersPage));
      final CommercePage<PaymentOrder> ordersPage = await dependencies
          .commerceRepository
          .fetchOrders(page: 1, pageSize: 50);
      final PaymentOrder projectedOrder = ordersPage.items.singleWhere(
        (PaymentOrder order) => order.orderNo == submittedOrder.orderNo,
      );
      expect(projectedOrder.amount, 68);
      expect(projectedOrder.giftCoinAmount, 700);
      expect(projectedOrder.channelName, '支付宝');
      expect(projectedOrder.status, PaymentOrderStatus.succeeded);
      expect(
        find.textContaining('订单号 ${submittedOrder.orderNo}'),
        findsOneWidget,
      );
      await tester.tap(find.textContaining('订单号 ${submittedOrder.orderNo}'));
      await tester.pumpAndSettle();
      await pumpUntilVisible(tester, find.byType(OrderDetailPage));
      expect(find.text('订单详情与补单'), findsOneWidget);
      expect(find.text(submittedOrder.orderNo), findsOneWidget);
      expect(find.text('支付成功'), findsOneWidget);
      expect(find.text('支付宝'), findsOneWidget);
      await tester.tap(find.text('刷新并补单核验'));
      await tester.pumpAndSettle();
      final PaymentOrder reconciledOrder = await dependencies.commerceRepository
          .queryOrderStatus(projectedOrder);
      expect(reconciledOrder.orderNo, submittedOrder.orderNo);
      expect(reconciledOrder.status, PaymentOrderStatus.succeeded);
      expect(find.text('支付成功'), findsOneWidget);
      await _captureFlowStep(
        tester,
        binding,
        'FLOW-012-05-order-detail-reconciled-$qaAvdId',
      );
      await _pageBackTo(tester, find.byType(OrdersPage));
      await _pageBackTo(tester, find.byType(CommerceHubPage));

      // Refund is an explicitly account-scoped legacy flow. Exercise either
      // the existing result (138 fixture) or a real application (other test
      // accounts), then verify the repository result for the exact account.
      await _scrollToAndTap(tester, find.text('退款申请'));
      await pumpUntilVisible(tester, find.byType(RefundListPage));
      final List<RefundApplication> refunds = await dependencies
          .commerceRepository
          .fetchRefundApplications(account);
      RefundApplication refund;
      if (refunds.isEmpty) {
        expect(find.text('暂无正在处理的退款申请'), findsOneWidget);
        await tester.tap(find.text('申请退款'));
        await pumpUntilVisible(tester, find.byType(RefundApplicationPage));
        expect(find.text('当前账号可以提交账户退款申请。'), findsOneWidget);
        await _enterFormText(tester, '账号使用人姓名', 'FLOW 验收用户');
        await _enterFormText(tester, '年龄', '26');
        await _enterFormText(tester, '申请退款金额', '30');
        await _enterFormText(tester, '退款原因', 'FLOW-012 账户退款流程验收');
        FocusManager.instance.primaryFocus?.unfocus();
        await _scrollToAndTap(tester, find.text('提交退款申请'));
        expect(find.text('确认提交退款申请？'), findsOneWidget);
        expect(
          find.text('申请账号：$account\n申请金额：¥30.00\n提交后将进入人工审核。'),
          findsOneWidget,
        );
        await tester.tap(find.text('确认提交'));
        await pumpUntilVisible(tester, find.byType(RefundResultPage));
        refund = tester
            .widget<RefundResultPage>(find.byType(RefundResultPage))
            .application;
      } else {
        expect(refunds, hasLength(1));
        refund = refunds.single;
        expect(find.text('${refund.statusText} · ¥30.00'), findsOneWidget);
        await tester.tap(find.textContaining('申请编号 ${refund.id}'));
        await pumpUntilVisible(tester, find.byType(RefundResultPage));
      }
      final RefundApplication authoritativeRefund = await dependencies
          .commerceRepository
          .fetchRefundResult(refund.id);
      expect(authoritativeRefund.account, account);
      expect(authoritativeRefund.amount, 30);
      expect(authoritativeRefund.status, RefundStatus.reviewing);
      expect(authoritativeRefund.statusText, '审核中');
      expect(find.text('审核中'), findsOneWidget);
      expect(find.text(refund.id), findsOneWidget);
      await _captureFlowStep(
        tester,
        binding,
        'FLOW-012-06-refund-result-$qaAvdId',
      );
      await _pageBackTo(tester, find.byType(RefundListPage));
      await _pageBackTo(tester, find.byType(CommerceHubPage));

      // Earnings must use the same server wallet and income ledger.
      await _scrollToAndTap(tester, find.text('主播收益'));
      await pumpUntilVisible(tester, find.byType(EarningsPage));
      final WalletSummary earningsWallet = await dependencies.commerceRepository
          .fetchWalletSummary();
      final CommercePage<LedgerEntry> incomePage = await dependencies
          .commerceRepository
          .fetchLedger(
            currency: LedgerCurrency.cashCny,
            direction: LedgerDirection.income,
            page: 1,
            pageSize: 50,
          );
      expect(earningsWallet.totalEarnings, 5688.80);
      expect(earningsWallet.yesterdayEarnings, 88);
      expect(incomePage.items.map((LedgerEntry item) => item.title), <String>[
        '普通礼物收益',
        '渠道结算收益',
      ]);
      expect(find.text('¥5688.80'), findsOneWidget);
      expect(find.text('¥88.00'), findsOneWidget);
      expect(find.text('普通礼物收益'), findsOneWidget);
      expect(find.text('渠道结算收益'), findsOneWidget);
      await _captureFlowStep(
        tester,
        binding,
        'FLOW-012-07-anchor-earnings-$qaAvdId',
      );
      await _pageBackTo(tester, find.byType(CommerceHubPage));

      // Withdrawal validates the minimum on the repository, confirms exact
      // fee/receipt values, and then verifies the mutated wallet and record.
      await _scrollToAndTap(tester, find.text('结算与提现'));
      await pumpUntilVisible(tester, find.byType(WithdrawalPage));
      final WithdrawalQuote quote = await dependencies.commerceRepository
          .fetchWithdrawalQuote(amount: 100);
      final CommercePage<WithdrawalRecord> withdrawalsBefore =
          await dependencies.commerceRepository.fetchWithdrawalRecords(
            page: 1,
            pageSize: 50,
          );
      expect(quote.minimumAmount, 100);
      expect(quote.feeRate, 0.01);
      expect(find.text('最低 ¥100 · 手续费 1%'), findsOneWidget);
      expect(find.text('可提现 ¥1288.50'), findsOneWidget);

      await _enterFormText(tester, '提现金额', '99');
      FocusManager.instance.primaryFocus?.unfocus();
      await _scrollToAndTap(tester, find.text('申请提现'));
      expect(find.text('确认申请提现？'), findsOneWidget);
      expect(
        (tester.widget<AlertDialog>(find.byType(AlertDialog)).content as Text)
            .data,
        '提现金额：¥99.00\n手续费：¥0.99\n预计到账：¥98.01',
      );
      await tester.tap(find.text('确认提现'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('单笔提现金额不得少于 100 元'), findsOneWidget);
      WalletSummary withdrawalWallet = await dependencies.commerceRepository
          .fetchWalletSummary();
      expect(withdrawalWallet.cashBalance, 1288.50);
      expect(withdrawalWallet.frozenBalance, 200);

      await _enterFormText(tester, '提现金额', '100');
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, '提现金额'))
            .controller!
            .text,
        '100',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await _scrollToAndTap(tester, find.text('申请提现'));
      expect(find.text('确认申请提现？'), findsOneWidget);
      expect(
        (tester.widget<AlertDialog>(find.byType(AlertDialog)).content as Text)
            .data,
        '提现金额：¥100.00\n手续费：¥1.00\n预计到账：¥99.00',
      );
      await tester.tap(find.text('确认提现'));
      await pumpUntilVisible(tester, find.text('提现申请已提交'));

      withdrawalWallet = await dependencies.commerceRepository
          .fetchWalletSummary();
      final CommercePage<WithdrawalRecord> withdrawalsAfter = await dependencies
          .commerceRepository
          .fetchWithdrawalRecords(page: 1, pageSize: 50);
      expect(withdrawalWallet.cashBalance, 1188.50);
      expect(withdrawalWallet.frozenBalance, 300);
      expect(withdrawalsAfter.total, withdrawalsBefore.total + 1);
      final WithdrawalRecord newWithdrawal = withdrawalsAfter.items.first;
      expect(newWithdrawal.amount, 100);
      expect(newWithdrawal.fee, 1);
      expect(newWithdrawal.receivedAmount, 99);
      expect(newWithdrawal.status, WithdrawalStatus.pending);
      expect(newWithdrawal.statusText, '待审核');
      await _scrollToFinder(tester, find.text('¥100.00 · 待审核'));
      expect(find.text('到账 ¥99.00'), findsOneWidget);
      expect(find.text('可提现 ¥1188.50'), findsOneWidget);
      await _captureFlowStep(
        tester,
        binding,
        'FLOW-012-08-withdrawal-confirmed-$qaAvdId',
      );
    },
  );

  testWidgets(
    'Android recharge exposes only WeChat and Alipay and confirms server result',
    (WidgetTester tester) async {
      await pumpQaPage(
        tester,
        const PaymentSubmissionPage(
          product: qaRechargeProduct,
          platform: ClientStorePlatform.android,
          youthModeEnabled: false,
        ),
      );

      final List<RadioListTile<PaymentChannelType>> channelTiles = tester
          .widgetList<RadioListTile<PaymentChannelType>>(
            find.byType(RadioListTile<PaymentChannelType>),
          )
          .toList(growable: false);
      expect(channelTiles, hasLength(2));
      expect(
        channelTiles.map(
          (RadioListTile<PaymentChannelType> tile) => tile.value,
        ),
        unorderedEquals(<PaymentChannelType>[
          PaymentChannelType.wechat,
          PaymentChannelType.alipay,
        ]),
      );
      expect(find.text('微信支付'), findsOneWidget);
      expect(find.text('支付宝'), findsOneWidget);
      expect(find.text('Apple IAP'), findsNothing);
      await tester.tap(find.text('提交充值订单'));
      await tester.pumpAndSettle();
      expect(find.text('确认充值信息'), findsOneWidget);
      expect(find.text('确认提交'), findsOneWidget);
      await tester.tap(find.text('确认提交'));
      await pumpUntilVisible(tester, find.byType(PaymentResultPage));
      await pumpUntilVisible(tester, find.text('刷新订单状态'));
      expect(find.text('服务端确认中'), findsOneWidget);
      expect(find.text('充值成功'), findsNothing);

      await tester.tap(find.text('刷新订单状态'));
      await pumpUntilVisible(tester, find.text('充值成功'));
      expect(find.text('服务端已确认到账'), findsOneWidget);

      await captureQaScreenshot(
        tester,
        binding,
        'FLOW-012-android-payment-server-result-$qaAvdId',
      );
    },
  );

  testWidgets('youth mode blocks only creation of a new recharge order', (
    WidgetTester tester,
  ) async {
    await pumpQaPage(
      tester,
      const PaymentSubmissionPage(
        product: qaRechargeProduct,
        platform: ClientStorePlatform.android,
        youthModeEnabled: true,
      ),
    );

    await tester.tap(find.text('提交充值订单'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认提交'));
    await tester.pumpAndSettle();
    expect(find.text('青少年模式已开启，暂不能创建新的充值订单'), findsOneWidget);

    await pumpQaPage(tester, const WalletPage());
    expect(find.text('礼物币余额'), findsWidgets);
  });

  testWidgets('ordinary gift catalog excludes all retired commerce features', (
    WidgetTester tester,
  ) async {
    final dependencies = await pumpQaPage(tester, const GiftCatalogPage());

    expect(find.text('普通礼物'), findsOneWidget);
    for (final GiftCatalogCategory category in GiftCatalogCategory.values) {
      await tester.tap(find.text(category.label));
      await tester.pumpAndSettle();
      expectNoRetiredFeatureText(reason: 'visible ${category.label} catalog');
    }

    final Future<List<GiftCatalogItem>> giftsFuture = dependencies
        .commerceCatalogRepository
        .fetchGiftCatalog();
    await tester.pump(const Duration(milliseconds: 100));
    final List<GiftCatalogItem> gifts = await giftsFuture;
    _expectNoRetiredTokens(<String>[
      for (final GiftCatalogItem gift in gifts) '${gift.id} ${gift.name}',
    ]);
  });
}

void _expectNoRetiredTokens(Iterable<String> values) {
  final List<String> normalizedValues = values
      .map((String value) => value.toLowerCase())
      .toList(growable: false);
  for (final String token in qaRetiredFeatureTokens) {
    expect(
      normalizedValues.where((String value) => value.contains(token)),
      isEmpty,
      reason: 'repository catalog contains retired token: $token',
    );
  }
}

Future<void> _captureFlowStep(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
  String name,
) async {
  // Desktop has no screenshot implementation; keep local Linux validation
  // running through the whole flow while Android records every evidence step.
  if (Platform.isLinux) {
    return;
  }
  await captureQaScreenshot(tester, binding, name);
}

Future<void> _enterFormText(
  WidgetTester tester,
  String label,
  String value,
) async {
  final Finder field = find.widgetWithText(TextField, label);
  await _scrollToFinder(tester, field);
  await tester.tap(field);
  await tester.pump();
  tester.testTextInput.enterText(value);
  await tester.pumpAndSettle();
}

Future<void> _scrollToFinder(
  WidgetTester tester,
  Finder finder, {
  double scrollDelta = 180,
}) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      scrollDelta,
      scrollable: find.byType(Scrollable).first,
    );
  }
  expect(finder, findsWidgets);
  await tester.ensureVisible(finder.first);
  await tester.pumpAndSettle();
}

Future<void> _scrollToAndTap(
  WidgetTester tester,
  Finder finder, {
  double scrollDelta = 180,
}) async {
  await _scrollToFinder(tester, finder, scrollDelta: scrollDelta);
  await tester.tap(finder.first);
  await tester.pumpAndSettle();
}

Future<void> _pageBackTo(WidgetTester tester, Finder expected) async {
  // pumpUntilVisible may return as soon as the incoming route is mounted;
  // finish the transition so only its AppBar back action remains hittable.
  await tester.pumpAndSettle();
  await tester.pageBack();
  await tester.pumpAndSettle();
  await pumpUntilVisible(tester, expected);
}

void _installLinuxSecureStorageTestStub() {
  if (!Platform.isLinux) {
    return;
  }
  final Map<String, String> values = <String, String>{};
  const MethodChannel channel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        final Map<Object?, Object?> arguments =
            (call.arguments as Map<Object?, Object?>?) ??
            const <Object?, Object?>{};
        final String? key = arguments['key'] as String?;
        switch (call.method) {
          case 'read':
            return key == null ? null : values[key];
          case 'write':
            if (key != null) {
              values[key] = arguments['value'] as String;
            }
            return null;
          case 'delete':
            if (key != null) {
              values.remove(key);
            }
            return null;
          case 'deleteAll':
            values.clear();
            return null;
          case 'readAll':
            return Map<String, String>.of(values);
          case 'containsKey':
            return key != null && values.containsKey(key);
        }
        throw MissingPluginException('Unsupported secure storage test call');
      });
}
