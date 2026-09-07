import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../integration_test/m4_commerce_ui_support.dart';

void main() {
  test('M4 requires gift readiness before ledger and gift navigation', () {
    final String source = File(
      'integration_test/m4_first_party_live_integration_test.dart',
    ).readAsStringSync();
    final String flow = source.substring(
      source.indexOf("evidence.invariant('commerce_wallet_page_reachable')"),
      source.indexOf("final Finder orders = find.text('充值订单')"),
    );
    expect('waitForCommerceGiftEntry(tester)'.allMatches(flow), hasLength(2));
    expect(flow, isNot(contains("find.text('礼物').last")));
    expect(flow, isNot(contains("'commerce.gift.ui'")));
  });

  testWidgets('waits past the hub title until delayed gift entry is visible', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(title: const Text('钱包与商城')),
          body: FutureBuilder<void>(
            future: Future<void>.delayed(const Duration(milliseconds: 600)),
            builder: (BuildContext context, AsyncSnapshot<void> snapshot) =>
                snapshot.connectionState == ConnectionState.done
                ? const Text('礼物')
                : const CircularProgressIndicator(),
          ),
        ),
      ),
    );
    expect(find.text('礼物'), findsNothing);
    final Finder gift = await waitForCommerceGiftEntry(tester);
    expect(gift, findsOneWidget);
    expect(gift.hitTestable(), findsOneWidget);
  });

  testWidgets(
    'missing gift fails explicitly instead of skipping or StateError',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(title: const Text('钱包与商城')),
            body: const Text('加载失败'),
          ),
        ),
      );
      Object? failure;
      try {
        await waitForCommerceGiftEntry(
          tester,
          timeout: const Duration(milliseconds: 300),
        );
      } catch (error) {
        failure = error;
      }
      expect(
        failure,
        isA<TestFailure>().having(
          (TestFailure error) => error.message,
          'message',
          contains('commerce hub gift entry'),
        ),
      );
    },
  );

  testWidgets('return from ledger restores and reveals the hub gift action', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            appBar: AppBar(title: const Text('钱包与商城')),
            body: ListView(
              children: <Widget>[
                TextButton(onPressed: () {}, child: const Text('礼物')),
                const SizedBox(height: 900),
                TextButton(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          Scaffold(appBar: AppBar(title: const Text('钱包与流水'))),
                    ),
                  ),
                  child: const Text('钱包与流水'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.scrollUntilVisible(find.text('钱包与流水'), 300);
    await tester.tap(find.text('钱包与流水'));
    await tester.pumpAndSettle();
    expect(find.text('礼物'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    final Finder gift = await waitForCommerceGiftEntry(tester);
    expect(gift.hitTestable(), findsOneWidget);
    expect(find.text('钱包与商城'), findsOneWidget);
  });
}
