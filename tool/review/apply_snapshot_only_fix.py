#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
path = ROOT / ".github/workflows/m32-pre-provider-review.yml"
text = path.read_text(encoding="utf-8")
old = """          script: |
            set -Eeuo pipefail
            DEVICE_ID=\"$(adb devices | awk 'NR>1 && $2==\"device\" {print $1; exit}')\"
"""
new = """          script: |
            set -eu
            DEVICE_ID=\"$(adb devices | awk 'NR>1 && $2==\"device\" {print $1; exit}')\"
"""
if text.count(old) != 1:
    raise SystemExit("expected exactly one emulator runner shell block")
path.write_text(text.replace(old, new, 1), encoding="utf-8")
