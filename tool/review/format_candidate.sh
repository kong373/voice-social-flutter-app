#!/usr/bin/env bash
set -Eeuo pipefail

python3 - <<'PY'
from pathlib import Path

path = Path('integration_test/m3_2_vendor_readiness_test.dart')
text = path.read_text(encoding='utf-8')
old = """      await tester.pageBack();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pageBack();
      await _waitFor(
        tester,
        () =>
            find.byKey(const Key('live-home-ready')).evaluate().isNotEmpty &&
            find.byKey(const Key('live-room-880217')).evaluate().isNotEmpty,
        description: 'home after search',
      );
"""
new = """      Navigator.of(
        tester.element(find.text('“深夜”的搜索结果')),
      ).pop();
      await tester.pumpAndSettle();
      await _waitFor(
        tester,
        () => find.byKey(const Key('global-search-field')).evaluate().isNotEmpty,
        description: 'global search after results',
      );
      Navigator.of(
        tester.element(find.byKey(const Key('global-search-field'))),
      ).pop();
      await tester.pumpAndSettle();
      await _waitFor(
        tester,
        () =>
            find.byKey(const Key('live-home-ready')).evaluate().isNotEmpty &&
            find.byKey(const Key('live-room-880217')).evaluate().isNotEmpty,
        description: 'home after search',
      );
"""
if text.count(old) != 1:
    raise SystemExit(f'expected one stacked search back block, got {text.count(old)}')
path.write_text(text.replace(old, new, 1), encoding='utf-8')
PY

mapfile -d '' dart_files < <(
  find lib test integration_test tool -type f -name '*.dart' -print0 | sort -z
)
test "${#dart_files[@]}" -gt 0
dart format "${dart_files[@]}"
