import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/features/shell/live_read_only_repository.dart';
import 'package:voice_social_app/features/shell/live_vendor_boundary_page.dart';

void main() {
  testWidgets(
    'readiness page renders all six formal capabilities and keeps them blocked',
    (WidgetTester tester) async {
      final _FakeReadinessRepository repository = _FakeReadinessRepository(
        _readinessOverview(),
      );
      await _pumpPage(tester, repository);

      expect(find.byKey(const Key('vendor-readiness-summary')), findsOneWidget);
      expect(find.text('运行状态：VENDOR_BLOCKED'), findsOneWidget);
      expect(find.text('所有运行时适配器均已配置，可以开始厂商沙箱联调。'), findsNothing);

      for (final (String capability, String label) in <(String, String)>[
        ('SMS', '短信'),
        ('RTC', '实时语音 RTC'),
        ('IM', '腾讯 IM'),
        ('PAYMENT', '支付'),
        ('PUSH', '推送'),
        ('OBJECT_STORAGE', '对象存储'),
      ]) {
        final Finder card = find.byKey(
          Key('vendor-${_capabilityKey(capability)}-status'),
        );
        await tester.scrollUntilVisible(
          card,
          240,
          scrollable: find.byType(Scrollable).first,
        );
        expect(card, findsOneWidget);
        expect(find.text(label), findsOneWidget);
        expect(find.text('运行时：VENDOR_BLOCKED'), findsWidgets);
      }

      expect(repository.fetchCount, 1);
    },
  );

  testWidgets(
    'missing capability is visible as an explicit fail-closed state',
    (WidgetTester tester) async {
      final VendorReadinessOverview overview = _readinessOverview();
      final Map<String, VendorCapabilityReadiness> capabilities =
          <String, VendorCapabilityReadiness>{...overview.capabilities}
            ..remove('PUSH');
      final _FakeReadinessRepository repository = _FakeReadinessRepository(
        VendorReadinessOverview(
          contractVersion: overview.contractVersion,
          integrationStatus: overview.integrationStatus,
          runtimeStatus: overview.runtimeStatus,
          allBoundariesReady: overview.allBoundariesReady,
          allRuntimeAdaptersReady: overview.allRuntimeAdaptersReady,
          capabilities: capabilities,
        ),
      );
      await _pumpPage(tester, repository);

      final Finder missingCard = find.byKey(const Key('vendor-push-status'));
      await tester.scrollUntilVisible(
        missingCard,
        240,
        scrollable: find.byType(Scrollable).first,
      );
      expect(missingCard, findsOneWidget);
      expect(find.text('推送'), findsOneWidget);
      expect(find.text('服务端未返回该正式能力，已安全阻断。'), findsWidgets);
      expect(find.text('运行时：UNKNOWN（已阻断）'), findsOneWidget);
      expect(find.text('运行时已启用'), findsNothing);
    },
  );

  testWidgets(
    'blocked capability statuses override an inconsistent top-level ready flag',
    (WidgetTester tester) async {
      final VendorReadinessOverview overview = _readinessOverview();
      final _FakeReadinessRepository repository = _FakeReadinessRepository(
        VendorReadinessOverview(
          contractVersion: overview.contractVersion,
          integrationStatus: overview.integrationStatus,
          runtimeStatus: 'READY',
          allBoundariesReady: overview.allBoundariesReady,
          allRuntimeAdaptersReady: true,
          capabilities: overview.capabilities,
        ),
      );
      await _pumpPage(tester, repository);

      expect(find.text('所有运行时适配器均已配置，可以开始厂商沙箱联调。'), findsNothing);
      expect(find.text('运行时仍被阻断；可以安全提交厂商凭证和适配器实现，不会误触发生产调用。'), findsOneWidget);
      expect(find.text('已禁用'), findsWidgets);
    },
  );

  testWidgets(
    'unknown runtime status remains disabled instead of becoming ready',
    (WidgetTester tester) async {
      final VendorReadinessOverview overview = _readinessOverview();
      final VendorCapabilityReadiness sms = overview.capabilities['SMS']!;
      final Map<String, VendorCapabilityReadiness> capabilities =
          <String, VendorCapabilityReadiness>{
            ...overview.capabilities,
            'SMS': VendorCapabilityReadiness(
              capability: sms.capability,
              boundaryStatus: sms.boundaryStatus,
              runtimeStatus: 'UNRECOGNIZED',
              provider: sms.provider,
              missingConfiguration: sms.missingConfiguration,
              serverOnlySecretProperties: sms.serverOnlySecretProperties,
              adapterContract: sms.adapterContract,
              securityBoundary: sms.securityBoundary,
            ),
          };
      final _FakeReadinessRepository repository = _FakeReadinessRepository(
        VendorReadinessOverview(
          contractVersion: overview.contractVersion,
          integrationStatus: overview.integrationStatus,
          runtimeStatus: overview.runtimeStatus,
          allBoundariesReady: overview.allBoundariesReady,
          allRuntimeAdaptersReady: overview.allRuntimeAdaptersReady,
          capabilities: capabilities,
        ),
      );
      await _pumpPage(tester, repository);

      final Finder smsCard = find.byKey(const Key('vendor-sms-status'));
      await tester.scrollUntilVisible(
        smsCard,
        240,
        scrollable: find.byType(Scrollable).first,
      );
      expect(smsCard, findsOneWidget);
      expect(find.text('运行时：UNRECOGNIZED（已阻断）'), findsOneWidget);
      expect(find.text('运行时已启用'), findsNothing);
    },
  );
}

Future<void> _pumpPage(
  WidgetTester tester,
  _FakeReadinessRepository repository,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      home: LiveVendorBoundaryPage(
        dependencies: AppDependencies.mock(),
        repository: repository,
      ),
    ),
  );
  await tester.pump();
  await tester.pumpAndSettle();
}

VendorReadinessOverview _readinessOverview() {
  final Map<String, VendorCapabilityReadiness> capabilities = {
    for (final String capability in <String>[
      'SMS',
      'RTC',
      'IM',
      'PAYMENT',
      'PUSH',
      'OBJECT_STORAGE',
    ])
      capability: VendorCapabilityReadiness(
        capability: capability,
        boundaryStatus: 'READY',
        runtimeStatus: 'VENDOR_BLOCKED',
        provider: 'UNCONFIGURED',
        missingConfiguration: const <String>['adapter-implementation'],
        serverOnlySecretProperties: const <String>[],
        adapterContract: 'VendorPorts.${capability}Port',
        securityBoundary: 'All secret values remain server-side.',
      ),
  };
  return VendorReadinessOverview(
    contractVersion: 'vendor-boundary-v2',
    integrationStatus: 'READY_FOR_PROVIDER_INTEGRATION',
    runtimeStatus: 'VENDOR_BLOCKED',
    allBoundariesReady: true,
    allRuntimeAdaptersReady: false,
    capabilities: capabilities,
  );
}

String _capabilityKey(String capability) =>
    capability.toLowerCase().replaceAll('_', '-');

class _FakeReadinessRepository extends LiveReadOnlyRepository {
  _FakeReadinessRepository(this.overview)
    : super(
        ApiClient(
          baseUri: Uri.parse('http://stub.invalid/'),
          clientType: 'Android',
          clientInnerVersion: '1',
          authorizationProvider: () => null,
        ),
      );

  final VendorReadinessOverview overview;
  int fetchCount = 0;

  @override
  Future<VendorReadinessOverview> fetchVendorReadiness() async {
    fetchCount += 1;
    return overview;
  }
}
