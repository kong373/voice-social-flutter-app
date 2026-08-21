import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final String preflightTool = File(
    'tool/m3_live_preflight.dart',
  ).readAsStringSync();
  final String hostedWorkflow = File(
    '.github/workflows/m3-live-contract-preflight.yml',
  ).readAsStringSync();
  final String selfHostedWorkflow = File(
    '.github/workflows/m3-self-hosted-development-preflight.yml',
  ).readAsStringSync();
  final String readinessDocumentation = File(
    'docs/m3-live-backend-readiness.md',
  ).readAsStringSync();

  test('preflight tool never accepts or forwards a client secret', () {
    expect(preflightTool, isNot(contains('M3_OAUTH_CLIENT_SECRET')));
    expect(preflightTool, isNot(contains('oauthClientSecret')));
    expect(preflightTool, contains("values['M3_OAUTH_CLIENT_ID']"));
  });

  test('both preflight workflows use only the public client configuration', () {
    for (final String workflow in <String>[
      hostedWorkflow,
      selfHostedWorkflow,
    ]) {
      expect(workflow, contains('M3_API_BASE_URL:'));
      expect(workflow, contains('M3_OAUTH_CLIENT_ID:'));
      expect(workflow, isNot(contains('M3_OAUTH_CLIENT_SECRET')));
      expect(workflow, isNot(contains('oauthClientSecret')));
    }
  });

  test('preflight workflows pin actions to immutable commits', () {
    expect(
      hostedWorkflow,
      contains(
        'actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2',
      ),
    );
    expect(
      hostedWorkflow,
      contains(
        'subosito/flutter-action@fd55f4c5af5b953cc57a2be44cb082c8f6635e8e # v2.21.0',
      ),
    );
    expect(
      hostedWorkflow,
      contains(
        'actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02 # v4.6.2',
      ),
    );
    expect(
      selfHostedWorkflow,
      contains(
        'actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2',
      ),
    );
    expect(
      selfHostedWorkflow,
      contains(
        'actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02 # v4.6.2',
      ),
    );
    expect(hostedWorkflow, isNot(contains('uses: actions/checkout@v4')));
    expect(hostedWorkflow, isNot(contains('uses: subosito/flutter-action@v2')));
    expect(hostedWorkflow, isNot(contains('uses: actions/upload-artifact@v4')));
    expect(selfHostedWorkflow, isNot(contains('uses: actions/checkout@v4')));
    expect(
      selfHostedWorkflow,
      isNot(contains('uses: actions/upload-artifact@v4')),
    );
  });

  test(
    'self-hosted preflight allows insecure HTTP only for private development hosts',
    () {
      expect(
        selfHostedWorkflow,
        contains('M3_ALLOW_PRIVATE_HTTP_ONLY: "true"'),
      );
      expect(
        preflightTool,
        contains('''values['M3_ALLOW_PRIVATE_HTTP_ONLY']'''),
      );
      expect(
        preflightTool,
        contains('HTTP 仅允许 loopback 或 private development host'),
      );
      expect(preflightTool, contains('_isLoopbackHost(host)'));
      expect(preflightTool, contains('_isPrivateDevelopmentHost(host)'));
    },
  );

  test('self-hosted preflight uploads only allowlisted redacted evidence', () {
    expect(
      selfHostedWorkflow,
      contains(
        r'''health_body_tmp="$(mktemp "$RUNNER_TEMP/m3-health-body.XXXXXX.json")"''',
      ),
    );
    expect(
      selfHostedWorkflow,
      contains(
        r'''jq '{code, data: {status: .data.status, environment: .data.environment}}' \''',
      ),
    );
    expect(
      selfHostedWorkflow,
      contains(r'${{ env.EVIDENCE_DIR }}/backend-health-summary.json'),
    );
    expect(
      selfHostedWorkflow,
      contains(r'${{ env.EVIDENCE_DIR }}/flutter-preflight-redacted.json'),
    );
    expect(selfHostedWorkflow, isNot(contains('backend-health.json')));
    expect(readinessDocumentation, contains('private development host'));
    expect(
      readinessDocumentation,
      contains('allowlisted redacted evidence files'),
    );
  });

  test('readiness documentation names only public client inputs', () {
    expect(readinessDocumentation, contains('M3_API_BASE_URL'));
    expect(readinessDocumentation, contains('M3_OAUTH_CLIENT_ID'));
    expect(readinessDocumentation, contains('public client'));
    expect(readinessDocumentation, contains('secret is backend-only'));
    expect(readinessDocumentation, isNot(contains('M3_OAUTH_CLIENT_SECRET')));
    expect(readinessDocumentation, isNot(contains('OAUTH_CLIENT_SECRET')));
  });
}
