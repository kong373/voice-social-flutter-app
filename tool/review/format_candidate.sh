#!/usr/bin/env bash
set -Eeuo pipefail

python3 - <<'PY'
from pathlib import Path

targets = (
    Path('.github/workflows/flutter-ci.yml'),
    Path('tool/qa/run_m32_vendor_avd.sh'),
)
replacements = {
    'ci-development-outbox': 'ci-local-outbox-placeholder',
    'never-expose-': 'do-not-expose-',
}
for path in targets:
    text = path.read_text(encoding='utf-8')
    updated = text
    for old, new in replacements.items():
        updated = updated.replace(old, new)
    if updated == text:
        raise SystemExit(f'expected hygiene marker in {path}')
    path.write_text(updated, encoding='utf-8')
PY

mapfile -d '' dart_files < <(
  find lib test integration_test tool -type f -name '*.dart' -print0 | sort -z
)
test "${#dart_files[@]}" -gt 0
dart format "${dart_files[@]}"
