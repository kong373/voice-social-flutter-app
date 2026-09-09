import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/room/data/backend_room_repository.dart';
import 'package:voice_social_app/features/room/domain/gift_send_models.dart';
import 'room_lease_contract_fixture.dart';

const giftId = '550e8400-e29b-41d4-a716-446655440000';
void main() {
  test(
    'real HTTP uses immutable per-recipient key/full body; changed target rejected; expired lease GET works',
    () async {
      final h = await Harness.start();
      addTearDown(h.close);
      final command = h.command();
      h.failPost = true;
      await expectLater(
        h.repo.sendGiftCommand(command, requireIdentity: () {}),
        throwsA(isA<ApiException>()),
      );
      h.failPost = false;
      await h.repo.sendGiftCommand(command, requireIdentity: () {});
      expect(h.bodies, [command.encodedBody, command.encodedBody]);
      expect(h.keys, [command.requestId, command.requestId]);
      expect(jsonDecode(h.bodies.first), {
        'roomId': '9527',
        'sessionId': roomLeaseSessionId,
        'giftId': giftId,
        'receiverUserId': 10002,
        'quantity': 10,
        'source': 'WALLET',
      });
      final other = h.command(receiver: 10003);
      await expectLater(
        h.repo.sendGiftCommand(other, requireIdentity: () {}),
        throwsA(isA<ApiException>()),
      );
      expect(h.bodies, hasLength(2));
      h.repo.leaseBinding.clear(h.repo.leaseBinding.generation);
      final receipt = await h.repo.queryGiftCommand(command);
      expect(receipt.receiverUserId, 10002);
      expect(h.gets, 1);
      await expectLater(
        h.repo.sendGiftCommand(command, requireIdentity: () {}),
        throwsA(isA<ApiException>()),
      );
      expect(h.bodies, hasLength(2));
    },
  );

  for (final field in [
    'roomId',
    'senderUserId',
    'receiverUserId',
    'giftId',
    'quantity',
    'requestId',
    'source',
    'reconciled',
  ]) {
    test('recovery rejects mismatched $field', () async {
      final h = await Harness.start();
      addTearDown(h.close);
      h.patch = {
        field: switch (field) {
          'senderUserId' || 'receiverUserId' => 999,
          'quantity' => 11,
          'reconciled' => false,
          'giftId' => '660e8400-e29b-41d4-a716-446655440000',
          _ => 'wrong',
        },
      };
      await expectLater(
        h.repo.queryGiftCommand(h.command()),
        throwsA(isA<ApiException>()),
      );
      expect(h.bodies, isEmpty);
    });
  }

  for (final scenario in [
    'open-switch',
    '401-switch',
    'refresh-same',
    'mic-leaves',
  ]) {
    test(
      'real changing Authorization and delayed transport: $scenario',
      () async {
        final h = await Harness.start(
          delay: scenario == 'open-switch' || scenario == 'mic-leaves',
        );
        addTearDown(h.close);
        var identity = 1;
        var onMic = true;
        h.firstUnauthorized =
            scenario == '401-switch' || scenario == 'refresh-same';
        h.onRequest = () {
          if (scenario == '401-switch') {
            identity = 2;
            h.token = 'Bearer B';
          }
        };
        h.api.setUnauthorizedRecovery(() async {
          h.token = 'Bearer A-refreshed';
          return true;
        });
        final result = h.repo
            .sendGiftCommand(
              h.command(),
              requireIdentity: () {
                if (identity != 1 || !onMic)
                  throw const ApiException(
                    kind: ApiFailureKind.conflict,
                    message: 'stale',
                  );
              },
            )
            .then<Object>((r) => r, onError: (Object error) => error);
        if (h.transport.delay) {
          await h.transport.entered.future;
          if (scenario == 'open-switch') {
            identity = 2;
            h.token = 'Bearer B';
          } else {
            onMic = false;
          }
          h.transport.release.complete();
        }
        final outcome = await result;
        if (scenario == 'refresh-same') {
          expect(outcome, isNot(isA<ApiException>()));
          expect(h.tokens, ['Bearer A', 'Bearer A-refreshed']);
          expect(h.bodies[0], h.bodies[1]);
          expect(h.keys[0], h.keys[1]);
        } else {
          expect(outcome, isA<ApiException>());
          expect(h.tokens, scenario == '401-switch' ? ['Bearer A'] : isEmpty);
        }
      },
    );
  }
}

class Harness {
  Harness(this.server, this.transport) {
    api = ApiClient(
      baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
      clientType: 'test',
      clientInnerVersion: '1',
      authorizationProvider: () => token,
      httpClient: transport,
    );
    repo = BackendRoomRepository(
      apiClient: api,
      leaseBinding: admittedRoomFixture(),
    );
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      final post = request.method == 'POST';
      if (post) {
        bodies.add(body);
        keys.add(request.headers.value('X-Request-Id'));
        tokens.add(request.headers.value(HttpHeaders.authorizationHeader));
        onRequest?.call();
      } else {
        gets++;
      }
      final unauthorized = post && firstUnauthorized && bodies.length == 1;
      request.response.statusCode = unauthorized
          ? 401
          : post && failPost
          ? 500
          : 200;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'code': request.response.statusCode,
          'message': 'fixture',
          'data': {
            'transferId': 'transfer-1',
            'roomId': '9527',
            'senderUserId': 10001,
            'receiverUserId': 10002,
            'giftId': giftId,
            'giftName': 'Rose',
            'quantity': 10,
            'source': 'WALLET',
            'deliveryMode': 'FIRST_PARTY_LEDGER_COMMITTED',
            'providerInvocation': false,
            'status': 'SUCCEEDED',
            'requestId': 'gift-original',
            'reconciled': true,
            'coinPrecision': {
              'currency': 'GIFT_COIN',
              'precisionVersion': 'GIFT_COIN_TENTHS_V1',
              'scale': 10,
              'availableTenths': '5',
              'frozenTenths': '0',
            },
            ...patch,
          },
        }),
      );
      await request.response.close();
    });
  }
  final HttpServer server;
  final DelayedClient transport;
  late final ApiClient api;
  late final BackendRoomRepository repo;
  String token = 'Bearer A';
  bool failPost = false, firstUnauthorized = false;
  Map<String, Object?> patch = {};
  void Function()? onRequest;
  final bodies = <String>[];
  final keys = <String?>[];
  final tokens = <String?>[];
  int gets = 0;
  GiftSendCommand command({int receiver = 10002}) => repo.freezeGift(
    actorId: 10001,
    roomId: '9527',
    giftId: giftId,
    receiverUserId: receiver,
    quantity: 10,
    requestId: 'gift-original',
  );
  static Future<Harness> start({bool delay = false}) async => Harness(
    await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    DelayedClient(delay),
  );
  Future<void> close() async {
    transport.close(force: true);
    await server.close(force: true);
  }
}

class DelayedClient implements HttpClient {
  DelayedClient(this.delay);
  final bool delay;
  final delegate = HttpClient();
  final entered = Completer<void>(), release = Completer<void>();
  int calls = 0;
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    if (++calls == 1 && delay) {
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
