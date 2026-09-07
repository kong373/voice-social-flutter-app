import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_client.dart';

void main() {
  test(
    'owned transport retires idle sockets before the backend five second limit',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0)
        ..idleTimeout = const Duration(seconds: 5);
      addTearDown(() => server.close(force: true));
      final ports = <int>[];
      server.listen((request) async {
        ports.add(request.connectionInfo!.remotePort);
        await request.drain<void>();
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({'code': 200, 'message': 'OK', 'data': null}),
        );
        await request.response.close();
      });
      final client = ApiClient(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}/'),
        clientType: 'Android',
        clientInnerVersion: '1',
        authorizationProvider: () => null,
      );
      await client.get('/health', authenticated: false);
      await Future<void>.delayed(const Duration(milliseconds: 2300));
      await client.get('/health', authenticated: false);
      expect(ports, hasLength(2), reason: 'No implicit request retries');
      expect(
        ports[1],
        isNot(ports[0]),
        reason:
            'Do not reuse a socket approaching the server idle-close boundary',
      );
    },
  );

  test('caller-owned transport retains its explicit idle policy', () {
    final transport = HttpClient()..idleTimeout = const Duration(seconds: 11);
    addTearDown(() => transport.close(force: true));
    ApiClient(
      baseUri: Uri.parse('http://127.0.0.1:28080/'),
      clientType: 'Android',
      clientInnerVersion: '1',
      authorizationProvider: () => null,
      httpClient: transport,
    );
    expect(transport.idleTimeout, const Duration(seconds: 11));
  });
}
