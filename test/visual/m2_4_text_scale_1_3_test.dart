import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'm2_4_visual_test_support.dart';

void main() {
  testWidgets('all 69 pages render at 360x800 and 1.3x text', (
    WidgetTester tester,
  ) async {
    await runM24VisualSuite(tester, size: const Size(360, 800), textScale: 1.3);
  });

  testWidgets('all 69 pages render at 390x844 and 1.3x text', (
    WidgetTester tester,
  ) async {
    await runM24VisualSuite(tester, size: const Size(390, 844), textScale: 1.3);
  });
}
