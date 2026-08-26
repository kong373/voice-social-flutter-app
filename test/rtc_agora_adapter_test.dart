import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/features/account/compliance/domain/account_compliance.dart';
import 'package:voice_social_app/features/account/compliance/infrastructure/native_permission_adapter.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/infrastructure/rtc_adapter.dart';

void main() {
  final DateTime now = DateTime.utc(2030, 1, 1, 12);

  test(
    'joins audio with server credentials and maps mute/leave lifecycle',
    () async {
      final _FakeRtcEngine engine = _FakeRtcEngine();
      final AgoraRtcAdapter adapter = AgoraRtcAdapter(
        engine: engine,
        now: () => now,
      );
      addTearDown(adapter.release);

      await adapter.join(_credentials(role: 'broadcaster'));

      expect(engine.initializeCalls, 1);
      expect(engine.enableAudioCalls, 1);
      expect(engine.joinCalls, 1);
      expect(engine.lastContext?.appId, 'public-app-id');
      expect(engine.lastJoinChannel, 'room-42');
      expect(engine.lastJoinUid, 42);
      expect(
        engine.lastJoinOptions?.clientRoleType,
        ClientRoleType.clientRoleBroadcaster,
      );
      expect(engine.lastJoinOptions?.publishMicrophoneTrack, isFalse);
      expect(adapter.localAudioEnabled, isFalse);
      expect(adapter.joined, isTrue);

      await adapter.setLocalAudioEnabled(false);
      expect(engine.muteCalls, <bool>[true]);
      expect(adapter.localAudioEnabled, isFalse);

      await adapter.leave();
      expect(engine.leaveCalls, 1);
      expect(adapter.joined, isFalse);
    },
  );

  test(
    'reconnect preserves muted state and reuses the initialized engine',
    () async {
      final _FakeRtcEngine engine = _FakeRtcEngine();
      final AgoraRtcAdapter adapter = AgoraRtcAdapter(
        engine: engine,
        now: () => now,
      );
      addTearDown(adapter.release);

      await adapter.join(_credentials(role: 'speaker'));
      await adapter.setLocalAudioEnabled(false);
      await adapter.reconnect(_credentials(role: 'speaker', token: 'token-2'));

      expect(engine.initializeCalls, 1);
      expect(engine.joinCalls, 2);
      expect(engine.leaveCalls, 1);
      expect(engine.renewedTokens, isEmpty);
      expect(engine.muteCalls, <bool>[true, true]);
      expect(adapter.localAudioEnabled, isFalse);
    },
  );

  test('permission denial never starts microphone publication', () async {
    final _FakeRtcEngine engine = _FakeRtcEngine();
    final _FakePermissionAdapter permissions = _FakePermissionAdapter(
      statusValue: PermissionState.denied,
      requestValue: PermissionState.denied,
    );
    final AgoraRtcAdapter adapter = AgoraRtcAdapter(
      engine: engine,
      now: () => now,
      microphonePermissionAdapter: permissions,
    );
    addTearDown(adapter.release);

    await adapter.join(_credentials(role: 'broadcaster'));
    await expectLater(
      adapter.setLocalAudioEnabled(true),
      throwsA(
        isA<RtcAdapterException>().having(
          (RtcAdapterException error) => error.failure,
          'failure',
          RtcAdapterFailure.permission,
        ),
      ),
    );
    expect(permissions.requestCalls, 1);
    expect(engine.updatedOptions, isEmpty);
    expect(engine.muteCalls, isEmpty);
    expect(adapter.localAudioEnabled, isFalse);
  });

  test(
    'granted microphone permission explicitly publishes broadcaster audio',
    () async {
      final _FakeRtcEngine engine = _FakeRtcEngine();
      final _FakePermissionAdapter permissions = _FakePermissionAdapter(
        statusValue: PermissionState.granted,
        requestValue: PermissionState.granted,
      );
      final AgoraRtcAdapter adapter = AgoraRtcAdapter(
        engine: engine,
        now: () => now,
        microphonePermissionAdapter: permissions,
      );
      addTearDown(adapter.release);

      await adapter.join(_credentials(role: 'broadcaster'));
      await adapter.setLocalAudioEnabled(true);
      expect(permissions.statusCalls, 1);
      expect(permissions.requestCalls, 0);
      expect(engine.updatedOptions.single.publishMicrophoneTrack, isTrue);
      expect(engine.muteCalls, <bool>[false]);
      expect(adapter.localAudioEnabled, isTrue);

      await adapter.setLocalAudioEnabled(false);
      expect(engine.updatedOptions.last.publishMicrophoneTrack, isFalse);
      expect(engine.muteCalls, <bool>[false, true]);
      expect(adapter.localAudioEnabled, isFalse);
    },
  );

  test('audience role cannot enable microphone even with permission', () async {
    final _FakeRtcEngine engine = _FakeRtcEngine();
    final _FakePermissionAdapter permissions = _FakePermissionAdapter(
      statusValue: PermissionState.granted,
      requestValue: PermissionState.granted,
    );
    final AgoraRtcAdapter adapter = AgoraRtcAdapter(
      engine: engine,
      now: () => now,
      microphonePermissionAdapter: permissions,
    );
    addTearDown(adapter.release);

    await adapter.join(_credentials(role: 'audience'));
    await expectLater(
      adapter.setLocalAudioEnabled(true),
      throwsA(
        isA<RtcAdapterException>().having(
          (RtcAdapterException error) => error.failure,
          'failure',
          RtcAdapterFailure.mute,
        ),
      ),
    );
    expect(permissions.statusCalls, 0);
    expect(engine.updatedOptions, isEmpty);
    expect(adapter.localAudioEnabled, isFalse);
  });

  test('expiry callbacks share one renewal request', () async {
    final _FakeRtcEngine engine = _FakeRtcEngine();
    final Completer<RtcCredentials> renewal = Completer<RtcCredentials>();
    int providerCalls = 0;
    final AgoraRtcAdapter adapter = AgoraRtcAdapter(
      engine: engine,
      now: () => now,
      credentialsProvider: (String roomId) {
        expect(roomId, 'room-42');
        providerCalls += 1;
        return renewal.future;
      },
    );
    addTearDown(adapter.release);
    await adapter.join(_credentials(role: 'broadcaster'));

    engine.handler!.onRequestToken!(RtcConnection());
    engine.handler!.onTokenPrivilegeWillExpire!(RtcConnection(), 'token-1');
    await Future<void>.delayed(Duration.zero);
    expect(providerCalls, 1);

    renewal.complete(_credentials(role: 'broadcaster', token: 'token-2'));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(engine.renewedTokens, <String>['token-2']);
    expect(adapter.credentials?.token, 'token-2');
  });

  test(
    'join callbacks are emitted once and stale callbacks after leave are ignored',
    () async {
      final _FakeRtcEngine engine = _FakeRtcEngine();
      final AgoraRtcAdapter adapter = AgoraRtcAdapter(
        engine: engine,
        now: () => now,
      );
      addTearDown(adapter.release);
      final List<RtcAdapterEvent> events = <RtcAdapterEvent>[];
      final StreamSubscription<RtcAdapterEvent> subscription = adapter.events
          .listen(events.add);
      addTearDown(subscription.cancel);

      await adapter.join(_credentials(role: 'audience'));
      final RtcEngineEventHandler handler = engine.handler!;
      handler.onJoinChannelSuccess!(RtcConnection(), 42);
      handler.onJoinChannelSuccess!(RtcConnection(), 42);
      expect(
        events.where(
          (RtcAdapterEvent event) => event.type == RtcAdapterEventType.joined,
        ),
        hasLength(1),
      );

      await adapter.leave();
      handler.onJoinChannelSuccess!(RtcConnection(), 42);
      expect(
        events.where(
          (RtcAdapterEvent event) => event.type == RtcAdapterEventType.joined,
        ),
        hasLength(1),
      );
    },
  );

  test(
    'callbacks after release are ignored and do not call the provider',
    () async {
      final _FakeRtcEngine engine = _FakeRtcEngine();
      int providerCalls = 0;
      final AgoraRtcAdapter adapter = AgoraRtcAdapter(
        engine: engine,
        now: () => now,
        credentialsProvider: (String _) async {
          providerCalls += 1;
          return _credentials(role: 'broadcaster', token: 'token-2');
        },
      );
      await adapter.join(_credentials(role: 'broadcaster'));
      final RtcEngineEventHandler handler = engine.handler!;
      await adapter.release();

      handler.onRequestToken!(RtcConnection());
      handler.onTokenPrivilegeWillExpire!(RtcConnection(), 'token-1');
      await Future<void>.delayed(Duration.zero);

      expect(providerCalls, 0);
      expect(engine.releaseCalls, 1);
      expect(adapter.joined, isFalse);
    },
  );

  test(
    'missing, expired, and wrong-provider credentials fail before SDK calls',
    () async {
      final _FakeRtcEngine engine = _FakeRtcEngine();
      final AgoraRtcAdapter adapter = AgoraRtcAdapter(
        engine: engine,
        now: () => now,
      );
      addTearDown(adapter.release);

      for (final RtcCredentials credentials in <RtcCredentials>[
        const RtcCredentials(
          solution: RtcSolution.agora,
          provider: 'agora',
          token: '',
          channelId: 'room-42',
          appId: 'public-app-id',
          uid: 42,
          role: 'audience',
        ),
        RtcCredentials(
          solution: RtcSolution.agora,
          provider: 'agora',
          token: 'token-1',
          channelId: 'room-42',
          appId: 'public-app-id',
          uid: 42,
          role: 'audience',
          expiresAt: DateTime.utc(2030, 1, 1, 11),
        ),
        const RtcCredentials(
          solution: RtcSolution.zego,
          provider: 'zego',
          token: 'token-1',
          channelId: 'room-42',
          appId: 'public-app-id',
          uid: 42,
          role: 'audience',
        ),
      ]) {
        await expectLater(
          adapter.join(credentials),
          throwsA(
            isA<RtcAdapterException>().having(
              (RtcAdapterException error) => error.failure,
              'failure',
              RtcAdapterFailure.invalidCredentials,
            ),
          ),
        );
      }
      expect(engine.initializeCalls, 0);
      expect(engine.joinCalls, 0);
    },
  );

  test(
    'join waits for the provider success callback and times out safely',
    () async {
      final _FakeRtcEngine engine = _FakeRtcEngine()..emitJoinSuccess = false;
      final AgoraRtcAdapter adapter = AgoraRtcAdapter(
        engine: engine,
        now: () => now,
        joinTimeout: const Duration(milliseconds: 20),
        leaveTimeout: const Duration(milliseconds: 20),
      );
      addTearDown(adapter.release);

      await expectLater(
        adapter.join(_credentials(role: 'audience')),
        throwsA(
          isA<RtcAdapterException>().having(
            (RtcAdapterException error) => error.failure,
            'failure',
            RtcAdapterFailure.join,
          ),
        ),
      );
      expect(adapter.joined, isFalse);
      expect(engine.joinCalls, 1);
      expect(engine.leaveCalls, 1);
    },
  );

  test(
    'concurrent joins share one native initialize and join operation',
    () async {
      final _FakeRtcEngine engine = _FakeRtcEngine();
      final AgoraRtcAdapter adapter = AgoraRtcAdapter(
        engine: engine,
        now: () => now,
      );
      addTearDown(adapter.release);

      final Future<void> first = adapter.join(_credentials(role: 'audience'));
      final Future<void> second = adapter.join(_credentials(role: 'audience'));
      expect(identical(first, second), isTrue);
      await Future.wait(<Future<void>>[first, second]);

      expect(engine.initializeCalls, 1);
      expect(engine.joinCalls, 1);
    },
  );

  test(
    'concurrent joins with different identities fail without touching the first session',
    () async {
      final _FakeRtcEngine engine = _FakeRtcEngine()..emitJoinSuccess = false;
      final AgoraRtcAdapter adapter = AgoraRtcAdapter(
        engine: engine,
        now: () => now,
        joinTimeout: const Duration(seconds: 1),
      );
      addTearDown(adapter.release);

      final RtcCredentials firstCredentials = _credentials(
        role: 'broadcaster',
        token: 'token-a',
      );
      final RtcCredentials secondCredentials = _credentials(
        role: 'audience',
        token: 'token-b',
        channelId: 'room-b',
        uid: 43,
      );
      final Future<void> first = adapter.join(firstCredentials);
      await Future<void>.delayed(Duration.zero);
      final Future<void> second = adapter.join(secondCredentials);

      expect(identical(first, second), isFalse);
      await expectLater(
        second,
        throwsA(
          isA<RtcAdapterException>()
              .having(
                (RtcAdapterException error) => error.failure,
                'failure',
                RtcAdapterFailure.join,
              )
              .having(
                (RtcAdapterException error) => error.toString(),
                'sanitized message',
                isNot(contains('token-b')),
              ),
        ),
      );

      engine.handler!.onJoinChannelSuccess!(
        RtcConnection(channelId: 'room-42', localUid: 42),
        42,
      );
      await first;
      expect(engine.joinCalls, 1);
      expect(engine.lastJoinChannel, 'room-42');
      expect(engine.lastJoinUid, 42);
      expect(adapter.credentials?.token, 'token-a');
      expect(adapter.credentials?.channelId, 'room-42');
      expect(adapter.joined, isTrue);
    },
  );

  test(
    'same identity joins share the first native operation and never replace its token',
    () async {
      final _FakeRtcEngine engine = _FakeRtcEngine()..emitJoinSuccess = false;
      final AgoraRtcAdapter adapter = AgoraRtcAdapter(
        engine: engine,
        now: () => now,
        joinTimeout: const Duration(seconds: 1),
      );
      addTearDown(adapter.release);

      final Future<void> first = adapter.join(
        _credentials(role: 'broadcaster', token: 'token-a'),
      );
      await Future<void>.delayed(Duration.zero);
      final Future<void> second = adapter.join(
        _credentials(role: 'publisher', token: 'token-b'),
      );

      expect(identical(first, second), isTrue);
      engine.handler!.onJoinChannelSuccess!(
        RtcConnection(channelId: 'room-42', localUid: 42),
        42,
      );
      await Future.wait(<Future<void>>[first, second]);

      expect(engine.initializeCalls, 1);
      expect(engine.joinCalls, 1);
      expect(engine.lastJoinChannel, 'room-42');
      expect(engine.lastJoinUid, 42);
      expect(adapter.credentials?.token, 'token-a');
      expect(adapter.credentials?.role, 'broadcaster');
    },
  );

  test(
    'joined A then join B fails closed and leaves native/session identity unchanged',
    () async {
      final _FakeRtcEngine engine = _FakeRtcEngine();
      final AgoraRtcAdapter adapter = AgoraRtcAdapter(
        engine: engine,
        now: () => now,
      );
      addTearDown(adapter.release);

      await adapter.join(_credentials(role: 'audience', token: 'token-a'));
      await expectLater(
        adapter.join(
          _credentials(
            role: 'broadcaster',
            token: 'token-b',
            channelId: 'room-b',
            uid: 43,
          ),
        ),
        throwsA(
          isA<RtcAdapterException>()
              .having(
                (RtcAdapterException error) => error.failure,
                'failure',
                RtcAdapterFailure.join,
              )
              .having(
                (RtcAdapterException error) => error.toString(),
                'sanitized message',
                isNot(contains('token-b')),
              ),
        ),
      );

      expect(engine.joinCalls, 1);
      expect(engine.leaveCalls, 0);
      expect(engine.lastJoinChannel, 'room-42');
      expect(engine.lastJoinUid, 42);
      expect(adapter.credentials?.token, 'token-a');
      expect(adapter.credentials?.channelId, 'room-42');
      expect(adapter.joined, isTrue);
    },
  );

  test(
    'joined A then same identity join is idempotent without replacing active token',
    () async {
      final _FakeRtcEngine engine = _FakeRtcEngine();
      final AgoraRtcAdapter adapter = AgoraRtcAdapter(
        engine: engine,
        now: () => now,
      );
      addTearDown(adapter.release);

      await adapter.join(_credentials(role: 'broadcaster', token: 'token-a'));
      await adapter.join(_credentials(role: 'publisher', token: 'token-b'));

      expect(engine.joinCalls, 1);
      expect(engine.leaveCalls, 0);
      expect(adapter.credentials?.token, 'token-a');
      expect(adapter.credentials?.role, 'broadcaster');
      expect(adapter.joined, isTrue);
    },
  );

  test(
    'initialize with a different identity while joined fails without overwriting active credentials',
    () async {
      final _FakeRtcEngine engine = _FakeRtcEngine();
      final AgoraRtcAdapter adapter = AgoraRtcAdapter(
        engine: engine,
        now: () => now,
      );
      addTearDown(adapter.release);

      await adapter.join(_credentials(role: 'audience', token: 'token-a'));
      await expectLater(
        adapter.initialize(
          _credentials(
            role: 'audience',
            token: 'token-b',
            channelId: 'room-b',
            uid: 43,
          ),
        ),
        throwsA(
          isA<RtcAdapterException>()
              .having(
                (RtcAdapterException error) => error.failure,
                'failure',
                RtcAdapterFailure.initialize,
              )
              .having(
                (RtcAdapterException error) => error.toString(),
                'sanitized message',
                isNot(contains('token-b')),
              ),
        ),
      );

      expect(engine.initializeCalls, 1);
      expect(engine.releaseCalls, 0);
      expect(engine.joinCalls, 1);
      expect(adapter.credentials?.appId, 'public-app-id');
      expect(adapter.credentials?.token, 'token-a');
      expect(adapter.credentials?.channelId, 'room-42');
      expect(adapter.joined, isTrue);
    },
  );

  test(
    'initialize with the same identity while joined never replaces the active token',
    () async {
      final _FakeRtcEngine engine = _FakeRtcEngine();
      final AgoraRtcAdapter adapter = AgoraRtcAdapter(
        engine: engine,
        now: () => now,
      );
      addTearDown(adapter.release);

      await adapter.join(_credentials(role: 'audience', token: 'token-a'));
      await adapter.initialize(
        _credentials(role: 'subscriber', token: 'token-b'),
      );

      expect(engine.initializeCalls, 1);
      expect(engine.releaseCalls, 0);
      expect(engine.joinCalls, 1);
      expect(adapter.credentials?.token, 'token-a');
      expect(adapter.credentials?.role, 'audience');
      expect(adapter.joined, isTrue);
    },
  );

  test(
    'concurrent reconnects with different identities fail without changing the first reconnect',
    () async {
      final _FakeRtcEngine engine = _FakeRtcEngine()..emitLeaveSuccess = false;
      final AgoraRtcAdapter adapter = AgoraRtcAdapter(
        engine: engine,
        now: () => now,
        leaveTimeout: const Duration(seconds: 1),
      );
      addTearDown(adapter.release);
      await adapter.join(_credentials(role: 'audience', token: 'token-a'));

      final Future<void> first = adapter.reconnect(
        _credentials(role: 'audience', token: 'token-a2'),
      );
      await Future<void>.delayed(Duration.zero);
      final Future<void> second = adapter.reconnect(
        _credentials(
          role: 'broadcaster',
          token: 'token-b',
          channelId: 'room-b',
          uid: 43,
        ),
      );

      expect(identical(first, second), isFalse);
      await expectLater(
        second,
        throwsA(
          isA<RtcAdapterException>()
              .having(
                (RtcAdapterException error) => error.failure,
                'failure',
                RtcAdapterFailure.join,
              )
              .having(
                (RtcAdapterException error) => error.toString(),
                'sanitized message',
                isNot(contains('token-b')),
              ),
        ),
      );

      engine.handler!.onLeaveChannel!(
        RtcConnection(channelId: 'room-42', localUid: 42),
        RtcStats(),
      );
      await first;

      expect(engine.joinCalls, 2);
      expect(engine.leaveCalls, 1);
      expect(engine.lastJoinChannel, 'room-42');
      expect(engine.lastJoinUid, 42);
      expect(adapter.credentials?.token, 'token-a2');
      expect(adapter.credentials?.channelId, 'room-42');
      expect(adapter.joined, isTrue);
    },
  );

  test(
    'concurrent reconnects with the same identity share one operation',
    () async {
      final _FakeRtcEngine engine = _FakeRtcEngine()..emitLeaveSuccess = false;
      final AgoraRtcAdapter adapter = AgoraRtcAdapter(
        engine: engine,
        now: () => now,
        leaveTimeout: const Duration(seconds: 1),
      );
      addTearDown(adapter.release);
      await adapter.join(_credentials(role: 'audience', token: 'token-a'));

      final Future<void> first = adapter.reconnect(
        _credentials(role: 'audience', token: 'token-a2'),
      );
      await Future<void>.delayed(Duration.zero);
      final Future<void> second = adapter.reconnect(
        _credentials(role: 'subscriber', token: 'token-b'),
      );

      expect(identical(first, second), isTrue);
      engine.handler!.onLeaveChannel!(
        RtcConnection(channelId: 'room-42', localUid: 42),
        RtcStats(),
      );
      await Future.wait(<Future<void>>[first, second]);

      expect(engine.joinCalls, 2);
      expect(engine.leaveCalls, 1);
      expect(engine.lastJoinChannel, 'room-42');
      expect(engine.lastJoinUid, 42);
      expect(adapter.credentials?.token, 'token-a2');
      expect(adapter.credentials?.role, 'audience');
      expect(adapter.joined, isTrue);
    },
  );

  test(
    'join provider error is authoritative and leaves the pending channel',
    () async {
      final _FakeRtcEngine engine = _FakeRtcEngine()..emitJoinSuccess = false;
      final AgoraRtcAdapter adapter = AgoraRtcAdapter(
        engine: engine,
        now: () => now,
        joinTimeout: const Duration(seconds: 1),
        leaveTimeout: const Duration(milliseconds: 20),
      );
      addTearDown(adapter.release);

      final Future<void> join = adapter.join(_credentials(role: 'audience'));
      await Future<void>.delayed(Duration.zero);
      engine.handler!.onError!(ErrorCodeType.errRefused, 'not logged');
      await expectLater(
        join,
        throwsA(
          isA<RtcAdapterException>().having(
            (RtcAdapterException error) => error.failure,
            'failure',
            RtcAdapterFailure.join,
          ),
        ),
      );
      expect(adapter.joined, isFalse);
      expect(engine.leaveCalls, 1);
    },
  );

  test(
    'leave waits for onLeaveChannel and times out into a clean state',
    () async {
      final _FakeRtcEngine engine = _FakeRtcEngine()..emitLeaveSuccess = false;
      final AgoraRtcAdapter adapter = AgoraRtcAdapter(
        engine: engine,
        now: () => now,
        leaveTimeout: const Duration(milliseconds: 20),
      );
      addTearDown(adapter.release);
      await adapter.join(_credentials(role: 'audience'));

      await expectLater(
        adapter.leave(),
        throwsA(
          isA<RtcAdapterException>().having(
            (RtcAdapterException error) => error.failure,
            'failure',
            RtcAdapterFailure.leave,
          ),
        ),
      );
      expect(adapter.joined, isFalse);
      expect(engine.leaveCalls, 1);
    },
  );

  test(
    'renewal requires onRenewTokenResult rather than native Future completion',
    () async {
      final _FakeRtcEngine engine = _FakeRtcEngine()..emitRenewResult = false;
      final AgoraRtcAdapter adapter = AgoraRtcAdapter(
        engine: engine,
        now: () => now,
        renewTimeout: const Duration(milliseconds: 20),
        credentialsProvider: (String _) async =>
            _credentials(role: 'audience', token: 'token-2'),
      );
      addTearDown(adapter.release);
      await adapter.join(_credentials(role: 'audience'));

      await expectLater(
        adapter.renewToken(),
        throwsA(
          isA<RtcAdapterException>().having(
            (RtcAdapterException error) => error.failure,
            'failure',
            RtcAdapterFailure.renewToken,
          ),
        ),
      );
      expect(adapter.credentials?.token, 'token-1');
    },
  );

  test('callbacks for a different connection are ignored', () async {
    final _FakeRtcEngine engine = _FakeRtcEngine();
    int providerCalls = 0;
    final AgoraRtcAdapter adapter = AgoraRtcAdapter(
      engine: engine,
      now: () => now,
      credentialsProvider: (String _) async {
        providerCalls += 1;
        return _credentials(role: 'audience', token: 'token-2');
      },
    );
    addTearDown(adapter.release);
    await adapter.join(_credentials(role: 'audience'));

    engine.handler!.onRequestToken!(
      RtcConnection(channelId: 'other-room', localUid: 42),
    );
    engine.handler!.onTokenPrivilegeWillExpire!(
      RtcConnection(channelId: 'room-42', localUid: 43),
      'token-1',
    );
    await Future<void>.delayed(Duration.zero);
    expect(providerCalls, 0);
  });
}

RtcCredentials _credentials({
  required String role,
  String token = 'token-1',
  String appId = 'public-app-id',
  String channelId = 'room-42',
  int uid = 42,
}) => RtcCredentials(
  solution: RtcSolution.agora,
  provider: 'agora',
  appId: appId,
  token: token,
  channelId: channelId,
  uid: uid,
  role: role,
  expiresAt: DateTime.utc(2030, 1, 1, 13),
  ttlSeconds: 3600,
);

class _FakeRtcEngine implements RtcEngine {
  RtcEngineContext? lastContext;
  String? lastJoinChannel;
  int? lastJoinUid;
  ChannelMediaOptions? lastJoinOptions;
  RtcEngineEventHandler? handler;
  int initializeCalls = 0;
  int enableAudioCalls = 0;
  int joinCalls = 0;
  int leaveCalls = 0;
  int releaseCalls = 0;
  String? _joinedChannel;
  int? _joinedUid;
  final List<bool> muteCalls = <bool>[];
  final List<ChannelMediaOptions> updatedOptions = <ChannelMediaOptions>[];
  final List<String> renewedTokens = <String>[];
  bool emitJoinSuccess = true;
  bool emitLeaveSuccess = true;
  bool emitRenewResult = true;

  @override
  Future<void> initialize(RtcEngineContext context) async {
    initializeCalls += 1;
    lastContext = context;
  }

  @override
  Future<void> enableAudio() async {
    enableAudioCalls += 1;
  }

  @override
  Future<void> joinChannel({
    required String token,
    required String channelId,
    required int uid,
    required ChannelMediaOptions options,
  }) async {
    joinCalls += 1;
    lastJoinChannel = channelId;
    lastJoinUid = uid;
    lastJoinOptions = options;
    _joinedChannel = channelId;
    _joinedUid = uid;
    if (emitJoinSuccess) {
      scheduleMicrotask(
        () => handler?.onJoinChannelSuccess?.call(
          RtcConnection(channelId: channelId, localUid: uid),
          0,
        ),
      );
    }
  }

  @override
  Future<void> leaveChannel({LeaveChannelOptions? options}) async {
    leaveCalls += 1;
    final String? channel = _joinedChannel;
    final int? uid = _joinedUid;
    _joinedChannel = null;
    _joinedUid = null;
    if (emitLeaveSuccess) {
      scheduleMicrotask(
        () => handler?.onLeaveChannel?.call(
          RtcConnection(channelId: channel, localUid: uid),
          RtcStats(),
        ),
      );
    }
  }

  @override
  Future<void> muteLocalAudioStream(bool mute) async {
    muteCalls.add(mute);
  }

  @override
  Future<void> updateChannelMediaOptions(ChannelMediaOptions options) async {
    updatedOptions.add(options);
  }

  @override
  Future<void> renewToken(String token) async {
    renewedTokens.add(token);
    if (emitRenewResult) {
      scheduleMicrotask(
        () => handler?.onRenewTokenResult?.call(
          RtcConnection(channelId: _joinedChannel, localUid: _joinedUid),
          token,
          RenewTokenErrorCode.renewTokenSuccess,
        ),
      );
    }
  }

  @override
  void registerEventHandler(RtcEngineEventHandler eventHandler) {
    handler = eventHandler;
  }

  @override
  void unregisterEventHandler(RtcEngineEventHandler eventHandler) {
    if (identical(handler, eventHandler)) {
      handler = null;
    }
  }

  @override
  Future<void> release({bool sync = false}) async {
    releaseCalls += 1;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _FakePermissionAdapter implements NativePermissionAdapter {
  _FakePermissionAdapter({
    required this.statusValue,
    required this.requestValue,
  });

  final PermissionState statusValue;
  final PermissionState requestValue;
  int statusCalls = 0;
  int requestCalls = 0;

  @override
  Future<PermissionState> status(PermissionKind kind) async {
    expect(kind, PermissionKind.microphone);
    statusCalls += 1;
    return statusValue;
  }

  @override
  Future<PermissionState> request(PermissionKind kind) async {
    expect(kind, PermissionKind.microphone);
    requestCalls += 1;
    return requestValue;
  }

  @override
  Future<void> openAppSettings() async {}
}
