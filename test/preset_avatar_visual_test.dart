import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/features/account/domain/preset_avatar.dart';
import 'package:voice_social_app/features/account/presentation/preset_avatar_view.dart';

import 'support/golden_baseline_path.dart';
import 'support/golden_font_gate.dart';

void main() {
  setUpAll(() async {
    await loadGoldenFonts();
    // The old golden subset predates these four label glyphs. Keep its bytes
    // and all existing baselines intact; this checked-in supplement is local
    // to the new gallery and never falls back to a machine-installed font.
    final bytes = File(
      'test/fonts/RegistrationAvatarCjkSupplement.otf',
    ).readAsBytesSync();
    await (FontLoader(
      'RegistrationAvatarCjkSupplement',
    )..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)))).load();
  });

  testWidgets('preset artwork has a readable gallery and small silhouettes', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 460);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          fontFamily: kGoldenFontFamily,
          fontFamilyFallback: const <String>['RegistrationAvatarCjkSupplement'],
        ),
        home: RepaintBoundary(
          key: const Key('avatar-gallery'),
          child: Scaffold(
            backgroundColor: Colors.white,
            body: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text('选择头像', style: TextStyle(fontSize: 24)),
                  const SizedBox(height: 8),
                  const Text('主动选择一款喜欢的头像'),
                  const SizedBox(height: 20),
                  PresetAvatarPicker(
                    selectedId: 'avatar-preset-star',
                    onSelected: (_) {},
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: <Widget>[
                      for (final PresetAvatar avatar in PresetAvatars.values)
                        PresetAvatarView(presetId: avatar.id, size: 32),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const Key('avatar-gallery')),
      matchesGoldenFile(m33GoldenPath('goldens/preset_avatar_gallery_360.png')),
    );
  });
}
