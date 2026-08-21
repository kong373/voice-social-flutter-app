import 'package:flutter_test/flutter_test.dart';

import 'support/golden_baseline_path.dart';

void main() {
  test('Linux resolves the dedicated M3.3 golden baseline', () {
    expect(
      m33GoldenPath(
        'goldens/m3_3_all/ac-001_390x844.png',
        operatingSystem: 'linux',
      ),
      'goldens/linux/m3_3_all/ac-001_390x844.png',
    );
  });

  test('macOS preserves the reviewed local M3.3 golden baseline', () {
    expect(
      m33GoldenPath('goldens/m3_3_home_390x844.png', operatingSystem: 'macos'),
      'goldens/m3_3_home_390x844.png',
    );
  });

  test(
    'unsupported platforms fail closed instead of using another baseline',
    () {
      expect(
        () => m33GoldenPath(
          'goldens/m3_3_home_390x844.png',
          operatingSystem: 'windows',
        ),
        throwsUnsupportedError,
      );
    },
  );

  test('paths outside the golden root are rejected', () {
    expect(
      () => m33GoldenPath('../m3_3_home_390x844.png', operatingSystem: 'linux'),
      throwsArgumentError,
    );
  });
}
