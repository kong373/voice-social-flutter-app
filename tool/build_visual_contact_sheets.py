#!/usr/bin/env python3
"""Build review contact sheets from the 69-page Flutter golden inventory."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


GROUPS = ("ac", "ds", "us", "rm", "ms", "cm", "sc")


def build_sheet(files: list[Path], destination: Path) -> None:
    thumb_width, thumb_height = 195, 422
    label_height, gap = 34, 12
    columns = 4
    rows = (len(files) + columns - 1) // columns
    sheet = Image.new(
        "RGB",
        (
            columns * thumb_width + (columns + 1) * gap,
            rows * (thumb_height + label_height) + (rows + 1) * gap,
        ),
        "#e9ecf5",
    )
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.load_default(size=15)
    for index, source in enumerate(files):
        with Image.open(source) as raw:
            image = raw.convert("RGB")
            image.thumbnail((thumb_width, thumb_height), Image.Resampling.LANCZOS)
            x = gap + (index % columns) * (thumb_width + gap)
            y = gap + (index // columns) * (thumb_height + label_height + gap)
            tile = Image.new("RGB", (thumb_width, thumb_height), "white")
            tile.paste(
                image,
                ((thumb_width - image.width) // 2, (thumb_height - image.height) // 2),
            )
            sheet.paste(tile, (x, y))
            draw.text(
                (x + thumb_width / 2, y + thumb_height + label_height / 2),
                source.stem.replace("_390x844", "").upper(),
                fill="#17213c",
                font=font,
                anchor="mm",
            )
    destination.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(destination, optimize=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    for group in GROUPS:
        files = sorted(args.source.glob(f"{group}-*_390x844.png"))
        if files:
            build_sheet(files, args.destination / f"{group}-contact.png")


if __name__ == "__main__":
    main()
