import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/features/account/domain/auth_models.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/commerce/catalog/data/mock_commerce_catalog_repository.dart';
import 'package:voice_social_app/features/commerce/catalog/domain/commerce_catalog_models.dart';
import 'package:voice_social_app/features/commerce/presentation/commerce_pages.dart';

void main() {
  testWidgets(
    'unknown purchase remains retryable after the product leaves sale',
    (tester) async {
      final spy = _Spy();
      spy.purchase = (_) async {
        throw const ApiException(
          kind: ApiFailureKind.network,
          message: 'unknown',
        );
      };
      await _show(tester, spy);
      await tester.tap(find.byKey(const Key('decoration-renew-product')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(SnackBar), const Offset(0, 100));
      await tester.pumpAndSettle();
      spy.items = [
        _item().copyWith(owned: false, equipped: false, forSale: false),
      ];
      await tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh();
      await tester.pumpAndSettle();
      expect(find.text('重试原购买'), findsOneWidget);
      await tester.tap(find.text('重试原购买'));
      await tester.pumpAndSettle();
      expect(find.textContaining('7 天，将扣除 25 礼物币'), findsOneWidget);
      expect(find.textContaining('沿用原请求'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(spy.purchases, 1);
      spy.items = [];
      await tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh();
      await tester.pumpAndSettle();
      expect(find.text('重试原购买'), findsOneWidget);
      expect(find.text('购买结果待确认'), findsOneWidget);
      expect(find.text('当前穿戴'), findsNothing);
    },
  );

  testWidgets(
    'renewal confirms the real term and only uses the server expiry',
    (tester) async {
      final spy = _Spy();
      final gate = Completer<DecorationItem>();
      spy.purchase = (_) => gate.future;
      await _show(tester, spy);
      await tester.tap(find.byKey(const Key('decoration-renew-product')));
      await tester.pumpAndSettle();
      expect(find.textContaining('7 天，将扣除 25 礼物币'), findsOneWidget);
      await tester.tap(find.text('确认'));
      await tester.pump();
      expect(spy.purchases, 1);
      expect(spy.equips, 0);
      expect(find.textContaining('2042-01-01'), findsOneWidget);
      spy.items = [_item(expiresAt: DateTime.utc(2050, 8, 9))];
      gate.complete(_item(expiresAt: DateTime.utc(2049)));
      await tester.pumpAndSettle();
      expect(find.textContaining('2050-08-09'), findsOneWidget);
      expect(find.textContaining('2049-01-01'), findsNothing);
      expect(find.text('当前穿戴'), findsOneWidget);
    },
  );

  testWidgets(
    'unknown renewal exposes only original purchase retry, not another equip',
    (tester) async {
      final spy = _Spy();
      spy.purchase = (_) async {
        throw const ApiException(
          kind: ApiFailureKind.network,
          message: 'unknown',
        );
      };
      await _show(tester, spy);
      await tester.tap(find.byKey(const Key('decoration-renew-product')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();
      expect(find.text('重试原购买'), findsOneWidget);
      expect(find.text('卸下'), findsNothing);
      await tester.drag(find.byType(SnackBar), const Offset(0, 100));
      await tester.pumpAndSettle();
      await tester.tap(find.text('重试原购买'));
      await tester.pumpAndSettle();
      expect(find.textContaining('沿用原请求'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(spy.purchases, 1);
      expect(spy.equips, 0);
    },
  );

  testWidgets(
    'historical permanent retains existing wear rights but cannot buy or renew',
    (tester) async {
      final spy = _Spy()
        ..items = [
          _item(
            days: 0,
            key: 'decoration/companion-badge',
            kind: DecorationKind.profileCard,
          ),
        ];
      await _show(tester, spy);
      expect(find.text('历史永久'), findsOneWidget);
      expect(
        find.byKey(const Key('decoration-action-product')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('decoration-renew-product')), findsNothing);
      await tester.tap(find.byKey(const Key('decoration-preview-product')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byKey(
            const ValueKey('decoration-art-decoration/companion-badge'),
          ),
        ),
        findsOneWidget,
      );
      expect(spy.purchases + spy.equips, 0);
      expect(spy.reads, 1);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('decoration-action-product')));
      await tester.pumpAndSettle();
      expect(spy.equips, 1);
      expect(spy.purchases, 0);
    },
  );

  testWidgets(
    'two same-type mock products show their own assets without writing',
    (tester) async {
      final spy = _Spy()
        ..items = [
          _item(),
          _item(id: 'second', key: 'assets/runtime/avatar-silver.png'),
        ];
      await _show(tester, spy);
      for (final entry in {
        'product': 'assets/runtime/avatar-rose.png',
        'second': 'assets/runtime/avatar-silver.png',
      }.entries) {
        await tester.tap(find.byKey(Key('decoration-preview-${entry.key}')));
        await tester.pumpAndSettle();
        final image = tester.widget<Image>(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(Image),
          ),
        );
        expect((image.image as AssetImage).assetName, entry.value);
        await tester.tap(find.text('关闭'));
        await tester.pumpAndSettle();
      }
      expect(spy.purchases + spy.equips, 0);
      expect(spy.reads, 1);
    },
  );

  for (final product in <(String, DecorationKind, bool)>[
    ('decoration/star-ring-frame', DecorationKind.avatarFrame, true),
    ('decoration/stream-entry', DecorationKind.entrance, true),
    ('decoration/stream-entry', DecorationKind.avatarFrame, false),
    ('decoration/unknown', DecorationKind.avatarFrame, false),
    ('https://untrusted.test/preview.png', DecorationKind.avatarFrame, false),
  ]) {
    testWidgets(
      '${product.$1}/${product.$2} preview uses only its exact registered product without writes',
      (tester) async {
        final spy = _Spy()..items = [_item(key: product.$1, kind: product.$2)];
        await _show(tester, spy);
        await tester.tap(find.byKey(const Key('decoration-preview-product')));
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(Image),
          ),
          findsNothing,
        );
        expect(find.text('预览未配置'), product.$3 ? findsNothing : findsWidgets);
        expect(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byKey(ValueKey('decoration-art-${product.$1}')),
          ),
          product.$3 ? findsOneWidget : findsNothing,
        );
        expect(spy.purchases + spy.equips, 0);
        expect(spy.reads, 1);
      },
    );
  }

  testWidgets(
    'account ABA invalidates an already visible confirmation before a tap can write',
    (tester) async {
      final spy = _Spy();
      final dependencies = await _show(tester, spy);
      await tester.tap(find.byKey(const Key('decoration-renew-product')));
      await tester.pumpAndSettle();
      final confirm = tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '确认'))
          .onPressed!;
      await dependencies.sessionManager.save(_session(2));
      await dependencies.sessionManager.save(_session(1));
      confirm();
      await tester.pumpAndSettle();
      expect(spy.purchases + spy.equips, 0);
      expect(find.byType(AlertDialog), findsNothing);
    },
  );

  testWidgets(
    'same-account token refresh does not discard a valid confirmation',
    (tester) async {
      final spy = _Spy();
      final dependencies = await _show(tester, spy);
      await tester.tap(find.byKey(const Key('decoration-renew-product')));
      await tester.pumpAndSettle();
      await dependencies.sessionManager.save(_session(1, token: 'refreshed'));
      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();
      expect(spy.purchases, 1);
    },
  );

  for (final failure in [false, true]) {
    testWidgets(
      'late ${failure ? 'error' : 'success'} after account ABA does not mutate the new page',
      (tester) async {
        final spy = _Spy();
        final gate = Completer<DecorationItem>();
        spy.purchase = (_) => gate.future;
        final dependencies = await _show(tester, spy);
        await tester.tap(find.byKey(const Key('decoration-renew-product')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('确认'));
        await tester.pump();
        await dependencies.sessionManager.save(_session(2));
        await dependencies.sessionManager.save(_session(1));
        await tester.pumpAndSettle();
        final reads = spy.reads;
        if (failure) {
          gate.completeError(StateError('OLD-ERROR'));
        } else {
          gate.complete(_item(expiresAt: DateTime.utc(2099)));
        }
        await tester.pumpAndSettle();
        expect(spy.reads, reads);
        expect(find.textContaining('2099'), findsNothing);
        expect(find.textContaining('OLD-ERROR'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'late initial catalog ${failure ? 'error' : 'success'} cannot overwrite a new actor load',
      (tester) async {
        final spy = _Spy();
        final gate = Completer<List<DecorationItem>>();
        spy.fetch = () => spy.reads == 1
            ? gate.future
            : Future.value([_item(id: 'new-account')]);
        final dependencies = await _show(tester, spy, settle: false);
        await dependencies.sessionManager.save(_session(2));
        await tester.pumpAndSettle();
        if (failure) {
          gate.completeError(StateError('OLD-CATALOG'));
        } else {
          gate.complete([_item()]);
        }
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('decoration-renew-new-account')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('decoration-renew-product')), findsNothing);
        expect(find.textContaining('OLD-CATALOG'), findsNothing);
      },
    );
  }

  testWidgets('leaving during a write ignores its late result', (tester) async {
    final spy = _Spy();
    final gate = Completer<DecorationItem>();
    spy.purchase = (_) => gate.future;
    await _show(tester, spy);
    await tester.tap(find.byKey(const Key('decoration-renew-product')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    final reads = spy.reads;
    gate.complete(_item());
    await tester.pumpAndSettle();
    expect(spy.reads, reads);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'owned decoration exposes independent renewal with duration and coin confirmation',
    (tester) async {
      final dependencies = AppDependencies.mock();
      addTearDown(dependencies.dispose);
      await tester.pumpWidget(
        AppDependencyScope(
          dependencies: dependencies,
          child: const MaterialApp(home: DecorationPage()),
        ),
      );
      await tester.pumpAndSettle();
      final renewal = find.byKey(
        const Key('decoration-renew-decor-frame-starlight'),
      );
      expect(renewal, findsOneWidget);
      await tester.tap(renewal);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.textContaining('30 天'), findsWidgets);
      expect(find.textContaining('520 礼物币'), findsWidgets);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.text('当前穿戴'), findsOneWidget);
    },
  );

  testWidgets('decoration has a read-only preview action', (tester) async {
    final dependencies = AppDependencies.mock();
    addTearDown(dependencies.dispose);
    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: dependencies,
        child: const MaterialApp(home: DecorationPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('decoration-preview-decor-frame-starlight')),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('仅预览'), findsWidgets);
    expect(find.text('试用'), findsNothing);
  });
}

DecorationItem _item({
  String id = 'product',
  String key = 'assets/runtime/avatar-rose.png',
  DecorationKind kind = DecorationKind.avatarFrame,
  int days = 7,
  DateTime? expiresAt,
}) => DecorationItem(
  id: id,
  name: id,
  kind: kind,
  priceGiftCoins: 25,
  durationDays: days,
  owned: true,
  equipped: true,
  assetUrl: key,
  expiresAt: days == 0 ? null : expiresAt ?? DateTime.utc(2042),
);

AuthSession _session(int id, {String token = 'test'}) => AuthSession(
  accessToken: token,
  tokenType: 'Bearer',
  expiresAt: DateTime(2099),
  userId: id,
  mobile: '',
  roles: 'USER',
);

Future<AppDependencies> _show(
  WidgetTester tester,
  _Spy spy, {
  bool settle = true,
}) async {
  final dependencies = AppDependencies.mock();
  await dependencies.sessionManager.save(_session(1));
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    dependencies.dispose();
  });
  await tester.pumpWidget(
    AppDependencyScope(
      dependencies: dependencies,
      child: MaterialApp(home: DecorationPage(repository: spy)),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
  return dependencies;
}

class _Spy extends MockCommerceCatalogRepository {
  List<DecorationItem> items = [_item()];
  int reads = 0;
  int purchases = 0;
  int equips = 0;
  Future<List<DecorationItem>> Function()? fetch;
  Future<DecorationItem> Function(String)? purchase;
  @override
  Future<List<DecorationItem>> fetchDecorations() async {
    reads++;
    return fetch == null ? items : await fetch!();
  }

  @override
  Future<DecorationItem> purchaseDecoration(String id) async {
    purchases++;
    return purchase == null ? items.first : await purchase!(id);
  }

  @override
  Future<DecorationItem> setDecorationEquipped({
    required String decorationId,
    required bool equipped,
  }) async {
    equips++;
    return items.first;
  }
}
