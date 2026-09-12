import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/features/commerce/data/backend_commerce_repository.dart';
import 'package:voice_social_app/features/commerce/domain/commerce_models.dart';
import 'package:voice_social_app/features/commerce/presentation/commerce_pages.dart';

import 'support/media_http_fakes.dart';

const _number = 'synthetic-order-1';
const _post = '/app-economy-api/pay/ali/order/reconcile';
const _get = '/app-economy-api/pay/isOrderSuccess';
const _button = '刷新并补单核验';

void main() {
  testWidgets('entering order detail and ordinary status GET stay DB-only', (
    tester,
  ) async {
    final f = _Fixture();
    await _mount(tester, f);
    expect(f.http.requests, isEmpty);
    await tester.runAsync(() => f.repository.queryOrderStatus(_order()));
    expect(f.routes, ['GET $_get']);
  });

  testWidgets(
    'explicit Alipay recovery POSTs then displays strict GET authority',
    (tester) async {
      final f = _Fixture();
      await _mount(tester, f);
      await _tap(tester);
      expect(f.routes, ['POST $_post', 'GET $_get']);
      expect(find.text('支付成功'), findsOneWidget);
      final request = f.http.requests.first;
      expect(request.uri.queryParameters, {'orderNo': _number});
      expect(request.body, isEmpty);
      expect(request.headers.value('Authorization'), f.actor.token);
      final stableKey =
          'alipay-rec-${sha256.convert(utf8.encode('voice-social:alipay-reconcile:$_number'))}';
      expect(request.headers.value('X-Request-Id'), stableKey);
      await _tap(tester);
      expect(f.routes, [
        'POST $_post',
        'GET $_get',
        'POST $_post',
        'GET $_get',
      ]);
      expect(f.http.requests[2].headers.value('X-Request-Id'), stableKey);
    },
  );

  for (final postFails in [false, true]) {
    testWidgets(
      'POST failure=$postFails cannot override confirming DB authority',
      (tester) async {
        final f = _Fixture(
          respond: (r) {
            if (r.method == 'POST' && postFails) {
              return MediaFakeResponse.json(null, status: 503, code: 50300);
            }
            return _response(
              status: r.method == 'POST' ? 'SUCCEEDED' : 'CONFIRMING',
            );
          },
        );
        await _mount(tester, f);
        await _tap(tester);
        expect(f.routes, ['POST $_post', 'GET $_get']);
        expect(f.http.requests.last.uri.queryParameters, {'orderNo': _number});
        expect(find.text('服务端确认中'), findsOneWidget);
        expect(find.text('支付成功'), findsNothing);
        expect(find.text('支付失败'), findsNothing);
      },
    );
  }

  testWidgets('failed POST still accepts a successful authoritative GET', (
    tester,
  ) async {
    final f = _Fixture(
      respond: (r) => r.method == 'POST'
          ? MediaFakeResponse.json(null, status: 503, code: 50300)
          : _response(),
    );
    await _mount(tester, f);
    await _tap(tester);
    expect(f.routes, ['POST $_post', 'GET $_get']);
    expect(find.text('支付成功'), findsOneWidget);
  });

  for (final invalid in [
    'other-order',
    'string-bool',
    'contradictory-bool',
    'unknown-status',
  ]) {
    testWidgets('malformed GET $invalid never displays payment success', (
      tester,
    ) async {
      final f = _Fixture(
        respond: (r) {
          if (r.method == 'POST') return _response();
          final data = _data();
          switch (invalid) {
            case 'other-order':
              data['orderNo'] = 'other-order';
            case 'string-bool':
              data['bool'] = 'true';
            case 'contradictory-bool':
              data['bool'] = false;
            case 'unknown-status':
              data['status'] = 'MADE_UP';
          }
          return MediaFakeResponse.json(data);
        },
      );
      await _mount(tester, f);
      await _tap(tester);
      expect(f.routes, ['POST $_post', 'GET $_get']);
      expect(find.text('服务端确认中'), findsOneWidget);
      expect(find.text('支付成功'), findsNothing);
    });
  }

  for (final channel in ['APPLE_IAP', 'WECHAT', 'ALIPAY_LOOKALIKE']) {
    testWidgets('$channel keeps original GET-only button behavior', (
      tester,
    ) async {
      final f = _Fixture(respond: (_) => _response(channel: channel));
      await _mount(tester, f, channel: channel);
      await _tap(tester);
      expect(f.routes, ['GET $_get']);
      expect(find.text('支付成功'), findsOneWidget);
    });
  }

  for (final sameUser in [false, true]) {
    testWidgets('old page cannot submit after logout; relogin=$sameUser', (
      tester,
    ) async {
      final f = _Fixture();
      await _mount(tester, f);
      f.actor.change(0);
      if (sameUser) f.actor.change(1);
      await tester.pumpAndSettle();
      if (find.text(_button).evaluate().isNotEmpty) await _tap(tester);
      expect(f.http.requests, isEmpty);
      expect(find.text('支付成功'), findsNothing);
    });
  }

  testWidgets(
    'pending connection ABA sends neither headers nor business request',
    (tester) async {
      final f = _Fixture();
      final entered = Completer<void>();
      final release = Completer<void>();
      f.http.beforeOpen = (_) {
        entered.complete();
        return release.future;
      };
      await _mount(tester, f);
      await _start(tester);
      await tester.pump();
      expect(entered.isCompleted, true);
      f.actor.change(0);
      f.actor.change(1);
      release.complete();
      await _drain(tester);
      await tester.pumpAndSettle();
      expect(f.http.requests, hasLength(1));
      expect(f.http.requests.single.aborted, true);
      expect(f.http.requests.single.closes, 0);
      expect(f.http.requests.single.headers.value('Authorization'), isNull);
      expect(find.text('支付成功'), findsNothing);
    },
  );

  for (final delayedMethod in ['POST', 'GET']) {
    testWidgets(
      'late $delayedMethod after same-user relogin cannot refill old page',
      (tester) async {
        final entered = Completer<void>();
        final release = Completer<HttpClientResponse>();
        final f = _Fixture(
          respond: (r) {
            if (r.method == delayedMethod) {
              entered.complete();
              return release.future;
            }
            return _response();
          },
        );
        await _mount(tester, f);
        await _start(tester);
        await tester.pump();
        // Baseline has no POST. Do not wait forever for the missing operation.
        expect(entered.isCompleted, true);
        f.actor.change(0);
        f.actor.change(1);
        release.complete(_response());
        await _drain(tester);
        await tester.pumpAndSettle();
        expect(
          f.routes,
          delayedMethod == 'POST'
              ? ['POST $_post']
              : ['POST $_post', 'GET $_get'],
        );
        expect(find.text('支付成功'), findsNothing);
        expect(find.text(_number), findsNothing);
      },
    );
  }

  for (final switchIdentity in [false, true]) {
    testWidgets(
      '401 refresh switch=$switchIdentity preserves initiating identity',
      (tester) async {
        var posts = 0;
        late final _Fixture f;
        f = _Fixture(
          respond: (r) {
            if (r.method == 'POST' && ++posts == 1) {
              return MediaFakeResponse.json(null, status: 401, code: 401);
            }
            return _response();
          },
          refresh: () async {
            if (switchIdentity) {
              f.actor.change(0);
              f.actor.change(1);
            } else {
              f.actor.refreshToken();
            }
            return true;
          },
        );
        await _mount(tester, f);
        await _tap(tester);
        expect(
          f.routes,
          switchIdentity
              ? ['POST $_post']
              : ['POST $_post', 'POST $_post', 'GET $_get'],
        );
        if (switchIdentity) {
          expect(find.text('支付成功'), findsNothing);
        } else {
          expect(find.text('支付成功'), findsOneWidget);
          expect(
            f.http.requests[0].headers.value('X-Request-Id'),
            f.http.requests[1].headers.value('X-Request-Id'),
          );
          expect(
            f.http.requests[0].headers.value('Authorization'),
            'Bearer contract-A-old',
          );
          expect(
            f.http.requests[1].headers.value('Authorization'),
            'Bearer contract-refreshed',
          );
        }
      },
    );
  }

  testWidgets(
    'disposed page ignores late DB success without additional requests',
    (tester) async {
      final release = Completer<HttpClientResponse>();
      final f = _Fixture(
        respond: (r) => r.method == 'GET' ? release.future : _response(),
      );
      await _mount(tester, f);
      await _start(tester);
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      release.complete(_response());
      await _drain(tester);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(f.routes, ['POST $_post', 'GET $_get']);
    },
  );
}

PaymentOrder _order({String channel = 'ALIPAY'}) => PaymentOrder(
  orderNo: _number,
  amount: .01,
  giftCoinAmount: 60,
  channelName: channel,
  createdAt: DateTime.utc(2026, 9, 12),
  status: PaymentOrderStatus.confirming,
  currency: LedgerCurrency.cashCny,
);

Map<String, Object?> _data({
  String status = 'SUCCEEDED',
  String channel = 'ALIPAY',
}) => {
  'orderNo': _number,
  'amount': .01,
  'ncoin': 60,
  'payType': channel,
  'createDate': '2026-09-12T00:00:00Z',
  'status': status,
  'bool': status == 'SUCCEEDED',
  'providerInvocation': false,
};
MediaFakeResponse _response({
  String status = 'SUCCEEDED',
  String channel = 'ALIPAY',
}) => MediaFakeResponse.json(_data(status: status, channel: channel));

class _Fixture {
  _Fixture({
    FutureOr<HttpClientResponse> Function(MediaFakeRequest)? respond,
    Future<bool> Function()? refresh,
  }) {
    http = MediaFakeHttp(respond ?? (_) => _response());
    repository = BackendCommerceRepository(
      apiClient: http.api(actor, refresh: refresh),
      currentUserId: () => actor.user == 0 ? null : actor.user.toString(),
      identityGeneration: () => actor.generation,
      withdrawalIdentityChanges: actor,
    );
    addTearDown(actor.dispose);
  }
  final actor = TestMediaIdentity();
  late final MediaFakeHttp http;
  late final BackendCommerceRepository repository;
  List<String> get routes => http.requests
      .where((r) => r.closes > 0)
      .map((r) => '${r.method} ${r.uri.path}')
      .toList();
}

Future<void> _mount(
  WidgetTester tester,
  _Fixture f, {
  String channel = 'ALIPAY',
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: OrderDetailPage(
        order: _order(channel: channel),
        repository: f.repository,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester) async {
  await tester.ensureVisible(find.text(_button));
  await _start(tester);
  await tester.pumpAndSettle();
}

Future<void> _start(WidgetTester tester) async {
  await tester.runAsync(() async {
    await tester.tap(find.text(_button));
    await Future<void>.delayed(Duration.zero);
  });
}

Future<void> _drain(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
}
