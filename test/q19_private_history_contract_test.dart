import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/features/message/data/backend_message_repository.dart';
import 'package:voice_social_app/features/message/domain/message_models.dart';
import 'support/media_http_fakes.dart';

const conversation = ConversationSummary(
  id: '00000000-0000-0000-0000-000000000001',
  kind: ConversationKind.privateChat,
  title: 'peer',
  lastMessage: '',
  updatedAt: null,
  unreadCount: 0,
  targetUserId: 2,
);

Map<String, Object?> watermark({String version = '0', String through = '0'}) =>
    {
      'conversationId': conversation.id,
      'targetUserId': 2,
      'historyVersion': version,
      'clearedThroughSequence': through,
    };
Map<String, Object?> row(String sequence) => {
  'messageId': 'msg-$sequence',
  'conversationId': conversation.id,
  'messageSequence': sequence,
  'senderUserId': 2,
  'receiverUserId': 1,
  'direction': 'INCOMING',
  'messageType': 'TEXT',
  'content': 'text-$sequence',
  'createdAt': '2026-09-10T00:00:00Z',
  'media': [],
};
Map<String, Object?> history({
  String version = '0',
  String through = '0',
  List<String> sequences = const ['1'],
}) => {
  ...watermark(version: version, through: through),
  'list': sequences.map(row).toList(),
  'hasMore': false,
  'nextCursor': '',
  'unreadCount': 0,
  'imStatus': 'VENDOR_BLOCKED',
  'providerInvocation': false,
};

class HistoryApi extends ApiClient {
  HistoryApi()
    : super(
        baseUri: Uri.parse('http://example.invalid'),
        clientType: 'test',
        clientInnerVersion: '1',
        authorizationProvider: () => 'test',
      );
  FutureOr<Object?> Function(String, Map<String, String>?) onGet = (_, _) =>
      history();
  FutureOr<Object?> Function(String, Map<String, Object?>?) onPost = (_, _) =>
      watermark(version: '1', through: '1');
  final posts = <({String path, Map<String, Object?>? body, String? key})>[];
  final gets = <String>[];
  Future<ApiResponse> _get(String path, Map<String, String>? query) async {
    gets.add(path);
    return ApiResponse(code: 200, message: '', data: await onGet(path, query));
  }

  Future<ApiResponse> _post(
    String path,
    Map<String, String>? headers,
    Map<String, Object?>? body,
  ) async {
    posts.add((path: path, body: body, key: headers?['X-Request-Id']));
    return ApiResponse(code: 200, message: '', data: await onPost(path, body));
  }

  @override
  Future<ApiResponse> get(
    String path, {
    Map<String, String>? query,
    Map<String, String>? headers,
    bool authenticated = true,
  }) => _get(path, query);
  @override
  Future<ApiResponse> post(
    String path, {
    Map<String, String>? query,
    Map<String, String>? headers,
    Map<String, Object?>? body,
    bool authenticated = true,
  }) => _post(path, headers, body);
  @override
  Future<ApiResponse> getBoundToIdentity(
    String path, {
    required void Function() requireIdentity,
    Map<String, String>? query,
    Map<String, String>? headers,
  }) async {
    requireIdentity();
    final result = await _get(path, query);
    requireIdentity();
    return result;
  }

  @override
  Future<ApiResponse> postBoundToIdentity(
    String path, {
    required void Function() requireIdentity,
    Map<String, String>? query,
    Map<String, String>? headers,
    Map<String, Object?>? body,
  }) async {
    requireIdentity();
    final result = await _post(path, headers, body);
    requireIdentity();
    return result;
  }
}

void main() {
  late HistoryApi api;
  late BackendMessageRepository repository;
  setUp(() {
    api = HistoryApi();
    repository = BackendMessageRepository(
      apiClient: api,
      routes: const BackendRouteCatalog(),
      currentUserIdProvider: () => 1,
    );
  });
  Future<void> clear() => repository.clearPrivateHistory(conversation);
  Future<List<ChatMessage>> page() async =>
      (await repository.fetchVisiblePrivateMessagePage(
        conversation,
        isCurrent: () => true,
      )).messages;

  for (final invalid in <Object?>[null, 0, -1, '1.0', '-1', ' 1', '1e3']) {
    test('history rejects non decimal-string watermark $invalid', () async {
      api.onGet = (_, _) => history()..['historyVersion'] = invalid;
      await expectLater(page(), throwsA(isA<ApiException>()));
      expect(api.posts, isEmpty);
    });
  }
  test('message sequence must be a positive decimal string', () async {
    api.onGet = (_, _) => history(sequences: ['0']);
    await expectLater(page(), throwsA(isA<ApiException>()));
  });
  test(
    'clear sends only target and retry retains key/body then a new action uses new key',
    () async {
      api.onPost = (_, _) => throw const ApiException(
        kind: ApiFailureKind.network,
        message: 'unknown',
      );
      await expectLater(clear(), throwsA(isA<ApiException>()));
      api.onPost = (_, _) => watermark(version: '1', through: '1');
      await clear();
      expect(api.posts, hasLength(2));
      expect(api.posts[0].key, api.posts[1].key);
      expect(api.posts[0].body, api.posts[1].body);
      expect(api.posts[0].path, '/app-mini-api/mini/v1/message/clear-history');
      expect(api.posts[0].body, {'targetUserId': 2});
      expect(api.posts[0].key, isNotEmpty);
      await clear();
      expect(api.posts.last.key, isNot(api.posts.first.key));
    },
  );
  test(
    'unknown clear then 40322 restores original receipt without clearing later messages',
    () async {
      final actor = TestMediaIdentity();
      addTearDown(actor.dispose);
      var writes = 0;
      String? originalKey;
      final http = MediaFakeHttp((request) {
        if (request.method == 'GET') {
          return MediaFakeResponse.json(
            history(version: '1', through: '1', sequences: ['2']),
          );
        }
        final key = request.headers.value('X-Request-Id');
        if (++writes == 1) {
          originalKey = key; // Committed through 1, but the receipt was lost.
          return MediaFakeResponse.json({}, status: 503, code: 50300);
        }
        if (writes == 2) {
          // Current actor authorization runs before historical receipt lookup.
          return MediaFakeResponse.json({}, status: 403, code: 40322);
        }
        return MediaFakeResponse.json(
          key == originalKey
              ? watermark(version: '1', through: '1')
              : watermark(version: '2', through: '2'),
        );
      });
      repository = BackendMessageRepository(
        apiClient: http.api(actor),
        routes: const BackendRouteCatalog(),
        currentUserIdProvider: () => actor.user,
        identityGenerationProvider: () => actor.generation,
      );
      await expectLater(clear(), throwsA(isA<ApiException>()));
      await expectLater(
        clear(),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 40322)),
      );
      expect(repository.hasPendingHistoryClear(2), isTrue);
      expect(repository.privateHistory.forTarget(2), isNull);
      actor.refreshToken(); // Eligibility recovers within the same identity.
      await clear();
      final posts = http.requests.where((r) => r.method == 'POST').toList();
      expect(posts, hasLength(3));
      expect(originalKey, isNotEmpty);
      for (final retry in posts.skip(1)) {
        expect(retry.headers.value('X-Request-Id'), originalKey);
        expect(retry.body, posts.first.body);
      }
      expect(repository.hasPendingHistoryClear(2), isFalse);
      expect(repository.privateHistory.forTarget(2)!.through, BigInt.one);
      expect((await page()).single.content, 'text-2');
    },
  );
  for (final nextUser in [0, 3]) {
    test(
      'unknown clear is not revived after identity ends via $nextUser',
      () async {
        var user = 1, generation = 0;
        repository = BackendMessageRepository(
          apiClient: api,
          routes: const BackendRouteCatalog(),
          currentUserIdProvider: () => user,
          identityGenerationProvider: () => generation,
        );
        api.onPost = (_, _) => throw const ApiException(
          kind: ApiFailureKind.network,
          message: 'unknown',
        );
        await expectLater(clear(), throwsA(isA<ApiException>()));
        final originalKey = api.posts.single.key;
        user = nextUser;
        generation++;
        if (nextUser == 0) {
          await expectLater(clear(), throwsA(isA<ApiException>()));
          expect(api.posts, hasLength(1));
        } else {
          expect(repository.hasPendingHistoryClear(2), isFalse);
        }
        user = 1;
        generation++;
        expect(repository.hasPendingHistoryClear(2), isFalse);
        api.onPost = (_, _) => watermark(version: '1', through: '1');
        await clear();
        expect(api.posts.last.key, isNot(originalKey));
      },
    );
  }
  test(
    'first definitive clear denial does not create an unknown intent',
    () async {
      api.onPost = (_, _) => throw const ApiException(
        kind: ApiFailureKind.forbidden,
        code: 40322,
        message: 'denied',
      );
      await expectLater(clear(), throwsA(isA<ApiException>()));
      expect(repository.hasPendingHistoryClear(2), isFalse);
      expect(repository.privateHistory.forTarget(2), isNull);
    },
  );
  test(
    'late history and old clear receipt never recover cleared messages; later messages survive',
    () async {
      final late = Completer<Object?>();
      api.onGet = (_, _) => late.future;
      final pending = page();
      await Future<void>.delayed(Duration.zero);
      await clear();
      late.complete(history());
      expect(await pending, isEmpty);
      api.onGet = (_, _) =>
          history(version: '2', through: '2', sequences: ['3']);
      expect((await page()).single.content, 'text-3');
      await clear(); // old version 1 receipt must not roll back version 2
      api.onGet = (_, _) =>
          history(version: '1', through: '1', sequences: ['2']);
      expect(await page(), isEmpty);
      api.onGet = (_, _) =>
          history(version: '2', through: '2', sequences: ['2', '3']);
      expect((await page()).map((m) => m.content), ['text-3']);
    },
  );
  test('BigInt watermark is lossless above safe JS integer', () async {
    api.onPost = (_, _) =>
        watermark(version: '9007199254740993', through: '9007199254740993');
    await clear();
    api.onGet = (_, _) => history(
      version: '9007199254740993',
      through: '9007199254740993',
      sequences: ['9007199254740993', '9007199254740994'],
    );
    expect((await page()).single.content, 'text-9007199254740994');
  });

  test('concurrent duplicate clear uses a single flight', () async {
    final gate = Completer<Object?>();
    api.onPost = (_, _) => gate.future;
    final first = clear();
    final second = clear();
    expect(api.posts, hasLength(1));
    gate.complete(watermark(version: '1', through: '1'));
    await Future.wait([first, second]);
    expect(repository.hasPendingHistoryClear(2), isFalse);
  });
  test(
    'clear is allowed for an unavailable existing peer, never for a draft',
    () async {
      await repository.clearPrivateHistory(
        conversation.copyWith(available: false),
      );
      expect(api.posts, hasLength(1));
      await expectLater(
        repository.clearPrivateHistory(
          const ConversationSummary.draft(
            kind: ConversationKind.privateChat,
            title: '',
            lastMessage: '',
            unreadCount: 0,
            targetUserId: 2,
          ),
        ),
        throwsA(isA<ApiException>()),
      );
      expect(api.posts, hasLength(1));
    },
  );
  for (final mutation in <Map<String, Object?>>[
    {'targetUserId': '2'},
    {'targetUserId': 3},
    {'conversationId': 'other'},
    {'historyVersion': '0'},
    {'clearedThroughSequence': 1},
  ]) {
    test('invalid clear receipt cannot claim success $mutation', () async {
      api.onPost = (_, _) => {
        ...watermark(version: '1', through: '1'),
        ...mutation,
      };
      await expectLater(clear(), throwsA(isA<ApiException>()));
      expect(repository.privateHistory.forTarget(2), isNull);
      expect(repository.hasPendingHistoryClear(2), isTrue);
    });
  }
  test(
    'same version disagreement and higher version decreasing watermark are rejected',
    () async {
      await clear();
      for (final version in ['1', '2']) {
        api.onGet = (_, _) => history(version: version, through: '0');
        await expectLater(page(), throwsA(isA<ApiException>()));
        expect(repository.privateHistory.forTarget(2)!.through, BigInt.one);
      }
    },
  );
  test(
    'empty conversation stays selectable with null time; stale summary is redacted',
    () async {
      Map<String, Object?> summaries(Map<String, Object?> item) => {
        'list': [item],
        'total': 1,
        'pageNum': 1,
        'pageSize': 100,
        'pages': 1,
        'hasMore': false,
      };
      await clear();
      api.onGet = (_, _) => summaries({
        ...watermark(version: '1', through: '1'),
        'lastMessageSequence': '0',
        'lastMessage': '',
        'lastMessageAt': '',
        'unreadCount': 0,
        'nickname': 'peer',
      });
      final empty = (await repository.fetchConversations()).single;
      expect(empty.id, conversation.id);
      expect(empty.isDraft, isFalse);
      expect(empty.updatedAt, isNull);
      expect(empty.lastMessage, '');
      api.onGet = (_, _) => summaries({
        ...watermark(),
        'lastMessageSequence': '1',
        'lastMessage': 'stale-secret',
        'lastMessageAt': '2026-09-10T00:00:00Z',
        'unreadCount': 9,
      });
      final stale = (await repository.fetchConversations()).single;
      expect(stale.lastMessage, '');
      expect(stale.unreadCount, 0);
      expect(stale.updatedAt, isNull);
    },
  );
  test(
    'read watermark removes messages fetched before a concurrent clear',
    () async {
      api.onPost = (_, _) => {
        ...watermark(version: '1', through: '1'),
        'markedRead': 0,
        'unreadCount': 0,
      };
      expect(await repository.fetchPrivateMessages(conversation), isEmpty);
    },
  );
  for (final operation in [
    'history',
    'clear',
    'read',
    'send',
    'conversations',
  ]) {
    test('$operation late response cannot survive account ABA', () async {
      var user = 1, generation = 0;
      repository = BackendMessageRepository(
        apiClient: api,
        routes: const BackendRouteCatalog(),
        currentUserIdProvider: () => user,
        identityGenerationProvider: () => generation,
      );
      final gate = Completer<Object?>();
      api.onGet = (_, _) => gate.future;
      api.onPost = (_, _) => gate.future;
      final Future<Object?> flight = switch (operation) {
        'history' => page(),
        'clear' => clear(),
        'read' => repository.markVisiblePrivateMessagesRead(
          conversation,
          isCurrent: () => true,
        ),
        'send' => repository.sendPrivateMessage(
          conversation: conversation,
          content: 'hello',
          requestId: 'old-key',
        ),
        _ => repository.fetchConversations(),
      };
      final result = expectLater(
        flight,
        throwsA(
          isA<ApiException>().having(
            (e) => e.kind,
            'kind',
            ApiFailureKind.unauthorized,
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      user = 3;
      generation++;
      expect(repository.privateHistory.forTarget(2), isNull);
      user = 1;
      generation++;
      gate.complete(history());
      await result;
      expect(repository.privateHistory.forTarget(2), isNull);
      expect(repository.hasPendingHistoryClear(2), isFalse);
    });
  }
  test(
    'late successful text send below known clear cannot return a bubble',
    () async {
      final gate = Completer<Object?>();
      api.onPost = (path, _) => path.endsWith('/send')
          ? gate.future
          : watermark(version: '1', through: '1');
      final send = repository.sendPrivateMessage(
        conversation: conversation,
        content: 'hello',
        requestId: 'old-key',
      );
      final result = expectLater(
        send,
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 40481)),
      );
      await clear();
      gate.complete({
        ...row('1'),
        ...watermark(),
        'senderUserId': 1,
        'receiverUserId': 2,
        'direction': 'OUTGOING',
        'content': 'hello',
        'providerInvocation': false,
        'storageStatus': 'FIRST_PARTY_STORED',
        'deliveryStatus': 'VENDOR_BLOCKED',
      });
      await result;
    },
  );
  for (final changed in [false, true]) {
    test(
      'real transport 401 ${changed ? "account ABA blocks retry" : "same account refresh preserves clear key and body"}',
      () async {
        final actor = TestMediaIdentity();
        addTearDown(actor.dispose);
        var calls = 0;
        final http = MediaFakeHttp(
          (_) => ++calls == 1
              ? MediaFakeResponse.json({}, status: 401, code: 40101)
              : MediaFakeResponse.json(watermark(version: '1', through: '1')),
        );
        repository = BackendMessageRepository(
          apiClient: http.api(
            actor,
            refresh: () async {
              if (changed) {
                actor.change(3);
                actor.change(1);
              } else {
                actor.refreshToken();
              }
              return true;
            },
          ),
          routes: const BackendRouteCatalog(),
          currentUserIdProvider: () => actor.user,
          identityGenerationProvider: () => actor.generation,
        );
        if (changed) {
          await expectLater(
            clear(),
            throwsA(
              isA<ApiException>().having(
                (e) => e.kind,
                'kind',
                ApiFailureKind.unauthorized,
              ),
            ),
          );
          expect(calls, 1);
          expect(repository.hasPendingHistoryClear(2), isFalse);
        } else {
          await clear();
          expect(calls, 2);
          expect(http.requests.last.body, http.requests.first.body);
          expect(
            http.requests.last.headers.value('X-Request-Id'),
            http.requests.first.headers.value('X-Request-Id'),
          );
          expect(
            http.requests.last.headers.value('Authorization'),
            'Bearer contract-refreshed',
          );
        }
      },
    );
  }
  test(
    'real transport clear late success cannot update the old or new account state',
    () async {
      final actor = TestMediaIdentity();
      addTearDown(actor.dispose);
      final gate = Completer<MediaFakeResponse>();
      final opened = Completer<void>();
      final http = MediaFakeHttp((_) {
        opened.complete();
        return gate.future;
      });
      repository = BackendMessageRepository(
        apiClient: http.api(actor),
        routes: const BackendRouteCatalog(),
        currentUserIdProvider: () => actor.user,
        identityGenerationProvider: () => actor.generation,
      );
      final old = repository.privateHistory;
      final failed = expectLater(clear(), throwsA(isA<ApiException>()));
      await opened.future;
      actor.change(3);
      actor.change(1);
      gate.complete(
        MediaFakeResponse.json(watermark(version: '1', through: '1')),
      );
      await failed;
      expect(old.forTarget(2), isNull);
      expect(repository.privateHistory.forTarget(2), isNull);
    },
  );
  test(
    'draft identity fallback after account change never queries A target with B token',
    () async {
      final actor = TestMediaIdentity();
      addTearDown(actor.dispose);
      final gate = Completer<MediaFakeResponse>();
      final listed = Completer<void>();
      final http = MediaFakeHttp((request) {
        if (request.uri.path.endsWith('/send')) {
          return MediaFakeResponse.json({
            ...row('1')..remove('conversationId'),
            ...watermark()..remove('conversationId'),
            'senderUserId': 1,
            'receiverUserId': 2,
            'direction': 'OUTGOING',
            'content': 'hello',
            'providerInvocation': false,
            'storageStatus': 'FIRST_PARTY_STORED',
            'deliveryStatus': 'VENDOR_BLOCKED',
          });
        }
        listed.complete();
        return gate.future;
      });
      repository = BackendMessageRepository(
        apiClient: http.api(actor),
        routes: const BackendRouteCatalog(),
        currentUserIdProvider: () => actor.user,
        identityGenerationProvider: () => actor.generation,
      );
      final denied = expectLater(
        repository.sendPrivateMessage(
          conversation: const ConversationSummary.draft(
            kind: ConversationKind.privateChat,
            title: 'A peer',
            lastMessage: '',
            unreadCount: 0,
            targetUserId: 2,
          ),
          content: 'hello',
        ),
        throwsA(
          isA<ApiException>().having(
            (e) => e.kind,
            'kind',
            ApiFailureKind.unauthorized,
          ),
        ),
      );
      await listed.future;
      actor.change(3);
      gate.complete(MediaFakeResponse.json({}, status: 403, code: 40322));
      await denied;
      expect(http.requests.map((r) => r.uri.path), [
        '/app-mini-api/mini/v1/message/send',
        '/app-mini-api/mini/v1/message/conversations',
      ]);
    },
  );
}
