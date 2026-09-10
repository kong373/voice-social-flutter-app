import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/commerce/data/mock_commerce_repository.dart';
import 'package:voice_social_app/features/commerce/domain/commerce_models.dart';
import 'package:voice_social_app/features/commerce/domain/payout_account_binding.dart';
import 'package:voice_social_app/features/commerce/presentation/commerce_pages.dart';

class _Repository extends MockCommerceRepository
    implements PayoutAccountBindingRepository {
  final changes = ChangeNotifier();
  int generation = 0;
  bool unknown = true;
  Completer<PayoutAccountSelection>? delayed;
  final calls = <(PayoutAccountInput, String)>[];
  @override
  (String?, int) get withdrawalIdentity => ('fixture', generation);
  @override
  Listenable get withdrawalIdentityChanges => changes;
  @override
  bool get supportsPayoutAccountSelection => true;
  @override
  Future<PayoutAccountSelection> fetchPayoutAccounts() async =>
      const PayoutAccountSelection(
        accounts: [
          PayoutAccount(
            payoutAccountId: 'bound',
            accountType: 'ALIPAY',
            accountMasked: 'f***@example.test',
            holderNameMasked: '测*',
            status: PayoutAccountStatus.bound,
            selectable: true,
            verificationSource: 'USER_DECLARED',
          ),
        ],
        selectedPayoutAccountId: 'bound',
        selectionRequired: false,
        canBind: true,
        bindingBlockReason: 'NONE',
      );
  @override
  Future<PayoutAccountSelection> bindPayoutAccount(
    PayoutAccountInput input, {
    required String requestId,
  }) async {
    calls.add((input, requestId));
    if (delayed != null) return delayed!.future;
    if (unknown)
      throw const ApiException(
        kind: ApiFailureKind.network,
        message: 'unknown',
      );
    return fetchPayoutAccounts();
  }

  void switchIdentity() {
    generation++;
    changes.notifyListeners();
  }
}

void main() {
  testWidgets(
    'bank card form requires bank and sends the four declared fields',
    (tester) async {
      final repo = _Repository();
      await tester.pumpWidget(
        MaterialApp(home: PayoutAccountBindingPage(repository: repo)),
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('银行卡').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), '测试用户');
      await tester.enterText(find.byType(TextFormField).at(1), '123456789012');
      await tester.tap(find.text('确认绑定'));
      await tester.pumpAndSettle();
      expect(repo.calls, isEmpty);
      expect(find.text('请填写开户银行'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).at(2), '测试银行');
      await tester.tap(find.text('确认绑定'));
      await tester.pumpAndSettle();
      expect(repo.calls.single.$1.toBody(), {
        'accountType': 'BANK_CARD',
        'accountNumber': '123456789012',
        'holderName': '测试用户',
        'bankName': '测试银行',
      });
      await tester.pumpWidget(const SizedBox());
      repo.changes.dispose();
    },
  );
  testWidgets(
    'back clears sensitive fields before the return animation finishes',
    (tester) async {
      final repo = _Repository()..delayed = Completer<PayoutAccountSelection>();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<bool>(
                    builder: (_) => PayoutAccountBindingPage(repository: repo),
                  ),
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), '测试用户');
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'fixture@example.test',
      );
      final controller = tester
          .widget<TextFormField>(find.byType(TextFormField).at(1))
          .controller!;
      await tester.tap(find.text('确认绑定'));
      await tester.pump();
      await tester.pageBack();
      await tester.pump();
      expect(controller.text, isEmpty);
      repo.delayed!.complete(await repo.fetchPayoutAccounts());
      await tester.pumpAndSettle();
      expect(find.text('打开'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      repo.changes.dispose();
    },
  );
  testWidgets(
    'ordinary identity has no binding entry even if account endpoint would permit binding',
    (tester) async {
      final repo = _Repository()..incomeRole = IncomeRole.ordinary;
      await tester.pumpWidget(
        MaterialApp(home: WithdrawalPage(repository: repo)),
      );
      await tester.pumpAndSettle();
      expect(find.text('新增 / 更换收款账户'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      repo.changes.dispose();
    },
  );
  testWidgets(
    'binding unknown freezes full input and retries original request; close clears next flow',
    (tester) async {
      final repo = _Repository();
      await tester.pumpWidget(
        MaterialApp(home: PayoutAccountBindingPage(repository: repo)),
      );
      await tester.enterText(find.byType(TextFormField).at(0), '测试用户');
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'fixture@example.test',
      );
      await tester.tap(find.text('确认绑定'));
      await tester.pumpAndSettle();
      expect(find.text('重试原绑定'), findsOneWidget);
      expect(
        tester.widget<TextFormField>(find.byType(TextFormField).first).enabled,
        false,
      );
      await tester.tap(find.text('重试原绑定'));
      await tester.pumpAndSettle();
      expect(repo.calls[1].$2, repo.calls[0].$2);
      expect(repo.calls[1].$1.toBody(), repo.calls[0].$1.toBody());
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MaterialApp(home: PayoutAccountBindingPage(repository: repo)),
      );
      expect(find.text('重试原绑定'), findsNothing);
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox());
      repo.changes.dispose();
    },
  );
  testWidgets(
    'identity change clears entered fields and late success cannot pop current page',
    (tester) async {
      final repo = _Repository()..delayed = Completer<PayoutAccountSelection>();
      await tester.pumpWidget(
        MaterialApp(home: PayoutAccountBindingPage(repository: repo)),
      );
      await tester.enterText(find.byType(TextFormField).at(0), '测试用户');
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'fixture@example.test',
      );
      await tester.tap(find.text('确认绑定'));
      await tester.pump();
      repo.switchIdentity();
      await tester.pump();
      expect(find.byType(TextFormField), findsNothing);
      repo.delayed!.complete(await repo.fetchPayoutAccounts());
      await tester.pumpAndSettle();
      expect(find.text('登录身份已变更，请关闭后重新进入'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      repo.changes.dispose();
    },
  );
  testWidgets('withdrawal presents BOUND as user declared with binding entry', (
    tester,
  ) async {
    final repo = _Repository();
    await tester.pumpWidget(
      MaterialApp(home: WithdrawalPage(repository: repo)),
    );
    await tester.pumpAndSettle();
    expect(find.text('新增 / 更换收款账户'), findsOneWidget);
    expect(find.textContaining('已绑定 / 用户填写'), findsWidgets);
    expect(find.textContaining('已验证'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    repo.changes.dispose();
  });
  test(
    'session is invalid forever after identity switch even when user returns',
    () async {
      final repo = _Repository();
      final session = PayoutBindingSession(repo);
      const input = PayoutAccountInput(
        accountType: 'BANK_CARD',
        accountNumber: '123456789',
        holderName: '测试用户',
        bankName: '测试银行',
      );
      await expectLater(session.submit(input), throwsA(isA<ApiException>()));
      expect(session.hasPending, true);
      repo.switchIdentity();
      expect(session.hasPending, false);
      expect(session.requestId, isNull);
      await expectLater(session.submit(input), throwsA(isA<ApiException>()));
      expect(repo.calls.length, 1);
      session.dispose();
      repo.changes.dispose();
    },
  );
}
