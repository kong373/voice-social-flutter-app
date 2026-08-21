import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_client.dart';

void main() {
  test(
    'api client sends authenticated DELETE requests with query and body',
    () async {
      final HttpServer server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => server.close(force: true));
      final Completer<void> handled = Completer<void>();

      server.listen((HttpRequest request) async {
        expect(request.method, 'DELETE');
        expect(request.uri.path, '/account');
        expect(request.uri.queryParameters['smsCode'], '123456');
        expect(request.headers.value('Client-Type'), 'Android');
        expect(request.headers.value('Client-Inner-Version'), '43');
        expect(
          request.headers.value(HttpHeaders.authorizationHeader),
          'Bearer delete-test',
        );
        final String body = await utf8.decoder.bind(request).join();
        expect(jsonDecode(body), <String, Object?>{'reason': 'user_request'});

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
        clientInnerVersion: '43',
        authorizationProvider: () => 'Bearer delete-test',
      );
      final ApiResponse response = await client.delete(
        '/account',
        query: <String, String>{'smsCode': '123456'},
        body: <String, Object?>{'reason': 'user_request'},
      );

      await handled.future;
      expect(response.isSuccess, isTrue);
      expect(response.data, <String, Object?>{'accepted': true});
    },
  );
}
