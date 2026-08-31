import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/features/im/domain/im_session_credentials.dart';
import 'package:voice_social_app/features/im/domain/im_session_events.dart';
import 'package:voice_social_app/features/im/infrastructure/tencent_im_session_adapter.dart';

void main() {
  final DateTime now = DateTime.utc(2030, 1, 1, 12);

  group('Official Tencent IM SDK observability', () {
    test('logs fixed callback marker for accepted room custom message', () async {
      final List<String> logs = <String>[];
      final OfficialTencentImSdkClient client = OfficialTencentImSdkClient(
        trustedHintEvaluator:
            ({
              required String? senderUserId,
              required String? groupId,
              required bool? isSelf,
            }) =>
                senderUserId == 'admin-system' &&
                groupId == 'room-group-1' &&
                isSelf == false,
        logger: logs.add,
      );
      final List<TencentImSdkEvent> events = <TencentImSdkEvent>[];
      final StreamSubscription<TencentImSdkEvent> subscription = client.events
          .listen(events.add);
      addTearDown(() async {
        await subscription.cancel();
        await client.dispose();
      });

      client.handleObservedMessageForTest(
        const TencentImObservedMessage(
          customData: '{"messageId":"payload-room-message-1","eventVersion":7}',
          senderUserId: 'admin-system',
          groupId: 'room-group-1',
          isSelf: false,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        logs,
        contains(
          'im.tencent.sdk.custom_callback::callback_seen=true::custom=present::group=present::sender=present::isSelf=false::providerTrusted=true',
        ),
      );
      expect(events, hasLength(1));
      expect(_joined(logs), isNot(contains('room-group-1')));
      expect(_joined(logs), isNot(contains('admin-system')));
      expect(_joined(logs), isNot(contains('payload-room-message-1')));
      expect(_joined(logs), isNot(contains('eventVersion')));
    });

    test('logs absent custom marker without emitting an event', () async {
      final List<String> logs = <String>[];
      final OfficialTencentImSdkClient client = OfficialTencentImSdkClient(
        logger: logs.add,
      );
      final List<TencentImSdkEvent> events = <TencentImSdkEvent>[];
      final StreamSubscription<TencentImSdkEvent> subscription = client.events
          .listen(events.add);
      addTearDown(() async {
        await subscription.cancel();
        await client.dispose();
      });

      client.handleObservedMessageForTest(
        const TencentImObservedMessage(
          customData: null,
          senderUserId: 'missing-custom-sender',
          groupId: 'missing-custom-group',
          isSelf: null,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        logs,
        contains(
          'im.tencent.sdk.custom_callback::callback_seen=true::custom=absent::group=present::sender=present::isSelf=unknown::providerTrusted=false',
        ),
      );
      expect(events, isEmpty);
      expect(_joined(logs), isNot(contains('missing-custom-group')));
      expect(_joined(logs), isNot(contains('missing-custom-sender')));
    });
  });

  group('Tencent IM adapter gate observability', () {
    test('logs accepted room gate without leaking room identifiers', () async {
      final _EventGroupSdk sdk = _EventGroupSdk();
      final List<String> logs = <String>[];
      final TencentImSessionAdapter adapter = TencentImSessionAdapter(
        sdkClient: sdk,
        now: () => now,
        operationTimeout: const Duration(milliseconds: 100),
        observabilityLogger: logs.add,
      );
      addTearDown(() async {
        await adapter.dispose();
        await sdk.dispose();
      });
      await adapter.login(_credentials(now));
      expect(
        await adapter.joinGroup(
          groupId: 'room-group-1',
          groupType: 'AVChatRoom',
        ),
        isTrue,
      );

      final List<Object> roomEvents = <Object>[];
      final StreamSubscription<Object> subscription = adapter.roomEvents.listen(
        roomEvents.add,
      );
      addTearDown(subscription.cancel);

      sdk.emit(
        TencentImSdkEvent.customElement(
          data: '{"messageId":"room-secret-1","eventVersion":1}',
          trustedFirstParty: true,
          senderUserId: 'administrator',
          groupId: 'room-group-1',
          isSelf: false,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        logs,
        contains(
          'im.tencent.adapter.room_gate::group=present::groupExact=true::senderExact=true::isSelfFalse=true::providerTrusted=true::parseAccepted=true',
        ),
      );
      expect(roomEvents, hasLength(1));
      expect(_joined(logs), isNot(contains('room-group-1')));
      expect(_joined(logs), isNot(contains('administrator')));
      expect(_joined(logs), isNot(contains('room-secret-1')));
    });

    test('logs wrong group as rejected room gate', () async {
      final _EventGroupSdk sdk = _EventGroupSdk();
      final List<String> logs = <String>[];
      final TencentImSessionAdapter adapter = TencentImSessionAdapter(
        sdkClient: sdk,
        now: () => now,
        operationTimeout: const Duration(milliseconds: 100),
        observabilityLogger: logs.add,
      );
      addTearDown(() async {
        await adapter.dispose();
        await sdk.dispose();
      });
      await adapter.login(_credentials(now));
      await adapter.joinGroup(groupId: 'room-group-1', groupType: 'AVChatRoom');

      sdk.emit(
        TencentImSdkEvent.customElement(
          data: '{"messageId":"wrong-group","eventVersion":2}',
          trustedFirstParty: true,
          senderUserId: 'administrator',
          groupId: 'room-group-2',
          isSelf: false,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        logs,
        contains(
          'im.tencent.adapter.room_gate::group=present::groupExact=false::senderExact=true::isSelfFalse=true::providerTrusted=true::parseAccepted=false',
        ),
      );
      expect(_joined(logs), isNot(contains('room-group-2')));
    });

    test('logs wrong sender as rejected room gate', () async {
      final _EventGroupSdk sdk = _EventGroupSdk();
      final List<String> logs = <String>[];
      final TencentImSessionAdapter adapter = TencentImSessionAdapter(
        sdkClient: sdk,
        now: () => now,
        operationTimeout: const Duration(milliseconds: 100),
        observabilityLogger: logs.add,
      );
      addTearDown(() async {
        await adapter.dispose();
        await sdk.dispose();
      });
      await adapter.login(_credentials(now));
      await adapter.joinGroup(groupId: 'room-group-1', groupType: 'AVChatRoom');

      sdk.emit(
        TencentImSdkEvent.customElement(
          data: '{"messageId":"wrong-sender","eventVersion":3}',
          trustedFirstParty: true,
          senderUserId: 'ordinary-user',
          groupId: 'room-group-1',
          isSelf: false,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        logs,
        contains(
          'im.tencent.adapter.room_gate::group=present::groupExact=true::senderExact=false::isSelfFalse=true::providerTrusted=true::parseAccepted=false',
        ),
      );
      expect(_joined(logs), isNot(contains('ordinary-user')));
    });

    test('logs self-authored room event as rejected gate', () async {
      final _EventGroupSdk sdk = _EventGroupSdk();
      final List<String> logs = <String>[];
      final TencentImSessionAdapter adapter = TencentImSessionAdapter(
        sdkClient: sdk,
        now: () => now,
        operationTimeout: const Duration(milliseconds: 100),
        observabilityLogger: logs.add,
      );
      addTearDown(() async {
        await adapter.dispose();
        await sdk.dispose();
      });
      await adapter.login(_credentials(now));
      await adapter.joinGroup(groupId: 'room-group-1', groupType: 'AVChatRoom');

      sdk.emit(
        TencentImSdkEvent.customElement(
          data: '{"messageId":"self-event","eventVersion":4}',
          trustedFirstParty: true,
          senderUserId: 'administrator',
          groupId: 'room-group-1',
          isSelf: true,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        logs,
        contains(
          'im.tencent.adapter.room_gate::group=present::groupExact=true::senderExact=true::isSelfFalse=false::providerTrusted=true::parseAccepted=false',
        ),
      );
      expect(_joined(logs), isNot(contains('self-event')));
    });

    test(
      'logs missing group as a C2C gate without leaking identifiers',
      () async {
        final _EventGroupSdk sdk = _EventGroupSdk();
        final List<String> logs = <String>[];
        final TencentImSessionAdapter adapter = TencentImSessionAdapter(
          sdkClient: sdk,
          now: () => now,
          operationTimeout: const Duration(milliseconds: 100),
          observabilityLogger: logs.add,
        );
        addTearDown(() async {
          await adapter.dispose();
          await sdk.dispose();
        });
        await adapter.login(_credentials(now));

        final List<ImSessionEvent> events = <ImSessionEvent>[];
        final StreamSubscription<ImSessionEvent> subscription = adapter.events
            .listen(events.add);
        addTearDown(subscription.cancel);

        sdk.emit(
          TencentImSdkEvent.customElement(
            data: '{"messageId":"c2c-secret-1","eventVersion":5}',
            trustedFirstParty: true,
            senderUserId: 'administrator',
            groupId: null,
            isSelf: false,
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(
          logs,
          contains(
            'im.tencent.adapter.c2c_gate::group=absent::groupExact=false::senderExact=true::isSelfFalse=true::providerTrusted=true::parseAccepted=true',
          ),
        );
        expect(
          events.where(
            (ImSessionEvent event) =>
                event.kind == ImSessionEventKind.refreshHint,
          ),
          hasLength(1),
        );
        expect(_joined(logs), isNot(contains('c2c-secret-1')));
      },
    );
  });
}

String _joined(List<String> logs) => logs.join('\n');

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

class _EventGroupSdk
    implements
        TencentImSdkClient,
        TencentImSdkEventSource,
        TencentImSdkGroupClient {
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

  @override
  Future<int> joinGroup({
    required String groupId,
    required String groupType,
  }) async => 0;

  @override
  Future<int> quitGroup({required String groupId}) async => 0;

  void emit(TencentImSdkEvent event) {
    if (!_events.isClosed) {
      _events.add(event);
    }
  }

  Future<void> dispose() => _events.close();
}
