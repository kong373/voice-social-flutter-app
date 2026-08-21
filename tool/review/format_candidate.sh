#!/usr/bin/env bash
set -Eeuo pipefail

python3 - <<'PY'
from pathlib import Path

path = Path('integration_test/m2_4_test_support.dart')
text = path.read_text(encoding='utf-8')
old = """  // Android needs a rendered frame after swapping FlutterSurfaceView for
  // FlutterImageView, otherwise the captured frame can be blank or stale.
  await tester.pump();
  await binding.takeScreenshot(safeName);
"""
new = """  // Android needs multiple platform-rendered frames after route, async-data,
  // and FlutterImageView transitions; a single fake-clock pump can otherwise
  // capture the immediately preceding loading frame even after assertions pass.
  for (int frame = 0; frame < 3; frame += 1) {
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 120));
  }
  await tester.pump();
  await binding.takeScreenshot(safeName);
"""
if text.count(old) != 1:
    raise SystemExit(f'expected one Android screenshot frame block, got {text.count(old)}')
path.write_text(text.replace(old, new, 1), encoding='utf-8')
PY

mapfile -d '' dart_files < <(
  find lib test integration_test tool -type f -name '*.dart' -print0 | sort -z
)
test "${#dart_files[@]}" -gt 0
dart format "${dart_files[@]}"
