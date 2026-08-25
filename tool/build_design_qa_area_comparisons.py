#!/usr/bin/env python3
"""Place video-reference states and rendered Flutter pages in one QA image."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageOps


AREAS: dict[str, tuple[str, tuple[str, ...]]] = {
    "account": (
        "frame-67s.png",
        (
            "ac-005_390x844.png",
            "ac-009_390x844.png",
            "us-001_390x844.png",
        ),
    ),
    "discovery": (
        "frame-7s.png",
        (
            "ds-002_390x844.png",
            "ds-007_390x844.png",
            "ds-008_390x844.png",
        ),
    ),
    "social": (
        "frame-58s.png",
        (
            "us-001_390x844.png",
            "us-003_390x844.png",
            "us-004_390x844.png",
        ),
    ),
    "room": (
        "frame-10s.png",
        (
            "rm-004_390x844.png",
            "rm-007_390x844.png",
            "rm-013_390x844.png",
        ),
    ),
    "messaging": (
        "frame-55s.png",
        (
            "ms-001_390x844.png",
            "ms-002_390x844.png",
            "ms-003_390x844.png",
        ),
    ),
    "commerce": (
        "frame-61s.png",
        (
            "cm-001_390x844.png",
            "cm-002_390x844.png",
            "cm-010_390x844.png",
        ),
    ),
    "community": (
        "frame-64s.png",
        (
            "sc-001_390x844.png",
            "sc-002_390x844.png",
            "sc-007_390x844.png",
        ),
    ),
}


def _phone(source: Path) -> Image.Image:
    with Image.open(source) as raw:
        return ImageOps.fit(
            raw.convert("RGB"),
            (390, 844),
            method=Image.Resampling.LANCZOS,
            centering=(0.5, 0.5),
        )


def build(
    *,
    name: str,
    reference: Path,
    implementations: tuple[Path, ...],
    destination: Path,
) -> None:
    gap = 16
    header = 52
    label_height = 34
    width = 4 * 390 + 5 * gap
    height = header + 844 + label_height + 2 * gap
    canvas = Image.new("RGB", (width, height), "#e9ecf5")
    draw = ImageDraw.Draw(canvas)
    title_font = ImageFont.load_default(size=20)
    label_font = ImageFont.load_default(size=15)
    draw.text(
        (gap, header / 2),
        f"{name.upper()} / SOURCE + RENDERED IMPLEMENTATION",
        fill="#17213c",
        font=title_font,
        anchor="lm",
    )
    sources = (reference, *implementations)
    labels = ("SOURCE VIDEO", *(path.stem.replace("_390x844", "").upper() for path in implementations))
    for index, (source, label) in enumerate(zip(sources, labels, strict=True)):
        x = gap + index * (390 + gap)
        y = header
        canvas.paste(_phone(source), (x, y))
        draw.text(
            (x + 195, y + 844 + label_height / 2),
            label,
            fill="#17213c",
            font=label_font,
            anchor="mm",
        )
    destination.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(destination, optimize=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("reference", type=Path)
    parser.add_argument("goldens", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    for name, (reference_name, implementation_names) in AREAS.items():
        build(
            name=name,
            reference=args.reference / reference_name,
            implementations=tuple(
                args.goldens / implementation_name
                for implementation_name in implementation_names
            ),
            destination=args.destination / f"{name}-area-comparison.png",
        )


if __name__ == "__main__":
    main()
