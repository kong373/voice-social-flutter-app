import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_environment.dart';
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
}

AppEnvironment _liveEnvironment({bool enableAgoraRtc = false}) {
  return AppEnvironment(
    backendMode: BackendMode.live,
    apiBaseUrl: 'http://127.0.0.1:18080/',
    clientType: 'Android',
    clientInnerVersion: '6',
    oauthClientId: 'public-client',
    realtimeEndpoint: '',
    deploymentEnvironment: DeploymentEnvironment.development,
    allowInsecureHttp: true,
    enableAgoraRtc: enableAgoraRtc,
  );
}
