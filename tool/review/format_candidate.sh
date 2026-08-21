#!/usr/bin/env bash
set -Eeuo pipefail

python3 - <<'PY'
from pathlib import Path

path = Path('integration_test/m3_2_vendor_readiness_test.dart')
text = path.read_text(encoding='utf-8')
old = """      await tester.pageBack();
      await _waitFor(
        tester,
        () => find
            .byKey(const Key('live-account-overview'))
            .evaluate()
            .isNotEmpty,
        description: 'account overview after developer diagnostics',
      );

      await tester.tap(find.text('消息').hitTestable());
"""
new = """      await tester.pageBack();
      await _waitFor(
        tester,
        () => find
            .byKey(const Key('live-account-overview'))
            .evaluate()
            .isNotEmpty,
        description: 'account overview after developer diagnostics',
      );
      await tester.fling(
        find.byKey(const Key('live-account-overview')),
        const Offset(0, 1200),
        2000,
      );
      await tester.pumpAndSettle();
      await _waitFor(
        tester,
        () =>
            find
                .byKey(const Key('current-user-contract-ready'))
                .evaluate()
                .isNotEmpty &&
            find
                .byKey(const Key('wallet-contract-ready'))
                .evaluate()
                .isNotEmpty,
        description: 'account overview reset after developer diagnostics',
      );

      await tester.tap(find.text('消息').hitTestable());
"""
if text.count(old) != 1:
    raise SystemExit(f'expected one post-diagnostics account block, got {text.count(old)}')
path.write_text(text.replace(old, new, 1), encoding='utf-8')
PY

mapfile -d '' dart_files < <(
  find lib test integration_test tool -type f -name '*.dart' -print0 | sort -z
)
test "${#dart_files[@]}" -gt 0
dart format "${dart_files[@]}"
