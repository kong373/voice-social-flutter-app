import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/features/commerce/catalog/data/backend_commerce_catalog_repository.dart';
import 'package:voice_social_app/features/commerce/catalog/data/mock_commerce_catalog_repository.dart';
import 'package:voice_social_app/features/commerce/catalog/domain/commerce_catalog_models.dart';

import 'support/media_http_fakes.dart';

const decorationId = '00000000-0000-0000-0000-000000004001';
Map<String, Object?> decorationRow() => {
  'decorationId': decorationId,
  'name': '星环头像框',
  'type': 'AVATAR_FRAME',
  'giftCoinCost': 520,
  'durationDays': 7,
  'assetKey': 'decoration/star-ring-frame',
  'owned': true,
  'equipped': true,
  'expiresAt': '2026-10-20T10:00:00Z',
};
Map<String, Object?> decorationCatalog(Map<String, Object?> row) => {
  'list': [row],
  'total': 1,
  'providerInvocation': false,
};

void main() {
  test(
    'owned-list second GET rejects pending-open ABA before credentials',
    () async {
      final fixture = _Fixture(
        (_) => MediaFakeResponse.json(decorationCatalog(decorationRow())),
      );
      final opened = Completer<void>();
      final release = Completer<void>();
      fixture.http.beforeOpen = (index) async {
        if (index == 2) {
          opened.complete();
          await release.future;
        }
      };
      final result = expectLater(
        fixture.repository.fetchDecorations(),
        _unauthorized,
      );
      await opened.future;
      fixture.actor.change(2);
      fixture.actor.change(1);
      release.complete();
      await result;
      final request = fixture.http.requests.last;
      expect(request.uri.path, '/app-api/user/userDecorations/getList');
      expect(request.aborted, true);
      expect(request.headers.value('Authorization'), isNull);
      expect(request.closes, 0);
    },
  );

  test(
    'sale catalog and owned history merge without hiding unowned or permanent items',
    () async {
      const freshId = '00000000-0000-0000-0000-000000004002';
      const legacyId = '00000000-0000-0000-0000-000000004003';
      const retiredId = '00000000-0000-0000-0000-000000004004';
      final fixture = _Fixture(
        (request) => MediaFakeResponse.json({
          'list': request.uri.path.endsWith('/mall/index')
              ? [
                  {...decorationRow(), 'equipped': false},
                  {
                    ...decorationRow(),
                    'decorationId': freshId,
                    'owned': false,
                    'equipped': false,
                    'expiresAt': null,
                  },
                ]
              : [
                  decorationRow(),
                  {
                    ...decorationRow(),
                    'decorationId': legacyId,
                    'durationDays': 0,
                    'expiresAt': null,
                  },
                  {...decorationRow(), 'decorationId': retiredId},
                ],
          'total': request.uri.path.endsWith('/mall/index') ? 2 : 3,
          'providerInvocation': false,
        }),
      );
      final items = await fixture.repository.fetchDecorations();
      expect(items.map((e) => e.id), [
        decorationId,
        freshId,
        legacyId,
        retiredId,
      ]);
      expect(
        items.first.equipped,
        true,
        reason: 'The subsequent owned read is authority.',
      );
      expect(items[1].owned, false);
      expect(items[1].canPurchase, true);
      expect(items[2].permanent, true);
      expect(items[2].canPurchase, false);
      expect(items[3].owned, true);
      expect(
        items[3].canPurchase,
        false,
        reason: 'Retired finite history is not a sale listing.',
      );
      expect(fixture.http.requests.map((r) => r.uri.path), [
        '/app-api/mall/index',
        '/app-api/user/userDecorations/getList',
      ]);
    },
  );

  test(
    'accepted purchase followed by denied authority read retains original key',
    () async {
      var reads = 0;
      final fixture = _Fixture((request) {
        if (request.method == 'POST') {
          return MediaFakeResponse.json({
            'decorationId': decorationId,
            'owned': true,
          });
        }
        if (++reads == 1) {
          return MediaFakeResponse.json({
            'code': 40301,
            'message': 'Forbidden',
          }, status: 403);
        }
        return MediaFakeResponse.json(decorationCatalog(decorationRow()));
      });
      await expectLater(
        fixture.repository.purchaseDecoration(decorationId),
        throwsA(isA<ApiException>()),
      );
      await fixture.repository.purchaseDecoration(decorationId);
      final writes = fixture.http.requests
          .where((r) => r.method == 'POST')
          .toList();
      expect(writes, hasLength(2));
      expect(
        writes[1].headers.value('X-Request-Id'),
        writes[0].headers.value('X-Request-Id'),
        reason: 'A denied read cannot undo the accepted monetary write.',
      );
    },
  );

  test(
    'malformed renewal receipt is unknown and cannot rotate the original purchase key',
    () async {
      var posts = 0;
      final fixture = _Fixture((request) {
        if (request.method == 'POST') {
          posts++;
          return MediaFakeResponse.json({
            'decorationId': posts == 1 ? 'wrong-id' : decorationId,
            'owned': true,
          });
        }
        return MediaFakeResponse.json(decorationCatalog(decorationRow()));
      });
      await expectLater(
        fixture.repository.purchaseDecoration(decorationId),
        throwsA(
          isA<ApiException>().having(
            (e) => e.kind,
            'kind',
            ApiFailureKind.protocol,
          ),
        ),
      );
      expect(
        fixture.http.requests,
        hasLength(1),
        reason: 'An already-owned item is not proof of the failed receipt.',
      );
      await fixture.repository.purchaseDecoration(decorationId);
      final writes = fixture.http.requests
          .where((r) => r.method == 'POST')
          .toList();
      expect(
        writes[0].headers.value('X-Request-Id'),
        writes[1].headers.value('X-Request-Id'),
      );
    },
  );

  test(
    'old permanent ownership stays nonrenewable even if the catalog now sells a finite term',
    () async {
      final fixture = _Fixture(
        (_) => MediaFakeResponse.json(
          decorationCatalog({...decorationRow(), 'expiresAt': null}),
        ),
      );
      final item = (await fixture.repository.fetchDecorations()).single;
      expect(item.durationDays, 7);
      expect(item.permanent, true);
      expect(item.canPurchase, false);
    },
  );
  for (final offset in [-10, 10]) {
    test(
      'mock renewal extends max(now, expiry) and preserves equipment for offset $offset',
      () async {
        final now = DateTime.utc(2030);
        final before = now.add(Duration(days: offset));
        final item = DecorationItem(
          id: 'x',
          name: 'x',
          kind: DecorationKind.avatarFrame,
          priceGiftCoins: 10,
          durationDays: 7,
          owned: offset > 0,
          equipped: offset > 0,
          expiresAt: before,
        );
        final repository = MockCommerceCatalogRepository(
          now: () => now,
          decorations: [item],
        );
        final renewed = await repository.purchaseDecoration('x');
        expect(
          renewed.expiresAt,
          (offset > 0 ? before : now).add(const Duration(days: 7)),
        );
        expect(renewed.durationDays, 7);
        expect(renewed.equipped, item.equipped);
        final again = await repository.purchaseDecoration('x');
        expect(
          again.expiresAt,
          renewed.expiresAt!.add(const Duration(days: 7)),
        );
      },
    );
  }
  test(
    'mock permanent cannot be purchased and finite same-type equipment stays exclusive',
    () async {
      final items = [
        for (final (id, days, equipped) in [
          ('a', 7, true),
          ('b', 7, false),
          ('legacy', 0, false),
        ])
          DecorationItem(
            id: id,
            name: id,
            kind: DecorationKind.avatarFrame,
            priceGiftCoins: 10,
            durationDays: days,
            owned: true,
            equipped: equipped,
          ),
      ];
      final repository = MockCommerceCatalogRepository(decorations: items);
      await expectLater(
        repository.purchaseDecoration('legacy'),
        throwsA(isA<ApiException>()),
      );
      await repository.setDecorationEquipped(decorationId: 'b', equipped: true);
      expect(
        (await repository.fetchDecorations())
            .where((e) => e.equipped)
            .map((e) => e.id),
        ['b'],
      );
    },
  );

  test(
    'live term and permanent zero come from the catalog unchanged',
    () async {
      for (final days in [7, 0]) {
        final fixture = _Fixture(
          (_) => MediaFakeResponse.json(
            decorationCatalog({...decorationRow(), 'durationDays': days}),
          ),
        );
        final item = (await fixture.repository.fetchDecorations()).single;
        expect(item.durationDays, days);
        expect(item.copyWith(equipped: false).durationDays, days);
        expect(item.canPurchase, days > 0);
      }
    },
  );

  test(
    'unknown renewal of pre-owned item does not fake success; retry retains original key',
    () async {
      var posts = 0;
      final fixture = _Fixture((request) {
        if (request.method == 'POST' && ++posts == 1)
          throw const SocketException('unknown');
        return MediaFakeResponse.json(
          request.method == 'POST'
              ? {'decorationId': decorationId, 'owned': true, 'equipped': true}
              : decorationCatalog(decorationRow()),
        );
      });
      await expectLater(
        fixture.repository.purchaseDecoration(decorationId),
        throwsA(
          isA<ApiException>().having(
            (e) => e.kind,
            'kind',
            ApiFailureKind.network,
          ),
        ),
      );
      fixture.actor.refreshToken();
      final result = await fixture.repository.purchaseDecoration(decorationId);
      final writes = fixture.http.requests
          .where((r) => r.method == 'POST')
          .toList();
      expect(writes, hasLength(2));
      expect(
        writes[0].headers.value('X-Request-Id'),
        writes[1].headers.value('X-Request-Id'),
      );
      expect(jsonDecode(utf8.decode(writes[1].body)), {
        'decorationId': decorationId,
      });
      expect(result.equipped, true);
      expect(result.expiresAt, DateTime.parse('2026-10-20T10:00:00Z'));
      expect(result.durationDays, 7);
    },
  );

  test(
    'successful renewal followed by a new deliberate renewal rotates its key',
    () async {
      final fixture = _Fixture(
        (request) => MediaFakeResponse.json(
          request.method == 'POST'
              ? {'decorationId': decorationId, 'owned': true, 'equipped': true}
              : decorationCatalog(decorationRow()),
        ),
      );
      await fixture.repository.purchaseDecoration(decorationId);
      await fixture.repository.purchaseDecoration(decorationId);
      final keys = fixture.http.requests
          .where((r) => r.method == 'POST')
          .map((r) => r.headers.value('X-Request-Id'))
          .toList();
      expect(keys, hasLength(2));
      expect(keys[0], isNot(keys[1]));
    },
  );

  test(
    'account ABA cannot share a flight or execute an old queued equip',
    () async {
      final gate = Completer<HttpClientResponse>();
      final started = Completer<void>();
      var posts = 0;
      final fixture = _Fixture((request) {
        if (request.method == 'POST') {
          if (++posts == 1) {
            started.complete();
            return gate.future;
          }
          return MediaFakeResponse.json({
            'decorationId': decorationId,
            'owned': true,
            'equipped': true,
          });
        }
        return MediaFakeResponse.json(decorationCatalog(decorationRow()));
      });
      final first = expectLater(
        fixture.repository.purchaseDecoration(decorationId),
        _unauthorized,
      );
      await started.future;
      final queued = expectLater(
        fixture.repository.setDecorationEquipped(
          decorationId: decorationId,
          equipped: false,
        ),
        _unauthorized,
      );
      fixture.actor.change(2);
      fixture.actor.change(1);
      final next = await fixture.repository.purchaseDecoration(decorationId);
      expect(next.equipped, true);
      expect(posts, 2);
      gate.complete(
        MediaFakeResponse.json({'decorationId': decorationId, 'owned': true}),
      );
      await first;
      await queued;
      expect(posts, 2);
      final keys = fixture.http.requests
          .where((r) => r.method == 'POST')
          .map((r) => r.headers.value('X-Request-Id'))
          .toList();
      expect(keys[0], isNot(keys[1]));
    },
  );

  for (final write in [false, true]) {
    test(
      '${write ? 'POST' : 'GET'} pending open rejects ABA before sending credentials or body',
      () async {
        final fixture = _Fixture(
          (request) =>
              MediaFakeResponse.json(decorationCatalog(decorationRow())),
        );
        final opened = Completer<void>();
        final release = Completer<void>();
        fixture.http.beforeOpen = (_) {
          opened.complete();
          return release.future;
        };
        final result = expectLater(
          write
              ? fixture.repository.purchaseDecoration(decorationId)
              : fixture.repository.fetchDecorations(),
          _unauthorized,
        );
        await opened.future;
        fixture.actor.change(2);
        fixture.actor.change(1);
        release.complete();
        await result;
        expect(fixture.http.requests.single.aborted, true);
        expect(
          fixture.http.requests.single.headers.value('Authorization'),
          isNull,
        );
        expect(fixture.http.requests.single.closes, 0);
      },
    );
  }

  for (final changeActor in [false, true]) {
    test(
      '401 refresh ${changeActor ? 'ABA does not replay' : 'same identity keeps key'}',
      () async {
        var posts = 0;
        final fixture = _Fixture(
          (request) {
            if (request.method == 'POST' && ++posts == 1)
              return MediaFakeResponse.json(null, status: 401, code: 401);
            return MediaFakeResponse.json(
              request.method == 'POST'
                  ? {'decorationId': decorationId, 'owned': true}
                  : decorationCatalog(decorationRow()),
            );
          },
          refresh: (actor) async {
            if (changeActor) {
              actor.change(2);
              actor.change(1);
            } else {
              actor.refreshToken();
            }
            return true;
          },
        );
        if (changeActor) {
          await expectLater(
            fixture.repository.purchaseDecoration(decorationId),
            _unauthorized,
          );
          expect(posts, 1);
        } else {
          await fixture.repository.purchaseDecoration(decorationId);
          final writes = fixture.http.requests
              .where((r) => r.method == 'POST')
              .toList();
          expect(writes[0].body, writes[1].body);
          expect(
            writes[0].headers.value('X-Request-Id'),
            writes[1].headers.value('X-Request-Id'),
          );
        }
      },
    );
  }

  for (final error in [false, true]) {
    test(
      'catalog late ${error ? 'error' : 'success'} cannot escape its captured generation',
      () async {
        final gate = Completer<HttpClientResponse>();
        final started = Completer<void>();
        final fixture = _Fixture((_) {
          started.complete();
          return gate.future;
        });
        final result = expectLater(
          fixture.repository.fetchDecorations(),
          _unauthorized,
        );
        await started.future;
        fixture.actor.change(2);
        fixture.actor.change(1);
        if (error) {
          gate.completeError(const SocketException('old'));
        } else {
          gate.complete(
            MediaFakeResponse.json(decorationCatalog(decorationRow())),
          );
        }
        await result;
      },
    );
  }

  test('missing live identity injection fails closed without HTTP', () async {
    final actor = TestMediaIdentity();
    addTearDown(actor.dispose);
    final http = MediaFakeHttp((_) => MediaFakeResponse.json(null));
    final repository = BackendCommerceCatalogRepository(
      apiClient: http.api(actor),
      routes: const BackendRouteCatalog(),
    );
    await expectLater(
      repository.fetchDecorations(),
      throwsA(
        isA<ApiException>().having(
          (e) => e.kind,
          'kind',
          ApiFailureKind.configuration,
        ),
      ),
    );
    await expectLater(
      repository.purchaseDecoration(decorationId),
      throwsA(isA<ApiException>()),
    );
    expect(http.requests, isEmpty);
  });
  for (final entry in <String, Map<String, Object?>>{
    'missing': decorationRow()..remove('durationDays'),
    'null': {...decorationRow(), 'durationDays': null},
    'negative': {...decorationRow(), 'durationDays': -1},
    'string': {...decorationRow(), 'durationDays': '7'},
  }.entries) {
    test(
      'live duration ${entry.key} cannot silently become a 30 day product',
      () async {
        final actor = TestMediaIdentity();
        addTearDown(actor.dispose);
        final http = MediaFakeHttp(
          (_) => MediaFakeResponse.json(decorationCatalog(entry.value)),
        );
        final repository = BackendCommerceCatalogRepository(
          apiClient: http.api(actor),
          routes: const BackendRouteCatalog(),
          currentUserIdProvider: () => actor.user,
          identityGeneration: () => actor.generation,
        );
        await expectLater(
          repository.fetchDecorations(),
          throwsA(
            isA<ApiException>().having(
              (e) => e.kind,
              'kind',
              ApiFailureKind.protocol,
            ),
          ),
        );
      },
    );
  }

  test(
    'mock owned equipped decoration renews instead of refusing a repeat purchase',
    () async {
      final repository = MockCommerceCatalogRepository();
      final original = (await repository.fetchDecorations()).first;
      final renewed = await repository.purchaseDecoration(original.id);
      expect(renewed.owned, true);
      expect(renewed.equipped, true);
      expect(renewed.expiresAt, isNotNull);
    },
  );
}

final _unauthorized = throwsA(
  isA<ApiException>().having(
    (e) => e.kind,
    'kind',
    ApiFailureKind.unauthorized,
  ),
);

class _Fixture {
  _Fixture(
    FutureOr<HttpClientResponse> Function(MediaFakeRequest) handler, {
    Future<bool> Function(TestMediaIdentity)? refresh,
  }) {
    http = MediaFakeHttp(handler);
    repository = BackendCommerceCatalogRepository(
      apiClient: http.api(
        actor,
        refresh: refresh == null ? null : () => refresh(actor),
      ),
      routes: const BackendRouteCatalog(),
      currentUserIdProvider: () => actor.user,
      identityGeneration: () => actor.generation,
      decorationPurchaseRequestIdGenerator: () => 'decoration-test-${++keys}',
    );
    addTearDown(actor.dispose);
  }
  final actor = TestMediaIdentity();
  int keys = 0;
  late final MediaFakeHttp http;
  late final BackendCommerceCatalogRepository repository;
}
