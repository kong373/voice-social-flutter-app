import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:voice_social_app/app/app_environment.dart';

enum LiveBackendReadinessStatus {
  mockMode,
  configurationInvalid,
  gatewayReachable,
  networkUnavailable,
  tlsRejected,
  timedOut,
  unexpectedFailure,
}

extension LiveBackendReadinessStatusLabel on LiveBackendReadinessStatus {
  String get label => switch (this) {
        LiveBackendReadinessStatus.mockMode => 'Mock 模式',
        LiveBackendReadinessStatus.configurationInvalid => '配置无效',
        LiveBackendReadinessStatus.gatewayReachable => '网关可达',
        LiveBackendReadinessStatus.networkUnavailable => '网络不可达',
        LiveBackendReadinessStatus.tlsRejected => 'TLS 校验失败',
        LiveBackendReadinessStatus.timedOut => '连接超时',
        LiveBackendReadinessStatus.unexpectedFailure => '探测失败',
      };
}

class GatewayProbeResult {
  const GatewayProbeResult({
    required this.status,
    required this.message,
    required this.checkedAt,
    this.latency,
    this.httpStatus,
  });

  final LiveBackendReadinessStatus status;
  final String message;
  final DateTime checkedAt;
  final Duration? latency;
  final int? httpStatus;
}

abstract interface class GatewayProbe {
  Future<GatewayProbeResult> probe(AppEnvironment environment);
}

class HttpGatewayProbe implements GatewayProbe {
  const HttpGatewayProbe();

  @override
  Future<GatewayProbeResult> probe(AppEnvironment environment) async {
    final Uri target = environment.apiBaseUri!.resolve(
      environment.liveProbePath,
    );
    final Stopwatch stopwatch = Stopwatch()..start();
    final HttpClient client = HttpClient()
      ..connectionTimeout = environment.apiTimeout;
    try {
      final HttpClientRequest request =
          await client.getUrl(target).timeout(environment.apiTimeout);
      request.followRedirects = false;
      request.headers
        ..set(HttpHeaders.acceptHeader, 'application/json')
        ..set('Client-Type', environment.clientType)
        ..set('Client-Inner-Version', environment.clientInnerVersion)
        ..set('Client-Id', environment.oauthClientId);
      final HttpClientResponse response =
          await request.close().timeout(environment.apiTimeout);
      await response.drain<void>().timeout(environment.apiTimeout);
      stopwatch.stop();
      return GatewayProbeResult(
        status: LiveBackendReadinessStatus.gatewayReachable,
        message: '网关已返回 HTTP ${response.statusCode}，传输链路可达。',
        checkedAt: DateTime.now().toUtc(),
        latency: stopwatch.elapsed,
        httpStatus: response.statusCode,
      );
    } on HandshakeException {
      stopwatch.stop();
      return GatewayProbeResult(
        status: LiveBackendReadinessStatus.tlsRejected,
        message: 'HTTPS 证书或 TLS 握手未通过，未绕过系统安全校验。',
        checkedAt: DateTime.now().toUtc(),
        latency: stopwatch.elapsed,
      );
    } on TimeoutException {
      stopwatch.stop();
      return GatewayProbeResult(
        status: LiveBackendReadinessStatus.timedOut,
        message: '网关在 ${environment.apiTimeout.inSeconds} 秒内没有响应。',
        checkedAt: DateTime.now().toUtc(),
        latency: stopwatch.elapsed,
      );
    } on SocketException {
      stopwatch.stop();
      return GatewayProbeResult(
        status: LiveBackendReadinessStatus.networkUnavailable,
        message: 'DNS、路由或网络连接失败。',
        checkedAt: DateTime.now().toUtc(),
        latency: stopwatch.elapsed,
      );
    } on HttpException {
      stopwatch.stop();
      return GatewayProbeResult(
        status: LiveBackendReadinessStatus.networkUnavailable,
        message: 'HTTP 连接在收到有效响应前中断。',
        checkedAt: DateTime.now().toUtc(),
        latency: stopwatch.elapsed,
      );
    } catch (_) {
      stopwatch.stop();
      return GatewayProbeResult(
        status: LiveBackendReadinessStatus.unexpectedFailure,
        message: '网关探测发生未分类错误，详情仅保留在受控诊断日志中。',
        checkedAt: DateTime.now().toUtc(),
        latency: stopwatch.elapsed,
      );
    } finally {
      client.close(force: true);
    }
  }
}

class LiveBackendReadinessSnapshot {
  const LiveBackendReadinessSnapshot({
    required this.status,
    required this.message,
    required this.checkedAt,
    required this.deploymentEnvironment,
    required this.apiOrigin,
    required this.probePath,
    required this.publicClientConfigured,
    required this.developmentOutboxConfigured,
    required this.realtimeEndpointConfigured,
    this.latency,
    this.httpStatus,
  });

  final LiveBackendReadinessStatus status;
  final String message;
  final DateTime checkedAt;
  final DeploymentEnvironment deploymentEnvironment;
  final String apiOrigin;
  final String probePath;
  final bool publicClientConfigured;
  final bool developmentOutboxConfigured;
  final bool realtimeEndpointConfigured;
  final Duration? latency;
  final int? httpStatus;

  @Deprecated('Use publicClientConfigured.')
  bool get oauthClientIdConfigured => publicClientConfigured;

  @Deprecated('Mobile public clients never carry a secret.')
  bool get oauthClientSecretConfigured => false;

  bool get canAttemptAuthentication =>
      status == LiveBackendReadinessStatus.gatewayReachable &&
      publicClientConfigured;

  Map<String, Object?> toRedactedJson() => <String, Object?>{
        'status': status.name,
        'statusLabel': status.label,
        'message': message,
        'checkedAt': checkedAt.toIso8601String(),
        'deploymentEnvironment': deploymentEnvironment.name,
        'apiOrigin': apiOrigin,
        'probePath': probePath,
        'publicClientConfigured': publicClientConfigured,
        'mobileClientSecretPresent': false,
        'developmentOutboxConfigured': developmentOutboxConfigured,
        'realtimeEndpointConfigured': realtimeEndpointConfigured,
        'latencyMs': latency?.inMilliseconds,
        'httpStatus': httpStatus,
        'canAttemptAuthentication': canAttemptAuthentication,
      };

  String toRedactedText() =>
      const JsonEncoder.withIndent('  ').convert(toRedactedJson());
}

class LiveBackendReadinessService {
  LiveBackendReadinessService({
    required this.environment,
    GatewayProbe? gatewayProbe,
  }) : _gatewayProbe = gatewayProbe ?? const HttpGatewayProbe();

  final AppEnvironment environment;
  final GatewayProbe _gatewayProbe;

  Future<LiveBackendReadinessSnapshot> check() async {
    if (!environment.isLive) {
      return _snapshot(
        status: LiveBackendReadinessStatus.mockMode,
        message: '当前使用本地 Mock Repository，未发起任何网络探测。',
        checkedAt: DateTime.now().toUtc(),
      );
    }

    try {
      environment.validateLiveConfiguration();
    } on StateError catch (error) {
      return _snapshot(
        status: LiveBackendReadinessStatus.configurationInvalid,
        message: error.message.toString(),
        checkedAt: DateTime.now().toUtc(),
      );
    }

    final GatewayProbeResult result = await _gatewayProbe.probe(environment);
    return _snapshot(
      status: result.status,
      message: result.message,
      checkedAt: result.checkedAt,
      latency: result.latency,
      httpStatus: result.httpStatus,
    );
  }

  LiveBackendReadinessSnapshot _snapshot({
    required LiveBackendReadinessStatus status,
    required String message,
    required DateTime checkedAt,
    Duration? latency,
    int? httpStatus,
  }) {
    final Map<String, Object?> summary = environment.redactedSummary;
    return LiveBackendReadinessSnapshot(
      status: status,
      message: message,
      checkedAt: checkedAt,
      deploymentEnvironment: environment.deploymentEnvironment,
      apiOrigin: environment.redactedApiOrigin,
      probePath: environment.liveProbePath,
      publicClientConfigured:
          summary['oauthClientIdConfigured'] as bool? ?? false,
      developmentOutboxConfigured:
          summary['developmentOutboxConfigured'] as bool? ?? false,
      realtimeEndpointConfigured:
          summary['realtimeEndpointConfigured'] as bool? ?? false,
      latency: latency,
      httpStatus: httpStatus,
    );
  }
}
