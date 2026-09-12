import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/features/account/domain/auth_models.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/features/im/domain/im_authoritative_refresh_bus.dart';
import 'package:voice_social_app/features/im/domain/im_correlation_trace.dart';
import 'package:voice_social_app/features/im/domain/im_refresh_hint.dart';
import 'package:voice_social_app/features/im/application/im_session_coordinator.dart';
import 'package:voice_social_app/features/im/domain/im_session_credentials.dart';
import 'package:voice_social_app/features/im/domain/im_session_repository.dart';
import 'package:voice_social_app/features/im/infrastructure/tencent_im_session_adapter.dart';
import 'package:voice_social_app/features/message/data/mock_message_repository.dart';
import 'package:voice_social_app/features/message/domain/message_models.dart';
import 'package:voice_social_app/features/message/domain/message_repository.dart';
import 'package:voice_social_app/features/message/presentation/message_pages.dart';

import 'support/media_http_fakes.dart';

void main() {
  group('IM correlation trace', () {
    test('uses one short fingerprint and fixed redacted fields', () {
      final List<String> logs = <String>[];
      final ImCorrelationTrace trace = ImCorrelationTrace.forTest(
        enabled: true,
        sink: logs.add,
      );
      const ImRefreshHint hint = ImRefreshHint(
        messageId: 'message-secret-123',
        eventVersion: 7,
      );

      trace.runForValidatedHint(hint, () {
        trace.sdkCallback();
        trace.adapterAccepted();
        trace.busAccepted(handlers: 1);
        trace.pageHandler(
          active: true,
          flight: false,
          action: ImCorrelationTracePageAction.entered,
        );
        trace.pageLoadStart();
        trace.pagePublish(followLatest: true);
        trace.pageFrame();
      });

      final String joined = logs.join('\n');
      final String fingerprint = ImCorrelationTrace.fingerprintFor(
        hint.messageId,
      );
      expect(logs, hasLength(7));
      expect(logs, everyElement(contains('fp=$fingerprint')));
      expect(joined, isNot(contains(hint.messageId)));
      expect(joined, isNot(contains('user-secret')));
      expect(joined, isNot(contains('Bearer secret-token')));
      expect(joined, isNot(contains('targetUserId=secret')));
      expect(joined, isNot(contains('raw-body')));
      expect(joined, isNot(contains('eventVersion')));
    });

    test('disabled trace is silent and a sink failure cannot escape', () {
      final List<String> logs = <String>[];
      final ImCorrelationTrace disabled = ImCorrelationTrace.forTest(
        enabled: false,
        sink: logs.add,
      );
      const ImRefreshHint hint = ImRefreshHint(
        messageId: 'message-disabled',
        eventVersion: 1,
      );
      disabled.runForValidatedHint(hint, disabled.sdkCallback);
      expect(logs, isEmpty);

      final ImCorrelationTrace throwing = ImCorrelationTrace.forTest(
        enabled: true,
        sink: (_) => throw StateError('test sink failure'),
      );
      expect(
        () => throwing.runForValidatedHint(hint, throwing.sdkCallback),
        returnsNormally,
      );
    });

    test('invalid hint cannot establish a trace context', () {
      final List<String> logs = <String>[];
      final ImCorrelationTrace trace = ImCorrelationTrace.forTest(
        enabled: true,
        sink: logs.add,
      );
      const ImRefreshHint invalid = ImRefreshHint(
        messageId: 'contains whitespace',
        eventVersion: 1,
      );

      trace.runForValidatedHint(invalid, trace.adapterAccepted);

      expect(logs, isEmpty);
      expect(ImCorrelationTrace.currentContext, isNull);
    });
  });

  test('trusted SDK callback uses the message fingerprint', () async {
    final List<String> logs = <String>[];
    final ImCorrelationTrace trace = ImCorrelationTrace.forTest(
      enabled: true,
      sink: logs.add,
    );
    final OfficialTencentImSdkClient client = OfficialTencentImSdkClient(
      trustedHintEvaluator:
          ({
            required String? senderUserId,
            required String? groupId,
            required bool? isSelf,
          }) =>
              senderUserId == 'administrator' &&
              groupId == null &&
              isSelf == false,
      logger: (_) {},
      correlationTrace: trace,
    );
    final StreamSubscription<TencentImSdkEvent> subscription = client.events
        .listen((TencentImSdkEvent _) {});
    addTearDown(() async {
      await subscription.cancel();
      await client.dispose();
    });

    client.handleObservedMessageForTest(
      const TencentImObservedMessage(
        customData: '{"messageId":"message-shared-1","eventVersion":9}',
        senderUserId: 'administrator',
        isSelf: false,
      ),
    );
    await Future<void>.delayed(Duration.zero);

    final String fingerprint = ImCorrelationTrace.fingerprintFor(
      'message-shared-1',
    );
    expect(
      logs,
      anyElement(
        allOf(contains('stage=sdk_callback'), contains('fp=$fingerprint')),
      ),
    );
  });

  test('adapter only traces a trusted, parsed hint', () async {
    final List<String> logs = <String>[];
    final ImCorrelationTrace trace = ImCorrelationTrace.forTest(
      enabled: true,
      sink: logs.add,
    );
    final _TraceSdk sdk = _TraceSdk();
    final DateTime now = DateTime.utc(2026, 9, 12, 12);
    final TencentImSessionAdapter adapter = TencentImSessionAdapter(
      sdkClient: sdk,
      operationTimeout: const Duration(milliseconds: 100),
      now: () => now,
      logger: (_) {},
      observabilityLogger: (_) {},
      correlationTrace: trace,
    );
    addTearDown(() async {
      await adapter.dispose();
      await sdk.dispose();
    });
    await adapter.login(_credentials(now));

    sdk.emit(
      TencentImSdkEvent.customElement(
        data: '{"messageId":"message-adapter-1","eventVersion":10}',
        trustedFirstParty: true,
        senderUserId: 'administrator',
        isSelf: false,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    final String fingerprint = ImCorrelationTrace.fingerprintFor(
      'message-adapter-1',
    );
    expect(
      logs,
      anyElement(
        allOf(contains('stage=adapter_parse'), contains('fp=$fingerprint')),
      ),
    );

    logs.clear();
    sdk.emit(
      TencentImSdkEvent.customElement(
        data: '{"messageId":"message-untrusted-1","eventVersion":11}',
        trustedFirstParty: false,
        senderUserId: 'ordinary-user',
        isSelf: false,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(logs, isEmpty);
  });

  test(
    'keeps correlation when a real adapter stream reaches the coordinator bus',
    () async {
      final List<String> logs = <String>[];
      final ImCorrelationTrace trace = ImCorrelationTrace.forTest(
        enabled: true,
        sink: logs.add,
      );
      final _TraceSdk sdk = _TraceSdk();
      final DateTime now = DateTime.utc(2026, 9, 12, 12);
      final TencentImSessionAdapter adapter = TencentImSessionAdapter(
        sdkClient: sdk,
        operationTimeout: const Duration(milliseconds: 100),
        now: () => now,
        logger: (_) {},
        observabilityLogger: (_) {},
        correlationTrace: trace,
      );
      final ImAuthoritativeRefreshBus bus = ImAuthoritativeRefreshBus(
        correlationTrace: trace,
      );
      final Completer<void> handled = Completer<void>();
      bus.subscribe((ImAuthoritativeRefreshRequest request) async {
        if (!handled.isCompleted) handled.complete();
      });
      final ImSessionCoordinator coordinator = ImSessionCoordinator(
        adapter: adapter,
        credentialsRepository: _TraceCredentialRepository(_credentials(now)),
        authoritativeRefreshBus: bus,
        now: () => now,
        correlationTrace: trace,
      );
      addTearDown(() async {
        coordinator.dispose();
        bus.dispose();
        await adapter.dispose();
        await sdk.dispose();
      });
      await coordinator.ensureAuthenticated(_authSession(now));
      logs.clear();

      sdk.emit(
        TencentImSdkEvent.customElement(
          data: '{"messageId":"message-stream-chain","eventVersion":18}',
          trustedFirstParty: true,
          senderUserId: 'administrator',
          isSelf: false,
        ),
      );
      await handled.future;
      await Future<void>.delayed(Duration.zero);

      final String fingerprint = ImCorrelationTrace.fingerprintFor(
        'message-stream-chain',
      );
      expect(
        logs,
        anyElement(
          allOf(contains('stage=adapter_parse'), contains('fp=$fingerprint')),
        ),
      );
      expect(
        logs,
        anyElement(
          allOf(contains('stage=bus_dispatch'), contains('fp=$fingerprint')),
        ),
      );
    },
  );

  test(
    'bus traces only a validated context and preserves dispatch result',
    () async {
      final List<String> logs = <String>[];
      final ImCorrelationTrace trace = ImCorrelationTrace.forTest(
        enabled: true,
        sink: logs.add,
      );
      final ImAuthoritativeRefreshBus bus = ImAuthoritativeRefreshBus(
        correlationTrace: trace,
      );
      addTearDown(bus.dispose);
      bus.subscribe((ImAuthoritativeRefreshRequest request) async {});
      const ImRefreshHint hint = ImRefreshHint(
        messageId: 'message-bus-1',
        eventVersion: 12,
      );

      final ImRefreshDispatchResult result = await trace.runForValidatedHint(
        hint,
        () => bus.publish(hint),
      );
      expect(result.status, ImRefreshDispatchStatus.delivered);
      final String fingerprint = ImCorrelationTrace.fingerprintFor(
        hint.messageId,
      );
      expect(
        logs,
        anyElement(
          allOf(contains('stage=bus_dispatch'), contains('fp=$fingerprint')),
        ),
      );

      logs.clear();
      await bus.publish(
        const ImRefreshHint(
          messageId: 'message-untrusted-bus',
          eventVersion: 13,
        ),
      );
      expect(logs, isEmpty);
    },
  );

  test(
    'traces identity-bound HTTP success without route or request material',
    () async {
      final List<String> logs = <String>[];
      final ImCorrelationTrace trace = ImCorrelationTrace.forTest(
        enabled: true,
        sink: logs.add,
      );
      final MediaFakeHttp http = MediaFakeHttp((MediaFakeRequest request) {
        expect(request.method, 'GET');
        return MediaFakeResponse.json(<String, Object?>{});
      });
      final ApiClient client = ApiClient(
        baseUri: Uri.parse('https://configured.backend.test'),
        clientType: 'test',
        clientInnerVersion: '1',
        authorizationProvider: () => 'Bearer secret-token',
        httpClient: http,
        correlationTrace: trace,
      );
      const ImRefreshHint hint = ImRefreshHint(
        messageId: 'message-http-1',
        eventVersion: 14,
      );

      final ApiResponse response = await trace.runForValidatedHint(
        hint,
        () => client.getBoundToIdentity(
          '/private-history/raw-path-must-not-log',
          query: <String, String>{'targetUserId': 'secret-query-value'},
          requireIdentity: () {},
        ),
      );

      expect(response.isSuccess, isTrue);
      final String joined = logs.join('\n');
      expect(joined, contains('stage=http event=start'));
      expect(joined, contains('method=GET bound=true'));
      expect(joined, contains('stage=http event=complete'));
      expect(joined, contains('status=200'));
      expect(joined, isNot(contains('raw-path-must-not-log')));
      expect(joined, isNot(contains('secret-query-value')));
      expect(joined, isNot(contains('Bearer secret-token')));
      expect(joined, isNot(contains(hint.messageId)));
    },
  );

  test('traces one 401 replay without changing the request contract', () async {
    final List<String> logs = <String>[];
    final ImCorrelationTrace trace = ImCorrelationTrace.forTest(
      enabled: true,
      sink: logs.add,
    );
    var attempts = 0;
    final MediaFakeHttp http = MediaFakeHttp((MediaFakeRequest request) {
      attempts += 1;
      if (attempts == 1) {
        return MediaFakeResponse.json(
          null,
          status: HttpStatus.unauthorized,
          code: HttpStatus.unauthorized,
        );
      }
      return MediaFakeResponse.json(<String, Object?>{});
    });
    final ApiClient client = ApiClient(
      baseUri: Uri.parse('https://configured.backend.test'),
      clientType: 'test',
      clientInnerVersion: '1',
      authorizationProvider: () => 'Bearer replay-token',
      unauthorizedRecovery: () async => true,
      httpClient: http,
      correlationTrace: trace,
    );
    const ImRefreshHint hint = ImRefreshHint(
      messageId: 'message-http-replay-1',
      eventVersion: 15,
    );

    final ApiResponse response = await trace.runForValidatedHint(
      hint,
      () =>
          client.getBoundToIdentity('/private-history', requireIdentity: () {}),
    );

    expect(response.isSuccess, isTrue);
    expect(attempts, 2);
    final String joined = logs.join('\n');
    expect(joined, contains('status=401'));
    expect(joined, contains('event=auth_recovery_start'));
    expect(joined, contains('event=replay_start'));
    expect(joined, contains('status=200'));
    expect(joined, isNot(contains('replay-token')));
    expect(joined, isNot(contains(hint.messageId)));
  });

  testWidgets('keeps the latest fingerprint when a private load is queued', (
    WidgetTester tester,
  ) async {
    final List<String> logs = <String>[];
    final ImCorrelationTrace trace = ImCorrelationTrace.forTest(
      enabled: true,
      sink: logs.add,
    );
    final ImAuthoritativeRefreshBus bus = ImAuthoritativeRefreshBus(
      correlationTrace: trace,
    );
    final _PagedTraceRepository repository = _PagedTraceRepository();
    final AppDependencies dependencies = AppDependencies.forTestEnvironment(
      environment: const AppEnvironment(
        backendMode: BackendMode.live,
        apiBaseUrl: 'http://127.0.0.1:28080/',
        clientType: 'test',
        clientInnerVersion: '1',
        oauthClientId: 'public-test-client',
        realtimeEndpoint: '',
        allowInsecureHttp: true,
      ),
      messageRepository: repository,
      imAuthoritativeRefreshBus: bus,
    );
    addTearDown(() {
      bus.dispose();
      dependencies.imSessionCoordinator.dispose();
    });
    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: dependencies,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: PrivateChatPage(conversation: _conversation()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('initial-message'), findsOneWidget);

    const ImRefreshHint firstHint = ImRefreshHint(
      messageId: 'message-queued-1',
      eventVersion: 16,
    );
    final Future<ImRefreshDispatchResult> first = trace.runForValidatedHint(
      firstHint,
      () => bus.publish(firstHint),
    );
    await tester.pump();
    expect(repository.pageCalls, 2);

    const ImRefreshHint secondHint = ImRefreshHint(
      messageId: 'message-queued-2',
      eventVersion: 17,
    );
    final Future<ImRefreshDispatchResult> second = trace.runForValidatedHint(
      secondHint,
      () => bus.publish(secondHint),
    );
    await tester.pump();
    final String secondFingerprint = ImCorrelationTrace.fingerprintFor(
      secondHint.messageId,
    );
    expect(
      logs,
      anyElement(
        allOf(
          contains('stage=page_handler'),
          contains('event=queued'),
          contains('fp=$secondFingerprint'),
        ),
      ),
    );

    repository.releaseRefresh.complete(_batch('refreshed-message'));
    await tester.pump();
    await tester.pump();
    await Future.wait(<Future<ImRefreshDispatchResult>>[first, second]);
    await tester.pumpAndSettle();
    expect(find.text('refreshed-message'), findsOneWidget);
    expect(repository.pageCalls, 3);
    expect(
      logs,
      anyElement(
        allOf(
          contains('stage=page_load'),
          contains('event=start'),
          contains('fp=$secondFingerprint'),
        ),
      ),
    );
  });

  testWidgets('does not emit a first-frame marker after the page is covered', (
    WidgetTester tester,
  ) async {
    final List<String> logs = <String>[];
    final ImCorrelationTrace trace = ImCorrelationTrace.forTest(
      enabled: true,
      sink: logs.add,
    );
    final ImAuthoritativeRefreshBus bus = ImAuthoritativeRefreshBus(
      correlationTrace: trace,
    );
    final _PagedTraceRepository repository = _PagedTraceRepository();
    final AppDependencies dependencies = AppDependencies.forTestEnvironment(
      environment: const AppEnvironment(
        backendMode: BackendMode.live,
        apiBaseUrl: 'http://127.0.0.1:28080/',
        clientType: 'test',
        clientInnerVersion: '1',
        oauthClientId: 'public-test-client',
        realtimeEndpoint: '',
        allowInsecureHttp: true,
      ),
      messageRepository: repository,
      imAuthoritativeRefreshBus: bus,
    );
    addTearDown(() {
      bus.dispose();
      dependencies.imSessionCoordinator.dispose();
    });
    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: dependencies,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: PrivateChatPage(conversation: _conversation()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    logs.clear();

    const ImRefreshHint hint = ImRefreshHint(
      messageId: 'message-covered-before-frame',
      eventVersion: 19,
    );
    final Future<ImRefreshDispatchResult> dispatch = trace.runForValidatedHint(
      hint,
      () => bus.publish(hint),
    );
    await tester.pump();
    expect(repository.pageCalls, 2);

    bool covered = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      covered = true;
      Navigator.of(
        tester.element(find.byType(PrivateChatPage)),
      ).push(MaterialPageRoute<void>(builder: (_) => const SizedBox()));
    });
    repository.releaseRefresh.complete(_batch('covered-message'));
    await tester.pump();
    await tester.pump();
    await dispatch;
    expect(covered, isTrue);
    expect(logs, anyElement(contains('stage=page_publish')));
    expect(logs, isNot(anyElement(contains('stage=page_frame'))));
  });
}

class _TraceSdk implements TencentImSdkClient, TencentImSdkEventSource {
  final StreamController<TencentImSdkEvent> _events =
      StreamController<TencentImSdkEvent>.broadcast(sync: true);

  @override
  Stream<TencentImSdkEvent> get events => _events.stream;

  @override
  Future<bool> initSdk({required int sdkAppId}) async => true;

  @override
  Future<int> login({required String userId, required String userSig}) async =>
      0;

  @override
  Future<int> logout() async => 0;

  @override
  Future<int> uninitSdk() async => 0;

  void emit(TencentImSdkEvent event) => _events.add(event);

  Future<void> dispose() => _events.close();
}

class _TraceCredentialRepository extends ImSessionCredentialRepository {
  _TraceCredentialRepository(this.credentials);

  final ImSessionCredentials credentials;

  @override
  Future<ImSessionCredentials> fetch() async => credentials;
}

class _PagedTraceRepository extends MockMessageRepository
    implements PagedPrivateMessageRepository {
  int pageCalls = 0;
  final Completer<PrivateMessageSyncBatch> releaseRefresh =
      Completer<PrivateMessageSyncBatch>();

  @override
  Future<PrivateMessageSyncBatch> fetchVisiblePrivateMessages(
    ConversationSummary conversation, {
    required bool Function() isCurrent,
    Set<String> knownMessageIds = const <String>{},
    String? resumeCursor,
  }) async => _batch('fallback-message');

  @override
  Future<PrivateMessageSyncBatch> fetchVisiblePrivateMessagePage(
    ConversationSummary conversation, {
    required bool Function() isCurrent,
    String? cursor,
  }) {
    pageCalls += 1;
    if (pageCalls == 2) return releaseRefresh.future;
    return Future<PrivateMessageSyncBatch>.value(
      _batch(pageCalls == 1 ? 'initial-message' : 'refreshed-message'),
    );
  }

  @override
  Future<void> markVisiblePrivateMessagesRead(
    ConversationSummary conversation, {
    required bool Function() isCurrent,
  }) async {}
}

PrivateMessageSyncBatch _batch(String content) =>
    PrivateMessageSyncBatch(<ChatMessage>[
      ChatMessage(
        id: 'message-rendered',
        conversationId: 'conversation-1',
        senderUserId: 123,
        senderName: '对方',
        content: content,
        createdAt: DateTime.utc(2030, 1, 1, 12),
        isMine: false,
        status: ChatMessageStatus.received,
      ),
    ]);

ConversationSummary _conversation() => ConversationSummary(
  id: 'conversation-1',
  kind: ConversationKind.privateChat,
  title: '对方',
  lastMessage: '',
  updatedAt: DateTime.utc(2030, 1, 1, 12),
  unreadCount: 0,
  targetUserId: 123,
);

ImSessionCredentials _credentials(DateTime now) => ImSessionCredentials(
  provider: ImSessionCredentials.expectedProvider,
  sdkAppId: 1400000000,
  userId: 'u-123',
  userSig: 'sig_123456789012',
  expiresAt: now.add(const Duration(hours: 1)),
  ttlSeconds: 3600,
  imStatus: ImSessionCredentials.readyStatus,
  systemAccount: 'administrator',
);

AuthSession _authSession(DateTime now) => AuthSession(
  accessToken: 'access-token',
  tokenType: 'Bearer',
  expiresAt: now.add(const Duration(hours: 1)),
  refreshToken: 'refresh-token',
  refreshExpiresAt: now.add(const Duration(hours: 2)),
  deviceId: 'device-1',
  userId: 123,
  mobile: '13800138000',
  roles: 'USER',
);
