import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/features/commerce/catalog/domain/commerce_catalog_models.dart';
import 'package:voice_social_app/features/commerce/presentation/decoration_preview.dart';
import 'package:voice_social_app/features/commerce/display/domain/equipped_decoration.dart';
import 'package:voice_social_app/features/commerce/display/presentation/decoration_artwork.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'product art has distinct real pixels and the frame leaves the avatar center transparent',
    () async {
      final frames = <Uint8List>[];
      for (final product in DecorationProduct.values) {
        final pixels = await _raster(product);
        expect(
          [
            for (var i = 3; i < pixels.length; i += 4) pixels[i],
          ].where((alpha) => alpha > 0).length,
          greaterThan(100),
        );
        for (final other in frames) {
          expect(pixels, isNot(orderedEquals(other)));
        }
        frames.add(pixels);
      }
      expect(frames.first[(50 * 100 + 50) * 4 + 3], 0);
      for (final progress in [0.0, double.nan, double.infinity]) {
        expect(
          await _raster(DecorationProduct.streamEntry, progress: progress),
          everyElement(0),
        );
      }
    },
  );
  for (final product in <(String, DecorationKind)>[
    ('decoration/star-ring-frame', DecorationKind.avatarFrame),
    ('decoration/stream-entry', DecorationKind.entrance),
    ('decoration/companion-badge', DecorationKind.profileCard),
  ]) {
    testWidgets(
      '${product.$1} preview is dedicated painted artwork without a generic image',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DecorationPreview(
                item: DecorationItem(
                  id: '00000000-0000-0000-0000-000000000001',
                  name: '商品',
                  kind: product.$2,
                  priceGiftCoins: 1,
                  durationDays: 7,
                  owned: false,
                  equipped: false,
                  assetUrl: product.$1,
                ),
              ),
            ),
          ),
        );
        expect(find.text('预览未配置'), findsNothing);
        expect(
          find.byKey(ValueKey('decoration-art-${product.$1}')),
          findsOneWidget,
        );
        expect(find.byType(Image), findsNothing);
      },
    );
  }
}

Future<Uint8List> _raster(
  DecorationProduct product, {
  double progress = 1,
}) async {
  final recorder = ui.PictureRecorder();
  DecorationProductPainter(
    product,
    progress: progress,
  ).paint(Canvas(recorder), const Size(100, 100));
  final picture = recorder.endRecording();
  final image = await picture.toImage(100, 100);
  try {
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    return bytes.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}
