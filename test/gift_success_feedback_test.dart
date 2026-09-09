import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/features/account/domain/auth_models.dart';
import 'package:voice_social_app/features/room/application/room_controller.dart';
import 'package:voice_social_app/features/room/data/backend_room_repository.dart';
import 'package:voice_social_app/features/room/data/room_lease_binding.dart';
import 'package:voice_social_app/features/room/presentation/gift_sheet.dart';

import 'room_lease_contract_fixture.dart';

const _giftId = '550e8400-e29b-41d4-a716-446655440000';
const _roomId = '9527';
const _feedbackKey = Key('gift-success-feedback');

void main() {
  testWidgets(
    'live App coordinator gifts animate each matched success without a second POST or legacy send',
    (tester) async {
      final h = (await tester.runAsync(FeedbackHarness.start))!;
      addTearDown(h.close);
      await h.mount(tester);
      await tester.tap(find.text('Bob'));
      await tester.pump();
      await tester.tap(find.text('赠送 · 20'));
      await h.io(tester, () => h.planDone);
      expect(h.postTargets, [10002, 10003]);
      expect(h.keys.toSet(), hasLength(2));
      expect(h.legacyCalls, 0);
      expect(h.dependencies.giftSendCoordinator.plan!.succeeded, 2);
      expect(find.byKey(_feedbackKey), findsOneWidget);
      expect(feedbackText('送给 Alice'), findsOneWidget);
      expect(feedbackText('送给 Bob'), findsNothing);
      final opacity = find.ancestor(
        of: find.byKey(_feedbackKey),
        matching: find.byType(Opacity),
      );
      expect(tester.widget<Opacity>(opacity.first).opacity, lessThan(1));
      await tester.pump(const Duration(milliseconds: 250));
      expect(tester.widget<Opacity>(opacity.first).opacity, 1);
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 250));
      expect(feedbackText('送给 Bob'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      expect(find.byKey(_feedbackKey), findsNothing);
      await h.recover(tester);
      await tester.pumpWidget(const SizedBox());
      await h.mount(tester);
      expect(find.byKey(_feedbackKey), findsNothing);
      expect(h.postTargets, [10002, 10003]);
      expect(h.legacyCalls, 0);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(h.close);
      await tester.pump();
    },
  );

  testWidgets(
    'partial success animates only strict receipts; unknown, rejected and wrong GET cannot celebrate',
    (tester) async {
      final h = (await tester.runAsync(FeedbackHarness.start))!;
      addTearDown(h.close);
      h.targets.add(const GiftTarget(userId: 10004, name: 'Carol'));
      h.postCodes.addAll({10003: 503, 10004: 400});
      h.receiptsVisible = false;
      await h.mount(tester);
      await tester.tap(find.text('Bob'));
      await tester.tap(find.text('Carol'));
      await tester.pump();
      await tester.tap(find.text('赠送 · 30'));
      await h.io(tester, () => h.planDone);
      expect(h.postTargets, [10002, 10003, 10004]);
      expect(h.dependencies.giftSendCoordinator.plan!.succeeded, 1);
      expect(feedbackText('送给 Alice'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      expect(find.byKey(_feedbackKey), findsNothing);
      h.receiptsVisible = true;
      h.wrongReceipt = true;
      await h.recover(tester);
      expect(find.byKey(_feedbackKey), findsNothing);
      expect(h.dependencies.giftSendCoordinator.plan!.succeeded, 1);
      h.wrongReceipt = false;
      await h.recover(tester);
      expect(feedbackText('送给 Bob'), findsOneWidget);
      expect(feedbackText('Carol'), findsNothing);
      expect(h.dependencies.giftSendCoordinator.plan!.succeeded, 2);
      final gets = h.gets;
      await tester.pump(const Duration(seconds: 4));
      await h.recover(tester);
      expect(find.byKey(_feedbackKey), findsNothing);
      expect(h.gets, gets); // Terminal recipients do not even need another GET.
      expect(h.postTargets, [10002, 10003, 10004]);
      expect(h.legacyCalls, 0);
      await h.finish(tester);
    },
  );

  testWidgets(
    'room change hides active feedback; account ABA drops queued feedback without resending',
    (tester) async {
      final h = (await tester.runAsync(FeedbackHarness.start))!;
      addTearDown(h.close);
      await h.mount(tester);
      await tester.tap(find.text('Bob'));
      await tester.pump();
      await tester.tap(find.text('赠送 · 20'));
      await h.io(tester, () => h.planDone);
      expect(feedbackText('送给 Alice'), findsOneWidget);
      h.visibleRoom = 'another-room';
      await h.mount(tester);
      expect(find.byKey(_feedbackKey), findsNothing);
      await tester.pump(const Duration(seconds: 4));
      expect(find.byKey(_feedbackKey), findsNothing);
      await h.login(20001);
      await tester.pump();
      expect(find.text('本次逐人结算'), findsNothing);
      await h.login(10001);
      h.visibleRoom = _roomId;
      await h.mount(tester);
      expect(find.byKey(_feedbackKey), findsNothing);
      await h.recover(tester);
      expect(find.byKey(_feedbackKey), findsNothing);
      expect(h.postTargets, [10002, 10003]);
      await h.finish(tester);
    },
  );

  testWidgets(
    'late A success cannot animate B or ABA; a new matching GET may confirm A once',
    (tester) async {
      final h = (await tester.runAsync(FeedbackHarness.start))!;
      addTearDown(h.close);
      h.postGate = Completer<void>();
      await h.mount(tester);
      await tester.tap(find.text('赠送 · 10'));
      await h.io(tester, () => h.postTargets.isNotEmpty, requireQuiet: false);
      await h.login(20001);
      await tester.pump();
      expect(find.byKey(_feedbackKey), findsNothing);
      expect(find.text('本次逐人结算'), findsNothing);
      await h.login(10001);
      h.postGate!.complete();
      await h.io(tester, () => h.activeRequests == 0);
      expect(find.byKey(_feedbackKey), findsNothing);
      expect(h.dependencies.giftSendCoordinator.plan!.succeeded, 0);
      await h.recover(tester);
      expect(feedbackText('送给 Alice'), findsOneWidget);
      await h.login(20001);
      await tester.pump();
      expect(find.byKey(_feedbackKey), findsNothing);
      await h.login(10001);
      await h.mount(tester);
      await h.recover(tester);
      expect(find.byKey(_feedbackKey), findsNothing);
      expect(h.postTargets, [10002]);
      expect(h.legacyCalls, 0);
      await h.finish(tester);
    },
  );

  testWidgets(
    'same transferId produces one presentation even across commands',
    (tester) async {
      final h = (await tester.runAsync(FeedbackHarness.start))!;
      addTearDown(h.close);
      h.sameTransfer = true;
      await h.mount(tester);
      await tester.tap(find.text('Bob'));
      await tester.pump();
      await tester.tap(find.text('赠送 · 20'));
      await h.io(tester, () => h.planDone);
      expect(feedbackText('送给 Alice'), findsOneWidget);
      expect(h.dependencies.giftSendCoordinator.plan!.succeeded, 2);
      await tester.pump(const Duration(seconds: 4));
      expect(find.byKey(_feedbackKey), findsNothing);
      expect(h.postTargets, [10002, 10003]);
      await h.finish(tester);
    },
  );
}

Finder feedbackText(String value) => find.descendant(
  of: find.byKey(_feedbackKey),
  matching: find.textContaining(value),
);

class FeedbackHarness {
  FeedbackHarness(this.server);
  final HttpServer server;
  final transport = _RealHttpOverrides();
  late final AppDependencies dependencies;
  late final RoomController controller;
  final postTargets = <int>[];
  final keys = <String>[];
  final receipts = <String, Map<String, Object?>>{};
  int legacyCalls = 0;
  int activeRequests = 0;
  bool closed = false;
  String visibleRoom = _roomId;
  final targets = [
    const GiftTarget(userId: 10002, name: 'Alice'),
    const GiftTarget(userId: 10003, name: 'Bob'),
  ];
  final postCodes = <int, int>{};
  bool receiptsVisible = true, wrongReceipt = false, sameTransfer = false;
  Completer<void>? postGate;
  int gets = 0;
  bool get planDone =>
      dependencies.giftSendCoordinator.plan != null &&
      !dependencies.giftSendCoordinator.busy;

  static Future<FeedbackHarness> start() async {
    final h = FeedbackHarness(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    h.server.listen(h.reply);
    // Actual App graph and HTTP transport, not a Mock gift repository or
    // Flutter's default widget-test HttpClient (which responds with 400).
    h.dependencies = HttpOverrides.runWithHttpOverrides(
      () => AppDependencies.forTestEnvironment(
        environment: AppEnvironment(
          backendMode: BackendMode.live,
          apiBaseUrl: 'http://127.0.0.1:${h.server.port}',
          clientType: 'Android',
          clientInnerVersion: '6',
          oauthClientId: 'contract-test',
          realtimeEndpoint: '',
          deploymentEnvironment: DeploymentEnvironment.development,
          allowInsecureHttp: true,
        ),
      ),
      h.transport,
    );
    await h.login(10001);
    await h.dependencies.commerceRepository.fetchWalletSummary();
    h.controller = h.dependencies.createRoomController(
      roomId: _roomId,
      title: 'Gift feedback contract',
    );
    // The test begins after admission; do not involve RTC, IM or room JOIN.
    final binding =
        (h.dependencies.roomRepository as BackendRoomRepository).leaseBinding;
    binding.bind(
      binding.beginEntry('gift-feedback-fixture'),
      _roomId,
      10001,
      parseRoomLease(roomLeaseWireFixture(), sessionId: roomLeaseSessionId),
    );
    return h;
  }

  Future<void> login(int actor) => dependencies.sessionManager.save(
    AuthSession(
      accessToken: 'contract-test-$actor',
      tokenType: 'Bearer',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
      userId: actor,
      mobile: '',
      roles: 'ROLE_USER',
    ),
  );

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: dependencies,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 390,
              height: 580,
              child: GiftSheet(
                roomId: visibleRoom,
                coordinator: controller.giftSendCoordinator,
                balance: null,
                account: '',
                targets: targets,
                canSendTo: (_) => true,
                onSend: (_) async {
                  legacyCalls++;
                  throw StateError('Feedback must never call legacy send');
                },
                onRechargeReturn: () async => null,
              ),
            ),
          ),
        ),
      ),
    );
    await io(
      tester,
      () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
    );
  }

  Future<void> io(
    WidgetTester tester,
    bool Function() done, {
    bool requireQuiet = true,
  }) async {
    var quiet = 0;
    for (var i = 0; i < 100; i++) {
      await tester.pump(const Duration(milliseconds: 1));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
      quiet = done() && (!requireQuiet || activeRequests == 0) ? quiet + 1 : 0;
      if (quiet == 5) return;
    }
    fail(
      'HTTP/UI condition did not finish: posts=$postTargets, '
      'plan=${dependencies.giftSendCoordinator.plan}, '
      'error=${dependencies.giftSendCoordinator.error}, '
      'texts=${tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).toList()}',
    );
  }

  Future<void> recover(WidgetTester tester) async {
    final work = dependencies.giftSendCoordinator.recover(canSend: (_) => true);
    await io(tester, () => !dependencies.giftSendCoordinator.busy);
    await work;
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(close);
    await tester.pump();
  }

  Future<void> reply(HttpRequest request) async {
    activeRequests++;
    final raw = await utf8.decoder.bind(request).join();
    Object? data;
    var code = 200;
    switch (request.uri.path) {
      case '/app-room-api/room/com/v1/sendGift':
        final body = jsonDecode(raw) as Map<String, dynamic>;
        final key = request.headers.value('X-Request-Id')!;
        postTargets.add(body['receiverUserId'] as int);
        keys.add(key);
        code = postCodes[body['receiverUserId']] ?? 200;
        data = receipts[key] = {
          ...body,
          'senderUserId': 10001,
          'giftName': 'Rose',
          'transferId': sameTransfer ? 'transfer-shared' : 'transfer-$key',
          'requestId': key,
          'status': 'SUCCEEDED',
          'providerInvocation': false,
          'deliveryMode': 'FIRST_PARTY_LEDGER_COMMITTED',
          'coinPrecision': _coins,
          'reconciled': true,
        };
        await postGate?.future;
      case '/app-room-api/room/com/v1/giftReceipt':
        gets++;
        final receipt = receipts[request.uri.queryParameters['requestId']];
        data = !receiptsVisible || receipt == null
            ? null
            : {...receipt, if (wrongReceipt) 'receiverUserId': 999};
        if (data == null) code = 404;
      case '/app-economy-api/ncoin':
        data = _coins;
      case '/app-mini-api/mini/v1/wallet/overview':
        data = {
          'incomeRole': 'ORDINARY',
          'incomeEligible': false,
          'canWithdraw': false,
          'balance': 0,
          'frozenBalance': 0,
          'totalEarnings': 0,
          'yesterdayEarnings': 0,
          'totalWithdraw': 0,
          'isRealName': false,
          'agentEarnings': null,
          'agentEarningsStatus': 'UNAVAILABLE',
          'superAgentEarnings': null,
          'superAgentEarningsStatus': 'UNAVAILABLE',
        };
      default:
        data = {
          'providerInvocation': false,
          'retiredCategoriesPresent': false,
          'deliveryMode': 'HTTP_STATE_ONLY',
          'total': 1,
          'list': [
            {
              'giftId': _giftId,
              'giftName': 'Rose',
              'unitCostGiftCoin': 10,
              'price': 10,
              'category': 'POPULAR',
            },
          ],
        };
    }
    request.response.headers.contentType = ContentType.json;
    request.response.statusCode = code;
    request.response.write(
      jsonEncode({'code': code, 'message': 'fixture', 'data': data}),
    );
    await request.response.close();
    activeRequests--;
  }

  Future<void> close() async {
    if (closed) return;
    closed = true;
    controller.dispose();
    dependencies.dispose();
    for (final client in transport.clients) {
      client.close(force: true);
    }
    await server.close(force: true);
  }
}

const _coins = {
  'currency': 'GIFT_COIN',
  'precisionVersion': 'GIFT_COIN_TENTHS_V1',
  'scale': 10,
  'availableTenths': '9991',
  'frozenTenths': '0',
};

class _RealHttpOverrides extends HttpOverrides {
  final clients = <HttpClient>[];
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    clients.add(client);
    return client;
  }
}
