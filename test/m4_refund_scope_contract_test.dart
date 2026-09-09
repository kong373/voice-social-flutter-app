import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../integration_test/m4_first_party_live_integration_test.dart' as live;

void main() {
  // Old strict/deferred refund positives: REMOVED_BY_PRODUCT Q15-06.
  test('both legacy profiles exclude only retired refund capabilities', () {
    final source = File(
      'integration_test/m4_first_party_live_integration_test.dart',
    ).readAsStringSync();
    const retained = {
      'commerce.gift.send',
      'commerce.withdraw.apply',
      'message.private.send',
    };
    for (final profile in ['strict', 'deferred']) {
      final scope = live.M4RefundScope(profile);
      expect(
        scope.requiredCapabilities({...retained, ...scope.removed}),
        retained,
      );
      expect(scope.removed, {
        'commerce.refund.submit',
        'commerce.refund.result',
        'commerce.refund.retry',
      });
      expect(scope.success, 'PASS_WITH_PRODUCT_REMOVALS');
    }
    expect(source, isNot(contains('.submitRefund(')));
    expect(source, isNot(contains('.resubmitRefund(')));
    expect(source, contains('M4_REMOVED_BY_PRODUCT'));
    expect(source, contains('required_mutation_not_executed'));
    expect(source, contains('required_route_outcome_missing'));
    expect(source, contains('required_authority_invariant_missing'));
    final mutationBlock = source
        .split('static const Set<String> _requiredMutationCapabilities')[1]
        .split('};')[0];
    expect(mutationBlock, isNot(contains('commerce.refund.')));
    for (final capability in retained) {
      expect(mutationBlock, contains(capability));
    }
  });

  for (final String script in <String>[
    'tool/qa/run_m4_authoritative_live_avd.sh',
    'tool/qa/aggregate_m4_authoritative_live_avd.sh',
  ]) {
    test('$script rejects missing removal evidence and retired success routes', () {
      final source = File(script).readAsStringSync();
      final validator = source.split("<<'PY'\n")[1].split('\nPY')[0];
      for (final profile in ['strict', 'deferred']) {
        final log = [
          'M4_REFUND_SCOPE::$profile',
          'M4_ACCEPTANCE::PASS_WITH_PRODUCT_REMOVALS',
          'M4_RELEASE_READINESS::NOT_RELEASE_READY',
          'M4_AUTHORITY_INVARIANT::app_refund_entry_absent',
          for (final capability in live.M4RefundScope(profile).removed)
            'M4_REMOVED_BY_PRODUCT::$capability',
        ].join('\n');
        int validate(String evidence) => Process.runSync('python3', [
          '-c',
          'import sys\nfrom pathlib import Path\nsys.argv = ["validator", "unused", "$profile", "PASS_WITH_PRODUCT_REMOVALS"]\nPath.read_text = lambda *a, **k: ${jsonEncode(evidence)}\n$validator',
        ]).exitCode;
        expect(validate(log), 0);
        expect(
          validate(
            log.replaceAll('M4_REMOVED_BY_PRODUCT::commerce.refund.retry', ''),
          ),
          isNonZero,
        );
        expect(
          validate(log.replaceAll('PASS_WITH_PRODUCT_REMOVALS', 'PASS')),
          isNonZero,
        );
        expect(
          validate(
            log.replaceAll(
              'M4_AUTHORITY_INVARIANT::app_refund_entry_absent',
              '',
            ),
          ),
          isNonZero,
        );
        expect(
          validate(
            '$log\nM4_ROUTE_STATUS::commerce.refund.submit::POST::/app-api/refund/application::200::success',
          ),
          isNonZero,
        );
      }
    });
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
