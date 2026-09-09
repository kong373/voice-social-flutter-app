import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/features/commerce/data/mock_commerce_repository.dart';
import 'package:voice_social_app/features/commerce/domain/commerce_models.dart';
import 'package:voice_social_app/features/room/application/room_controller.dart';
import 'package:voice_social_app/features/room/data/mock_room_repository.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/domain/room_repository.dart';
import 'package:voice_social_app/features/room/infrastructure/room_realtime_gateway.dart';
import 'package:voice_social_app/features/room/infrastructure/rtc_adapter.dart';
import 'package:voice_social_app/features/room/presentation/gift_sheet.dart';
import 'package:voice_social_app/features/room/presentation/video_runtime_room_page.dart';

const _alice = GiftTarget(userId: 20, name: 'Alice');
const _bob = GiftTarget(userId: 30, name: 'Bob');

Finder get _send => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == '赠送礼物',
);

bool _sendEnabled(WidgetTester tester) =>
    tester.widget<Semantics>(_send).properties.enabled == true;

void main() {
  testWidgets('S09 selecting two recipients previews and submits each once', (
    tester,
  ) async {
    final h = _SheetHarness([_alice, _bob]);
    addTearDown(h.dispose);
    await h.mount(tester);
    await tester.tap(find.text('Bob'));
    await tester.pump();
    expect(find.text('赠送 · 20'), findsOneWidget);
    await tester.tap(_send);
    await tester.pumpAndSettle();
    expect(h.requests.map((request) => request.target.userId), [20, 30]);
    expect(h.requests.map((request) => request.quantity), [1, 1]);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('S07 gift balance shows tenths but whole price is not repriced', (
    tester,
  ) async {
    final h = _SheetHarness([_alice]);
    addTearDown(h.dispose);
    (h.dependencies.commerceRepository as MockCommerceRepository).giftCoins =
        GiftCoinAmount.fromTenths('5');
    await h.mount(tester);
    expect(find.text('0.5'), findsOneWidget);
    await tester.tap(_send);
    await tester.pumpAndSettle();
    expect(find.text('礼物币不足'), findsOneWidget);
    expect(h.requests, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'S09 20.1 coins covers exactly two 10-coin recipients without rounding balance',
    (tester) async {
      final h = _SheetHarness([_alice, _bob]);
      addTearDown(h.dispose);
      (h.dependencies.commerceRepository as MockCommerceRepository).giftCoins =
          GiftCoinAmount.fromTenths('201');
      await h.mount(tester);
      expect(find.text('20.1'), findsOneWidget);
      await tester.tap(find.text('Bob'));
      await tester.pump();
      await tester.tap(_send);
      await tester.pumpAndSettle();
      expect(find.text('礼物币不足'), findsNothing);
      expect(h.requests, hasLength(2));
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('removed recipient is not replaced or submitted accidentally', (
    tester,
  ) async {
    final h = _SheetHarness([_alice, _bob]);
    addTearDown(h.dispose);
    await h.mount(tester);
    expect(_sendEnabled(tester), isTrue);
    h.targets.value = [_bob];
    await tester.pumpAndSettle();
    expect(find.text('Alice'), findsNothing);
    expect(_sendEnabled(tester), isFalse);
    await tester.tap(_send);
    await tester.pumpAndSettle();
    expect(h.requests, isEmpty);
    await tester.tap(find.text('Bob'));
    await tester.pump();
    await tester.tap(_send);
    await tester.pumpAndSettle();
    expect(h.requests.single.target.userId, 30);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'same recipient keeps selection and receives latest display name',
    (tester) async {
      final h = _SheetHarness([_alice, _bob]);
      addTearDown(h.dispose);
      await h.mount(tester);
      h.targets.value = [_bob, const GiftTarget(userId: 20, name: 'Alice new')];
      await tester.pumpAndSettle();
      await tester.tap(_send);
      await tester.pumpAndSettle();
      expect(h.requests.single.target.userId, 20);
      expect(h.requests.single.target.name, 'Alice new');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('pending send retains intent while the recipient leaves', (
    tester,
  ) async {
    final h = _SheetHarness([_alice, _bob]);
    h.pending = Completer<bool>();
    addTearDown(h.dispose);
    await h.mount(tester);
    await tester.tap(_send);
    await tester.pump();
    h.targets.value = [_bob];
    await tester.pump();
    expect(h.requests.single.target.userId, 20);
    expect(_sendEnabled(tester), isFalse);
    h.pending!.complete(false);
    await tester.pumpAndSettle();
    expect(_sendEnabled(tester), isFalse);
    expect(h.requests, hasLength(1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('room authority updates the already open gift sheet', (
    tester,
  ) async {
    final h = _RoomHarness();
    addTearDown(h.dispose);
    await h.mount(tester);
    expect(find.text('当前没有可赠送的麦上用户'), findsOneWidget);
    h.repository.targets = [_alice];
    await h.controller.refreshRoomAuthority();
    await tester.pumpAndSettle();
    expect(find.text('当前没有可赠送的麦上用户'), findsNothing);
    expect(
      find.descendant(of: find.byType(GiftSheet), matching: find.text('Alice')),
      findsOneWidget,
    );
    // A newly arriving user must be chosen explicitly, not auto-selected.
    expect(_sendEnabled(tester), isFalse);
    await tester.tap(
      find.descendant(of: find.byType(GiftSheet), matching: find.text('Alice')),
    );
    await tester.pump();
    expect(_sendEnabled(tester), isTrue);
    h.repository.targets = [_bob];
    await h.controller.refreshRoomAuthority();
    await tester.pumpAndSettle();
    expect(_sendEnabled(tester), isFalse);
    expect(h.repository.sends, 0);
    await tester.pumpWidget(const SizedBox());
    h.controller.dispose();
  });

  testWidgets(
    'temporary reconnect disables sending but preserves the chosen user',
    (tester) async {
      final h = _RoomHarness();
      h.repository.targets = [_alice];
      addTearDown(h.dispose);
      await h.mount(tester);
      expect(_sendEnabled(tester), isTrue);
      h.repository.reconnectCompletion = Completer<RoomSnapshot>();
      final reconnect = h.controller.reconnect();
      await tester.pump();
      expect(_sendEnabled(tester), isFalse);
      h.repository.reconnectCompletion!.complete(h.repository.current);
      await reconnect;
      await tester.pumpAndSettle();
      expect(_sendEnabled(tester), isTrue);
      expect(h.repository.sends, 0);
      await tester.pumpWidget(const SizedBox());
      h.controller.dispose();
    },
  );

  for (final changeIdentity in [false, true]) {
    testWidgets(
      'open gift sheet loses authority on session end ($changeIdentity)',
      (tester) async {
        final h = _RoomHarness();
        h.repository.targets = [_alice];
        addTearDown(h.dispose);
        await h.mount(tester);
        expect(_sendEnabled(tester), isTrue);
        if (changeIdentity) {
          h.identity.value = 11;
        } else {
          h.repository.memberActive = false;
          await h.controller.refreshRoomAuthority();
        }
        await tester.pumpAndSettle();
        expect(_sendEnabled(tester), isFalse);
        await tester.tap(_send);
        await tester.pumpAndSettle();
        expect(h.repository.sends, 0);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}

class _SheetHarness {
  _SheetHarness(List<GiftTarget> initial) : targets = ValueNotifier(initial);
  final dependencies = AppDependencies.mock();
  final ValueNotifier<List<GiftTarget>> targets;
  final requests = <GiftSendRequest>[];
  Completer<bool>? pending;

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: dependencies,
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 390,
                height: 490,
                child: ValueListenableBuilder<List<GiftTarget>>(
                  valueListenable: targets,
                  builder: (_, current, _) => GiftSheet(
                    balance: 1200,
                    account: '',
                    targets: current,
                    onSend: (request) async {
                      requests.add(request);
                      return pending == null ? false : await pending!.future;
                    },
                    onRechargeReturn: () async => 1200,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  void dispose() {
    targets.dispose();
    dependencies.dispose();
  }
}

class _RoomHarness {
  final dependencies = AppDependencies.mock();
  final repository = _Repository();
  final realtime = MockRoomRealtimeGateway();
  final identity = ValueNotifier<int?>(10);
  late final controller = RoomController(
    roomId: 'gift-target-room',
    title: 'Gift targets',
    currentUserId: 10,
    accessToken: 'fixture',
    repository: repository,
    rtcAdapter: MockRtcAdapter(),
    realtimeGateway: realtime,
    sessionChanges: identity,
    activeUserId: () => identity.value,
  );

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: dependencies,
        child: MaterialApp(home: VideoRuntimeRoomPage(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('礼物').hitTestable());
    await tester.pumpAndSettle();
  }

  Future<void> dispose() async {
    controller.dispose();
    identity.dispose();
    await realtime.dispose();
    dependencies.dispose();
  }
}

class _Repository extends MockRoomRepository
    implements RoomAuthorityRepository {
  List<GiftTarget> targets = [];
  bool memberActive = true;
  int sends = 0;
  int version = 0;
  late RoomSnapshot base;
  Completer<RoomSnapshot>? reconnectCompletion;

  RoomSnapshot get current => base.copyWith(
    seats: [
      for (var i = 0; i < targets.length; i++)
        MicSeat(
          number: i + 1,
          backendIndex: i + 1,
          state: MicSeatState.occupied,
          userId: targets[i].userId,
          userName: targets[i].name,
        ),
    ],
    transportMode: RoomTransportMode.snapshotOnly,
  );

  @override
  Future<RoomSnapshot> enterRoom({
    required String roomId,
    required String? password,
    required RoomEntrySource source,
    required int currentUserId,
  }) async {
    base = await super.enterRoom(
      roomId: roomId,
      password: password,
      source: source,
      currentUserId: currentUserId,
    );
    return current;
  }

  @override
  Future<RoomSnapshot> reconnectRoom({
    required String roomId,
    required int currentUserId,
  }) async =>
      reconnectCompletion == null ? current : await reconnectCompletion!.future;

  @override
  Future<RoomAuthorityProjection> fetchRoomAuthority({
    required String roomId,
    required int currentUserId,
  }) async => RoomAuthorityProjection(
    snapshot: current,
    viewerUserId: currentUserId,
    memberActive: memberActive,
    roomMuted: false,
    version: ++version,
  );

  @override
  Future<GiftReceipt> sendGift({
    required String roomId,
    required String giftId,
    required List<int> receiverUserIds,
    required int quantity,
    required int giftFrom,
    String? requestId,
  }) async {
    sends++;
    return super.sendGift(
      roomId: roomId,
      giftId: giftId,
      receiverUserIds: receiverUserIds,
      quantity: quantity,
      giftFrom: giftFrom,
      requestId: requestId,
    );
  }
}
