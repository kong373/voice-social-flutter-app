import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/page_manifest.dart';
import 'package:voice_social_app/debug/qa_console/qa_page_catalog.dart';

void main() {
  test('removed page IDs are explicit dispositions, never PASS or reused', () {
    expect(removedProductPages.keys.toSet(), {
      'US-005',
      'SC-004',
      'SC-005',
      'SC-006',
      'SC-007',
    });
    expect(removedProductPages.values.toSet(), {'REMOVED_BY_PRODUCT'});
    expect(
      appPageManifest
          .map((page) => page.id)
          .toSet()
          .intersection(removedProductPages.keys.toSet()),
      isEmpty,
    );
  });

  test('64-page product scope is complete and unique', () {
    expect(appPageManifest, hasLength(64));
    expect(
      appPageManifest.map((AppPageDefinition page) => page.id).toSet(),
      hasLength(64),
    );
  });

  test('active page-area denominators reflect product removals', () {
    final Map<ProductArea, int> expected = <ProductArea, int>{
      ProductArea.account: 12,
      ProductArea.discovery: 8,
      ProductArea.social: 9,
      ProductArea.room: 14,
      ProductArea.message: 6,
      ProductArea.commerce: 12,
      ProductArea.community: 3,
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

  test('active Page IDs preserve order without reusing removed IDs', () {
    final List<String> expected = <String>[
      ..._ids('AC', 12),
      ..._ids('DS', 8),
      ..._ids('US', 10).where((id) => id != 'US-005'),
      ..._ids('RM', 14),
      ..._ids('MS', 6),
      ..._ids('CM', 12),
      ..._ids('SC', 3),
    ];

    expect(
      appPageManifest.map((AppPageDefinition page) => page.id).toList(),
      expected,
    );
  });

  test('QA catalog maps every manifest page to a real implementation', () {
    expect(qaPageCatalog, hasLength(64));
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
