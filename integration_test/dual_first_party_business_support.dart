import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/features/account/domain/auth_models.dart';

/// Private, short-lived host relay contract (not a business proxy):
/// - Shared defines: DUAL_RELAY_PORT=<ephemeral port>, BACKEND_MODE=live,
///   APP_ENV=local|development, API_BASE_URL=http://10.0.2.2:28080/ on Android
///   or http://127.0.0.1:28080/ on iOS Simulator,
///   ALLOW_INSECURE_HTTP=true. All vendor/formal flags must be false.
///   DUAL_EXPECTED_FLUTTER_SHA and DUAL_EXPECTED_BACKEND_SHA are required
///   public full 40-character lowercase Git SHAs, exactly matching config.
/// - Host provisions a distinct random bearer per device in app-private cache
///   `dual-runtime-relay-token` (0600); never argv, defines, screenshots or logs.
///   Beside it, provision `dual-runtime-role` (0600), containing A or B (an
///   optional trailing newline is allowed). Missing/invalid roles fail closed;
///   config.role must exactly match this device-local role. No role define.
///   For Android pairs build one APK and use that SAME binary on both devices
///   with flutter drive --use-application-binary; SHA and relay-port defines
///   are shared. For Android/iOS pairs build from the same Flutter Git SHA,
///   with platform-specific API_BASE_URL and the same public expected SHAs.
///   Host config.apiBaseUrl must match each receiving platform. Remove both
///   private runtime files in finally. Never put runtime sessions in defines.
/// - GET /dual/config, Authorization: Bearer <private token>, returns JSON:
///   {role, runId, expiresAt, apiBaseUrl, oauthClientId, clientType,
///    clientInnerVersion, session: <AuthSession.toJson>, peerUserId, roomId,
///    peerPostId, flutterSha, backendSha}. Session/client values exist only in
///   protected runtime memory. Reports contain runId and both public SHAs only.
/// - POST /dual/barrier body {runId, role, phase}; return immediately with
///   {runId, phase, released: bool}. Polling is idempotent, bounded at 90s.
///   Only two DISTINCT authenticated roles in this run release a phase.
///   Phases: joined, seated, public-sent, reentry-off-mic, reentry-left,
///   manual_room_reentry, gift-seated, gift-A, gift-B,
///   off-mic, ten private-ready-N/private-received-N pairs, complete.
///   Host records the ready release BEFORE either UI send and each peer-visible
///   acknowledgement AFTER observation on one monotonic clock. The difference
///   is an upper bound, not a cross-device wall-clock estimate. Require twenty
///   distinct samples <= 5s for HTTP-fallback latency acceptance.
///   Reject unknown/out-of-order phases.
/// - Bind loopback only; reject redirects, expired/reused runs, role/token
///   mismatch; disable access/body logs; no business endpoints on this relay.
///   Run TTL <= 20 minutes; abort both drives on either failure; delete tokens,
///   revoke sessions and stop relay in host finally, including timeout.
/// - Prepare two fresh distinct users with reciprocal peer IDs, same empty
///   DIRECT room, available seats 1/2, snapshot-only transport, seeded gift
///   00000000-0000-0000-0000-000000002001 enabled
///   in its catalog category, enough gift coins, no following/block relation,
///   one visible unliked post per peer. No third participant or concurrent
///   wallet mutation. Relay verifies these before serving either config.
/// - Business writes happen ONLY inside production page callbacks. Public
///   history and seats must automatically converge before any room reentry;
///   manual_room_reentry is a separate persistence/recovery scenario. Private
///   history requires automatic_http_sync_no_navigation. Disabled RTC/IM never PASS.
///   Host accepts only TWO successful drive results.
const dualBackend = 'http://10.0.2.2:28080/';

enum DualPlatform { android, ios }

/// QA only. iOS host files: $(xcrun simctl get_app_container <UDID>
/// com.kong373.voiceSocialApp data)/tmp/dual-runtime-{role,relay-token}.
/// Provision both as regular files with mode 0600 and remove in host finally.
/// Android and iOS builds share expected SHAs and relay port; API_BASE_URL
/// must match the platform below, as must the host's per-device runtime config.
class DualPlatformSupport {
  const DualPlatformSupport._(this.platform);
  final DualPlatform platform;

  static DualPlatformSupport current() {
    if (Platform.isAndroid)
      return const DualPlatformSupport._(DualPlatform.android);
    if (Platform.isIOS) return const DualPlatformSupport._(DualPlatform.ios);
    throw StateError('Unsupported dual runtime platform.');
  }

  @visibleForTesting
  factory DualPlatformSupport.forTest(DualPlatform platform) {
    _requireUnitTest();
    return DualPlatformSupport._(platform);
  }

  String get relayHost =>
      platform == DualPlatform.android ? '10.0.2.2' : '127.0.0.1';
  String get backend => 'http://$relayHost:28080/';
  String runtimePath(String name) {
    if (!{'dual-runtime-role', 'dual-runtime-relay-token'}.contains(name)) {
      throw StateError('Invalid private runtime file.');
    }
    final directory = platform == DualPlatform.android
        ? '/data/user/0/com.kong373.voice_social_app/cache'
        : Directory.systemTemp.path.replaceFirst(RegExp(r'/+$'), '');
    return '$directory/$name';
  }
}

void _requireUnitTest() {
  if (kReleaseMode ||
      Platform.isAndroid ||
      Platform.isIOS ||
      Platform.environment['FLUTTER_TEST'] != 'true') {
    throw StateError('Dual test injection is restricted to host unit tests.');
  }
}

DualPlatformSupport _platform(DualPlatformSupport? injected) {
  if (injected == null) return DualPlatformSupport.current();
  _requireUnitTest();
  return injected;
}

Future<String> _readPrivateRuntime(String name) async {
  final path = DualPlatformSupport.current().runtimePath(name);
  if (await FileSystemEntity.type(path, followLinks: false) !=
          FileSystemEntityType.file ||
      (await File(path).stat()).mode & 0x1ff != 0x180) {
    throw StateError('Invalid private runtime file.');
  }
  return File(path).readAsString();
}

Future<String> readDualRuntimeToken({Future<String> Function()? read}) async {
  try {
    if (read != null) _requireUnitTest();
    final token =
        (await (read ??
                () => _readPrivateRuntime('dual-runtime-relay-token'))())
            .trim();
    if (token.length < 32 || token.contains(RegExp(r'\s')))
      throw StateError('invalid');
    return token;
  } catch (_) {
    throw StateError('Missing or invalid private dual runtime token.');
  }
}

Future<String> readDualRuntimeRole({Future<String> Function()? read}) async {
  try {
    if (read != null) _requireUnitTest();
    final contents =
        await (read ?? () => _readPrivateRuntime('dual-runtime-role'))();
    if (!RegExp(r'^[AB](?:\r?\n)?$').hasMatch(contents)) {
      throw StateError('invalid role');
    }
    return contents.trim();
  } catch (_) {
    throw StateError('Missing or invalid private dual runtime role.');
  }
}

final List<String> dualPhases = List<String>.unmodifiable(<String>[
  'joined',
  'seated',
  'public-sent',
  'reentry-off-mic',
  'reentry-left',
  'manual_room_reentry',
  'gift-seated',
  'gift-A',
  'gift-B',
  'off-mic',
  for (int index = 0; index < 10; index++) ...<String>[
    'private-ready-$index',
    'private-received-$index',
  ],
  'complete',
]);

void validateDualEnvironment(
  AppEnvironment env, {
  bool release = kReleaseMode,
  DualPlatformSupport? platformForTest,
}) {
  if (release ||
      !env.isLive ||
      !env.deploymentEnvironmentConfigured ||
      !env.deploymentEnvironment.allowsDevelopmentTools ||
      env.apiBaseUrl != _platform(platformForTest).backend ||
      !env.allowInsecureHttp ||
      env.enableAgoraRtc ||
      env.enableTencentIm ||
      env.enableAppleIap ||
      env.enableAlipayAppPay ||
      env.alipayFormalAcceptance ||
      env.realtimeEndpoint.isNotEmpty) {
    throw StateError('Dual test requires isolated development, vendors off.');
  }
}

class DualConfig {
  DualConfig(
    Map<String, dynamic> json,
    String expectedRole, {
    String expectedFlutterSha = const String.fromEnvironment(
      'DUAL_EXPECTED_FLUTTER_SHA',
    ),
    String expectedBackendSha = const String.fromEnvironment(
      'DUAL_EXPECTED_BACKEND_SHA',
    ),
    DualPlatformSupport? platformForTest,
  }) {
    try {
      final platform = _platform(platformForTest);
      flutterSha = json['flutterSha'] as String;
      backendSha = json['backendSha'] as String;
      final shaPattern = RegExp(r'^[0-9a-f]{40}$');
      if (!shaPattern.hasMatch(expectedFlutterSha) ||
          !shaPattern.hasMatch(expectedBackendSha) ||
          flutterSha != expectedFlutterSha ||
          backendSha != expectedBackendSha) {
        throw StateError('candidate identity rejected');
      }
      role = json['role'] as String;
      runId = json['runId'] as String;
      roomId = json['roomId'] as String;
      peerPostId = json['peerPostId'] as String;
      peerUserId = json['peerUserId'] as int;
      session = AuthSession.decode(jsonEncode(json['session']))!;
      final expiry = DateTime.parse(json['expiresAt'] as String);
      final now = DateTime.now();
      if (!{'A', 'B'}.contains(role) ||
          role != expectedRole ||
          !RegExp(r'^[a-zA-Z0-9_-]{8,48}$').hasMatch(runId) ||
          roomId.isEmpty ||
          peerPostId.isEmpty ||
          peerUserId <= 0 ||
          session.userId <= 0 ||
          session.userId == peerUserId ||
          !expiry.isAfter(now) ||
          expiry.difference(now) > const Duration(minutes: 20) ||
          session.expiresAt.isBefore(expiry) ||
          json['apiBaseUrl'] != platform.backend) {
        throw StateError('invalid');
      }
      environment = AppEnvironment(
        backendMode: BackendMode.live,
        apiBaseUrl: platform.backend,
        clientType: json['clientType'] as String,
        clientInnerVersion: json['clientInnerVersion'] as String,
        oauthClientId: json['oauthClientId'] as String,
        realtimeEndpoint: '',
        allowInsecureHttp: true,
      );
      environment.validateLiveConfiguration();
      validateDualEnvironment(environment, platformForTest: platformForTest);
    } catch (_) {
      // Never include malformed credential payloads in exception diagnostics.
      throw StateError(
        'Invalid or expired private dual runtime configuration.',
      );
    }
  }
  late final String role, runId, roomId, peerPostId;
  late final String flutterSha, backendSha;
  late final int peerUserId;
  late final AuthSession session;
  late final AppEnvironment environment;
  String get peerRole => role == 'A' ? 'B' : 'A';
  String message(String sender, String kind) => 'dual-$runId-$sender-$kind';
}

class DualRelay {
  DualRelay(this.port, this.role);
  final int port;
  final String role;
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10);
  String? _bearer;

  Future<Map<String, dynamic>> request(
    String path, [
    Map<String, String>? body,
  ]) async {
    if (port < 1024 ||
        port > 65535 ||
        port == 18080 ||
        port == 28080 ||
        !{'A', 'B'}.contains(role) ||
        !{'/dual/config', '/dual/barrier'}.contains(path)) {
      throw StateError('Invalid private relay target.');
    }
    String stage = 'CREDENTIAL';
    try {
      final platform = DualPlatformSupport.current();
      _bearer ??= await readDualRuntimeToken();
      stage = 'CONNECT';
      final req = await _client.openUrl(
        body == null ? 'GET' : 'POST',
        Uri(scheme: 'http', host: platform.relayHost, port: port, path: path),
      );
      req.followRedirects = false;
      // UI steps can outlive the host relay's idle keep-alive window. This
      // control channel uses a fresh connection, never a business retry.
      req.persistentConnection = false;
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_bearer');
      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode(body));
      }
      stage = 'RESPONSE';
      final response = await req.close().timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) throw StateError('rejected');
      stage = 'BODY';
      final data = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 10));
      stage = 'DECODE';
      return jsonDecode(data) as Map<String, dynamic>;
    } catch (error) {
      // Fixed categories only. Exception text may contain an authenticated
      // endpoint or device-private payload and must never reach artifacts.
      final category = error is TimeoutException
          ? 'TIMEOUT'
          : error is SocketException
          ? 'SOCKET'
          : error is HttpException
          ? 'HTTP'
          : error is FormatException
          ? 'FORMAT'
          : 'REJECTED';
      throw StateError('Private relay failed: $stage/$category (redacted).');
    }
  }

  bool released(Map<String, dynamic> reply, DualConfig config, String phase) {
    if (!dualPhases.contains(phase) ||
        reply['runId'] != config.runId ||
        reply['phase'] != phase ||
        reply['released'] is! bool) {
      throw StateError('Invalid dual barrier acknowledgement.');
    }
    return reply['released'] == true;
  }

  void close() {
    _bearer = null;
    _client.close(force: true);
  }
}
