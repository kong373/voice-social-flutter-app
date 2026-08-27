import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/features/account/domain/auth_models.dart';
import 'package:voice_social_app/features/im/application/im_session_coordinator.dart';
import 'package:voice_social_app/features/im/domain/im_authoritative_refresh_bus.dart';
import 'package:voice_social_app/features/im/domain/im_refresh_hint.dart';
import 'package:voice_social_app/features/im/domain/im_session_adapter.dart';
import 'package:voice_social_app/features/im/domain/im_session_credentials.dart';
import 'package:voice_social_app/features/im/domain/im_session_repository.dart';
import 'package:voice_social_app/features/message/data/backend_message_repository.dart';
import 'package:voice_social_app/features/message/domain/message_models.dart';

void main() {
  final DateTime now = DateTime.utc(2030, 1, 1, 12);

  test('ApiClient aggregates response headers by lower-case name', () async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(() => server.close(force: true));
    server.listen((HttpRequest request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.headers.add('Cache-Control', 'max-age=0');
      request.response.headers.add('Cache-Control', 'no-store');
      request.response.write(
        jsonEncode(<String, Object?>{
          'code': 200,
          'message': 'OK',
          'data': <String, Object?>{'ok': true},
        }),
      );
      await request.response.close();
    });
    final ApiResponse response = await ApiClient(
      baseUri: Uri.parse('http://${server.address.address}:${server.port}/'),
      clientType: 'Android',
      clientInnerVersion: '6',
      authorizationProvider: () => null,
    ).get('/headers', authenticated: false);
    expect(response.responseHeaders['cache-control'], 'max-age=0, no-store');
    expect(response.responseHeaders.keys, isNot(contains('Cache-Control')));
  });

  group('refresh hint boundary', () {
    test(
      'rejects untrusted, malformed, oversized and provider-shaped hints',
      () {
        final Map<String, Object?> valid = <String, Object?>{
          'messageId': 'private-message-1',
          'eventVersion': 1,
        };
        expect(ImRefreshHint.tryParse(valid, trustedSource: false), isNull);
        expect(
          ImRefreshHint.tryParse(<String, Object?>{
            ...valid,
            'content': 'never-display',
          }, trustedSource: true),
          isNull,
        );
        expect(
          ImRefreshHint.tryParse(
            '{"messageId":"private-message-1"',
            trustedSource: true,
          ),
          isNull,
        );
        expect(
          ImRefreshHint.tryParse(<String, Object?>{
            'messageId': 'private-message-1',
            'eventVersion': 1,
            'unknown': true,
          }, trustedSource: true),
          isNull,
        );
        expect(
          ImRefreshHint.tryParse(<String, Object?>{
            'messageId': ' private-message-1',
            'eventVersion': 1,
          }, trustedSource: true),
          isNull,
        );
        expect(
          ImRefreshHint.tryParse(<String, Object?>{
            'messageId': 'private/message-1',
            'eventVersion': 1,
          }, trustedSource: true),
          isNull,
        );
        expect(
          ImRefreshHint.tryParse(<String, Object?>{
            'messageId': 'private-message-1',
            'eventVersion': 0,
          }, trustedSource: true),
          isNull,
        );
        expect(
          ImRefreshHint.tryParse(<String, Object?>{
            'messageId': 'private-message-1',
            'eventVersion': -1,
          }, trustedSource: true),
          isNull,
        );
        expect(
          ImRefreshHint.tryParse(<String, Object?>{
            'messageId': 'private-message-1',
            'eventVersion': ImRefreshHint.maximumEventVersion + 1,
          }, trustedSource: true),
          isNull,
        );
        expect(
          ImRefreshHint.tryParse(
            jsonEncode(<String, Object?>{
                  'messageId': 'private-message-1',
                  'eventVersion': 1,
                }) +
                List<String>.filled(8200, 'x').join(),
            trustedSource: true,
          ),
          isNull,
        );
      },
    );

    test('accepts the Java signed-long boundary including 2^31', () {
      expect(
        ImRefreshHint.tryParse(<String, Object?>{
          'messageId': 'boundary-32',
          'eventVersion': 0x80000000,
        }, trustedSource: true)?.eventVersion,
        0x80000000,
      );
      expect(
        ImRefreshHint.tryParse(<String, Object?>{
          'messageId': 'boundary-64',
          'eventVersion': ImRefreshHint.maximumEventVersion,
        }, trustedSource: true)?.eventVersion,
        ImRefreshHint.maximumEventVersion,
      );
    });
  });

  group('authoritative refresh bus', () {
    test(
      'coalesces duplicate and stale versions and handles no subscribers',
      () async {
        final ImAuthoritativeRefreshBus bus = ImAuthoritativeRefreshBus();
        final ImRefreshHint hint = _hint(messageId: 'message-1', version: 1);

        final ImRefreshDispatchResult noSubscribers = await bus.publish(hint);
        expect(noSubscribers.status, ImRefreshDispatchStatus.noSubscribers);
        expect(await bus.publish(hint), isA<ImRefreshDispatchResult>());
        expect(
          (await bus.publish(_hint(messageId: 'message-2', version: 1))).status,
          ImRefreshDispatchStatus.stale,
        );

        var calls = 0;
        final ImAuthoritativeRefreshSubscription subscription = bus.subscribe((
          ImAuthoritativeRefreshRequest request,
        ) async {
          calls += 1;
          await Future<void>.delayed(Duration.zero);
        });
        final Future<ImRefreshDispatchResult> first = bus.publish(
          _hint(messageId: 'message-3', version: 3),
        );
        final Future<ImRefreshDispatchResult> duplicate = bus.publish(
          _hint(messageId: 'message-3', version: 3),
        );
        final List<ImRefreshDispatchResult> results = await Future.wait(
          <Future<ImRefreshDispatchResult>>[first, duplicate],
        );
        expect(calls, 1);
        expect(
          results.map((ImRefreshDispatchResult result) => result.status),
          contains(ImRefreshDispatchStatus.duplicate),
        );
        subscription.cancel();
        bus.dispose();
      },
    );

    test(
      'reports a failed consumer without leaking details or blocking later hints',
      () async {
        final ImAuthoritativeRefreshBus bus = ImAuthoritativeRefreshBus();
        addTearDown(bus.dispose);
        var calls = 0;
        bus.subscribe((ImAuthoritativeRefreshRequest request) async {
          calls += 1;
          if (calls == 1) {
            throw StateError('provider payload must not escape');
          }
        });

        final ImRefreshDispatchResult failed = await bus.publish(
          _hint(messageId: 'message-1', version: 1),
        );
        expect(failed.status, ImRefreshDispatchStatus.failed);
        expect(failed.failedHandlers, 1);
        final ImRefreshDispatchResult recovered = await bus.publish(
          _hint(messageId: 'message-2', version: 2),
        );
        expect(recovered.status, ImRefreshDispatchStatus.delivered);
        expect(calls, 2);
      },
    );

    test('drops an event after account generation is fenced', () async {
      final ImAuthoritativeRefreshBus bus = ImAuthoritativeRefreshBus();
      addTearDown(bus.dispose);
      var current = true;
      var calls = 0;
      bus.subscribe((ImAuthoritativeRefreshRequest request) async {
        calls += 1;
      });
      final ImRefreshDispatchResult result = await bus.publish(
        _hint(messageId: 'message-1', version: 1),
        isCurrent: () => current,
      );
      expect(result.status, ImRefreshDispatchStatus.delivered);
      current = false;
      final ImRefreshDispatchResult stale = await bus.publish(
        _hint(messageId: 'message-2', version: 2),
        isCurrent: () => current,
      );
      expect(stale.status, ImRefreshDispatchStatus.stale);
      expect(calls, 1);
    });
  });

  group('provider event recovery', () {
    test(
      'expiry and reconnect obtain fresh credentials single-flight',
      () async {
        final ImSessionCredentials first = _credentials(now: now);
        final ImSessionCredentials second = _credentials(
          now: now,
          userSig: 'sig_renewed_123456',
        );
        final Completer<void> secondStarted = Completer<void>();
        final Completer<void> releaseSecond = Completer<void>();
        final _ScriptedCredentialRepository repository =
            _ScriptedCredentialRepository(
              <FutureOr<ImSessionCredentials> Function()>[
                () => first,
                () async {
                  if (!secondStarted.isCompleted) {
                    secondStarted.complete();
                  }
                  await releaseSecond.future;
                  return second;
                },
              ],
            );
        final FakeImSessionAdapter adapter = FakeImSessionAdapter(
          now: () => now,
        );
        final ImSessionCoordinator coordinator = ImSessionCoordinator(
          adapter: adapter,
          credentialsRepository: repository,
          now: () => now,
        );
        addTearDown(coordinator.dispose);

        final AuthSession session = _session(userId: 123);
        await coordinator.ensureAuthenticated(session);
        expect(coordinator.realtimeReady, isTrue);
        adapter.emitUserSigExpired();
        adapter.emitUserSigExpired();
        await secondStarted.future;
        expect(repository.fetchCalls, 2);
        releaseSecond.complete();
        await _eventTurn();
        expect(coordinator.realtimeReady, isTrue);
        expect(adapter.loginCalls, 2);

        final Completer<void> thirdStarted = Completer<void>();
        repository.add(() async {
          if (!thirdStarted.isCompleted) {
            thirdStarted.complete();
          }
          return _credentials(now: now, userSig: 'sig_online_123456');
        });
        adapter.emitNetworkOffline();
        expect(coordinator.realtimeReady, isFalse);
        adapter.emitNetworkOnline();
        await thirdStarted.future;
        await _eventTurn();
        expect(coordinator.realtimeReady, isTrue);
        expect(repository.fetchCalls, 3);
      },
    );

    test(
      'failed refresh keeps first-party session usable and remains fail-closed',
      () async {
        final _ScriptedCredentialRepository repository =
            _ScriptedCredentialRepository(
              <FutureOr<ImSessionCredentials> Function()>[
                () => _credentials(now: now),
                () => throw const ImCredentialException(
                  ImCredentialFailure.invalidValue,
                ),
                () => _credentials(now: now, userSig: 'sig_recovered_123456'),
              ],
            );
        final FakeImSessionAdapter adapter = FakeImSessionAdapter(
          now: () => now,
        );
        final ImSessionCoordinator coordinator = ImSessionCoordinator(
          adapter: adapter,
          credentialsRepository: repository,
          now: () => now,
        );
        addTearDown(coordinator.dispose);
        final AuthSession session = _session(userId: 123);

        await coordinator.ensureAuthenticated(session);
        adapter.emitUserSigExpired();
        await _waitFor(() => repository.fetchCalls == 2);
        await _eventTurn();
        expect(coordinator.realtimeReady, isFalse);
        expect(coordinator.lastFailure, isNotNull);

        adapter.emitNetworkOnline();
        await _waitFor(() => repository.fetchCalls == 3);
        await _eventTurn();
        expect(coordinator.realtimeReady, isTrue);
        expect(session.userId, 123);
      },
    );

    test(
      'logout fences expiry recovery and clears adapter credentials',
      () async {
        final Completer<void> started = Completer<void>();
        final Completer<void> release = Completer<void>();
        final _ScriptedCredentialRepository repository =
            _ScriptedCredentialRepository(
              <FutureOr<ImSessionCredentials> Function()>[
                () async {
                  if (!started.isCompleted) {
                    started.complete();
                  }
                  await release.future;
                  return _credentials(now: now);
                },
              ],
            );
        final FakeImSessionAdapter adapter = FakeImSessionAdapter(
          now: () => now,
        );
        final ImSessionCoordinator coordinator = ImSessionCoordinator(
          adapter: adapter,
          credentialsRepository: repository,
          now: () => now,
        );
        addTearDown(coordinator.dispose);
        final Future<void> restore = coordinator.restore(_session(userId: 123));
        await started.future;
        adapter.emitUserSigExpired();
        await coordinator.logout();
        release.complete();
        await restore;
        await _eventTurn();

        expect(adapter.credentials, isNull);
        expect(coordinator.activeAuthSession, isNull);
        expect(coordinator.realtimeReady, isFalse);
      },
    );
  });

  group('first-party status projection', () {
    test(
      'maps backend delivery statuses and accepts capability READY',
      () async {
        final HttpServer server = await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        addTearDown(() => server.close(force: true));
        String deliveryStatus = 'DELIVERED';
        server.listen((HttpRequest request) async {
          final String path = request.uri.path;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode(<String, Object?>{
              'code': 200,
              'message': 'OK',
              'data': path == BackendRouteCatalog().privateChatHistory
                  ? <String, Object?>{
                      'conversationId': 'conversation-1',
                      'targetUserId': 123,
                      'hasMore': false,
                      'nextCursor': '',
                      'unreadCount': 0,
                      'imStatus': 'READY',
                      'providerInvocation': true,
                      'list': <Object?>[
                        <String, Object?>{
                          'id': 'message-1',
                          'conversationId': 'conversation-1',
                          'senderUserId': 123,
                          'senderName': '我',
                          'content': 'authoritative',
                          'createTime': '2030-01-01T12:00:00Z',
                          'direction': 'OUTGOING',
                          'storageStatus': 'FIRST_PARTY_STORED',
                          'deliveryStatus': deliveryStatus,
                        },
                      ],
                    }
                  : <String, Object?>{
                      'conversationId': 'conversation-1',
                      'targetUserId': 123,
                      'markedRead': 0,
                      'unreadCount': 0,
                    },
            }),
          );
          await request.response.close();
        });
        final ApiClient apiClient = ApiClient(
          baseUri: Uri.parse(
            'http://${server.address.address}:${server.port}/',
          ),
          clientType: 'Android',
          clientInnerVersion: '6',
          authorizationProvider: () => 'Bearer first-party',
        );
        final BackendMessageRepository repository = BackendMessageRepository(
          apiClient: apiClient,
          routes: const BackendRouteCatalog(),
          currentUserIdProvider: () => 123,
          privateRealtimeAvailabilityProvider: () => true,
        );
        final ConversationSummary conversation = _conversation();

        for (final String status in <String>[
          'PENDING',
          'PROCESSING',
          'RETRY',
          'UNKNOWN',
          'DELIVERED',
          'FAILED',
          'VENDOR_BLOCKED',
        ]) {
          deliveryStatus = status;
          final ChatMessage message = (await repository.fetchPrivateMessages(
            conversation,
          )).single;
          expect(message.deliveryStatus, tryParseMessageDeliveryStatus(status));
          expect(
            message.status,
            status == 'DELIVERED'
                ? ChatMessageStatus.sent
                : status == 'FAILED'
                ? ChatMessageStatus.failed
                : ChatMessageStatus.storedPendingDelivery,
          );
        }
        expect(repository.supportsPrivateRealtime, isTrue);
      },
    );
  });
}

ImRefreshHint _hint({required String messageId, required int version}) =>
    ImRefreshHint(messageId: messageId, eventVersion: version);

ImSessionCredentials _credentials({
  required DateTime now,
  String userId = 'u-123',
  String userSig = 'sig_123456789012',
  String systemAccount = 'administrator',
}) => ImSessionCredentials(
  provider: ImSessionCredentials.expectedProvider,
  sdkAppId: 1400000000,
  userId: userId,
  userSig: userSig,
  expiresAt: now.add(const Duration(hours: 1)),
  ttlSeconds: 3600,
  imStatus: ImSessionCredentials.readyStatus,
  systemAccount: systemAccount,
);

AuthSession _session({required int userId}) => AuthSession(
  accessToken: 'access-$userId',
  tokenType: 'Bearer',
  expiresAt: DateTime.utc(2030, 1, 1, 13),
  refreshToken: 'refresh-$userId',
  refreshExpiresAt: DateTime.utc(2030, 1, 2),
  deviceId: 'device-$userId',
  userId: userId,
  mobile: '13800138000',
  roles: 'USER',
);

ConversationSummary _conversation() => ConversationSummary(
  id: 'conversation-1',
  kind: ConversationKind.privateChat,
  title: '晚风',
  lastMessage: '',
  updatedAt: DateTime.utc(2030, 1, 1, 12),
  unreadCount: 0,
  targetUserId: 123,
);

Future<void> _eventTurn() => Future<void>.delayed(Duration.zero);

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 100 && !condition(); attempt += 1) {
    await _eventTurn();
  }
  expect(condition(), isTrue);
}

class _ScriptedCredentialRepository extends ImSessionCredentialRepository {
  _ScriptedCredentialRepository(this._steps);

  final List<FutureOr<ImSessionCredentials> Function()> _steps;
  int fetchCalls = 0;

  void add(FutureOr<ImSessionCredentials> Function() step) => _steps.add(step);

  @override
  Future<ImSessionCredentials> fetch() async {
    fetchCalls += 1;
    final FutureOr<ImSessionCredentials> Function()? step = _steps.isEmpty
        ? null
        : _steps.removeAt(0);
    if (step == null) {
      return _credentials(now: DateTime.utc(2030, 1, 1, 12));
    }
    return step();
  }
}
