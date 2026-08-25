import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/features/discovery/dynamic/data/backend_dynamic_repository.dart';
import 'package:voice_social_app/features/discovery/dynamic/domain/dynamic_models.dart';

void main() {
  test(
    'music publishing fails closed before making a backend request',
    () async {
      var requestCount = 0;
      final HttpServer server = await _startServer((HttpRequest request) async {
        requestCount += 1;
        await _reply(request, data: _post(category: 'OTHER'));
      });
      addTearDown(() => server.close(force: true));
      final BackendDynamicRepository repository = _repository(server);

      await expectLater(
        repository.publish(
          const PublishDynamicRequest(
            content: '分享一首歌',
            category: DynamicCategory.music,
          ),
        ),
        throwsA(
          isA<ApiException>()
              .having(
                (ApiException error) => error.kind,
                'kind',
                ApiFailureKind.configuration,
              )
              .having(
                (ApiException error) => error.message,
                'message',
                contains('音乐'),
              ),
        ),
      );
      expect(requestCount, 0);
    },
  );

  test(
    'all-category publishing fails closed instead of becoming chat',
    () async {
      var requestCount = 0;
      final HttpServer server = await _startServer((HttpRequest request) async {
        requestCount += 1;
        await _reply(request, data: _post(category: 'CHAT'));
      });
      addTearDown(() => server.close(force: true));
      final BackendDynamicRepository repository = _repository(server);

      await expectLater(
        repository.publish(
          const PublishDynamicRequest(
            content: '没有发布分类',
            category: DynamicCategory.all,
          ),
        ),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.configuration,
          ),
        ),
      );
      expect(requestCount, 0);
    },
  );

  test(
    'music feed filter fails closed before making a backend request',
    () async {
      var requestCount = 0;
      final HttpServer server = await _startServer((HttpRequest request) async {
        requestCount += 1;
        await _reply(
          request,
          data: <String, Object?>{
            'current': 1,
            'pageSize': 20,
            'total': 1,
            'pages': 1,
            'records': <Object?>[_post(category: 'OTHER')],
            'list': <Object?>[_post(category: 'OTHER')],
          },
        );
      });
      addTearDown(() => server.close(force: true));
      final BackendDynamicRepository repository = _repository(server);

      await expectLater(
        repository.fetchFeed(category: DynamicCategory.music),
        throwsA(
          isA<ApiException>()
              .having(
                (ApiException error) => error.kind,
                'kind',
                ApiFailureKind.configuration,
              )
              .having(
                (ApiException error) => error.message,
                'message',
                contains('音乐'),
              ),
        ),
      );
      expect(requestCount, 0);
    },
  );

  for (final ({String name, Object? value}) category
      in <({String name, Object? value})>[
        (name: 'OTHER', value: 'OTHER'),
        (name: 'MUSIC', value: 'MUSIC'),
        (name: 'unknown', value: 'FUTURE_CATEGORY'),
        (name: 'missing', value: null),
      ]) {
    test('read rejects unsupported ${category.name} category', () async {
      final HttpServer server = await _startServer((HttpRequest request) async {
        await _reply(request, data: _post(category: category.value));
      });
      addTearDown(() => server.close(force: true));
      final BackendDynamicRepository repository = _repository(server);

      await expectLater(
        repository.fetchPost('42'),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.protocol,
          ),
        ),
      );
    });
  }
}

BackendDynamicRepository _repository(HttpServer server) =>
    BackendDynamicRepository(
      apiClient: ApiClient(
        baseUri: Uri.parse('http://${server.address.address}:${server.port}/'),
        clientType: 'Android',
        clientInnerVersion: '6',
        authorizationProvider: () => 'Bearer category-contract-test',
      ),
      routes: const BackendRouteCatalog(),
      currentUserIdProvider: () => 10001,
    );

Map<String, Object?> _post({required Object? category}) => <String, Object?>{
  'dynamicId': '42',
  'userId': 10001,
  'nickName': '晚星',
  'content': '今晚听歌吗',
  'createdAt': '2026-08-22T09:00:00Z',
  if (category != null) 'category': category,
  'topic': '夜聊',
  'location': '上海',
  'likeCount': 0,
  'commentCount': 0,
  'liked': false,
  'isLike': 0,
  'images': <String>[],
};

Future<HttpServer> _startServer(
  Future<void> Function(HttpRequest request) handler,
) async {
  final HttpServer server = await HttpServer.bind(
    InternetAddress.loopbackIPv4,
    0,
  );
  server.listen(handler);
  return server;
}

Future<void> _reply(HttpRequest request, {required Object? data}) async {
  request.response
    ..statusCode = HttpStatus.ok
    ..headers.contentType = ContentType.json
    ..write(
      jsonEncode(<String, Object?>{'code': 200, 'message': 'OK', 'data': data}),
    );
  await request.response.close();
}
