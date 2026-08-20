#!/usr/bin/env bash
set -Eeuo pipefail

python3 - <<'PY'
from pathlib import Path

home_path = Path('lib/features/shell/live_read_only_pages.dart')
home = home_path.read_text(encoding='utf-8')
home_old = """              InkWell(
                borderRadius: BorderRadius.circular(18),
"""
home_new = """              InkWell(
                key: const Key('open-global-search'),
                borderRadius: BorderRadius.circular(18),
"""
if home.count(home_old) != 1:
    raise SystemExit(f'expected one home search entry, got {home.count(home_old)}')
home_path.write_text(home.replace(home_old, home_new, 1), encoding='utf-8')

test_path = Path('integration_test/m3_2_vendor_readiness_test.dart')
text = test_path.read_text(encoding='utf-8')
replacements = [
    (
        """      expect(find.text('实时后端 · 只读验收'), findsOneWidget);
      expect(find.textContaining('HTTP_SNAPSHOT_ONLY'), findsOneWidget);
""",
        """      expect(find.text('此刻适合你的房间'), findsOneWidget);
      expect(find.byKey(const Key('live-room-880217')), findsOneWidget);
      expect(find.text('深夜陪伴电台'), findsOneWidget);
""",
    ),
    (
        "await tester.tap(find.byTooltip('搜索').hitTestable());",
        "await tester.tap(find.byKey(const Key('open-global-search')).hitTestable());",
    ),
    (
        "find.text('搜索用户与房间').evaluate().isNotEmpty",
        "find.text('最近搜索').evaluate().isNotEmpty",
    ),
    (
        """      final Finder searchField = find.widgetWithText(
        TextField,
        '输入昵称、ID、房间名或房间号',
      );
""",
        """      final Finder searchField = find.widgetWithText(
        TextField,
        '搜索房间、用户或房间号',
      );
""",
    ),
    (
        """      await _waitFor(
        tester,
        () =>
            find.byType(RoomPage).evaluate().isNotEmpty &&
            find.textContaining('HTTP_SNAPSHOT_ONLY').evaluate().isNotEmpty,
        description: 'authoritative room snapshot',
      );
""",
        """      await _waitFor(
        tester,
        () =>
            find.byType(RoomPage).evaluate().isNotEmpty &&
            find.text('当前不可发送公屏消息').evaluate().isNotEmpty,
        description: 'authoritative room snapshot',
      );
""",
    ),
    (
        "await tester.tap(find.text('接入').hitTestable());",
        """await tester.tap(find.text('我的').hitTestable());
      await _waitFor(
        tester,
        () => find.byKey(const Key('live-account-overview')).evaluate().isNotEmpty,
        description: 'account overview before developer diagnostics',
      );
      final Finder vendorDiagnostics = find.byKey(
        const Key('open-vendor-diagnostics'),
      );
      await tester.scrollUntilVisible(
        vendorDiagnostics,
        240,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(vendorDiagnostics.hitTestable());""",
    ),
    (
        """      await announceQaEvidence(tester, 'M32_VENDOR_BOUNDARY_READY');

      await tester.tap(find.text('消息').hitTestable());
""",
        """      await announceQaEvidence(tester, 'M32_VENDOR_BOUNDARY_READY');
      await tester.pageBack();
      await _waitFor(
        tester,
        () => find.byKey(const Key('live-account-overview')).evaluate().isNotEmpty,
        description: 'account overview after developer diagnostics',
      );

      await tester.tap(find.text('消息').hitTestable());
""",
    ),
    (
        "expect(find.textContaining('腾讯 IM · VENDOR_BLOCKED'), findsOneWidget);",
        """expect(find.text('消息服务正在准备'), findsOneWidget);
      expect(find.textContaining('暂不能收发私聊'), findsOneWidget);""",
    ),
]
for old, new in replacements:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'expected one integration-test fragment, got {count}: {old[:80]!r}')
    text = text.replace(old, new, 1)
test_path.write_text(text, encoding='utf-8')
PY

mapfile -d '' dart_files < <(
  find lib test integration_test tool -type f -name '*.dart' -print0 | sort -z
)
test "${#dart_files[@]}" -gt 0
dart format "${dart_files[@]}"
