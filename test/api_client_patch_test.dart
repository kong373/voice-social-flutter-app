import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_client.dart';

void main() {
  test('api client sends PATCH bodies with authenticated headers', () async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(() => server.close(force: true));
    final Completer<void> handled = Completer<void>();

    server.listen((HttpRequest request) async {
      expect(request.method, 'PATCH');
      expect(request.uri.path, '/room/topic');
      expect(
        request.headers.value(HttpHeaders.authorizationHeader),
        'Bearer room-test',
      );
      final String body = await utf8.decoder.bind(request).join();
      expect(jsonDecode(body), <String, Object?>{
        'roomId': 9527,
        'topicTitle': '今晚话题',
      });
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(<String, Object?>{
          'code': 200,
          'message': '操作成功',
          'data': <String, Object?>{'value': true},
        }),
      );
      await request.response.close();
      handled.complete();
    });

    final ApiClient client = ApiClient(
      baseUri: Uri.parse('http://${server.address.address}:${server.port}/'),
      clientType: 'Android',
      clientInnerVersion: '43',
      authorizationProvider: () => 'Bearer room-test',
    );
    await client.patch(
      '/room/topic',
      body: <String, Object?>{'roomId': 9527, 'topicTitle': '今晚话题'},
    );
    await handled.future;
  });
}
