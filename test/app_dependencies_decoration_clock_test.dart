import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('mock decoration expiry uses the injected application clock', () async {
    final dependencies = AppDependencies.mock(
      mockNow: DateTime.utc(2026, 8, 20, 18, 12),
    );
    addTearDown(dependencies.dispose);
    final items = await dependencies.commerceCatalogRepository
        .fetchDecorations();

    expect(
      items.singleWhere((item) => item.id == 'decor-frame-starlight').expiresAt,
      DateTime.utc(2026, 9, 19, 18, 12),
    );
    expect(
      items.singleWhere((item) => item.id == 'decor-wave-soft').expiresAt,
      DateTime.utc(2026, 9, 3, 18, 12),
    );
  });
}
