import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/network/live_backend_readiness.dart';
import 'package:voice_social_app/features/account/presentation/live_backend_readiness_page.dart';

void main() {
  testWidgets('live readiness page renders only redacted gateway evidence', (
    WidgetTester tester,
  ) async {
    final AppEnvironment environment = AppEnvironment(
      backendMode: BackendMode.live,
      apiBaseUrl: 'https://dev.example.com/private/gateway/',
      clientType: 'Android',
      clientInnerVersion: '6',
      oauthClientId: 'client-id-value',
      oauthClientSecret: 'secret-value',
      realtimeEndpoint: '',
      deploymentEnvironment: DeploymentEnvironment.development,
    );
    final LiveBackendReadinessService service = LiveBackendReadinessService(
      environment: environment,
      gatewayProbe: _FakeGatewayProbe(),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: LiveBackendReadinessPage(service: service),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('开发环境联调诊断'), findsOneWidget);
    expect(find.text('网关可达'), findsOneWidget);
    expect(find.text('https://dev.example.com'), findsOneWidget);

    final Finder businessBoundary =
        find.textContaining('不等于短信、登录、首页');
    await tester.scrollUntilVisible(
      businessBoundary,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    expect(businessBoundary, findsOneWidget);

    final Finder vendorBoundary = find.textContaining('VENDOR_BLOCKED');
    await tester.scrollUntilVisible(
      vendorBoundary,
      160,
      scrollable: find.byType(Scrollable).first,
    );
    expect(vendorBoundary, findsOneWidget);

    expect(find.textContaining('secret-value'), findsNothing);
    expect(find.textContaining('client-id-value'), findsNothing);
    expect(find.textContaining('/private/gateway/'), findsNothing);
  });
}

class _FakeGatewayProbe implements GatewayProbe {
  @override
  Future<GatewayProbeResult> probe(AppEnvironment environment) async {
    return GatewayProbeResult(
      status: LiveBackendReadinessStatus.gatewayReachable,
      message: '网关已返回 HTTP 401，传输链路可达。',
      checkedAt: DateTime.utc(2026, 8, 17),
      latency: const Duration(milliseconds: 73),
      httpStatus: 401,
    );
  }
}
