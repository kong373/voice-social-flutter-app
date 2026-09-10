import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/media/media_identity.dart';
import 'support/media_http_fakes.dart';

const avatarAsset = '11111111-1111-4111-8111-111111111111';
MediaFakeResponse avatarResponse({
  List<int> bytes = const [1, 2, 3],
  int? length,
  String type = 'image/png',
  String cache = 'private, no-store',
  String? encoding,
  int status = 200,
  Stream<List<int>>? stream,
}) {
  final value = MediaFakeResponse(
    status,
    stream ?? Stream.value(bytes),
    contentLength: length ?? bytes.length,
    type: type,
  );
  value.headers.set('Cache-Control', cache);
  if (encoding != null) value.headers.set('Content-Encoding', encoding);
  return value;
}

void main() {
  for (final type in ['image/jpeg', 'image/png', 'image/webp']) {
    test(
      'controlled $type GET uses only fixed route and current bearer',
      () async {
        final user = TestMediaIdentity();
        final scope = user.scope();
        final http = MediaFakeHttp((_) => avatarResponse(type: type));
        final api = ApiClient(
          baseUri: Uri.parse('https://backend.test/base'),
          clientType: 'test',
          clientInnerVersion: '1',
          authorizationProvider: () => user.token,
          httpClient: http,
          requestHeadersProvider: () => {
            'Cookie': 'must-not-send',
            'X-Registration-Avatar-Capability': 'must-not-send',
            'Client-Id': 'public-client',
          },
        );
        expect(
          await api.readUserAvatarContent(
            assetId: avatarAsset,
            version: 2,
            identity: scope,
          ),
          [1, 2, 3],
        );
        final request = http.requests.single;
        expect(
          request.uri.toString(),
          'https://backend.test/app-api/media/v1/assets/$avatarAsset/content',
        );
        expect(request.method, 'GET');
        expect(request.followRedirects, false);
        expect(request.maxRedirects, 0);
        expect(request.headers.value('Authorization'), user.token);
        expect(request.headers.value('Cookie'), isNull);
        expect(
          request.headers.value('X-Registration-Avatar-Capability'),
          isNull,
        );
        expect(request.headers.value('Accept-Encoding'), 'identity');
        expect(request.headers.value('Cache-Control'), 'no-store');
        expect(request.body, isEmpty);
        scope.dispose();
        user.dispose();
      },
    );
  }
  final badResponses = <String, MediaFakeResponse Function()>{
    'redirect': () => avatarResponse(status: 302),
    'partial': () => avatarResponse(status: 206),
    'SVG': () => avatarResponse(type: 'image/svg+xml'),
    'JSON': () => avatarResponse(type: 'application/json'),
    'encoded': () => avatarResponse(encoding: 'gzip'),
    'not private': () => avatarResponse(cache: 'no-store'),
    'cacheable': () => avatarResponse(cache: 'private, max-age=300'),
    'public': () => avatarResponse(cache: 'public, private, no-store'),
    'empty': () => avatarResponse(bytes: []),
    'short': () => avatarResponse(length: 4),
    'long': () => avatarResponse(length: 2),
    'declared overflow': () => avatarResponse(length: 10000001),
    'chunked overflow': () => avatarResponse(
      length: -1,
      stream: Stream.fromIterable([
        Uint8List(10000000),
        [1],
      ]),
    ),
  };
  for (final entry in badResponses.entries) {
    test('rejects ${entry.key}, aborts and never follows/replays', () async {
      final user = TestMediaIdentity();
      final scope = user.scope();
      final http = MediaFakeHttp((_) => entry.value());
      await expectLater(
        http
            .api(user)
            .readUserAvatarContent(
              assetId: avatarAsset,
              version: 0,
              identity: scope,
            ),
        throwsA(anything),
      );
      expect(http.requests, hasLength(1));
      expect(http.requests.single.aborted, true);
      scope.dispose();
      user.dispose();
    });
  }
  test(
    'unknown length accepts exactly 10MB with bounded actual bytes',
    () async {
      final user = TestMediaIdentity();
      final scope = user.scope();
      final http = MediaFakeHttp(
        (_) => avatarResponse(length: -1, bytes: Uint8List(10000000)),
      );
      expect(
        (await http
                .api(user)
                .readUserAvatarContent(
                  assetId: avatarAsset,
                  version: 0,
                  identity: scope,
                ))
            .length,
        10000000,
      );
      scope.dispose();
      user.dispose();
    },
  );
  test('invalid UUID/version/config never opens a connection', () async {
    final user = TestMediaIdentity();
    final scope = user.scope();
    final http = MediaFakeHttp((_) => avatarResponse());
    final api = http.api(user);
    for (final id in [
      'https://external.test/avatar',
      '$avatarAsset?token=x',
      '../$avatarAsset',
    ]) {
      await expectLater(
        api.readUserAvatarContent(assetId: id, version: 0, identity: scope),
        throwsA(anything),
      );
    }
    await expectLater(
      api.readUserAvatarContent(
        assetId: avatarAsset,
        version: -1,
        identity: scope,
      ),
      throwsA(anything),
    );
    final queryApi = ApiClient(
      baseUri: Uri.parse('https://backend.test/?secret=x'),
      clientType: 'test',
      clientInnerVersion: '1',
      authorizationProvider: () => user.token,
      httpClient: http,
    );
    await expectLater(
      queryApi.readUserAvatarContent(
        assetId: avatarAsset,
        version: 0,
        identity: scope,
      ),
      throwsA(anything),
    );
    expect(http.requests, isEmpty);
    scope.dispose();
    user.dispose();
  });
  test(
    'openUrl ABA aborts late socket without writing auth headers or closing request',
    () async {
      final user = TestMediaIdentity();
      final scope = user.scope();
      final gate = Completer<void>();
      final http = MediaFakeHttp((_) => avatarResponse())
        ..beforeOpen = (_) => gate.future;
      final future = http
          .api(user)
          .readUserAvatarContent(
            assetId: avatarAsset,
            version: 0,
            identity: scope,
          );
      final rejected = expectLater(
        future,
        throwsA(same(MediaIdentityScope.invalid)),
      );
      user.change(2);
      user.change(1);
      gate.complete();
      await rejected;
      await Future<void>.delayed(Duration.zero);
      expect(http.requests.single.aborted, true);
      expect(
        (http.requests.single.headers as MediaFakeHeaders).values,
        isEmpty,
      );
      expect(http.requests.single.closes, 0);
      user.dispose();
    },
  );
  test(
    'idle response stream is cancelled on identity loss; late error cannot leak',
    () async {
      final user = TestMediaIdentity();
      final scope = user.scope();
      final stream = StreamController<List<int>>();
      var cancelled = false;
      stream.onCancel = () {
        cancelled = true;
      };
      final http = MediaFakeHttp(
        (_) => avatarResponse(length: -1, stream: stream.stream),
      );
      final future = http
          .api(user)
          .readUserAvatarContent(
            assetId: avatarAsset,
            version: 0,
            identity: scope,
          );
      final rejected = expectLater(
        future,
        throwsA(same(MediaIdentityScope.invalid)),
      );
      await Future<void>.delayed(Duration.zero);
      stream.add([1]);
      user.change(2);
      stream.addError(const SocketException('OLD SECRET'));
      await rejected;
      expect(cancelled, true);
      expect(http.requests.single.aborted, true);
      await stream.close();
      user.dispose();
    },
  );
  test(
    '401 refresh retries GET only in unchanged identity and binds fresh token',
    () async {
      final user = TestMediaIdentity();
      final scope = user.scope();
      var reads = 0;
      final http = MediaFakeHttp(
        (_) => ++reads == 1 ? avatarResponse(status: 401) : avatarResponse(),
      );
      expect(
        await http
            .api(
              user,
              refresh: () async {
                user.refreshToken();
                return true;
              },
            )
            .readUserAvatarContent(
              assetId: avatarAsset,
              version: 0,
              identity: scope,
            ),
        [1, 2, 3],
      );
      expect(
        http.requests.last.headers.value('Authorization'),
        'Bearer contract-refreshed',
      );
      scope.dispose();
      user.dispose();
    },
  );
  test('401 refresh ABA cannot issue another GET', () async {
    final user = TestMediaIdentity();
    final scope = user.scope();
    final http = MediaFakeHttp((_) => avatarResponse(status: 401));
    await expectLater(
      http
          .api(
            user,
            refresh: () async {
              user.change(2);
              user.change(1);
              return true;
            },
          )
          .readUserAvatarContent(
            assetId: avatarAsset,
            version: 0,
            identity: scope,
          ),
      throwsA(same(MediaIdentityScope.invalid)),
    );
    expect(http.requests, hasLength(1));
    user.dispose();
  });
}
