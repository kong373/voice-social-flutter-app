import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_client.dart';

void main() {
  test('api client injects required headers and parses the result envelope', () async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(() => server.close(force: true));
    final Completer<void> handled = Completer<void>();

    server.listen((HttpRequest request) async {
      expect(request.method, 'POST');
      expect(request.uri.path, '/contract');
      expect(request.headers.value('Client-Type'), 'Android');
      expect(request.headers.value('Client-Inner-Version'), '42');
      expect(request.headers.value(HttpHeaders.authorizationHeader), 'Bearer test');
      final String body = await utf8.decoder.bind(request).join();
      expect(jsonDecode(body), <String, Object?>{'hello': 'world'});

      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(<String, Object?>{
          'code': 200,
          'message': '操作成功',
          'data': <String, Object?>{'accepted': true},
        }),
      );
      await request.response.close();
      handled.complete();
    });

    final ApiClient client = ApiClient(
      baseUri: Uri.parse('http://${server.address.address}:${server.port}/'),
      clientType: 'Android',
      clientInnerVersion: '42',
      authorizationProvider: () => 'Bearer test',
    );
    final ApiResponse response = await client.post(
      '/contract',
      body: <String, Object?>{'hello': 'world'},
    );

    await handled.future;
    expect(response.isSuccess, isTrue);
    expect(response.data, <String, Object?>{'accepted': true});
  });
}
