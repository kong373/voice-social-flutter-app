import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';

void main() {
  for (final scenario in [
    'open',
    '401-switch',
    'refresh-switch',
    'refresh-same',
    'retry-open-switch',
  ]) {
    test('bound financial request: $scenario', () async {
      var identity = 'A:1';
      var token = 'Bearer A-old';
      var recoveryCalls = 0;
      final received = <String>[];
      final payloads = <String>[];
      final keys = <String?>[];
      final entered = Completer<void>();
      final release = Completer<void>();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        received.add(request.headers.value(HttpHeaders.authorizationHeader)!);
        keys.add(request.headers.value('X-Request-Id'));
        payloads.add(await utf8.decoder.bind(request).join());
        final first = received.length == 1;
        if (scenario == '401-switch' && first) {
          identity = 'B:2';
          token = 'Bearer B';
        }
        request.response.statusCode = first && scenario != 'open' ? 401 : 200;
        request.response.write(
          jsonEncode({
            'code': request.response.statusCode,
            'message': 'test',
            'data': <String, Object?>{},
          }),
        );
        await request.response.close();
      });
      final transport = _DelayedClient(
        entered,
        release,
        scenario == 'open'
            ? 1
            : scenario == 'retry-open-switch'
            ? 2
            : 0,
      );
      final client = ApiClient(
        clientType: 'test',
        clientInnerVersion: '1',
        baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
        authorizationProvider: () => token,
        httpClient: transport,
        unauthorizedRecovery: () async {
          recoveryCalls++;
          if (scenario == 'refresh-switch') identity = 'B:2';
          token = identity == 'A:1' ? 'Bearer A-new' : 'Bearer B';
          return true;
        },
      );
      addTearDown(() async {
        transport.close(force: true);
        await server.close(force: true);
      });
      final result = client
          .postBoundToIdentity(
            '/apply',
            requireIdentity: () {
              if (identity != 'A:1')
                throw const ApiException(
                  kind: ApiFailureKind.protocol,
                  message: 'identity changed',
                );
            },
            headers: {'X-Request-Id': 'A-original-key'},
            body: {'amountMinor': 10100, 'payoutAccountId': 'A-account'},
          )
          .then<Object>((value) => value, onError: (Object error) => error);
      if (scenario == 'open' || scenario == 'retry-open-switch') {
        await entered.future;
        identity = 'B:2';
        token = 'Bearer B';
        release.complete();
      }
      final outcome = await result;
      if (scenario == 'refresh-same') {
        expect(outcome, isNot(isA<ApiException>()));
        expect(received, ['Bearer A-old', 'Bearer A-new']);
        expect(keys, ['A-original-key', 'A-original-key']);
        expect(payloads[0], payloads[1]);
      } else {
        expect(outcome, isA<ApiException>());
        expect(received, scenario == 'open' ? isEmpty : ['Bearer A-old']);
      }
      expect(
        recoveryCalls,
        scenario.startsWith('refresh-') || scenario == 'retry-open-switch'
            ? 1
            : 0,
      );
    });
  }
}

class _DelayedClient implements HttpClient {
  _DelayedClient(this.entered, this.release, this.delay);
  final HttpClient delegate = HttpClient();
  final Completer<void> entered;
  final Completer<void> release;
  final int delay;
  int opens = 0;
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    if (++opens == delay) {
      entered.complete();
      await release.future;
    }
    return delegate.openUrl(method, url);
  }

  @override
  void close({bool force = false}) => delegate.close(force: force);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
