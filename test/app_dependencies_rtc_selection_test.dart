import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/features/commerce/infrastructure/alipay_app_pay_adapter.dart';
import 'package:voice_social_app/features/room/infrastructure/rtc_adapter.dart';

void main() {
  test('live dependencies opt into Agora only with the explicit switch', () {
    final AppDependencies dependencies = AppDependencies.forTestEnvironment(
      environment: _liveEnvironment(enableAgoraRtc: true),
    );

    expect(dependencies.environment.enableAgoraRtc, isTrue);
    expect(dependencies.rtcAdapter, isA<AgoraRtcAdapter>());
  });

  test('live dependencies stay snapshot-only when the switch is omitted', () {
    final AppDependencies dependencies = AppDependencies.forTestEnvironment(
      environment: _liveEnvironment(),
    );

    expect(dependencies.environment.enableAgoraRtc, isFalse);
    expect(dependencies.rtcAdapter, isA<SnapshotOnlyRtcAdapter>());
  });

  test(
    'live development dependencies pass the Alipay sandbox mode to the adapter',
    () {
      final AppDependencies dependencies = AppDependencies.forTestEnvironment(
        environment: _liveEnvironment(enableAlipayAppPay: true),
      );

      expect(
        dependencies.alipayAppPayAdapter,
        isA<MethodChannelAlipayAppPayAdapter>(),
      );
      final MethodChannelAlipayAppPayAdapter adapter =
          dependencies.alipayAppPayAdapter as MethodChannelAlipayAppPayAdapter;
      expect(adapter.sandboxMode, isTrue);
    },
  );

  test('live staging dependencies never pass Alipay sandbox mode', () {
    final AppDependencies dependencies = AppDependencies.forTestEnvironment(
      environment: _liveEnvironment(
        deployment: DeploymentEnvironment.staging,
        enableAlipayAppPay: true,
      ),
    );

    final MethodChannelAlipayAppPayAdapter adapter =
        dependencies.alipayAppPayAdapter as MethodChannelAlipayAppPayAdapter;
    expect(adapter.sandboxMode, isFalse);
  });
}

AppEnvironment _liveEnvironment({
  bool enableAgoraRtc = false,
  bool enableAlipayAppPay = false,
  DeploymentEnvironment deployment = DeploymentEnvironment.development,
}) {
  return AppEnvironment(
    backendMode: BackendMode.live,
    apiBaseUrl: 'http://127.0.0.1:18080/',
    clientType: 'Android',
    clientInnerVersion: '6',
    oauthClientId: 'public-client',
    realtimeEndpoint: '',
    deploymentEnvironment: deployment,
    allowInsecureHttp: true,
    enableAgoraRtc: enableAgoraRtc,
    enableAlipayAppPay: enableAlipayAppPay,
  );
}
