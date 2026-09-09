import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/features/discovery/dynamic/data/backend_dynamic_repository.dart';

void main() {
  test(
    'S14 unknown followed by40952 retains original command without success',
    () async {
      final h = await _Harness.start();
      addTearDown(h.close);
      h.status = 500;
      await expectLater(
        h.repo.deleteComment(dynamicId: 'p1', commentId: 'c1'),
        throwsA(isA<ApiException>()),
      );
      final original = h.repo.pendingCommentMutation!.requestId;
      h.status = 409;
      h.code = 40952;
      await expectLater(
        h.repo.deleteComment(dynamicId: 'p1', commentId: 'c1'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 40952)),
      );
      expect(h.repo.pendingCommentMutation?.requestId, original);
      expect(h.writes.first, h.writes.last);
    },
  );
  test('S14 duplicate delete taps share a single transport request', () async {
    final h = await _Harness.start();
    addTearDown(h.close);
    h.holdResponse = true;
    final first = h.repo.deleteComment(dynamicId: 'p1', commentId: 'c1');
    await h.entered.future;
    final second = h.repo.deleteComment(dynamicId: 'p1', commentId: 'c1');
    h.release.complete();
    expect((await first).commentCount, 7);
    expect((await second).commentCount, 7);
    expect(h.writes, hasLength(1));
  });
  test(
    'S14 parent tombstone and missing capabilities fail closed; add replay hides body',
    () async {
      var row = <String, Object?>{
        'commentId': 'c1',
        'content': 'child text',
        'userId': 1,
        'nickName': 'A',
        'createdAt': '2026-09-09T00:00:00Z',
        'parentCommentId': 'parent',
        'status': 'PUBLISHED',
        'deleted': false,
        'parentCommentStatus': 'DELETED',
        'parentCommentUnavailable': true,
        'parentCommentPlaceholder': '该评论已删除',
      };
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final transport = HttpClient();
      addTearDown(() async {
        transport.close(force: true);
        await server.close(force: true);
      });
      server.listen((request) async {
        await request.drain<void>();
        request.response.write(
          jsonEncode({
            'code': 200,
            'message': 'OK',
            'data': request.method == 'POST'
                ? row
                : {
                    'list': [row],
                    'records': [row],
                    'total': 1,
                    'pages': 1,
                    'current': 1,
                    'pageSize': 30,
                  },
          }),
        );
        await request.response.close();
      });
      final repo = BackendDynamicRepository(
        apiClient: ApiClient(
          baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
          clientType: 'test',
          clientInnerVersion: '1',
          authorizationProvider: () => 'Bearer A',
          httpClient: transport,
        ),
        routes: const BackendRouteCatalog(),
        currentUserIdProvider: () => 1,
      );
      final comment = (await repo.fetchComments(dynamicId: 'p1')).items.single;
      expect(comment.content, 'child text');
      expect(comment.parentCommentPlaceholder, '该评论已删除');
      expect(comment.canDelete, isFalse);
      expect(comment.canReply, isFalse);
      final valid = Map<String, Object?>.of(row);
      for (final invalid in [
        <String, Object?>{'deleted': true},
        {'canReply': 'true'},
        {'parentCommentUnavailable': false},
        {'parentCommentStatus': 'UNKNOWN'},
        {'parentCommentPlaceholder': 'leaked parent text'},
      ]) {
        row = {...valid, ...invalid};
        await expectLater(
          repo.fetchComments(dynamicId: 'p1'),
          throwsA(isA<ApiException>()),
        );
      }
      row = {
        ...valid,
        'status': 'DELETED',
        'deleted': true,
        'content': '',
        'canReply': false,
        'canDelete': false,
      };
      final hidden = await repo.addComment(
        dynamicId: 'p1',
        content: 'original archived text',
        replyToCommentId: 'parent',
        requestId: 'original-key',
      );
      expect(hidden.content, isEmpty);
      expect(hidden.status, 'DELETED');
    },
  );
  test(
    'S14 delete exact HTTP body/key, unknown retry and target binding',
    () async {
      final h = await _Harness.start();
      addTearDown(h.close);
      h.status = 500;
      await expectLater(
        h.repo.deleteComment(dynamicId: 'p1', commentId: 'c1'),
        throwsA(isA<ApiException>()),
      );
      final pending = h.repo.pendingCommentMutation!;
      await expectLater(
        h.repo.deleteComment(dynamicId: 'p1', commentId: 'c2'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 40903)),
      );
      expect(h.writes, hasLength(1));
      h.status = 200;
      final result = await h.repo.deleteComment(
        dynamicId: 'p1',
        commentId: 'c1',
      );
      expect(result.commentCount, 7);
      expect(h.writes, hasLength(2));
      expect(h.writes[0], h.writes[1]);
      expect(jsonDecode(h.writes[0].$3), {
        'dynamicId': 'p1',
        'commentId': 'c1',
      });
      expect(h.writes[0].$2, pending.requestId);
      expect(h.repo.pendingCommentMutation, isNull);
      await expectLater(
        h.repo.deleteComment(
          dynamicId: 'p1',
          commentId: 'c2',
          requestId: pending.requestId,
        ),
        throwsA(isA<ApiException>()),
      );
    },
  );
  for (final code in [40352, 40452, 40451, 40903, 40952]) {
    test('S14 definite rejection $code never reports deletion', () async {
      final h = await _Harness.start();
      addTearDown(h.close);
      h.status = code ~/ 100;
      h.code = code;
      await expectLater(
        h.repo.deleteComment(dynamicId: 'p1', commentId: 'c1'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', code)),
      );
      expect(h.repo.pendingCommentMutation, isNull);
      expect(h.writes, hasLength(1));
    });
  }
  test('S14 mismatched deletion receipt remains unknown', () async {
    final h = await _Harness.start();
    addTearDown(h.close);
    for (final invalid in [
      <String, Object?>{'commentId': 'other'},
      {'commentCount': 1.5},
      {'canReply': true},
      {'deleted': false},
      {'status': 'HIDDEN'},
    ]) {
      h.overrides = invalid;
      await expectLater(
        h.repo.deleteComment(dynamicId: 'p1', commentId: 'c1'),
        throwsA(isA<ApiException>()),
      );
      expect(h.repo.pendingCommentMutation, isNotNull);
    }
    expect(h.writes.map((r) => r.$2).toSet(), hasLength(1));
  });
  for (final stage in ['open', 'response']) {
    test(
      'S14 identity $stage fence keeps A key/body, B never reuses A future',
      () async {
        final h = await _Harness.start(delayOpen: stage == 'open');
        addTearDown(h.close);
        h.holdResponse = stage == 'response';
        final old = h.repo
            .deleteComment(dynamicId: 'p1', commentId: 'c1')
            .then<Object>((v) => v, onError: (Object e) => e);
        await (stage == 'open' ? h.transport.entered.future : h.entered.future);
        final pending = h.repo.pendingCommentMutation!;
        h.user = 2;
        h.generation++;
        expect(h.repo.pendingCommentMutation, isNull);
        if (stage == 'open')
          h.transport.release.complete();
        else
          h.release.complete();
        expect(await old, isA<ApiException>());
        expect(h.writes.any((r) => r.$1 == 'Bearer user-2'), isFalse);
        if (stage == 'open') expect(h.writes, isEmpty);
        final b = await h.repo.deleteComment(dynamicId: 'p1', commentId: 'c1');
        expect(b.commentCount, 7);
        final bKey = h.writes.last.$2;
        expect(bKey, isNot(pending.requestId));
        h.user = 1;
        h.generation++;
        expect(h.repo.pendingCommentMutation?.requestId, pending.requestId);
        await h.repo.deleteComment(dynamicId: 'p1', commentId: 'c1');
        expect(h.writes.last.$2, pending.requestId);
        expect(h.writes.last.$3, jsonEncode(pending.body));
        if (stage == 'response') expect(h.writes.first, h.writes.last);
      },
    );
  }
  test(
    'S14 hidden comment text in list is rejected, never displayed',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        final row = <String, Object?>{
          'commentId': 'c1',
          'userId': 1,
          'nickName': 'A',
          'content': 'hidden secret',
          'createdAt': '2026-09-09T01:00:00Z',
          'status': 'HIDDEN',
          'deleted': false,
          'canDelete': true,
          'canReply': false,
          'parentCommentId': '',
          'parentCommentStatus': 'NONE',
          'parentCommentUnavailable': false,
          'parentCommentPlaceholder': '',
        };
        request.response.write(
          jsonEncode({
            'code': 200,
            'message': 'OK',
            'data': {
              'list': [row],
              'records': [row],
              'total': 1,
              'pages': 1,
              'current': 1,
              'pageSize': 30,
            },
          }),
        );
        await request.response.close();
      });
      final transport = HttpClient();
      addTearDown(() async {
        transport.close(force: true);
        await server.close(force: true);
      });
      final repo = BackendDynamicRepository(
        apiClient: ApiClient(
          baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
          clientType: 'test',
          clientInnerVersion: '1',
          authorizationProvider: () => 'Bearer A',
          httpClient: transport,
        ),
        routes: const BackendRouteCatalog(),
        currentUserIdProvider: () => 1,
      );
      await expectLater(
        repo.fetchComments(dynamicId: 'p1'),
        throwsA(isA<ApiException>()),
      );
    },
  );
}

class _Harness {
  _Harness(this.server, this.transport);
  final HttpServer server;
  final _DelayedClient transport;
  late BackendDynamicRepository repo;
  int user = 1, generation = 0, status = 200;
  int? code;
  Map<String, Object?> overrides = {};
  final writes = <(String?, String?, String)>[];
  final entered = Completer<void>(), release = Completer<void>();
  bool holdResponse = false;
  static Future<_Harness> start({bool delayOpen = false}) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final h = _Harness(server, _DelayedClient(delayOpen));
    h.repo = BackendDynamicRepository(
      apiClient: ApiClient(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
        clientType: 'test',
        clientInnerVersion: '1',
        authorizationProvider: () => 'Bearer user-${h.user}',
        httpClient: h.transport,
      ),
      routes: const BackendRouteCatalog(),
      currentUserIdProvider: () => h.user,
      identityGeneration: () => h.generation,
    );
    server.listen((request) async {
      expect(request.method, 'POST');
      expect(request.uri.path, '/app-mini-api/mini/v1/dynamic/comment/delete');
      h.writes.add((
        request.headers.value('Authorization'),
        request.headers.value('X-Request-Id'),
        await utf8.decoder.bind(request).join(),
      ));
      if (h.holdResponse) {
        h.holdResponse = false;
        h.entered.complete();
        await h.release.future;
      }
      request.response.statusCode = h.status;
      request.response.write(
        jsonEncode({
          'code': h.code ?? h.status,
          'message': 'fixture',
          'data': {
            'dynamicId': 'p1',
            'commentId': 'c1',
            'status': 'DELETED',
            'deleted': true,
            'canDelete': false,
            'canReply': false,
            'commentCount': 7,
            ...h.overrides,
          },
        }),
      );
      await request.response.close();
    });
    return h;
  }

  Future<void> close() async {
    transport.close(force: true);
    await server.close(force: true);
  }
}

class _DelayedClient implements HttpClient {
  _DelayedClient(this.delay);
  bool delay;
  final delegate = HttpClient();
  final entered = Completer<void>(), release = Completer<void>();
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    if (delay) {
      delay = false;
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
