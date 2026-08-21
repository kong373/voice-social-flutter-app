#!/usr/bin/env bash
set -Eeuo pipefail

python3 - <<'PY'
from pathlib import Path

path = Path('integration_test/m3_2_vendor_readiness_test.dart')
text = path.read_text(encoding='utf-8')
old = """      final Finder searchField = find.widgetWithText(TextField, '搜索房间、用户或房间号');
      await tester.enterText(searchField, '深夜');
"""
new = """      final Finder searchField = find.byKey(
        const Key('global-search-field'),
      );
      expect(searchField, findsOneWidget);
      await tester.enterText(searchField, '深夜');
"""
if text.count(old) != 1:
    raise SystemExit(f'expected one ambiguous search-field finder, got {text.count(old)}')
path.write_text(text.replace(old, new, 1), encoding='utf-8')
PY

mapfile -d '' dart_files < <(
  find lib test integration_test tool -type f -name '*.dart' -print0 | sort -z
)
test "${#dart_files[@]}" -gt 0
dart format "${dart_files[@]}"
