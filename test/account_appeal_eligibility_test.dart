import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/features/account/compliance/data/mock_account_compliance_repository.dart';
import 'package:voice_social_app/features/account/compliance/domain/account_compliance.dart';
import 'package:voice_social_app/features/account/compliance/presentation/account_status_pages.dart';
import 'package:voice_social_app/features/account/presentation/account_oxygen_components.dart';

void main() {
  Future<void> mount(
    WidgetTester tester,
    MockAccountComplianceRepository repo,
  ) async {
    final dependencies = AppDependencies.forTestEnvironment(
      environment: AppEnvironment.mock(),
      accountComplianceRepository: repo,
    );
    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: dependencies,
        child: const MaterialApp(home: AccountAppealPage(account: 'user7')),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(dependencies.dispose);
  }

  testWidgets(
    'submit only enables with ten trimmed characters and eligibility',
    (tester) async {
      await mount(tester, _ControlledRepository());
      AccountPrimaryAction action() => tester.widget<AccountPrimaryAction>(
        find.byType(AccountPrimaryAction),
      );
      expect(action().onPressed, isNull);
      await tester.enterText(find.byType(TextField), '          ');
      await tester.pump();
      expect(action().onPressed, isNull);
      await tester.enterText(find.byType(TextField), '123456789');
      await tester.pump();
      expect(action().onPressed, isNull);
      await tester.enterText(find.byType(TextField), ' 1234567890 ');
      await tester.pump();
      expect(action().onPressed, isNotNull);
    },
  );

  for (final lateError in [false, true]) {
    testWidgets('reason selection fences older query; late error=$lateError', (
      tester,
    ) async {
      final repo = _ControlledRepository();
      await mount(tester, repo);
      await tester.tap(find.text('内容处罚'));
      await tester.pump();
      await tester.tap(find.text('账号安全'));
      await tester.pump();
      expect(repo.reasons, ['1', '3', '1']);
      repo.pending[1].complete(_eligible('最新账号原因', '1'));
      await tester.pumpAndSettle();
      if (lateError) {
        repo.pending[0].completeError(StateError('old query failure'));
      } else {
        repo.pending[0].complete(_eligible('旧内容原因', '3'));
      }
      await tester.pumpAndSettle();
      expect(find.text('处罚原因：最新账号原因'), findsOneWidget);
      expect(find.textContaining('旧内容原因'), findsNothing);
      final selector = tester.widget<SegmentedButton<String>>(
        find.byType(SegmentedButton<String>),
      );
      expect(selector.selected, {'1'});
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'new penalty form preserves separate historical terminal record',
    (tester) async {
      await mount(
        tester,
        _ControlledRepository(
          value: AppealCase(
            account: 'user7',
            nickname: '',
            reason: '新处罚',
            reasonType: '1',
            state: AppealState.none,
            eligiblePenaltyId: 'current',
            processText: '尚未提交申诉',
            resultText: '',
            previousAppeal: const AppealCase(
              account: 'user7',
              nickname: '',
              reason: '旧处罚',
              reasonType: '1',
              state: AppealState.rejected,
              appealId: 'old',
              processText: '申诉未通过',
              resultText: '平台驳回原因',
            ),
          ),
        ),
      );
      expect(find.byType(TextField), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('历史处罚申诉'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.textContaining('平台驳回原因'), findsOneWidget);
    },
  );

  testWidgets('no penalty and no appeal has no writable form', (tester) async {
    final dependencies = AppDependencies.forTestEnvironment(
      environment: AppEnvironment.mock(),
      accountComplianceRepository: _EmptyAppealRepository(),
    );
    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: dependencies,
        child: const MaterialApp(home: AccountAppealPage(account: 'user7')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('无可申诉处罚'), findsOneWidget);
    expect(find.text('提交申诉'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining('待平台返回'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    dependencies.dispose();
  });
}

AppealCase _eligible(String reason, String reasonType) => AppealCase(
  account: 'user7',
  nickname: '',
  reason: reason,
  reasonType: reasonType,
  state: AppealState.none,
  eligiblePenaltyId: 'current',
  processText: '尚未提交申诉',
  resultText: '',
);

class _ControlledRepository extends MockAccountComplianceRepository {
  _ControlledRepository({this.value});
  final AppealCase? value;
  final reasons = <String>[];
  final pending = <Completer<AppealCase>>[];
  @override
  Future<AppealCase> queryAppeal({
    required String account,
    required String reasonType,
  }) {
    reasons.add(reasonType);
    if (reasons.length == 1)
      return Future.value(value ?? _eligible('初始原因', reasonType));
    final result = Completer<AppealCase>();
    pending.add(result);
    return result.future;
  }
}

class _EmptyAppealRepository extends MockAccountComplianceRepository {
  @override
  Future<AppealCase> queryAppeal({
    required String account,
    required String reasonType,
  }) async => AppealCase(
    account: account,
    nickname: '当前用户',
    reason: '',
    reasonType: reasonType,
    state: AppealState.none,
    processText: '尚未提交申诉',
    resultText: '',
  );
}
