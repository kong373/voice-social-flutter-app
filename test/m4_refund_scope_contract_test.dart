import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/features/commerce/domain/commerce_models.dart';

import '../integration_test/m4_first_party_live_integration_test.dart' as live;

void main() {
  const RefundEligibility denied = RefundEligibility(
    allowed: false,
    existingApplicationId: null,
    message: 'Provider unavailable',
  );

  test(
    'strict executes original operation; deferred performs zero writes',
    () async {
      int submissions = 0;
      int retries = 0;
      Future<void> operation() async {
        submissions++;
        retries++;
      }

      final live.M4RefundScope strict = live.M4RefundScope('strict');
      expect(await strict.runRefund(denied, operation), false);
      expect(submissions, 1);
      expect(retries, 1);
      expect(strict.success, 'PASS');
      expect(strict.exemptions, isEmpty);
      final live.M4RefundScope deferred = live.M4RefundScope('deferred');
      expect(await deferred.runRefund(denied, operation), true);
      expect(submissions, 1);
      expect(retries, 1);
      expect(deferred.success, 'PASS_WITH_EXEMPTIONS');
      for (final RefundEligibility invalid in <RefundEligibility>[
        const RefundEligibility(
          allowed: true,
          existingApplicationId: null,
          message: 'allowed',
        ),
        const RefundEligibility(
          allowed: false,
          existingApplicationId: 'old',
          message: '',
        ),
      ]) {
        await expectLater(
          deferred.runRefund(invalid, operation),
          throwsA(isA<TestFailure>()),
        );
      }
      expect(submissions, 1);
      expect(retries, 1);
    },
  );

  test('scope retains every other capability and strict mutations', () {
    final String source = File(
      'integration_test/m4_first_party_live_integration_test.dart',
    ).readAsStringSync();
    final String block = source
        .split('static const Set<String> _requiredMutationCapabilities')[1]
        .split('};')[0];
    final Set<String> strict = RegExp(
      r"'([a-z_.]+)'",
    ).allMatches(block).map((Match m) => m[1]!).toSet();
    expect(
      strict,
      containsAll(<String>['commerce.refund.submit', 'commerce.refund.result']),
    );
    expect(live.M4RefundScope('strict').requiredCapabilities(strict), strict);
    final Set<String> scoped = live.M4RefundScope(
      'deferred',
    ).requiredCapabilities(strict);
    expect(strict.difference(scoped), <String>{
      'commerce.refund.submit',
      'commerce.refund.result',
    });
    expect(
      scoped,
      containsAll(<String>[
        'commerce.gift.send',
        'commerce.withdraw.apply',
        'message.private.send',
      ]),
    );
    expect(source, contains('required_mutation_not_executed'));
    expect(source, contains('required_route_outcome_missing'));
    expect(source, contains('required_authority_invariant_missing'));
    expect(source, contains("defaultValue: 'strict'"));
    final String wrapper = source
        .split('Future<void> _runRefundMutation(')[1]
        .split('Future<void> _runStrictRefundMutation(')[0];
    expect(wrapper, contains('await _refundScope.runRefund('));
    expect(wrapper, isNot(contains('.submitRefund(')));
    expect(wrapper, isNot(contains('.resubmitRefund(')));
  });

  for (final String script in <String>[
    'tool/qa/run_m4_authoritative_live_avd.sh',
    'tool/qa/aggregate_m4_authoritative_live_avd.sh',
  ]) {
    test(
      '$script scope parser defaults strict and rejects unknown before work',
      () {
        final String source = File(script).readAsStringSync();
        final String block = source.substring(
          source.indexOf('parse_refund_scope() {'),
          source.indexOf('# Validate profile evidence'),
        );
        final Map<String, String> environment = <String, String>{
          'PATH': '/usr/bin:/bin',
        };
        ProcessResult parse(String? value) => Process.runSync(
          '/bin/bash',
          <String>['-c', '$block\nprintf "%s" "\$REFUND_SCOPE"'],
          environment: <String, String>{
            ...environment,
            if (value != null) 'QA_M4_REFUND_SCOPE': value,
          },
          includeParentEnvironment: false,
        );
        expect(parse(null).stdout, 'strict');
        expect(parse('strict').stdout, 'strict');
        expect(parse('deferred').stdout, 'deferred');
        for (final String invalid in <String>[
          '',
          'skip',
          'DEFERRED',
          'deferred ',
        ]) {
          expect(() => live.M4RefundScope(invalid), throwsArgumentError);
          expect(parse(invalid).exitCode, 64);
          final ProcessResult result = Process.runSync(
            '/bin/bash',
            <String>[script],
            environment: <String, String>{
              ...environment,
              'QA_M4_REFUND_SCOPE': invalid,
            },
            includeParentEnvironment: false,
          );
          expect(result.exitCode, 64);
          expect(
            result.stderr,
            contains('QA_M4_REFUND_SCOPE must be strict or deferred'),
          );
        }
      },
    );
  }
}
