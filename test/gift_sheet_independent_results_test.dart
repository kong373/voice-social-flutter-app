import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/features/commerce/domain/commerce_models.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/storage/key_value_store.dart';
import 'package:voice_social_app/features/commerce/catalog/domain/commerce_catalog_repository.dart';
import 'package:voice_social_app/features/commerce/data/mock_commerce_repository.dart';
import 'package:voice_social_app/features/room/application/gift_send_coordinator.dart';
import 'package:voice_social_app/features/room/domain/gift_send_models.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/presentation/gift_sheet.dart';

void main() {
  testWidgets(
    'app-owned room controller uses independent journal and preserves fractional Mock balance',
    (tester) async {
      final dependencies = AppDependencies.mock();
      final commerce =
          dependencies.commerceRepository as MockCommerceRepository;
      commerce.giftCoins = GiftCoinAmount.fromTenths('201');
      final controller = dependencies.createRoomController(
        roomId: '880217',
        title: 'Gift room',
      );
      await tester.runAsync(controller.join);
      final targets = controller.seats
          .where(
            (seat) =>
                seat.isOccupied && seat.userId != controller.currentUserId,
          )
          .take(2)
          .map((seat) => GiftTarget(userId: seat.userId!, name: seat.userName!))
          .toList();
      expect(targets, hasLength(2));
      addTearDown(() {
        controller.dispose();
        dependencies.dispose();
      });
      await tester.pumpWidget(
        AppDependencyScope(
          dependencies: dependencies,
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 390,
                height: 490,
                child: GiftSheet(
                  balance: controller.giftBalance,
                  account: 'mock',
                  targets: targets,
                  roomId: controller.roomId,
                  coordinator: controller.giftSendCoordinator,
                  canSendTo: (id) => controller.seats.any(
                    (s) => s.isOccupied && s.userId == id,
                  ),
                  onSend: (_) async => throw StateError('legacy path'),
                  onRechargeReturn: () async => null,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(targets.last.name));
      await tester.pump();
      await tester.tap(find.text('赠送 · 20'));
      await tester.pumpAndSettle();
      expect(dependencies.giftSendCoordinator.plan!.succeeded, 2);
      expect((await commerce.fetchWalletSummary()).giftCoins!.text, '0.1');
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'partial success stays visible and remount recovers unknown only, even off mic',
    (tester) async {
      final h = Harness();
      addTearDown(h.dispose);
      await h.mount(tester);
      await tester.tap(find.text('Bob'));
      await tester.pump();
      await tester.tap(find.text('赠送 · 20'));
      await tester.pumpAndSettle();
      expect(find.text('已送出（已确认）'), findsOneWidget);
      expect(find.textContaining('结果未确认：'), findsOneWidget);
      expect(h.repo.sends.map((c) => c.receiverUserId), [20, 30]);
      final original = h.repo.sends.last;
      await tester.pumpWidget(const SizedBox());
      h.targets = [];
      h.allowed = false;
      await h.mount(tester);
      expect(find.text('用户 30'), findsOneWidget);
      h.repo.found = true;
      await tester.tap(find.text('查询原回执'));
      await tester.pumpAndSettle();
      expect(find.text('已送出（已确认）'), findsNWidgets(2));
      expect(h.repo.sends, hasLength(2));
      expect(h.repo.queries.last.encodedBody, original.encodedBody);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'account B sees no A command and old success cannot paint A after ABA',
    (tester) async {
      final h = Harness();
      addTearDown(h.dispose);
      h.repo.gate = Completer<GiftReceipt>();
      await h.mount(tester);
      await tester.tap(find.text('赠送 · 10'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      final original = h.repo.sends.single;
      h.identity.value = (2, 1);
      await tester.pumpAndSettle();
      expect(find.text('本次逐人结算'), findsNothing);
      expect(find.text('身份已切换，请重新进入房间'), findsWidgets);
      h.identity.value = (1, 2);
      h.repo.gate!.complete(receipt(original));
      await tester.pumpAndSettle();
      expect(find.text('已送出（已确认）'), findsNothing);
      expect(find.textContaining('结果未确认：'), findsOneWidget);
      expect(h.coordinator.plan!.command.encodedBody, original.encodedBody);
      expect(h.repo.sends, hasLength(1));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'double click cannot duplicate commands; completed record needs explicit new selection',
    (tester) async {
      final h = Harness();
      addTearDown(h.dispose);
      await h.mount(tester);
      await tester.tap(find.text('赠送 · 10'));
      await tester.tap(find.text('赠送 · 10'));
      await tester.pumpAndSettle();
      expect(h.repo.sends, hasLength(1));
      expect(find.text('已送出（已确认）'), findsOneWidget);
      expect(find.text('赠送 · 10'), findsNothing);
      await tester.tap(find.text('完成查看，重新选择礼物'));
      await tester.pumpAndSettle();
      expect(h.repo.sends, hasLength(1));
      await tester.tap(find.text('赠送 · 10'));
      await tester.pumpAndSettle();
      expect(h.repo.sends, hasLength(2));
      expect(h.repo.sends[0].requestId, isNot(h.repo.sends[1].requestId));
      await tester.pumpWidget(const SizedBox());
    },
  );
}

GiftReceipt receipt(GiftSendCommand c) => GiftReceipt(
  success: true,
  remainingBalance: null,
  transferId: 'transfer-${c.requestId}',
  requestId: c.requestId,
  roomId: c.roomId,
  senderUserId: c.actorId,
  receiverUserId: c.receiverUserId,
  giftId: c.giftId,
  quantity: c.quantity,
  source: 'WALLET',
  providerInvocation: false,
  reconciled: true,
);

class Harness {
  Harness() {
    dependencies = Dependencies(identity);
    coordinator = GiftSendCoordinator(
      repository: repo,
      store: MemoryKeyValueStore(),
      identity: () => identity.value,
      identityChanges: identity,
    );
  }
  final identity = ValueNotifier<(int?, int)>((1, 0));
  late final Dependencies dependencies;
  late final GiftSendCoordinator coordinator;
  final repo = Repository();
  bool allowed = true;
  List<GiftTarget> targets = const [
    GiftTarget(userId: 20, name: 'Alice'),
    GiftTarget(userId: 30, name: 'Bob'),
  ];
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
                child: GiftSheet(
                  balance: 1200,
                  account: 'test',
                  targets: targets,
                  coordinator: coordinator,
                  roomId: 'room',
                  sendingAllowed: allowed,
                  canSendTo: (id) =>
                      allowed && targets.any((t) => t.userId == id),
                  onSend: (_) async =>
                      throw StateError('legacy path must not run'),
                  onRechargeReturn: () async => null,
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
    coordinator.dispose();
    dependencies.backing.dispose();
    identity.dispose();
  }
}

class Dependencies extends Fake implements AppDependencies {
  Dependencies(ValueNotifier<(int?, int)> identity)
    : commerceRepository = Commerce(identity);
  final backing = AppDependencies.mock();
  @override
  final Commerce commerceRepository;
  @override
  CommerceCatalogRepository get commerceCatalogRepository =>
      backing.commerceCatalogRepository;
}

class Commerce extends MockCommerceRepository {
  Commerce(this.identity);
  final ValueNotifier<(int?, int)> identity;
  @override
  (String?, int) get withdrawalIdentity =>
      (identity.value.$1?.toString(), identity.value.$2);
  @override
  Listenable get withdrawalIdentityChanges => identity;
}

class Repository implements GiftCommandRepository {
  final sends = <GiftSendCommand>[];
  final queries = <GiftSendCommand>[];
  bool found = false;
  Completer<GiftReceipt>? gate;
  @override
  GiftSendCommand freezeGift({
    required int actorId,
    required String roomId,
    required String giftId,
    required int receiverUserId,
    required int quantity,
    required String requestId,
  }) => GiftSendCommand(
    actorId: actorId,
    requestId: requestId,
    roomId: roomId,
    sessionId: 'lease',
    giftId: giftId,
    receiverUserId: receiverUserId,
    quantity: quantity,
  );
  @override
  Future<GiftReceipt> sendGiftCommand(
    GiftSendCommand c, {
    required void Function() requireIdentity,
  }) async {
    requireIdentity();
    sends.add(c);
    if (gate != null) return gate!.future;
    if (c.receiverUserId == 30)
      throw const ApiException(
        kind: ApiFailureKind.timeout,
        message: 'unknown',
      );
    return receipt(c);
  }

  @override
  Future<GiftReceipt> queryGiftCommand(GiftSendCommand c) async {
    queries.add(c);
    if (found) return receipt(c);
    throw const ApiException(
      kind: ApiFailureKind.business,
      code: 404,
      message: 'not found',
    );
  }
}
