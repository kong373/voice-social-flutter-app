import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/page_manifest.dart';
import 'package:voice_social_app/debug/qa_console/qa_page_catalog.dart';

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
        appPageManifest.where(
          (AppPageDefinition page) => page.area == entry.key,
        ),
        hasLength(entry.value),
      );
    }
  });

  test('the complete ordered Page ID denominator stays frozen', () {
    final List<String> expected = <String>[
      ..._ids('AC', 12),
      ..._ids('DS', 8),
      ..._ids('US', 10),
      ..._ids('RM', 14),
      ..._ids('MS', 6),
      ..._ids('CM', 12),
      ..._ids('SC', 7),
    ];

    expect(
      appPageManifest.map((AppPageDefinition page) => page.id).toList(),
      expected,
    );
  });

  test('QA catalog maps every manifest page to a real implementation', () {
    expect(qaPageCatalog, hasLength(69));
    expect(
      qaPageCatalog.map((entry) => entry.id).toList(),
      appPageManifest.map((AppPageDefinition page) => page.id).toList(),
    );
    for (final entry in qaPageCatalog) {
      expect(entry.widgetClass, isNotEmpty, reason: entry.id);
      expect(entry.sourcePath, isNotEmpty, reason: entry.id);
      expect(entry.userEntry, isNotEmpty, reason: entry.id);
      expect(
        entry.widgetClass,
        isNot(contains('ScopedPlaceholderPage')),
        reason: entry.id,
      );
    }
  });
}

List<String> _ids(String prefix, int count) => <String>[
  for (int value = 1; value <= count; value += 1)
    '$prefix-${value.toString().padLeft(3, '0')}',
];
