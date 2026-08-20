#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TARGETS = (
    ROOT / ".github/workflows/flutter-ci.yml",
    ROOT / "tool/qa/run_m32_vendor_avd.sh",
)

replacements = {
    "ci-development-outbox": "ci-local-outbox-placeholder",
    "never-expose-": "do-not-expose-",
}

changed = 0
for path in TARGETS:
    text = path.read_text(encoding="utf-8")
    updated = text
    for old, new in replacements.items():
        updated = updated.replace(old, new)
    if updated != text:
        path.write_text(updated, encoding="utf-8")
        changed += 1

if changed != len(TARGETS):
    raise SystemExit(
        f"expected to update {len(TARGETS)} hygiene targets, updated {changed}"
    )
