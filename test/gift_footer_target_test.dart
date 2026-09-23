import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/features/commerce/data/mock_commerce_repository.dart';
import 'package:voice_social_app/features/commerce/domain/commerce_models.dart';
import 'package:voice_social_app/features/commerce/presentation/commerce_pages.dart';
import 'package:voice_social_app/features/room/presentation/gift_sheet.dart';
import 'package:voice_social_app/features/shell/main_shell.dart';

import 'support/golden_font_gate.dart';

const _captureKey = Key('gift-footer-target-capture');
final _sheet = find.byType(GiftSheet);

Finder _button(String label) => find.descendant(
  of: find.descendant(
    of: _sheet,
    matching: find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.label == label,
    ),
  ),
  matching: find.byType(InkWell),
);

Finder get _quantity => find.descendant(
  of: find.descendant(of: _sheet, matching: find.byType(PopupMenuButton<int>)),
  matching: find.byType(InkWell),
);

void main() {
  for (final view in [
    (size: const Size(360, 800), scale: 1.3),
    (size: const Size(360, 640), scale: 1.3),
    (size: const Size(390, 844), scale: 1.0),
  ]) {
    testWidgets('gift modal targets ${view.size} text ${view.scale}', (
      tester,
    ) async {
      await loadGoldenFonts();
      tester.view.devicePixelRatio = 2.4;
      tester.view.physicalSize = view.size * 2.4;
      tester.view.padding = const FakeViewPadding(top: 72, bottom: 57.6);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      final dependencies = AppDependencies.mock();
      await tester.pumpWidget(
        AppDependencyScope(
          dependencies: dependencies,
          child: MaterialApp(
            theme: AppTheme.social(fontFamily: kGoldenFontFamily),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(view.scale)),
              child: RepaintBoundary(key: _captureKey, child: child!),
            ),
            home: MainShell(dependencies: dependencies, onSignOut: () async {}),
          ),
        ),
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        dependencies.dispose();
      });
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('live-room-880217')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('live-room-880217')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('礼物').hitTestable());
      await tester.pumpAndSettle();
      expect(_sheet, findsOneWidget);
      final gift = tester.widget<GiftSheet>(_sheet);
      final refresh = find.descendant(
        of: find.byTooltip('刷新余额'),
        matching: find.byType(InkWell),
      );
      final targets = <String, Finder>{
        'quantity': _quantity,
        'send': _button('赠送礼物'),
        'refresh': refresh,
        'recharge': _button('充值'),
      };
      for (final entry in targets.entries) {
        debugPrint('${entry.key}: ${tester.getRect(entry.value)}');
      }
      await _capture(
        tester,
        '${view.size.width.toInt()}x${view.size.height.toInt()}-text${view.scale}',
      );
      for (final entry in targets.entries) {
        final rect = tester.getRect(entry.value);
        expect(rect.width, greaterThanOrEqualTo(48), reason: entry.key);
        expect(rect.height, greaterThanOrEqualTo(48), reason: entry.key);
        expect(
          entry.value.hitTestable(at: const Alignment(0, 0.95)),
          findsOneWidget,
        );
      }

      final grid = find.descendant(of: _sheet, matching: find.byType(GridView));
      final gridRect = tester.getRect(grid);
      final tiles = find.descendant(of: grid, matching: find.byType(InkWell));
      expect(tiles, findsAtLeastNWidgets(4));
      for (var index = 0; index < 4; index++) {
        final rect = tester.getRect(tiles.at(index));
        expect(rect.top, greaterThanOrEqualTo(gridRect.top));
        expect(rect.bottom, lessThanOrEqualTo(gridRect.bottom));
        for (final text
            in find
                .descendant(of: tiles.at(index), matching: find.byType(Text))
                .evaluate()) {
          expect(
            tester.getBottomRight(find.byWidget(text.widget)).dy,
            lessThanOrEqualTo(gridRect.bottom),
          );
        }
      }

      final commerce =
          dependencies.commerceRepository as MockCommerceRepository;
      commerce.giftCoins = GiftCoinAmount.whole(1234);
      await tester.tapAt(
        tester.getRect(refresh).bottomCenter - const Offset(0, 1),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: _sheet, matching: find.text('1234')),
        findsOneWidget,
      );

      await tester.tapAt(
        tester.getRect(_button('充值')).bottomCenter - const Offset(0, 1),
      );
      await tester.pumpAndSettle();
      expect(find.byType(RechargeCatalogPage), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(_sheet, findsOneWidget);

      await tester.tapAt(
        tester.getRect(_quantity).bottomCenter - const Offset(0, 1),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('×10').last);
      await tester.pumpAndSettle();
      final compact = view.size.width < 380 || view.scale > 1.15;
      expect(find.text(compact ? '赠送 100' : '赠送 · 100'), findsOneWidget);
      await tester.tapAt(
        tester.getRect(_button('赠送礼物')).bottomCenter - const Offset(0, 1),
      );
      await tester.pumpAndSettle();
      expect(gift.coordinator!.plan!.command.quantity, 10);
      expect(gift.coordinator!.plan!.totalCoins, BigInt.from(100));
      expect(gift.coordinator!.plan!.succeeded, 1);
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _capture(WidgetTester tester, String name) async {
  const directory = String.fromEnvironment('GIFT_FOOTER_EVIDENCE_DIR');
  if (directory.isEmpty) return;
  final context = tester.element(_sheet);
  await tester.runAsync(() async {
    for (final image in tester.widgetList<Image>(
      find.descendant(of: _sheet, matching: find.byType(Image)),
    )) {
      await precacheImage(image.image, context);
    }
  });
  await tester.pump();
  await tester.runAsync(() async {
    final image = await tester
        .renderObject<RenderRepaintBoundary>(find.byKey(_captureKey))
        .toImage(pixelRatio: 1);
    try {
      final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      await File(
        '$directory/$name.png',
      ).writeAsBytes(data.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
