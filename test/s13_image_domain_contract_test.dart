import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/features/discovery/dynamic/data/backend_dynamic_repository.dart';
import 'package:voice_social_app/features/discovery/dynamic/domain/dynamic_models.dart';
import 'package:voice_social_app/features/social/data/backend_social_repository.dart';
import 'package:voice_social_app/core/media/media_models.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'support/media_http_fakes.dart';

const imageAsset = '11111111-2222-4333-8444-555555555555';
Map<String, Object?> imageReference(String purpose) => {
  'assetId': imageAsset,
  'purpose': purpose,
  'mediaType': 'image/png',
  'bytes': 12,
  'durationMillis': 0,
  'version': 3,
};
Map<String, Object?> imagePost({String content = ''}) => {
  'dynamicId': '42',
  'userId': 1,
  'nickName': '作者',
  'content': content,
  'category': 'LIFE',
  'topic': '',
  'location': '',
  'createdAt': '2026-09-10T00:00:00Z',
  'likeCount': 0,
  'commentCount': 0,
  'liked': false,
  'images': <String>[],
  'media': [imageReference('DYNAMIC_IMAGE')],
  'objectStorageStatus': 'VENDOR_BLOCKED',
};

void main() {
  for (final support in [false, true]) {
    test(
      '${support ? 'support' : 'dynamic'} image write binds send before delayed open and rejects ABA',
      () async {
        final identity = TestMediaIdentity();
        addTearDown(identity.dispose);
        final entered = Completer<void>();
        final release = Completer<void>();
        final http = MediaFakeHttp((r) => throw StateError('must not send'))
          ..beforeOpen = (_) async {
            entered.complete();
            await release.future;
          };
        final api = http.api(identity);
        final result = expectLater(
          support
              ? BackendSocialRepository(
                  apiClient: api,
                  currentUserIdProvider: () => identity.user,
                  identityGeneration: () => identity.generation,
                ).submitFeedback(
                  subject: '主题',
                  content: '描述',
                  requestId: 'bound-image',
                  media: [
                    MediaReference.fromJson(imageReference('SUPPORT_IMAGE')),
                  ],
                )
              : BackendDynamicRepository(
                  apiClient: api,
                  routes: const BackendRouteCatalog(),
                  currentUserIdProvider: () => identity.user,
                  identityGeneration: () => identity.generation,
                ).publish(
                  PublishDynamicRequest(
                    content: '',
                    category: DynamicCategory.companionship,
                    media: [
                      MediaReference.fromJson(imageReference('DYNAMIC_IMAGE')),
                    ],
                  ),
                  requestId: 'bound-image',
                ),
          throwsA(isA<ApiException>()),
        );
        await entered.future;
        identity.change(2);
        identity.change(1);
        release.complete();
        await result;
        expect(http.requests.single.body, isEmpty);
        expect(http.requests.single.closes, 0);
        expect(http.requests.single.aborted, isTrue);
      },
    );
  }
  test(
    'image domain 401 refresh same identity preserves key and payload; changed identity never retries',
    () async {
      for (final change in [false, true]) {
        final identity = TestMediaIdentity();
        var calls = 0;
        var refreshes = 0;
        final http = MediaFakeHttp((r) {
          if (++calls == 1) {
            if (change) identity.change(2);
            return MediaFakeResponse.json(null, status: 401, code: 40101);
          }
          return MediaFakeResponse.json(imagePost());
        });
        final api = http.api(
          identity,
          refresh: () async {
            refreshes++;
            identity.refreshToken();
            return true;
          },
        );
        final repo = BackendDynamicRepository(
          apiClient: api,
          routes: const BackendRouteCatalog(),
          currentUserIdProvider: () => identity.user,
          identityGeneration: () => identity.generation,
        );
        final result = repo.publish(
          PublishDynamicRequest(
            content: '',
            category: DynamicCategory.companionship,
            media: [MediaReference.fromJson(imageReference('DYNAMIC_IMAGE'))],
          ),
          requestId: 'refresh-image',
        );
        if (change) {
          await expectLater(result, throwsA(isA<ApiException>()));
          expect(calls, 1);
          expect(refreshes, 0);
        } else {
          await result;
          expect(calls, 2);
          expect(refreshes, 1);
          expect(http.requests[0].body, http.requests[1].body);
          expect(
            http.requests[0].headers.value('X-Request-Id'),
            http.requests[1].headers.value('X-Request-Id'),
          );
          expect(
            http.requests[1].headers.value('Authorization'),
            'Bearer contract-refreshed',
          );
        }
        identity.dispose();
      }
    },
  );
  test(
    'dynamic publishes pure image with IDs only and fixed request key',
    () async {
      await withImageServer(
        (r, body) async {
          expect(r.uri.path, '/app-mini-api/mini/v1/dynamic/publish');
          expect(r.headers.value('X-Request-Id'), 'image-command');
          expect(body, {
            'content': '',
            'category': 'LIFE',
            'topic': '',
            'location': '',
            'mediaAssetIds': [imageAsset],
          });
          return imagePost();
        },
        (api) async {
          final repo = dynamicRepo(api);
          expect(repo.supportsImagePublishing, isTrue);
          final post = await repo.publish(
            PublishDynamicRequest(
              content: '',
              category: DynamicCategory.companionship,
              media: [MediaReference.fromJson(imageReference('DYNAMIC_IMAGE'))],
            ),
            requestId: 'image-command',
          );
          expect(post.media.single.assetId, imageAsset);
        },
      );
    },
  );
  test('missing returned attachment is not publish success', () async {
    await withImageServer(
      (r, body) async => imagePost(content: '文字')..['media'] = [],
      (api) async {
        await expectLater(
          dynamicRepo(api).publish(
            PublishDynamicRequest(
              content: '文字',
              category: DynamicCategory.companionship,
              media: [MediaReference.fromJson(imageReference('DYNAMIC_IMAGE'))],
            ),
            requestId: 'image-command',
          ),
          throwsA(isA<ApiException>()),
        );
      },
    );
  });
  for (final bad in <Object?>[
    null,
    'https://external.invalid/image',
    [imageReference('SUPPORT_IMAGE')],
    [
      imageReference('DYNAMIC_IMAGE')
        ..['url'] = 'https://external.invalid/image',
    ],
    [imageReference('DYNAMIC_IMAGE')..['bytes'] = 1.5],
    List.generate(10, (_) => imageReference('DYNAMIC_IMAGE')),
  ]) {
    test('dynamic fails closed for invalid six-field media $bad', () async {
      await withImageServer((r, body) async => imagePost()..['media'] = bad, (
        api,
      ) async {
        await expectLater(
          dynamicRepo(api).fetchPost('42'),
          throwsA(isA<ApiException>()),
        );
      });
    });
  }
  test(
    'support create/reply post asset IDs and parse event-scoped six fields',
    () async {
      final paths = <String>[];
      await withImageServer(
        (r, body) async {
          paths.add(r.uri.path);
          final reply = r.uri.path.endsWith('/replies');
          expect(
            body,
            reply
                ? {
                    'message': '补充',
                    'mediaAssetIds': [imageAsset],
                  }
                : {
                    'subject': '主题',
                    'content': '描述',
                    'mediaAssetIds': [imageAsset],
                  },
          );
          expect(
            r.headers.value('X-Request-Id'),
            reply ? 'reply-original' : 'create-original',
          );
          return imageTicket(reply: reply);
        },
        (api) async {
          final repo = BackendSocialRepository(
            apiClient: api,
            currentUserIdProvider: () => 1,
          );
          final media = [
            MediaReference.fromJson(imageReference('SUPPORT_IMAGE')),
          ];
          final created = await repo.submitFeedback(
            subject: '主题',
            content: '描述',
            media: media,
            requestId: 'create-original',
          );
          expect(created.events.single.media.single.assetId, imageAsset);
          final replied = await repo.replyToSupportTicket(
            ticketId: 'ticket-1',
            message: '补充',
            media: media,
            requestId: 'reply-original',
          );
          expect(replied.events.length, 2);
          expect(replied.events.every((e) => e.media.length == 1), isTrue);
        },
      );
      expect(paths, [
        '/app-api/suggestion/saveSugggestion',
        '/app-mini-api/mini/v1/support/tickets/ticket-1/replies',
      ]);
    },
  );
  test(
    'support each event limit and legacy null event id are independent',
    () async {
      final wire = imageTicket();
      await withImageServer((r, body) async => wire, (api) async {
        final repo = BackendSocialRepository(
          apiClient: api,
          currentUserIdProvider: () => 1,
        );
        wire['events'] = [
          imageEvent('CREATED', '描述')
            ..['media'] = []
            ..['eventId'] = null,
        ];
        expect(
          (await repo.fetchSupportTicket('ticket-1')).events.single.eventId,
          isNull,
        );
        wire['events'] = [imageEvent('CREATED', '描述')..['eventId'] = null];
        await expectLater(
          repo.fetchSupportTicket('ticket-1'),
          throwsA(isA<ApiException>()),
        );
        wire['events'] = [
          imageEvent('CREATED', '描述')
            ..['media'] = List.generate(
              4,
              (_) => imageReference('SUPPORT_IMAGE'),
            ),
        ];
        await expectLater(
          repo.fetchSupportTicket('ticket-1'),
          throwsA(isA<ApiException>()),
        );
      });
    },
  );
  test('late dynamic and support reads reject identity ABA', () async {
    var generation = 1;
    final entered = Completer<void>();
    final release = Completer<void>();
    await withImageServer(
      (r, body) async {
        if (!entered.isCompleted) entered.complete();
        await release.future;
        return r.uri.path.contains('dynamic') ? imagePost() : imageTicket();
      },
      (api) async {
        final dynamic = BackendDynamicRepository(
          apiClient: api,
          routes: const BackendRouteCatalog(),
          currentUserIdProvider: () => 1,
          identityGeneration: () => generation,
        );
        final social = BackendSocialRepository(
          apiClient: api,
          currentUserIdProvider: () => 1,
          identityGeneration: () => generation,
        );
        final one = expectLater(
          dynamic.fetchPost('42'),
          throwsA(isA<ApiException>()),
        );
        final two = expectLater(
          social.fetchSupportTicket('ticket-1'),
          throwsA(isA<ApiException>()),
        );
        await entered.future;
        generation += 2;
        release.complete();
        await Future.wait([one, two]);
      },
    );
  });
  test(
    'pure-image dynamic detail accepts authoritative media despite legacy vendor status',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final http = HttpClient();
      addTearDown(() async {
        http.close(force: true);
        await server.close(force: true);
      });
      server.listen((r) async {
        await r.drain<void>();
        r.response.write(
          jsonEncode({'code': 200, 'message': 'OK', 'data': imagePost()}),
        );
        await r.response.close();
      });
      final repo = BackendDynamicRepository(
        apiClient: ApiClient(
          baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
          clientType: 'test',
          clientInnerVersion: '1',
          authorizationProvider: () => 'Bearer contract-s13',
          httpClient: http,
        ),
        routes: const BackendRouteCatalog(),
        currentUserIdProvider: () => 1,
      );
      expect((await repo.fetchPost('42')).content, '');
    },
  );
}

BackendDynamicRepository dynamicRepo(ApiClient api) => BackendDynamicRepository(
  apiClient: api,
  routes: const BackendRouteCatalog(),
  currentUserIdProvider: () => 1,
);
Map<String, Object?> imageEvent(String type, String text) => {
  'eventId': imageAsset,
  'actorType': 'USER',
  'eventType': type,
  'message': text,
  'createdAt': '2026-09-10T00:00:00Z',
  'media': [imageReference('SUPPORT_IMAGE')],
};
Map<String, Object?> imageTicket({bool reply = false}) => {
  'ticketId': 'ticket-1',
  'subject': '主题',
  'content': '描述',
  'status': 'PROCESSING',
  'createdAt': '2026-09-10T00:00:00Z',
  'progressAvailable': true,
  'version': reply ? 1 : 0,
  'events': [
    imageEvent('CREATED', '描述'),
    if (reply) imageEvent('MESSAGE', '补充'),
  ],
};
Future<void> withImageServer(
  Future<Object?> Function(HttpRequest, Object?) respond,
  Future<void> Function(ApiClient) action,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final http = HttpClient();
  server.listen((r) async {
    final raw = await utf8.decoder.bind(r).join();
    final data = await respond(r, raw.isEmpty ? null : jsonDecode(raw));
    r.response.write(jsonEncode({'code': 200, 'message': 'OK', 'data': data}));
    await r.response.close();
  });
  try {
    await action(
      ApiClient(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
        clientType: 'test',
        clientInnerVersion: '1',
        authorizationProvider: () => 'Bearer contract-s13',
        httpClient: http,
      ),
    );
  } finally {
    http.close(force: true);
    await server.close(force: true);
  }
}
