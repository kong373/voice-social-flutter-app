import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/storage/key_value_store.dart';
import 'package:voice_social_app/features/account/registration_avatar/registration_avatar_host.dart';
import 'package:voice_social_app/features/account/registration_avatar/registration_avatar_models.dart';
import 'package:voice_social_app/features/account/registration_avatar/registration_avatar_transport_adapter.dart';
import 'package:voice_social_app/features/media/native_image_selection.dart';
import 'media_http_fakes.dart';

const avatarTestId = '11111111-1111-4111-8111-111111111111';
const avatarChallenge = '22222222-2222-4222-8222-222222222222';
final avatarPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
);

class AvatarSignal extends ChangeNotifier {
  int generation = 1;
  final expiresAt = DateTime.now().toUtc().add(const Duration(minutes: 4));
  void change() {
    generation++;
    notifyListeners();
  }

  RegistrationAvatarContext context({
    String phone = '13800138000',
    String code = '123456',
    String challenge = avatarChallenge,
    String device = 'device-A',
    String client = 'public-client',
    DateTime? expiry,
  }) {
    final captured = generation;
    return RegistrationAvatarContext(
      phone: phone,
      smsCode: code,
      challengeId: challenge,
      deviceId: device,
      clientId: client,
      expiresAt: expiry ?? expiresAt,
      requireCurrent: () {
        if (captured != generation) throw registrationAvatarContextExpired;
      },
      changes: this,
    );
  }
}

class AvatarStore implements KeyValueStore {
  final data = <String, String>{};
  Future<void> Function(Map<String, Object?>)? beforeWrite;
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> delete(String key) async {
    data.remove(key);
  }

  @override
  Future<void> write(String key, String value) async {
    await beforeWrite?.call(jsonDecode(value) as Map<String, Object?>);
    data[key] = value;
  }

  Map<String, Object?> get record =>
      jsonDecode(data.values.single) as Map<String, Object?>;
}

class AvatarPicker implements ImageSelection {
  AvatarPicker(this.files);
  List<XFile> files;
  int calls = 0;
  Completer<void>? pause;
  Completer<void>? entered;
  @override
  Future<List<XFile>> pick(int remaining) async {
    if (remaining != 1) throw StateError('Expected one image');
    calls++;
    entered?.complete();
    await pause?.future;
    return files;
  }
}

class AvatarServer {
  AvatarServer(this.expiresAt) {
    http = MediaFakeHttp(respond);
  }
  final DateTime expiresAt;
  late final MediaFakeHttp http;
  String state = 'ALLOCATED';
  int version = 0, allocations = 0, puts = 0, completes = 0, gets = 0;
  bool loseAllocation = false,
      losePut = false,
      loseComplete = false,
      scanUnavailable = false;
  bool changeId = false, extendExpiry = false, regress = false;
  Map<String, Object?> projection() => {
    'assetId': changeId ? '33333333-3333-4333-8333-333333333333' : avatarTestId,
    'purpose': 'AVATAR',
    'state': regress ? 'ALLOCATED' : state,
    'version': regress ? 0 : version,
    'maximumBytes': 10000000,
    'expiresAt':
        (extendExpiry ? expiresAt.add(const Duration(seconds: 1)) : expiresAt)
            .toIso8601String(),
    'bytes': state == 'ALLOCATED' || state == 'UPLOADING'
        ? null
        : avatarPng.length,
    'mediaType': state == 'READY' || state == 'BOUND' ? 'image/png' : null,
    'durationMillis': state == 'READY' || state == 'BOUND' ? 0 : null,
  };
  Future<HttpClientResponse> respond(MediaFakeRequest request) async {
    if (request.method == 'GET') {
      gets++;
      return MediaFakeResponse.json(projection());
    }
    if (request.method == 'PUT') {
      puts++;
      state = 'QUARANTINED';
      version = 2;
      if (losePut) {
        losePut = false;
        throw const SocketException('lost upload response');
      }
      return MediaFakeResponse.json(projection());
    }
    if (request.uri.path.endsWith('/complete')) {
      completes++;
      if (state == 'ALLOCATED')
        return MediaFakeResponse.json(null, status: 409, code: 40983);
      if (scanUnavailable)
        return MediaFakeResponse.json(null, status: 503, code: 50381);
      state = 'READY';
      version = 3;
      if (loseComplete) {
        loseComplete = false;
        throw const SocketException('lost scan response');
      }
      return MediaFakeResponse.json(projection());
    }
    allocations++;
    if (loseAllocation) {
      loseAllocation = false;
      throw const SocketException('lost allocation response');
    }
    return MediaFakeResponse.json(projection());
  }

  ApiClient api({int maximum = 2048, Future<bool> Function()? refresh}) =>
      ApiClient(
        baseUri: Uri.parse('https://configured.backend.test'),
        clientType: 'Android',
        clientInnerVersion: '6',
        authorizationProvider: () =>
            throw StateError('Registration must never read App token'),
        requestHeadersProvider: () =>
            throw StateError('Registration must never read App headers'),
        unauthorizedRecovery: refresh,
        httpClient: http,
        maximumResponseBytes: maximum,
      );
}

class AvatarFixture {
  AvatarFixture._(
    this.directory,
    this.original,
    this.signal,
    this.store,
    this.picker,
    this.server,
  );
  final Directory directory;
  final File original;
  final AvatarSignal signal;
  final AvatarStore store;
  final AvatarPicker picker;
  final AvatarServer server;
  final hosts = <RegistrationAvatarHost>[];
  final contexts = <RegistrationAvatarContext>[];
  static Future<AvatarFixture> create() async {
    final directory = await Directory.systemTemp.createTemp('r01-avatar-test-');
    final original = File('${directory.path}/picker-owned.png');
    await original.writeAsBytes(avatarPng);
    final signal = AvatarSignal();
    return AvatarFixture._(
      directory,
      original,
      signal,
      AvatarStore(),
      AvatarPicker([XFile(original.path)]),
      AvatarServer(signal.expiresAt),
    );
  }

  RegistrationAvatarHost host({RegistrationAvatarContext? context}) {
    final captured = context ?? signal.context();
    contexts.add(captured);
    final value = RegistrationAvatarHost(
      context: captured,
      transport: ApiRegistrationAvatarTransport(server.api()),
      store: store,
      picker: picker,
      temporaryParent: () async => directory,
    );
    hosts.add(value);
    return value;
  }

  Future<void> dispose() async {
    for (final host in hosts) {
      host.dispose();
      await host.cleanup;
    }
    for (final context in contexts) {
      context.dispose();
    }
    signal.dispose();
    await directory.delete(recursive: true);
  }
}
