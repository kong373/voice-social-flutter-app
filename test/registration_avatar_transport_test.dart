import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/account/registration_avatar/registration_avatar_models.dart';
import 'support/media_http_fakes.dart';
import 'support/registration_avatar_fakes.dart';

String _testCapability() =>
    base64Url.encode(List<int>.generate(32, (i) => i)).replaceAll('=', '');
RegistrationAvatarRequestScope _scope(
  RegistrationAvatarContext context, {
  String? cap,
  String key = 'r01-test-key',
}) => RegistrationAvatarRequestScope(
  clientId: context.clientId,
  deviceId: context.deviceId,
  requestId: key,
  capability: cap ?? _testCapability(),
  check: context.check,
  wait: context.wait,
  onCancel: context.onCancel,
);

ApiClient _api(
  MediaFakeHttp http, {
  int maximum = 2048,
  Future<bool> Function()? refresh,
}) => ApiClient(
  baseUri: Uri.parse('https://configured.backend.test'),
  clientType: 'Android',
  clientInnerVersion: '6',
  authorizationProvider: () =>
      throw StateError('App token must not be accessed'),
  requestHeadersProvider: () =>
      throw StateError('App headers must not be accessed'),
  unauthorizedRecovery: refresh,
  httpClient: http,
  maximumResponseBytes: maximum,
);

void main() {
  test(
    'real loopback HTTP uses exact allocate PUT complete GET wire without App auth',
    () async {
      final signal = AvatarSignal();
      addTearDown(signal.dispose);
      final context = signal.context();
      addTearDown(context.dispose);
      final scope = _scope(context);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final observed = <(String, Uri, List<int>, bool, bool, bool, String?)>[];
      server.listen((request) async {
        final chunks = await request.toList();
        observed.add((
          request.method,
          request.uri,
          chunks.expand((c) => c).toList(),
          request.headers.value('Authorization') == null,
          request.headers.value('X-Registration-Avatar-Capability') ==
              scope.capability,
          request.headers.value('X-Request-Id') == scope.requestId,
          request.headers.value('Content-Encoding'),
        ));
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'code': 200,
            'message': 'OK',
            'data': AvatarServer(signal.expiresAt).projection(),
          }),
        );
        await request.response.close();
      });
      final api = ApiClient(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
        clientType: 'test',
        clientInnerVersion: '1',
        authorizationProvider: () => throw StateError('No token'),
        requestHeadersProvider: () => throw StateError('No headers'),
      );
      await api.registrationAvatarExchange(
        action: RegistrationAvatarAction.allocate,
        scope: scope,
        phone: context.phone,
        smsCode: context.smsCode,
        challengeId: context.challengeId,
      );
      await api.registrationAvatarExchange(
        action: RegistrationAvatarAction.upload,
        scope: scope,
        assetId: avatarTestId,
        expectedVersion: 0,
        bytes: avatarPng.length,
        content: Stream.fromIterable([
          avatarPng.sublist(0, 8),
          avatarPng.sublist(8),
        ]),
      );
      await api.registrationAvatarExchange(
        action: RegistrationAvatarAction.complete,
        scope: scope,
        assetId: avatarTestId,
        expectedVersion: 2,
      );
      await api.registrationAvatarExchange(
        action: RegistrationAvatarAction.status,
        scope: scope,
        assetId: avatarTestId,
      );
      expect(observed.map((r) => r.$1), ['POST', 'PUT', 'POST', 'GET']);
      expect(jsonDecode(utf8.decode(observed[0].$3)), {
        'phone': context.phone,
        'smsCode': context.smsCode,
        'challengeId': context.challengeId,
        'deviceId': context.deviceId,
      });
      expect(observed[1].$3, avatarPng);
      expect(observed[1].$2.queryParameters, {'expectedVersion': '0'});
      expect(jsonDecode(utf8.decode(observed[2].$3)), {'expectedVersion': 2});
      expect(observed.last.$3, isEmpty);
      expect(observed.every((r) => r.$4 && r.$5 && r.$6 && r.$7 == null), true);
      expect(
        observed.every((r) => !r.$2.toString().contains(scope.capability)),
        true,
      );
    },
  );
  for (final status in [301, 302, 307, 308, 401, 403, 409, 500]) {
    test(
      'HTTP $status does not redirect refresh or replay and never echoes credential',
      () async {
        final signal = AvatarSignal();
        addTearDown(signal.dispose);
        final context = signal.context();
        addTearDown(context.dispose);
        final scope = _scope(context);
        var refreshes = 0;
        final http = MediaFakeHttp(
          (_) => MediaFakeResponse(
            status,
            Stream.value(
              utf8.encode(
                jsonEncode({
                  'code': status,
                  'message': scope.capability,
                  'data': null,
                }),
              ),
            ),
          ),
        );
        final api = _api(
          http,
          refresh: () async {
            refreshes++;
            return true;
          },
        );
        Object? failure;
        try {
          await api.registrationAvatarExchange(
            action: RegistrationAvatarAction.status,
            scope: scope,
            assetId: avatarTestId,
          );
        } catch (error) {
          failure = error;
        }
        expect(failure, isA<ApiException>());
        expect(failure.toString().contains(scope.capability), false);
        expect(refreshes, 0);
        expect(http.requests.length, 1);
        expect(http.requests.single.followRedirects, false);
        expect(http.requests.single.maxRedirects, 0);
      },
    );
  }
  for (final kind in [
    'cap padding',
    'cap noncanonical',
    'asset newline',
    'asset URL',
    'request newline',
    'phone newline',
    'code newline',
  ]) {
    test('$kind is rejected before opening HTTP', () async {
      final signal = AvatarSignal();
      addTearDown(signal.dispose);
      final context = signal.context();
      addTearDown(context.dispose);
      final cap = _testCapability();
      final scope = _scope(
        context,
        cap: kind == 'cap padding'
            ? '$cap='
            : kind == 'cap noncanonical'
            ? '${cap.substring(0, 42)}_'
            : cap,
        key: kind == 'request newline' ? 'key\n' : 'key',
      );
      final http = MediaFakeHttp((_) => MediaFakeResponse.json(null));
      final api = _api(http);
      final allocate = kind == 'phone newline' || kind == 'code newline';
      await expectLater(
        api.registrationAvatarExchange(
          action: allocate
              ? RegistrationAvatarAction.allocate
              : RegistrationAvatarAction.status,
          scope: scope,
          assetId: allocate
              ? null
              : kind == 'asset newline'
              ? '$avatarTestId\n'
              : kind == 'asset URL'
              ? 'https://other.test/x'
              : avatarTestId,
          phone: allocate
              ? '${context.phone}${kind == 'phone newline' ? '\n' : ''}'
              : null,
          smsCode: allocate
              ? '${context.smsCode}${kind == 'code newline' ? '\n' : ''}'
              : null,
          challengeId: allocate ? context.challengeId : null,
        ),
        throwsA(isA<ApiException>()),
      );
      expect(http.opens, 0);
    });
  }
  for (final size in [0, 10000001]) {
    test('invalid upload length $size never opens a request', () async {
      final signal = AvatarSignal();
      addTearDown(signal.dispose);
      final context = signal.context();
      addTearDown(context.dispose);
      final http = MediaFakeHttp((_) => MediaFakeResponse.json(null));
      await expectLater(
        _api(http).registrationAvatarExchange(
          action: RegistrationAvatarAction.upload,
          scope: _scope(context),
          assetId: avatarTestId,
          expectedVersion: 0,
          bytes: size,
          content: const Stream.empty(),
        ),
        throwsA(isA<ApiException>()),
      );
      expect(http.opens, 0);
    });
  }
  for (final actual in [3, 5]) {
    test(
      'raw upload actual $actual bytes cannot contradict declared four',
      () async {
        final signal = AvatarSignal();
        addTearDown(signal.dispose);
        final context = signal.context();
        addTearDown(context.dispose);
        final http = MediaFakeHttp((_) => MediaFakeResponse.json(null));
        await expectLater(
          _api(http).registrationAvatarExchange(
            action: RegistrationAvatarAction.upload,
            scope: _scope(context),
            assetId: avatarTestId,
            expectedVersion: 0,
            bytes: 4,
            content: Stream.value(List.filled(actual, 1)),
          ),
          throwsA(isA<ApiException>()),
        );
        expect(http.requests.single.closes, 0);
        expect(http.requests.single.aborted, true);
      },
    );
  }
  test(
    'metadata response stays bounded independently of ten MB upload limit',
    () async {
      final signal = AvatarSignal();
      addTearDown(signal.dispose);
      final context = signal.context();
      addTearDown(context.dispose);
      final http = MediaFakeHttp(
        (_) => MediaFakeResponse(
          200,
          Stream.fromIterable([List.filled(20, 32), List.filled(21, 32)]),
        ),
      );
      await expectLater(
        _api(http, maximum: 40).registrationAvatarExchange(
          action: RegistrationAvatarAction.status,
          scope: _scope(context),
          assetId: avatarTestId,
        ),
        throwsA(isA<ApiException>()),
      );
      expect(http.requests.single.aborted, true);
    },
  );
  for (final phase in ['open', 'body', 'response']) {
    test(
      'challenge ABA cancels $phase without adopting late bytes or result',
      () async {
        final signal = AvatarSignal();
        addTearDown(signal.dispose);
        final context = signal.context();
        addTearDown(context.dispose);
        final reached = Completer<void>(), release = Completer<void>();
        final response = Completer<HttpClientResponse>();
        final content = StreamController<List<int>>.broadcast(
          onListen: phase == 'body' ? reached.complete : null,
        );
        addTearDown(content.close);
        final http = MediaFakeHttp((_) {
          reached.complete();
          return response.future;
        });
        if (phase == 'open')
          http.beforeOpen = (_) async {
            reached.complete();
            await release.future;
          };
        final operation = expectLater(
          _api(http).registrationAvatarExchange(
            action: phase == 'body'
                ? RegistrationAvatarAction.upload
                : RegistrationAvatarAction.status,
            scope: _scope(context),
            assetId: avatarTestId,
            expectedVersion: phase == 'body' ? 0 : null,
            bytes: phase == 'body' ? 4 : null,
            content: phase == 'body' ? content.stream : null,
          ),
          throwsA(isA<ApiException>()),
        );
        await reached.future.timeout(const Duration(seconds: 5));
        signal.change();
        signal.change();
        release.complete();
        response.complete(
          MediaFakeResponse.json(AvatarServer(signal.expiresAt).projection()),
        );
        await operation;
        if (phase == 'open') await Future<void>.delayed(Duration.zero);
        expect(http.requests.single.aborted, true);
        if (phase == 'open')
          expect(
            http.requests.single.headers.value(
              'X-Registration-Avatar-Capability',
            ),
            isNull,
          );
        if (phase != 'response') expect(http.requests.single.closes, 0);
      },
    );
  }
}
