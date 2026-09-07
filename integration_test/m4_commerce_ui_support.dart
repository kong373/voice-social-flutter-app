import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Finder> waitForCommerceGiftEntry(
  WidgetTester tester, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final DateTime deadline = tester.binding.clock.now().add(timeout);
  final Finder gifts = find.text('礼物');
  while (tester.binding.clock.now().isBefore(deadline)) {
    // The hub title is already present while the wallet request is pending.
    // Never apply .last until the unrestricted finder has a result.
    if (find.text('钱包与商城').hitTestable().evaluate().isNotEmpty) {
      if (gifts.evaluate().isNotEmpty) {
        final Finder gift = gifts.last;
        await tester.ensureVisible(gift);
        await tester.pump();
        if (gift.hitTestable().evaluate().isNotEmpty) {
          return gift.hitTestable();
        }
      } else {
        // Returning from a scrolled ledger entry can leave the shortcuts
        // outside ListView's built range. Restore them through a UI scroll.
        final Finder list = find.byType(ListView).hitTestable();
        if (list.evaluate().isNotEmpty) {
          await tester.drag(list.first, const Offset(0, 300));
        }
      }
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
  throw TestFailure(
    'Timed out waiting for commerce hub gift entry: '
    'expected 钱包与商城 with a visible 礼物 action.',
  );
}
