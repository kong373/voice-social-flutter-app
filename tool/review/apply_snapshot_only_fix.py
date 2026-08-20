#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
path = ROOT / ".github/workflows/m32-pre-provider-review.yml"
text = path.read_text(encoding="utf-8")
old = """          script: |
            set -Eeuo pipefail
"""
new = """          script: |
            set -eu
"""
if text.count(old) != 1:
    raise SystemExit(f"expected exactly one emulator runner shell block, got {text.count(old)}")
path.write_text(text.replace(old, new, 1), encoding="utf-8")
