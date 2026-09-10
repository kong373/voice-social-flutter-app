import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/media/media_identity.dart';
import 'package:voice_social_app/core/media/media_models.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/features/message/data/backend_message_repository.dart';
import 'package:voice_social_app/features/message/domain/message_models.dart';
import 'package:voice_social_app/features/message/domain/message_repository.dart';

import 'support/media_http_fakes.dart';

const _assetId = '11111111-1111-4111-8111-111111111111';
const _conversation = ConversationSummary(
  id: 'server-conversation',
  kind: ConversationKind.privateChat,
  title: 'Peer',
  lastMessage: '',
  updatedAt: null,
  unreadCount: 0,
  targetUserId: 99,
);

Map<String, Object?> _media() => {
  'assetId': _assetId,
  'purpose': 'PRIVATE_IMAGE',
  'mediaType': 'image/png',
  'bytes': 50,
  'durationMillis': 0,
  'version': 3,
};

Map<String, Object?> _row() => {
  'messageSequence': '1',
  'historyVersion': '0',
  'clearedThroughSequence': '0',
  'messageId': 'stored-message',
  'senderUserId': 1,
  'receiverUserId': 99,
  'direction': 'OUTGOING',
  'messageType': 'IMAGE',
  'content': '',
  'media': [_media()],
  'storageStatus': 'FIRST_PARTY_STORED',
  'deliveryStatus': 'VENDOR_BLOCKED',
  'imStatus': 'VENDOR_BLOCKED',
  'providerInvocation': false,
  'read': false,
  'readAt': '',
  'createdAt': '2026-09-10T00:00:00Z',
};

Map<String, Object?> _page(Map<String, Object?> row) => {
  'historyVersion': '0',
  'clearedThroughSequence': '0',
  'conversationId': _conversation.id,
  'targetUserId': 99,
  'list': [row],
  'hasMore': false,
  'nextCursor': '',
  'unreadCount': 0,
  'imStatus': 'VENDOR_BLOCKED',
  'providerInvocation': false,
};

final _protocol = throwsA(
  isA<ApiException>().having((e) => e.kind, 'kind', ApiFailureKind.protocol),
);
final _unauthorized = throwsA(
  isA<ApiException>().having(
    (e) => e.kind,
    'kind',
    ApiFailureKind.unauthorized,
  ),
);
final _conflict = throwsA(
  isA<ApiException>().having((e) => e.kind, 'kind', ApiFailureKind.conflict),
);

void main() {
  final invalidRows = <String, Map<String, Object?>>{
    'missing attachment': _row()..remove('media'),
    'empty attachment list': {..._row(), 'media': <Object?>[]},
    'null attachment list': {..._row(), 'media': null},
    'object instead of list': {..._row(), 'media': _media()},
    'two attachments': {
      ..._row(),
      'media': [_media(), _media()],
    },
    'URL in metadata': {
      ..._row(),
      'media': [
        {..._media(), 'url': 'https://untrusted.test/image'},
      ],
    },
    'missing metadata': {
      ..._row(),
      'media': [_media()..remove('bytes')],
    },
    'wrong metadata numeric type': {
      ..._row(),
      'media': [
        {..._media(), 'bytes': '50'},
      ],
    },
    'mismatched purpose': {
      ..._row(),
      'media': [
        {..._media(), 'purpose': 'DYNAMIC_IMAGE'},
      ],
    },
    'unknown message type': {..._row(), 'messageType': 'FILE'},
    'wrong message type casing': {..._row(), 'messageType': 'image'},
    'null message type': {..._row(), 'messageType': null},
    'TEXT attachment': {..._row(), 'messageType': 'TEXT', 'content': 'hello'},
    'legacy type with attachment': _row()..remove('messageType'),
    'media nonempty content': {..._row(), 'content': 'not empty'},
    'media missing content': _row()..remove('content'),
    'wrong media receiver': {..._row(), 'receiverUserId': 100},
  };
  for (final entry in invalidRows.entries) {
    test(
      'history rejects ${entry.key} before any read acknowledgement',
      () async {
        final actor = TestMediaIdentity();
        addTearDown(actor.dispose);
        final http = MediaFakeHttp(
          (request) => MediaFakeResponse.json(
            request.method == 'GET'
                ? _page(entry.value)
                : {'targetUserId': 99, 'markedRead': 0, 'unreadCount': 0},
          ),
        );
        final repository = BackendMessageRepository(
          apiClient: http.api(actor),
          routes: const BackendRouteCatalog(),
          currentUserIdProvider: () => actor.user,
        );
        await expectLater(
          repository.fetchPrivateMessages(_conversation),
          _protocol,
        );
        expect(http.requests, hasLength(1));
        expect(http.requests.single.method, 'GET');
      },
    );
  }

  for (final type in [
    ChatMessageType.image,
    ChatMessageType.voice,
    ChatMessageType.video,
  ]) {
    test(
      '${type.wire} send uses exact body and retains the six metadata fields',
      () async {
        final metadata = {
          ..._media(),
          'purpose': type.mediaPurpose!.wire,
          'mediaType': switch (type) {
            ChatMessageType.voice => 'audio/ogg',
            ChatMessageType.video => 'video/mp4',
            _ => 'image/png',
          },
          'durationMillis': type == ChatMessageType.image ? 0 : 1000,
        };
        final row = {
          ..._row(),
          'messageType': type.wire,
          'media': [metadata],
        };
        final fixture = _Fixture((_) => MediaFakeResponse.json(row));
        final message = await fixture.send(
          media: MediaReference.fromJson(metadata),
        );
        expect(fixture.repository, isA<MediaPrivateMessageRepository>());
        expect(message.messageType, type);
        expect(message.media!.toJson(), metadata);
        expect(message.content, '');
        expect(message.status, ChatMessageStatus.storedPendingDelivery);
        expect(message.deliveryStatus, MessageDeliveryStatus.vendorBlocked);
        expect(message.receiptLabel, '已留存·未读·实时不可用');
        final request = fixture.http.requests.single;
        expect(request.method, 'POST');
        expect(request.uri.path, '/app-mini-api/mini/v1/message/send');
        expect(request.uri.query, '');
        expect(request.headers.value('X-Request-Id'), 'private-media-key');
        expect(jsonDecode(utf8.decode(request.body)), {
          'targetUserId': 99,
          'messageType': type.wire,
          'mediaAssetId': _assetId,
        });
      },
    );

    test(
      '${type.wire} incoming history and receipt copies preserve the attachment',
      () async {
        final metadata = {
          ..._media(),
          'purpose': type.mediaPurpose!.wire,
          'mediaType': type == ChatMessageType.voice
              ? 'audio/ogg'
              : type == ChatMessageType.video
              ? 'video/mp4'
              : 'image/png',
          'durationMillis': type == ChatMessageType.image ? 0 : 1000,
        };
        final fixture = _Fixture(
          (_) => MediaFakeResponse.json(
            _page({
              ..._row(),
              'senderUserId': 99,
              'receiverUserId': 1,
              'direction': 'INCOMING',
              'messageType': type.wire,
              'media': [metadata],
            }),
          ),
        );
        final batch = await fixture.repository.fetchVisiblePrivateMessagePage(
          _conversation,
          isCurrent: () => true,
        );
        final message = batch.messages.single;
        final copy = message
            .copyWith(
              read: true,
              readAt: DateTime.utc(2026, 9, 10),
              deliveryStatus: MessageDeliveryStatus.delivered,
            )
            .copyWith(
              status: ChatMessageStatus.received,
              conversationId: 'resolved',
              read: false,
            );
        expect(message.isMine, false);
        expect(copy.messageType, type);
        expect(identical(copy.media, message.media), true);
        expect(copy.media!.toJson(), metadata);
        expect(copy.content, '');
        expect(copy.read, true);
        expect(copy.readAt, DateTime.utc(2026, 9, 10));
        expect(fixture.http.requests.single.method, 'GET');
      },
    );
  }

  for (final legacy in [true, false]) {
    test(
      'TEXT ${legacy ? 'legacy absent' : 'explicit empty'} media stays compatible',
      () async {
        final row = {
          ..._row(),
          'messageType': 'TEXT',
          'content': 'hello',
          'media': <Object?>[],
        };
        if (legacy) {
          row.remove('messageType');
          row.remove('media');
        }
        final fixture = _Fixture((_) => MediaFakeResponse.json(_page(row)));
        final message =
            (await fixture.repository.fetchVisiblePrivateMessagePage(
              _conversation,
              isCurrent: () => true,
            )).messages.single;
        expect(message.messageType, ChatMessageType.text);
        expect(message.media, isNull);
        expect(message.content, 'hello');
        expect(
          ChatMessage(
            id: 'local',
            conversationId: null,
            senderUserId: 1,
            senderName: 'Me',
            content: 'draft',
            createdAt: DateTime.utc(2026),
            isMine: true,
            status: ChatMessageStatus.sending,
          ).messageType,
          ChatMessageType.text,
        );
      },
    );
  }

  final badReceipts = <String, Map<String, Object?>>{
    ...invalidRows,
    'sender mismatch': {..._row(), 'senderUserId': 2},
    'sender coercion': {..._row(), 'senderUserId': '1'},
    'receiver coercion': {..._row(), 'receiverUserId': '99'},
    'incoming receipt': {
      ..._row(),
      'senderUserId': 99,
      'receiverUserId': 1,
      'direction': 'INCOMING',
    },
    'different conversation': {..._row(), 'conversationId': 'other'},
    'not stored': {..._row(), 'storageStatus': 'PENDING'},
    'no storage evidence': _row()..remove('storageStatus'),
    'no IM evidence': _row()..remove('imStatus'),
    'unknown IM evidence': {..._row(), 'imStatus': 'MAYBE'},
    'no delivery evidence': _row()..remove('deliveryStatus'),
    'provider coercion': {..._row(), 'providerInvocation': 'false'},
    'blocked but invoked': {..._row(), 'providerInvocation': true},
    for (final entry in <String, Object?>{
      'assetId': '22222222-2222-4222-8222-222222222222',
      'purpose': 'SUPPORT_IMAGE',
      'mediaType': 'image/jpeg',
      'bytes': 51,
      'durationMillis': 1,
      'version': 4,
    }.entries)
      'changed ${entry.key}': {
        ..._row(),
        'media': [
          {..._media(), entry.key: entry.value},
        ],
      },
  };
  for (final entry in badReceipts.entries) {
    test('send refuses receipt ${entry.key}', () async {
      final fixture = _Fixture((_) => MediaFakeResponse.json(entry.value));
      await expectLater(fixture.send(), _protocol);
      expect(fixture.http.requests, hasLength(1));
    });
  }

  test(
    'voice receipt duration must match even when both durations are valid',
    () async {
      final metadata = {
        ..._media(),
        'purpose': 'PRIVATE_VOICE',
        'mediaType': 'audio/ogg',
        'durationMillis': 1000,
      };
      final fixture = _Fixture(
        (_) => MediaFakeResponse.json({
          ..._row(),
          'messageType': 'VOICE',
          'media': [
            {...metadata, 'durationMillis': 2000},
          ],
        }),
      );
      await expectLater(
        fixture.send(media: MediaReference.fromJson(metadata)),
        _protocol,
      );
    },
  );

  for (final delivery in [
    'PENDING',
    'PROCESSING',
    'RETRY',
    'UNKNOWN',
    'FAILED',
    'DELIVERED',
  ]) {
    test(
      'first-party storage does not upgrade $delivery delivery evidence',
      () async {
        final fixture = _Fixture(
          (_) => MediaFakeResponse.json({
            ..._row(),
            'deliveryStatus': delivery,
            'imStatus': delivery,
            'providerInvocation': true,
          }),
        );
        final message = await fixture.send();
        expect(
          message.status,
          delivery == 'DELIVERED'
              ? ChatMessageStatus.sent
              : delivery == 'FAILED'
              ? ChatMessageStatus.failed
              : ChatMessageStatus.storedPendingDelivery,
        );
        expect(message.deliveryStatus, tryParseMessageDeliveryStatus(delivery));
      },
    );
  }

  test(
    'draft send keeps actual receipt without inventing a conversation or acknowledging history',
    () async {
      final fixture = _Fixture(null);
      final message = await fixture.send(
        conversation: const ConversationSummary.draft(
          kind: ConversationKind.privateChat,
          title: 'Peer',
          lastMessage: '',
          unreadCount: 0,
          targetUserId: 99,
        ),
      );
      expect(message.id, 'stored-message');
      expect(message.conversationId, isNull);
      expect(fixture.http.requests, hasLength(1));
    },
  );

  for (final purpose in ['DYNAMIC_IMAGE', 'SUPPORT_IMAGE']) {
    test('non-private $purpose is rejected before HTTP', () async {
      final fixture = _Fixture(null);
      await expectLater(
        fixture.send(
          media: MediaReference.fromJson({..._media(), 'purpose': purpose}),
        ),
        _protocol,
      );
      expect(fixture.http.requests, isEmpty);
    });
  }
  for (final key in ['', '   ', 'bad key', 'x' * 81]) {
    test('invalid explicit key length ${key.length} is not replaced', () async {
      final fixture = _Fixture(null);
      await expectLater(fixture.send(key: key), throwsA(anything));
      expect(fixture.http.requests, isEmpty);
    });
  }

  test(
    'same scope intent shares one flight; changed target, asset or metadata conflicts',
    () async {
      final started = Completer<void>();
      final response = Completer<HttpClientResponse>();
      final fixture = _Fixture((_) {
        started.complete();
        return response.future;
      });
      final first = fixture.send();
      await started.future;
      final second = fixture.send();
      for (final delta in [
        {'assetId': '22222222-2222-4222-8222-222222222222'},
        {'version': 4},
        {'bytes': 51},
        {'mediaType': 'image/jpeg'},
      ]) {
        await expectLater(
          fixture.send(media: MediaReference.fromJson({..._media(), ...delta})),
          _conflict,
        );
      }
      await expectLater(
        fixture.send(
          conversation: const ConversationSummary.draft(
            kind: ConversationKind.privateChat,
            title: 'Other',
            lastMessage: '',
            unreadCount: 0,
            targetUserId: 100,
          ),
        ),
        _conflict,
      );
      response.complete(MediaFakeResponse.json(_row()));
      expect((await first).id, (await second).id);
      expect(fixture.http.requests, hasLength(1));
    },
  );

  test(
    'unknown retries retain key asset and fingerprint, including after token refresh',
    () async {
      var attempts = 0;
      final fixture = _Fixture((_) {
        if (++attempts == 1) throw const SocketException('unknown write');
        return MediaFakeResponse.json(_row());
      });
      await expectLater(
        fixture.send(),
        throwsA(
          isA<ApiException>().having(
            (e) => e.kind,
            'kind',
            ApiFailureKind.network,
          ),
        ),
      );
      await expectLater(
        fixture.send(
          media: MediaReference.fromJson({..._media(), 'version': 4}),
        ),
        _conflict,
      );
      fixture.actor.refreshToken();
      expect((await fixture.send()).media!.assetId, _assetId);
      expect(attempts, 2);
      expect(fixture.http.requests[0].body, fixture.http.requests[1].body);
      expect(
        fixture.http.requests.map((r) => r.headers.value('X-Request-Id')),
        ['private-media-key', 'private-media-key'],
      );
      expect(
        fixture.http.requests.last.headers.value('Authorization'),
        fixture.actor.token,
      );
    },
  );

  test(
    'same identity 401 refresh replays only original body and key',
    () async {
      var attempts = 0;
      final fixture = _Fixture(
        (_) => ++attempts == 1
            ? MediaFakeResponse.json(null, status: 401, code: 401)
            : MediaFakeResponse.json(_row()),
        refresh: (actor) async {
          actor.refreshToken();
          return true;
        },
      );
      expect((await fixture.send()).media!.assetId, _assetId);
      expect(fixture.http.requests, hasLength(2));
      expect(fixture.http.requests[0].body, fixture.http.requests[1].body);
      expect(
        fixture.http.requests[0].headers.value('X-Request-Id'),
        fixture.http.requests[1].headers.value('X-Request-Id'),
      );
      expect(
        fixture.http.requests[1].headers.value('Authorization'),
        fixture.actor.token,
      );
    },
  );

  test('account ABA during refresh cannot replay the original send', () async {
    final fixture = _Fixture(
      (_) => MediaFakeResponse.json(null, status: 401, code: 401),
      refresh: (actor) async {
        actor.change(2);
        actor.change(1);
        return true;
      },
    );
    await expectLater(fixture.send(), _unauthorized);
    expect(fixture.http.requests, hasLength(1));
  });

  for (final lateError in [false, true]) {
    test(
      'account ABA cancels pending send and discards late ${lateError ? 'error' : 'success'}',
      () async {
        final started = Completer<void>();
        final response = Completer<HttpClientResponse>();
        final fixture = _Fixture((_) {
          started.complete();
          return response.future;
        });
        final result = expectLater(fixture.send(), _unauthorized);
        await started.future;
        fixture.actor.change(2);
        fixture.actor.change(1);
        await result;
        if (lateError) {
          response.completeError(const SocketException('old account response'));
        } else {
          response.complete(MediaFakeResponse.json(_row()));
        }
        await Future<void>.delayed(Duration.zero);
        await expectLater(fixture.send(), _unauthorized);
        expect(fixture.http.requests, hasLength(1));
      },
    );
  }

  test(
    'ABA while openUrl is pending aborts before credentials or body are written',
    () async {
      final fixture = _Fixture(null);
      final opened = Completer<void>();
      final release = Completer<void>();
      fixture.http.beforeOpen = (_) {
        opened.complete();
        return release.future;
      };
      final result = expectLater(fixture.send(), _unauthorized);
      await opened.future;
      fixture.actor.change(2);
      fixture.actor.change(1);
      await result;
      release.complete();
      await Future<void>.delayed(Duration.zero);
      expect(fixture.http.requests.single.aborted, true);
      expect(fixture.http.requests.single.body, isEmpty);
      expect(
        fixture.http.requests.single.headers.value('Authorization'),
        isNull,
      );
      expect(fixture.http.requests.single.closes, 0);
    },
  );

  test(
    'different scopes never join a flight even for the same actor and key',
    () async {
      final responses = [
        Completer<HttpClientResponse>(),
        Completer<HttpClientResponse>(),
      ];
      final started = Completer<void>();
      var calls = 0;
      final fixture = _Fixture((_) {
        final index = calls++;
        if (calls == 2) started.complete();
        return responses[index].future;
      });
      final otherScope = fixture.actor.scope();
      addTearDown(otherScope.dispose);
      final first = fixture.send();
      final second = fixture.send(identity: otherScope);
      await started.future;
      fixture.scope.dispose();
      await expectLater(first, _unauthorized);
      responses[0].complete(MediaFakeResponse.json(_row()));
      responses[1].complete(
        MediaFakeResponse.json({..._row(), 'messageId': 'second-flight'}),
      );
      expect((await second).id, 'second-flight');
      expect(fixture.http.requests, hasLength(2));
    },
  );

  test('different actors never share the previous actor flight', () async {
    final started = Completer<void>();
    final response = Completer<HttpClientResponse>();
    var calls = 0;
    final fixture = _Fixture((_) {
      if (++calls == 1) {
        started.complete();
        return response.future;
      }
      return MediaFakeResponse.json({
        ..._row(),
        'senderUserId': 2,
        'messageId': 'actor-2',
      });
    });
    final first = expectLater(fixture.send(), _unauthorized);
    await started.future;
    fixture.actor.change(2);
    await first;
    final scope = fixture.actor.scope();
    addTearDown(scope.dispose);
    expect((await fixture.send(identity: scope)).id, 'actor-2');
    response.complete(MediaFakeResponse.json(_row()));
    expect(fixture.http.requests, hasLength(2));
  });

  for (final late in [false, true]) {
    for (final error in [false, true]) {
      test(
        'repository actor mismatch ${late ? 'after' : 'before'} HTTP rejects ${error ? 'error' : 'success'}',
        () async {
          var provider = late ? 1 : 2;
          final fixture = _Fixture((_) {
            provider = 2;
            if (error) throw const SocketException('wrong actor');
            return MediaFakeResponse.json(_row());
          }, provider: () => provider);
          await expectLater(fixture.send(), _unauthorized);
          expect(fixture.http.requests, hasLength(late ? 1 : 0));
        },
      );
    }
  }

  test(
    'observed provider mismatch permanently invalidates its scope',
    () async {
      var provider = 2;
      final fixture = _Fixture(null, provider: () => provider);
      await expectLater(fixture.send(), _unauthorized);
      provider = 1;
      await expectLater(fixture.send(), _unauthorized);
      expect(fixture.http.requests, isEmpty);
    },
  );
}

class _Fixture {
  _Fixture(
    FutureOr<HttpClientResponse> Function(MediaFakeRequest)? respond, {
    int Function()? provider,
    Future<bool> Function(TestMediaIdentity)? refresh,
  }) {
    scope = actor.scope();
    http = MediaFakeHttp(respond ?? (_) => MediaFakeResponse.json(_row()));
    repository = BackendMessageRepository(
      apiClient: http.api(
        actor,
        refresh: refresh == null ? null : () => refresh(actor),
      ),
      routes: const BackendRouteCatalog(),
      currentUserIdProvider: provider ?? () => actor.user,
    );
    addTearDown(actor.dispose);
    addTearDown(scope.dispose);
  }
  final actor = TestMediaIdentity();
  late final MediaIdentityScope scope;
  late final MediaFakeHttp http;
  late final BackendMessageRepository repository;

  Future<ChatMessage> send({
    MediaReference? media,
    MediaIdentityScope? identity,
    ConversationSummary conversation = _conversation,
    String key = 'private-media-key',
  }) => repository.sendPrivateMediaMessage(
    conversation: conversation,
    media: media ?? MediaReference.fromJson(_media()),
    identity: identity ?? scope,
    requestId: key,
  );
}
