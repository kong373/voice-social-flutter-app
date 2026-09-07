import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/features/account/domain/auth_models.dart';

/// Private, short-lived host relay contract (not a business proxy):
/// - Shared defines: DUAL_RELAY_PORT=<ephemeral port>, BACKEND_MODE=live,
///   APP_ENV=local|development, API_BASE_URL=http://10.0.2.2:28080/,
///   ALLOW_INSECURE_HTTP=true. All vendor/formal flags must be false.
///   DUAL_EXPECTED_FLUTTER_SHA and DUAL_EXPECTED_BACKEND_SHA are required
///   public full 40-character lowercase Git SHAs, exactly matching config.
/// - Host provisions a distinct random bearer per device in app-private cache
///   `dual-runtime-relay-token` (0600); never argv, defines, screenshots or logs.
///   Beside it, provision `dual-runtime-role` (0600), containing A or B (an
///   optional trailing newline is allowed). Missing/invalid roles fail closed;
///   config.role must exactly match this device-local role. No role define.
///   Build one integration APK and install/use that SAME binary on both devices
///   with flutter drive --use-application-binary; SHA and relay-port defines
///   are shared. Only private runtime files differ. Remove both files in finally.
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
///   off-mic, private-sent, complete. Reject unknown/out-of-order phases.
/// - Bind loopback only; reject redirects, expired/reused runs, role/token
///   mismatch; disable access/body logs; no business endpoints on this relay.
///   Run TTL <= 20 minutes; abort both drives on either failure; delete tokens,
///   revoke sessions and stop relay in host finally, including timeout.
/// - Prepare two fresh distinct users with reciprocal peer IDs, same empty
///   DIRECT room, available seats 1/2, snapshot-only transport, Star enabled
///   in its catalog category, enough gift coins, no following/block relation,
///   one visible unliked post per peer. No third participant or concurrent
///   wallet mutation. Relay verifies these before serving either config.
/// - Business writes happen ONLY inside production page callbacks. Public
///   history and seats must automatically converge before any room reentry;
///   manual_room_reentry is a separate persistence/recovery scenario. Private
///   history requires automatic_http_sync_no_navigation. Disabled RTC/IM never PASS.
///   Host accepts only TWO successful drive results.
const dualBackend = 'http://10.0.2.2:28080/';

Future<String> readDualRuntimeRole({Future<String> Function()? read}) async {
  try {
    final contents =
        await (read ??
            () => File(
              '/data/user/0/com.kong373.voice_social_app/cache/dual-runtime-role',
            ).readAsString())();
    if (!RegExp(r'^[AB](?:\r?\n)?$').hasMatch(contents)) {
      throw StateError('invalid role');
    }
    return contents.trim();
  } catch (_) {
    throw StateError('Missing or invalid private dual runtime role.');
  }
}

const dualPhases = <String>[
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
  'private-sent',
  'complete',
];

void validateDualEnvironment(
  AppEnvironment env, {
  bool release = kReleaseMode,
}) {
  if (release ||
      !env.isLive ||
      !env.deploymentEnvironmentConfigured ||
      !env.deploymentEnvironment.allowsDevelopmentTools ||
      env.apiBaseUrl != dualBackend ||
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
  }) {
    try {
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
          expiry.difference(now).inMinutes > 20 ||
          session.expiresAt.isBefore(expiry) ||
          json['apiBaseUrl'] != dualBackend) {
        throw StateError('invalid');
      }
      environment = AppEnvironment(
        backendMode: BackendMode.live,
        apiBaseUrl: dualBackend,
        clientType: json['clientType'] as String,
        clientInnerVersion: json['clientInnerVersion'] as String,
        oauthClientId: json['oauthClientId'] as String,
        realtimeEndpoint: '',
        allowInsecureHttp: true,
      );
      environment.validateLiveConfiguration();
      validateDualEnvironment(environment);
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
    try {
      _bearer ??= (await File(
        '/data/user/0/com.kong373.voice_social_app/cache/dual-runtime-relay-token',
      ).readAsString()).trim();
      if (_bearer!.length < 32 || _bearer!.contains(RegExp(r'\s'))) {
        throw StateError('invalid');
      }
      final req = await _client.openUrl(
        body == null ? 'GET' : 'POST',
        Uri(scheme: 'http', host: '10.0.2.2', port: port, path: path),
      );
      req.followRedirects = false;
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_bearer');
      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode(body));
      }
      final response = await req.close().timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) throw StateError('rejected');
      final data = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 10));
      return jsonDecode(data) as Map<String, dynamic>;
    } catch (_) {
      throw StateError('Private relay request failed (details redacted).');
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
