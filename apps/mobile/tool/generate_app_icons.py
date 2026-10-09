#!/usr/bin/env python3
"""Render CoRHub's versioned SVG masters into app and platform assets.

Install tool/requirements-icons.txt in a private environment. No temporary
files, background services or network requests are used during generation.
"""

from __future__ import annotations

from io import BytesIO
import json
from pathlib import Path
import xml.etree.ElementTree as ET

import cairosvg
from PIL import Image

MOBILE = Path(__file__).resolve().parents[1]
BRAND = MOBILE / "assets/branding"
BACKGROUND = "#F6F9FC"


def raster(source: str, size: int) -> Image.Image:
    data = cairosvg.svg2png(
        bytestring=source.encode(), output_width=size, output_height=size
    )
    return Image.open(BytesIO(data)).convert("RGBA")


def save(image: Image.Image, target: Path) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    image.save(target, optimize=True)


def adaptive(source: str) -> str:
    # Fit the whole character within Android's central 66/108 safe region.
    root = ET.fromstring(source)
    group = next(child for child in root if child.tag.endswith("}g"))
    group.set("transform", "translate(74.24 74.24) scale(0.71)")
    return ET.tostring(root, encoding="unicode")


def main() -> None:
    sources = {
        variant: (BRAND / f"corhub-{variant}.svg").read_text()
        for variant in ("mark", "mark-small", "mark-monochrome")
    }
    for variant, source in sources.items():
        save(raster(source, 1024), BRAND / f"corhub-{variant}.png")

    icon = Image.new("RGB", (1024, 1024), BACKGROUND)
    mark = raster(sources["mark"], 1024)
    icon.paste(mark, (0, 0), mark)
    save(icon, BRAND / "corhub-icon.png")

    android = MOBILE / "android/app/src/main/res"
    densities = {"mdpi": (48, 108), "hdpi": (72, 162), "xhdpi": (96, 216),
                 "xxhdpi": (144, 324), "xxxhdpi": (192, 432)}
    for density, (legacy_size, adaptive_size) in densities.items():
        save(icon.resize((legacy_size, legacy_size), Image.Resampling.LANCZOS),
             android / f"mipmap-{density}/ic_launcher.png")
        for name, variant in (("foreground", "mark"), ("monochrome", "mark-monochrome")):
            save(raster(adaptive(sources[variant]), adaptive_size),
                 android / f"drawable-{density}/ic_launcher_{name}.png")

    ios = MOBILE / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    for entry in json.loads((ios / "Contents.json").read_text())["images"]:
        if "filename" not in entry:
            continue
        points = float(entry["size"].split("x")[0])
        size = round(points * float(entry["scale"].removesuffix("x")))
        save(icon.resize((size, size), Image.Resampling.LANCZOS), ios / entry["filename"])
    print("Generated CoRHub brand marks, Android legacy/adaptive/themed icons and iOS icons.")


if __name__ == "__main__":
    main()
