import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/media/media_models.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'media_models_test.dart' show reference, mediaId;
import 'support/media_http_fakes.dart';

void main() {
  test(
    'media and existing identity-bound JSON share one refresh flight',
    () async {
      final actor = TestMediaIdentity();
      final scope = actor.scope();
      addTearDown(scope.dispose);
      final bothOld = Completer<void>();
      final refreshing = Completer<void>();
      final release = Completer<void>();
      int oldRequests = 0;
      int refreshes = 0;
      final http = MediaFakeHttp((r) {
        if (r.headers.value('Authorization') == 'Bearer contract-A-old') {
          if (++oldRequests == 2) bothOld.complete();
          return MediaFakeResponse.json(null, status: 401, code: 40101);
        }
        return MediaFakeResponse.json({});
      });
      final api = http.api(
        actor,
        refresh: () async {
          refreshes++;
          if (!refreshing.isCompleted) refreshing.complete();
          await release.future;
          actor.token = 'Bearer contract-A-new';
          return true;
        },
      );
      final media = api.mediaAssetJson(
        action: MediaAssetAction.allocate,
        purpose: MediaPurpose.privateImage,
        requestId: 'original-media-key',
        identity: scope,
      );
      final json = api.postBoundToIdentity(
        '/existing-json',
        requireIdentity: scope.check,
        headers: {'X-Request-Id': 'original-json-key'},
        body: {'value': 1},
      );
      await bothOld.future;
      await refreshing.future;
      release.complete();
      await Future.wait([media, json]);
      expect(refreshes, 1);
      expect(http.requests, hasLength(4));
      for (final path in ['/app-api/media/v1/assets', '/existing-json']) {
        final pair = http.requests.where((r) => r.uri.path == path).toList();
        expect(pair[0].body, pair[1].body);
        expect(
          pair[0].headers.value('X-Request-Id'),
          pair[1].headers.value('X-Request-Id'),
        );
      }
    },
  );

  test(
    'GET retry delayed open cannot adopt another account after refresh',
    () async {
      final actor = TestMediaIdentity();
      final scope = actor.scope();
      addTearDown(scope.dispose);
      final entered = Completer<void>();
      final release = Completer<void>();
      final http = MediaFakeHttp(
        (_) => MediaFakeResponse.json(null, status: 401, code: 40101),
      );
      http.beforeOpen = (number) async {
        if (number == 2) {
          entered.complete();
          await release.future;
        }
      };
      final api = http.api(
        actor,
        refresh: () async {
          actor.token = 'Bearer contract-A-new';
          return true;
        },
      );
      final pending = api
          .mediaAssetJson(
            action: MediaAssetAction.status,
            assetId: mediaId,
            identity: scope,
          )
          .then<Object>((value) => value, onError: (Object e) => e);
      await entered.future;
      actor.change(2);
      release.complete();
      expect(await pending, isA<ApiException>());
      await Future<void>.delayed(Duration.zero);
      expect(http.requests.where((r) => r.closes > 0), hasLength(1));
      expect(http.requests.last.aborted, isTrue);
      expect(http.requests.last.headers.value('Authorization'), isNull);
    },
  );
  test(
    'PUT actual chunks are raw, bounded, fixed path, no encoding or redirects',
    () async {
      final actor = TestMediaIdentity();
      final scope = actor.scope();
      addTearDown(scope.dispose);
      final http = MediaFakeHttp((_) => MediaFakeResponse.json({}));
      await http
          .api(actor)
          .putMediaAssetContent(
            assetId: mediaId,
            expectedVersion: 0,
            purpose: MediaPurpose.privateImage,
            bytes: 4,
            content: Stream.fromIterable([
              [0, 255],
              [1, 2],
            ]),
            identity: scope,
          );
      final sent = http.requests.single;
      expect(sent.body, [0, 255, 1, 2]);
      expect(sent.contentLength, 4);
      expect(
        sent.uri.toString(),
        'https://configured.backend.test/app-api/media/v1/assets/$mediaId/content?expectedVersion=0',
      );
      expect(sent.headers.value('Content-Type'), 'application/octet-stream');
      expect(sent.headers.value('Content-Encoding'), isNull);
      expect(sent.followRedirects, isFalse);
      expect(
        () => http
            .api(actor)
            .putMediaAssetContent(
              assetId: 'https://evil.test/$mediaId',
              expectedVersion: 0,
              purpose: MediaPurpose.privateImage,
              bytes: 4,
              content: const Stream.empty(),
              identity: scope,
            ),
        throwsA(isA<ApiException>()),
      );
    },
  );
  for (final chunks in [
    [
      [1, 2, 3, 4, 5],
    ],
    [
      [1, 2, 3],
    ],
  ]) {
    test('actual upload length mismatch aborts: $chunks', () async {
      final actor = TestMediaIdentity();
      final scope = actor.scope();
      addTearDown(scope.dispose);
      final http = MediaFakeHttp((_) => MediaFakeResponse.json({}));
      await expectLater(
        http
            .api(actor)
            .putMediaAssetContent(
              assetId: mediaId,
              expectedVersion: 0,
              purpose: MediaPurpose.privateImage,
              bytes: 4,
              content: Stream.fromIterable(chunks),
              identity: scope,
            ),
        throwsA(isA<ApiException>()),
      );
      expect(http.requests.single.aborted, isTrue);
      expect(http.requests.single.closes, 0);
      expect(http.requests.single.body.length, lessThanOrEqualTo(4));
    });
  }
  for (final verb in ['put', 'get']) {
    test(
      '$verb 401 shares refresh; only read replays with same identity',
      () async {
        final actor = TestMediaIdentity();
        final scope = actor.scope();
        addTearDown(scope.dispose);
        int calls = 0;
        int refreshes = 0;
        final http = MediaFakeHttp((_) {
          if (++calls == 1)
            return MediaFakeResponse.json(null, status: 401, code: 40101);
          return MediaFakeResponse(
            200,
            Stream.value(List.filled(12, 7)),
            type: 'image/png',
            contentLength: 12,
          );
        });
        final api = http.api(
          actor,
          refresh: () async {
            refreshes++;
            actor.token = 'Bearer contract-A-new';
            return true;
          },
        );
        if (verb == 'put') {
          await expectLater(
            api.putMediaAssetContent(
              assetId: mediaId,
              expectedVersion: 0,
              purpose: MediaPurpose.privateImage,
              bytes: 2,
              content: Stream.value([1, 2]),
              identity: scope,
            ),
            throwsA(isA<ApiException>().having((e) => e.code, 'code', 40101)),
          );
          expect(calls, 1);
        } else {
          final output = <int>[];
          await api.readMediaAssetContent(
            media: MediaReference.fromJson(reference()),
            identity: scope,
            onChunk: (data) async {
              output.addAll(data);
            },
          );
          expect(output, List.filled(12, 7));
          expect(calls, 2);
          expect(
            http.requests.last.headers.value('Authorization'),
            'Bearer contract-A-new',
          );
        }
        expect(
          http.requests.first.headers.value('Authorization'),
          'Bearer contract-A-old',
        );
        expect(refreshes, 1);
      },
    );
  }
  for (final moment in ['open', '401', 'refresh', 'body', 'idle-read']) {
    test(
      'identity ABA aborts $moment without B token, retry or late output',
      () async {
        final actor = TestMediaIdentity();
        final scope = actor.scope();
        addTearDown(scope.dispose);
        final entered = Completer<void>();
        final release = Completer<void>();
        final stream = StreamController<List<int>>.broadcast();
        addTearDown(stream.close);
        int refreshes = 0;
        final http = MediaFakeHttp((_) async {
          if (moment == '401') {
            actor.change(2);
            actor.change(1);
          }
          if (moment == '401' || moment == 'refresh')
            return MediaFakeResponse.json(null, status: 401, code: 40101);
          if (moment == 'idle-read') {
            entered.complete();
            return MediaFakeResponse(200, stream.stream, type: 'image/png');
          }
          return MediaFakeResponse.json({});
        });
        if (moment == 'open')
          http.beforeOpen = (_) async {
            entered.complete();
            await release.future;
          };
        final api = http.api(
          actor,
          refresh: () async {
            refreshes++;
            actor.change(2);
            actor.change(1);
            return true;
          },
        );
        int output = 0;
        Stream<List<int>> upload() async* {
          yield [1];
          if (moment == 'body') {
            entered.complete();
            await release.future;
          }
          yield [2];
        }

        final operation = moment == 'idle-read'
            ? api.readMediaAssetContent(
                media: MediaReference.fromJson(reference()),
                identity: scope,
                onChunk: (_) async {
                  output++;
                },
              )
            : api.putMediaAssetContent(
                assetId: mediaId,
                expectedVersion: 0,
                purpose: MediaPurpose.privateImage,
                bytes: 2,
                content: upload(),
                identity: scope,
              );
        final outcome = operation.then<Object?>(
          (value) => value,
          onError: (Object e) => e,
        );
        if (['open', 'body', 'idle-read'].contains(moment)) {
          await entered.future;
          actor.change(2);
          actor.change(1);
          release.complete();
        }
        expect(
          await outcome.timeout(const Duration(seconds: 2)),
          isA<ApiException>(),
        );
        await Future<void>.delayed(Duration.zero);
        expect(http.requests.every((r) => r.aborted), isTrue);
        expect(
          http.requests.any(
            (r) => r.headers.value('Authorization') == 'Bearer contract-2',
          ),
          isFalse,
        );
        expect(output, 0);
        expect(http.requests.length, lessThanOrEqualTo(1));
        expect(refreshes, moment == 'refresh' ? 1 : 0);
      },
    );
  }
  test(
    'redirect never follows Location; binary mismatches never succeed',
    () async {
      final actor = TestMediaIdentity();
      final scope = actor.scope();
      addTearDown(scope.dispose);
      for (final response in [
        MediaFakeResponse(302, const Stream.empty())
          ..headers.set('Location', 'https://outside.test/steal'),
        MediaFakeResponse(
          200,
          Stream.value(List.filled(13, 1)),
          type: 'image/png',
        ),
        MediaFakeResponse(
          200,
          Stream.value(List.filled(11, 1)),
          type: 'image/png',
        ),
        MediaFakeResponse(
          200,
          Stream.value(List.filled(12, 1)),
          type: 'video/mp4',
        ),
        MediaFakeResponse(
          200,
          Stream.value(List.filled(12, 1)),
          type: 'image/png',
        )..headers.set('Content-Encoding', 'gzip'),
      ]) {
        final http = MediaFakeHttp((_) => response);
        await expectLater(
          http
              .api(actor)
              .readMediaAssetContent(
                media: MediaReference.fromJson(reference()),
                identity: scope,
                onChunk: (_) async {},
              ),
          throwsA(isA<ApiException>()),
        );
        expect(http.requests, hasLength(1));
        expect(http.requests.single.followRedirects, isFalse);
      }
    },
  );
  test(
    '100MB controlled read streams chunks; metadata JSON limit remains 2MB',
    () async {
      final actor = TestMediaIdentity();
      final scope = actor.scope();
      addTearDown(scope.dispose);
      final media = MediaReference.fromJson({
        ...reference(purpose: 'PRIVATE_VIDEO'),
        'mediaType': 'video/mp4',
        'bytes': 100000000,
        'durationMillis': 30000,
      });
      final http = MediaFakeHttp(
        (r) => r.uri.path.endsWith('/content')
            ? MediaFakeResponse(
                200,
                Stream.fromIterable(
                  Iterable.generate(1000, (_) => List.filled(100000, 1)),
                ),
                type: 'video/mp4',
              )
            : MediaFakeResponse(
                200,
                Stream.value(
                  utf8.encode(
                    jsonEncode({
                      'code': 200,
                      'message': 'x' * (2 * 1024 * 1024),
                      'data': null,
                    }),
                  ),
                ),
              ),
      );
      final api = http.api(actor);
      int total = 0;
      int largest = 0;
      await api.readMediaAssetContent(
        media: media,
        identity: scope,
        onChunk: (chunk) async {
          total += chunk.length;
          if (chunk.length > largest) largest = chunk.length;
        },
      );
      expect(total, 100000000);
      expect(largest, 100000);
      expect(api.maximumResponseBytes, 2 * 1024 * 1024);
      await expectLater(
        api.mediaAssetJson(
          action: MediaAssetAction.status,
          assetId: mediaId,
          identity: scope,
        ),
        throwsA(isA<ApiException>()),
      );
    },
  );
}
