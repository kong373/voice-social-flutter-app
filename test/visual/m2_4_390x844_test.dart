import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'm2_4_visual_test_support.dart';

void main() {
  testWidgets('all 69 pages render at Android 390x844 and 1.0x text', (
    WidgetTester tester,
  ) async {
    await runM24VisualSuite(tester, size: const Size(390, 844), textScale: 1);
  });
}
