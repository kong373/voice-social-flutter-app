#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
FONTS_DIR = REPO_ROOT / "test" / "fonts"
TMP_ENV_NAME = "m33_golden_font_venv"
SOURCE_DATE_EPOCH = "0"
FONTTOOLS_VERSION = "4.63.0"

UPSTREAM_COMMIT = "f8d157532fbfaeda587e826d4cd5b21a49186f7c"
UPSTREAM_BASE = (
    "https://raw.githubusercontent.com/notofonts/noto-cjk/"
    f"{UPSTREAM_COMMIT}"
)
LICENSE_URL = f"{UPSTREAM_BASE}/Sans/LICENSE"
REGULAR_URL = f"{UPSTREAM_BASE}/Sans/SubsetOTF/SC/NotoSansSC-Regular.otf"
BOLD_URL = f"{UPSTREAM_BASE}/Sans/SubsetOTF/SC/NotoSansSC-Bold.otf"

LICENSE_BLOB_SHA = "d952d62c065f3f35fb83a173496e90b21525aef3"
REGULAR_BLOB_SHA = "fc0fda9394367c16c1af7555a2ae4d5e2e6a6f02"
BOLD_BLOB_SHA = "bcc11bc30e65b69b9e5a508c3e2138197c5543cf"

LICENSE_SHA256 = "6a73f9541c2de74158c0e7cf6b0a58ef774f5a780bf191f2d7ec9cc53efe2bf2"
REGULAR_SHA256 = "faa6c9df652116dde789d351359f3d7e5d2285a2b2a1f04a2d7244df706d5ea9"
BOLD_SHA256 = "c6cb5a93abaa9edc8ee7463b7ebb7f42d618d40e6ed2f7a5371c97b0b64767c0"

REGULAR_OUTPUT = FONTS_DIR / "M3GoldenCjkRegular.otf"
BOLD_OUTPUT = FONTS_DIR / "M3GoldenCjkBold.otf"
LICENSE_OUTPUT = FONTS_DIR / "OFL.txt"
SOURCE_OUTPUT = FONTS_DIR / "SOURCE.txt"
CHARSET_OUTPUT = FONTS_DIR / "M3GoldenCjk.charset.txt"

TEXT_SOURCE_GLOBS = (
    "lib/**/*.dart",
    "test/**/*.dart",
)

ASCII_SEED = (
    " !\"#$%&'()*+,-./0123456789:;<=>?@"
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`"
    "abcdefghijklmnopqrstuvwxyz{|}~"
)


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def download(url: str, expected_sha256: str) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": "codex"})
    with urllib.request.urlopen(request) as response:
        data = response.read()
    digest = sha256_bytes(data)
    if digest != expected_sha256:
        raise SystemExit(f"sha256 mismatch for {url}: {digest} != {expected_sha256}")
    return data


def collect_charset() -> str:
    chars = set(ASCII_SEED)
    for pattern in TEXT_SOURCE_GLOBS:
        for path in sorted(REPO_ROOT.glob(pattern)):
            text = path.read_text(encoding="utf-8")
            chars.update(ch for ch in text if ch >= " " and ch not in "\x7f")
    return "".join(sorted(chars))


def ensure_fonttools(venv_dir: Path) -> Path:
    if not venv_dir.exists():
        subprocess.run([sys.executable, "-m", "venv", str(venv_dir)], check=True)
    pip = venv_dir / "bin" / "pip"
    pyftsubset = venv_dir / "bin" / "pyftsubset"
    subprocess.run([str(pip), "install", f"fonttools=={FONTTOOLS_VERSION}"], check=True)
    if not pyftsubset.exists():
        raise SystemExit("pyftsubset was not installed correctly")
    return pyftsubset


def subset_font(pyftsubset: Path, source: Path, output: Path, text_file: Path) -> None:
    env = os.environ.copy()
    env["SOURCE_DATE_EPOCH"] = SOURCE_DATE_EPOCH
    env["TZ"] = "UTC"
    env["LC_ALL"] = "C"
    subprocess.run(
        [
            str(pyftsubset),
            str(source),
            f"--output-file={output}",
            f"--text-file={text_file}",
            "--layout-features=*",
            "--glyph-names",
            "--symbol-cmap",
            "--legacy-cmap",
            "--notdef-glyph",
            "--notdef-outline",
            "--recommended-glyphs",
            "--name-IDs=*",
            "--name-legacy",
            "--name-languages=*",
            "--drop-tables=",
            "--passthrough-tables",
            "--no-hinting",
            "--desubroutinize",
            "--canonical-order",
        ],
        check=True,
        env=env,
    )


def main() -> None:
    FONTS_DIR.mkdir(parents=True, exist_ok=True)
    charset = collect_charset()
    CHARSET_OUTPUT.write_text(charset, encoding="utf-8")

    with tempfile.TemporaryDirectory(prefix="m33-golden-fonts-") as temp_dir_raw:
        temp_dir = Path(temp_dir_raw)
        regular_source = temp_dir / "NotoSansSC-Regular.otf"
        bold_source = temp_dir / "NotoSansSC-Bold.otf"
        license_source = temp_dir / "OFL.txt"

        regular_source.write_bytes(download(REGULAR_URL, REGULAR_SHA256))
        bold_source.write_bytes(download(BOLD_URL, BOLD_SHA256))
        license_source.write_bytes(download(LICENSE_URL, LICENSE_SHA256))
        regular_source_size = regular_source.stat().st_size
        bold_source_size = bold_source.stat().st_size

        pyftsubset = ensure_fonttools(temp_dir / TMP_ENV_NAME)
        subset_font(pyftsubset, regular_source, REGULAR_OUTPUT, CHARSET_OUTPUT)
        subset_font(pyftsubset, bold_source, BOLD_OUTPUT, CHARSET_OUTPUT)
        shutil.copyfile(license_source, LICENSE_OUTPUT)

    subset_outputs = [
        {
            "path": REGULAR_OUTPUT.name,
            "sha256": sha256_bytes(REGULAR_OUTPUT.read_bytes()),
            "size": REGULAR_OUTPUT.stat().st_size,
        },
        {
            "path": BOLD_OUTPUT.name,
            "sha256": sha256_bytes(BOLD_OUTPUT.read_bytes()),
            "size": BOLD_OUTPUT.stat().st_size,
        },
    ]

    metadata = {
        "upstream_repo": "https://github.com/notofonts/noto-cjk",
        "upstream_commit": UPSTREAM_COMMIT,
        "fonttools_version": FONTTOOLS_VERSION,
        "license": {
            "path": "Sans/LICENSE",
            "blob_sha": LICENSE_BLOB_SHA,
            "sha256": LICENSE_SHA256,
            "size": LICENSE_OUTPUT.stat().st_size,
        },
        "upstream_sources": [
            {
                "path": "Sans/SubsetOTF/SC/NotoSansSC-Regular.otf",
                "blob_sha": REGULAR_BLOB_SHA,
                "sha256": REGULAR_SHA256,
                "size": regular_source_size,
            },
            {
                "path": "Sans/SubsetOTF/SC/NotoSansSC-Bold.otf",
                "blob_sha": BOLD_BLOB_SHA,
                "sha256": BOLD_SHA256,
                "size": bold_source_size,
            },
        ],
        "subset_outputs": subset_outputs,
        "charset_file": CHARSET_OUTPUT.name,
        "generated_with": "pyftsubset",
        "source_date_epoch": SOURCE_DATE_EPOCH,
    }
    SOURCE_OUTPUT.write_text(
        json.dumps(metadata, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
