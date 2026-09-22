import 'dart:typed_data';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/design_system/runtime_surfaces.dart';

void main() {
  for (final mode in ['reference', 'inactive', 'active']) {
    final active = mode == 'active';
    testWidgets('$mode control has visible press feedback', (tester) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.social(),
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(
                key: key,
                child: Material(
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: mode == 'reference'
                        ? InkWell(
                            key: const Key('reference-control'),
                            onTap: () {},
                            overlayColor: const WidgetStatePropertyAll(
                              Colors.blue,
                            ),
                            child: const SizedBox(
                              width: 80,
                              height: 44,
                              child: Center(child: Text('Filter')),
                            ),
                          )
                        : SocialPill(
                            label: 'Filter',
                            active: active,
                            onTap: () {},
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<Uint8List> capture(String frame) async {
        return (await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1);
          try {
            const output = String.fromEnvironment('UI_OUTPUT');
            if (output.isNotEmpty) {
              final png = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              Directory(output).createSync(recursive: true);
              File(
                '$output/press-$mode-$frame.png',
              ).writeAsBytesSync(png!.buffer.asUint8List());
            }
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            );
            return Uint8List.fromList(bytes!.buffer.asUint8List());
          } finally {
            image.dispose();
          }
        }))!;
      }

      final before = await capture('before');
      final target = mode == 'reference'
          ? find.byKey(const Key('reference-control'))
          : find.byType(SocialPill);
      final boundaryRect = tester.getRect(find.byKey(key));
      final interior = tester
          .getRect(target)
          .deflate(4)
          .shift(-boundaryRect.topLeft);
      final pixelWidth = boundaryRect.width.ceil();
      final gesture = await tester.startGesture(tester.getCenter(target));
      await tester.pump(const Duration(milliseconds: 180));
      await tester.pump(const Duration(milliseconds: 180));
      final after = await capture('held');
      var changedPixels = 0;
      var changedInteriorPixels = 0;
      expect(after.length, before.length);
      for (var offset = 0; offset < before.length; offset += 4) {
        if (before[offset] != after[offset] ||
            before[offset + 1] != after[offset + 1] ||
            before[offset + 2] != after[offset + 2]) {
          changedPixels++;
          final pixel = offset ~/ 4;
          if (interior.contains(
            Offset((pixel % pixelWidth) + 0.5, (pixel ~/ pixelWidth) + 0.5),
          )) {
            changedInteriorPixels++;
          }
        }
      }
      await gesture.up();
      await tester.pumpAndSettle();
      await capture('released');
      debugPrint(
        'PRESS_PROBE mode=$mode changedPixels=$changedPixels changedInteriorPixels=$changedInteriorPixels',
      );
      expect(
        changedInteriorPixels,
        greaterThan(0),
        reason:
            'The control surface must show press feedback, not only a thin border; this checks raster output, not only overlay properties.',
      );
    });
  }
}
