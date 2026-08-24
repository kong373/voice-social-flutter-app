import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/debug/qa_console/qa_fixtures.dart';
import 'package:voice_social_app/features/commerce/data/mock_commerce_repository.dart';
import 'package:voice_social_app/features/commerce/domain/commerce_models.dart';
import 'package:voice_social_app/features/commerce/presentation/commerce_pages.dart';

void main() {
  testWidgets('order refund form only exposes the first-party order contract', (
    WidgetTester tester,
  ) async {
    final dependencies = await createQaDependencies();
    final PaymentOrder order = PaymentOrder(
      orderNo: 'ORDER-20260822-001',
      amount: 30,
      giftCoinAmount: 300,
      channelName: '开发支付渠道',
      createdAt: DateTime.utc(2026, 8, 22),
      status: PaymentOrderStatus.succeeded,
    );

    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: dependencies,
        child: MaterialApp(
          theme: AppTheme.social(),
          home: RefundApplicationPage(order: order),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('充值订单退款'), findsOneWidget);
    expect(find.text('订单号'), findsOneWidget);
    expect(find.text('退款金额'), findsOneWidget);
    expect(find.text('退款原因'), findsNWidgets(2));
    expect(find.text('账号使用人姓名'), findsNothing);
    expect(find.text('收款与监护信息'), findsNothing);
    expect(find.text('退款收款账号'), findsNothing);
    expect(find.text('监护人姓名（未成年人场景）'), findsNothing);
  });

  testWidgets('withdrawal quote is requested for the entered amount', (
    WidgetTester tester,
  ) async {
    final dependencies = await createQaDependencies();
    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: dependencies,
        child: MaterialApp(
          theme: AppTheme.social(),
          home: const WithdrawalPage(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('计算到账金额'), findsOneWidget);
    expect(find.text('输入金额后计算服务端报价'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '100');
    await tester.tap(find.text('计算到账金额'));
    await tester.pumpAndSettle();
    expect(find.textContaining('持卡人 晚*'), findsOneWidget);
    expect(find.textContaining('服务端报价'), findsOneWidget);
    expect(find.textContaining('预计到账 ¥98.00'), findsOneWidget);
  });

  testWidgets(
    'live withdrawal blocker leaves the first-party quote and records visible',
    (WidgetTester tester) async {
      final _WithdrawalUiSpyRepository repository =
          _WithdrawalUiSpyRepository();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.social(),
          home: WithdrawalPage(repository: repository),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.textContaining('基于 payoutAccountId 的提现申请'), findsOneWidget);
      expect(find.text('计算到账金额'), findsOneWidget);
      expect(find.text('提现记录'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '100');
      await tester.tap(find.text('计算到账金额'));
      await tester.pumpAndSettle();

      expect(find.textContaining('服务端报价'), findsOneWidget);
      expect(find.textContaining('预计到账 ¥98.00'), findsOneWidget);
      final FilledButton apply = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '申请提现'),
      );
      expect(apply.onPressed, isNull);
    },
  );

  testWidgets(
    'payout account transport failures remain visible and retryable',
    (WidgetTester tester) async {
      final _FailingPayoutAccountRepository repository =
          _FailingPayoutAccountRepository();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.social(),
          home: WithdrawalPage(repository: repository),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('收款账户服务连接失败'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      expect(find.textContaining('尚未提供 payoutAccountId'), findsNothing);
    },
  );

  testWidgets('order refund eligibility is bound to the selected order', (
    WidgetTester tester,
  ) async {
    final _RefundUiSpyRepository repository = _RefundUiSpyRepository(
      eligibility: const RefundEligibility(
        allowed: false,
        existingApplicationId: 'refund-selected-order',
        message: '该订单已有退款申请正在处理。',
      ),
    );
    final PaymentOrder order = PaymentOrder(
      orderNo: 'ORDER-SELECTED-001',
      amount: 30,
      giftCoinAmount: 300,
      channelName: '开发支付渠道',
      createdAt: DateTime(2026, 8, 22),
      status: PaymentOrderStatus.succeeded,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.social(),
        home: RefundApplicationPage(order: order, repository: repository),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(repository.checkedSubjects, <String>['ORDER-SELECTED-001']);
    expect(find.text('该订单已有退款申请正在处理。'), findsOneWidget);
    final FilledButton submit = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '提交订单退款申请'),
    );
    expect(submit.onPressed, isNull);
  });

  for (final (int, ApiFailureKind) failure in <(int, ApiFailureKind)>[
    (403, ApiFailureKind.forbidden),
    (409, ApiFailureKind.conflict),
    (422, ApiFailureKind.validation),
    (500, ApiFailureKind.server),
  ]) {
    testWidgets('refund $failure preserves the draft and never shows success', (
      WidgetTester tester,
    ) async {
      final _RefundUiSpyRepository repository = _RefundUiSpyRepository(
        submissionError: ApiException(
          kind: failure.$2,
          httpStatus: failure.$1,
          message: 'refund-${failure.$1}',
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.social(),
          home: RefundApplicationPage(
            account: '13800138000',
            repository: repository,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final Finder fields = find.byType(TextFormField);
      await tester.enterText(fields.at(1), '测试用户');
      await tester.enterText(fields.at(2), '26');
      await tester.enterText(fields.at(3), '30');
      await tester.enterText(fields.at(4), '重复充值需要退款');
      final TextEditingController nameController = tester
          .widget<TextFormField>(fields.at(1))
          .controller!;
      final TextEditingController ageController = tester
          .widget<TextFormField>(fields.at(2))
          .controller!;
      final TextEditingController amountController = tester
          .widget<TextFormField>(fields.at(3))
          .controller!;
      final TextEditingController reasonController = tester
          .widget<TextFormField>(fields.at(4))
          .controller!;
      await tester.drag(find.byType(ListView).last, const Offset(0, -1000));
      await tester.pump();
      final Finder submitButton = find.text('提交退款申请', skipOffstage: false);
      await tester.ensureVisible(submitButton);
      await tester.tap(submitButton);
      await tester.pump();
      await tester.tap(find.text('确认提交'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(repository.submitCount, 1);
      expect(find.text('退款申请'), findsOneWidget);
      expect(find.text('退款申请结果'), findsNothing);
      expect(nameController.text, '测试用户');
      expect(ageController.text, '26');
      expect(amountController.text, '30');
      expect(reasonController.text, '重复充值需要退款');
      expect(find.textContaining('refund-${failure.$1}'), findsOneWidget);
    });
  }

  testWidgets('double tapping refund submit produces one write', (
    WidgetTester tester,
  ) async {
    final Completer<RefundApplication> completion =
        Completer<RefundApplication>();
    final _RefundUiSpyRepository repository = _RefundUiSpyRepository(
      submission: completion.future,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.social(),
        home: RefundApplicationPage(
          account: '13800138000',
          repository: repository,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    final Finder fields = find.byType(TextFormField);
    await tester.enterText(fields.at(1), '测试用户');
    await tester.enterText(fields.at(2), '26');
    await tester.enterText(fields.at(3), '30');
    await tester.enterText(fields.at(4), '重复充值需要退款');
    await tester.drag(find.byType(ListView).last, const Offset(0, -1000));
    await tester.pump();
    final Finder submitButton = find.text('提交退款申请', skipOffstage: false);
    await tester.ensureVisible(submitButton);
    await tester.tap(submitButton);
    await tester.pump();
    await tester.tap(find.text('确认提交'));
    await tester.pump();
    expect(repository.submitCount, 1);

    final Finder submitControl = find.byType(FilledButton).last;
    expect(tester.widget<FilledButton>(submitControl).onPressed, isNull);
    expect(tester.widget<FilledButton>(submitControl).onPressed, isNull);
    expect(repository.submitCount, 1);

    completion.complete(
      RefundApplication(
        id: 'refund-double-tap',
        account: '13800138000',
        amount: 30,
        status: RefundStatus.reviewing,
        statusText: '审核中',
        rejectedReason: '',
        createdAt: DateTime(2026, 8, 22),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('退款申请结果'), findsOneWidget);
  });

  testWidgets('refund retry sends the selected refund and order identity', (
    WidgetTester tester,
  ) async {
    final _RefundUiSpyRepository repository = _RefundUiSpyRepository(
      scope: RefundScope.order,
      retryResult: RefundApplication(
        id: 'refund-selected',
        account: 'ORDER-SELECTED-002',
        amount: 30,
        status: RefundStatus.resubmitted,
        statusText: '已重新提交',
        rejectedReason: '',
        createdAt: DateTime(2026, 8, 22),
      ),
    );
    final RefundApplication rejected = RefundApplication(
      id: 'refund-selected',
      account: 'ORDER-SELECTED-002',
      amount: 30,
      status: RefundStatus.rejected,
      statusText: '已拒绝',
      rejectedReason: '资料不足',
      createdAt: DateTime(2026, 8, 22),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.social(),
        home: RefundResultPage(application: rejected, repository: repository),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('重新提交申请'));
    await tester.pumpAndSettle();

    expect(repository.retryApplicationId, 'refund-selected');
    expect(repository.retryOrderNo, 'ORDER-SELECTED-002');
    expect(find.text('充值订单号'), findsOneWidget);
    expect(find.text('申请账号'), findsNothing);
    expect(find.text('已重新提交'), findsOneWidget);
  });

  testWidgets('refund result refresh is single-flight before rebuild', (
    WidgetTester tester,
  ) async {
    final Completer<RefundApplication> completion =
        Completer<RefundApplication>();
    final _RefundUiSpyRepository repository = _RefundUiSpyRepository(
      resultSubmission: completion.future,
    );
    final RefundApplication application = RefundApplication(
      id: 'refund-refresh',
      account: 'ORDER-REFRESH-001',
      amount: 30,
      status: RefundStatus.reviewing,
      statusText: '审核中',
      rejectedReason: '',
      createdAt: DateTime(2026, 8, 22),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.social(),
        home: RefundResultPage(
          application: application,
          repository: repository,
        ),
      ),
    );
    await tester.pump();
    final Finder refresh = find.byTooltip('刷新');
    await tester.tap(refresh);
    await tester.tap(refresh);

    expect(repository.resultCount, 1);
    completion.complete(application);
    await tester.pumpAndSettle();
  });

  testWidgets('refund retry is single-flight before rebuild', (
    WidgetTester tester,
  ) async {
    final Completer<RefundApplication> completion =
        Completer<RefundApplication>();
    final _RefundUiSpyRepository repository = _RefundUiSpyRepository(
      retrySubmission: completion.future,
    );
    final RefundApplication application = RefundApplication(
      id: 'refund-retry-flight',
      account: 'ORDER-RETRY-001',
      amount: 30,
      status: RefundStatus.rejected,
      statusText: '已拒绝',
      rejectedReason: '资料不足',
      createdAt: DateTime(2026, 8, 22),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.social(),
        home: RefundResultPage(
          application: application,
          repository: repository,
        ),
      ),
    );
    await tester.pump();
    final Finder retry = find.text('重新提交申请');
    await tester.tap(retry);
    await tester.tap(retry);

    expect(repository.retryCount, 1);
    completion.complete(
      application.copyWith(
        status: RefundStatus.resubmitted,
        statusText: '已重新提交',
        rejectedReason: '',
      ),
    );
    await tester.pumpAndSettle();
  });
}

class _RefundUiSpyRepository extends MockCommerceRepository {
  _RefundUiSpyRepository({
    RefundScope scope = RefundScope.accountLegacy,
    this.eligibility = const RefundEligibility(
      allowed: true,
      existingApplicationId: null,
      message: '当前账号可以提交账户退款申请。',
    ),
    this.submissionError,
    this.submission,
    this.retryResult,
    this.resultSubmission,
    this.retrySubmission,
  }) : _scope = scope;

  final RefundScope _scope;
  final RefundEligibility eligibility;
  final ApiException? submissionError;
  final Future<RefundApplication>? submission;
  final RefundApplication? retryResult;
  final Future<RefundApplication>? resultSubmission;
  final Future<RefundApplication>? retrySubmission;
  final List<String> checkedSubjects = <String>[];
  int submitCount = 0;
  int resultCount = 0;
  int retryCount = 0;

  @override
  RefundScope get refundScope => _scope;
  String? retryApplicationId;
  String? retryOrderNo;

  @override
  Future<RefundEligibility> checkRefundEligibility(String account) async {
    checkedSubjects.add(account);
    return eligibility;
  }

  @override
  Future<RefundApplication> fetchRefundResult(
    String applicationId, {
    String? expectedOrderNo,
  }) {
    resultCount += 1;
    final Future<RefundApplication>? pending = resultSubmission;
    if (pending != null) {
      return pending;
    }
    return super.fetchRefundResult(
      applicationId,
      expectedOrderNo: expectedOrderNo,
    );
  }

  @override
  Future<RefundApplication> submitRefund(RefundRequest request) {
    submitCount += 1;
    final ApiException? error = submissionError;
    if (error != null) {
      return Future<RefundApplication>.error(error);
    }
    final Future<RefundApplication>? pending = submission;
    if (pending != null) {
      return pending;
    }
    return Future<RefundApplication>.value(
      RefundApplication(
        id: 'refund-spy',
        account: request.account,
        amount: request.amount,
        status: RefundStatus.reviewing,
        statusText: '审核中',
        rejectedReason: '',
        createdAt: DateTime(2026, 8, 22),
      ),
    );
  }

  @override
  Future<RefundApplication> resubmitRefund(
    String applicationId, {
    String? expectedOrderNo,
  }) async {
    retryCount += 1;
    retryApplicationId = applicationId;
    retryOrderNo = expectedOrderNo;
    final Future<RefundApplication>? pending = retrySubmission;
    if (pending != null) {
      return pending;
    }
    return retryResult!;
  }
}

class _WithdrawalUiSpyRepository extends MockCommerceRepository {
  @override
  bool get supportsWithdrawalApplication => false;

  @override
  Future<WithdrawalQuote> fetchWithdrawalQuote({required double amount}) async {
    return WithdrawalQuote(
      quotedAmount: amount,
      feeAmount: amount * 0.02,
      receivedAmount: amount * 0.98,
      feeRate: 0.02,
      feeRateText: '2.00%',
      minimumAmount: 10,
    );
  }
}

class _FailingPayoutAccountRepository extends MockCommerceRepository {
  @override
  bool get supportsWithdrawalApplication => true;

  @override
  bool get supportsPayoutAccountSelection => true;

  @override
  Future<PayoutAccountSelection> fetchPayoutAccounts() =>
      Future<PayoutAccountSelection>.error(
        const ApiException(kind: ApiFailureKind.network, message: '收款账户服务连接失败'),
      );
}
