import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/page_manifest.dart';

void main() {
  test('69-page product scope is complete and unique', () {
    expect(appPageManifest, hasLength(69));
    expect(
      appPageManifest.map((AppPageDefinition page) => page.id).toSet(),
      hasLength(69),
    );
  });

  test('page-area denominators stay frozen', () {
    final Map<ProductArea, int> expected = <ProductArea, int>{
      ProductArea.account: 12,
      ProductArea.discovery: 8,
      ProductArea.social: 10,
      ProductArea.room: 14,
      ProductArea.message: 6,
      ProductArea.commerce: 12,
      ProductArea.community: 7,
    };

    for (final MapEntry<ProductArea, int> entry in expected.entries) {
      expect(
        appPageManifest
            .where((AppPageDefinition page) => page.area == entry.key),
        hasLength(entry.value),
      );
    }
  });
}
