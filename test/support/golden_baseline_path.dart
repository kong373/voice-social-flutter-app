import 'dart:io';

String m33GoldenPath(String path, {String? operatingSystem}) {
  if (!path.startsWith('goldens/') ||
      path.startsWith('/') ||
      path.split('/').contains('..')) {
    throw ArgumentError.value(path, 'path', 'must stay under goldens/');
  }

  return switch (operatingSystem ?? Platform.operatingSystem) {
    'linux' => 'goldens/linux/${path.substring('goldens/'.length)}',
    'macos' => path,
    final String unsupported => throw UnsupportedError(
      'M3.3 has no reviewed golden baseline for $unsupported.',
    ),
  };
}
