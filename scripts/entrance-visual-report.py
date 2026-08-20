#!/usr/bin/env python3
"""Compare deterministic animation keyframes produced by two renderers.

The capture script writes ``<demo>.tXXXX.<renderer>.png`` frames. This script
produces a TSV with robust pixel metrics and optional contact sheets so every
animation can be reviewed visually, rather than inferred from animator counts.
"""

from __future__ import annotations

import argparse
import csv
import math
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFont, ImageStat


def metrics(native: Image.Image, web: Image.Image) -> tuple[float, float]:
    diff = ImageChops.difference(native.convert("RGB"), web.convert("RGB")).convert("L")
    histogram = diff.histogram()
    total = sum(histogram)
    return ImageStat.Stat(diff).mean[0], 100.0 * sum(histogram[31:]) / total


def key(path: Path) -> tuple[str, int]:
    demo, timestamp, _platform = path.stem.rsplit(".", 2)
    return demo, int(timestamp[1:])


def frame_path(root: Path, demo: str, time: int, platform: str) -> Path:
    name = f"{demo}.t{time:04d}.{platform}.png"
    candidates = (root / platform / name, root / demo / name, root / name)
    return next((path for path in candidates if path.exists()), candidates[0])


def frame_strip(
    root: Path,
    demo: str,
    times: list[int],
    platforms: tuple[str, ...],
    thumb_width: int = 180,
) -> Image.Image:
    rows: list[Image.Image] = []
    for platform in platforms:
        frames: list[Image.Image] = []
        for time in times:
            path = frame_path(root, demo, time, platform)
            image = Image.open(path).convert("RGB")
            height = round(image.height * thumb_width / image.width)
            frames.append(image.resize((thumb_width, height), Image.Resampling.LANCZOS))
        strip = concat(frames, horizontal=True, gap=2)
        labeled = Image.new("RGB", (strip.width + 64, strip.height), "white")
        ImageDraw.Draw(labeled).text((4, 4), platform, fill="black", font=ImageFont.load_default())
        labeled.paste(strip, (64, 0))
        rows.append(labeled)
    body = concat(rows, horizontal=False, gap=2)
    canvas = Image.new("RGB", (body.width, body.height + 24), "white")
    canvas.paste(body, (0, 24))
    title = f"{demo} | " + ", ".join(f"t={time}ms" for time in times)
    ImageDraw.Draw(canvas).text((4, 4), title, fill="black", font=ImageFont.load_default())
    return canvas


def concat(images: list[Image.Image], horizontal: bool, gap: int = 0) -> Image.Image:
    if horizontal:
        size = (sum(im.width for im in images) + gap * (len(images) - 1), max(im.height for im in images))
    else:
        size = (max(im.width for im in images), sum(im.height for im in images) + gap * (len(images) - 1))
    output = Image.new("RGB", size, "white")
    cursor = 0
    for image in images:
        output.paste(image, (cursor, 0) if horizontal else (0, cursor))
        cursor += (image.width if horizontal else image.height) + gap
    return output


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("root", type=Path)
    parser.add_argument("--tsv", type=Path)
    parser.add_argument("--contacts", type=Path)
    parser.add_argument("--per-page", type=int, default=12)
    parser.add_argument("--page-prefix", default="entrance-page")
    parser.add_argument(
        "--platforms",
        help="comma-separated renderer suffixes to show as contact-sheet rows",
    )
    parser.add_argument(
        "--native-platform",
        default="native",
        help="filename platform suffix for the native-side frames (default: native)",
    )
    parser.add_argument(
        "--web-platform",
        default="web",
        help="filename platform suffix for the reference frames (default: web)",
    )
    args = parser.parse_args()

    native_suffix = f".{args.native_platform}.png"
    web_suffix = f".{args.web_platform}.png"
    native_paths = sorted(args.root.rglob(f"*{native_suffix}"), key=key)
    rows: list[tuple[str, int, float, float]] = []
    for native_path in native_paths:
        demo, time = key(native_path)
        web_path = frame_path(args.root, demo, time, args.web_platform)
        if not web_path.exists():
            continue
        mae, changed = metrics(Image.open(native_path), Image.open(web_path))
        rows.append((demo, time, mae, changed))

    if args.tsv:
        args.tsv.parent.mkdir(parents=True, exist_ok=True)
        with args.tsv.open("w", newline="") as file:
            writer = csv.writer(file, delimiter="\t")
            writer.writerow(("demo", "time_ms", "mae", "pixels_over_30_percent"))
            writer.writerows((demo, time, f"{mae:.4f}", f"{changed:.4f}") for demo, time, mae, changed in rows)

    if args.contacts:
        platforms = tuple(args.platforms.split(",")) if args.platforms else (
            args.native_platform,
            args.web_platform,
        )
        if not platforms or any(not platform for platform in platforms):
            parser.error("--platforms must contain at least one non-empty renderer")

        demo_times: dict[str, list[int]] = {}
        first_suffix = f".{platforms[0]}.png"
        first_paths = sorted(args.root.rglob(f"*{first_suffix}"), key=key)
        for first_path in first_paths:
            demo, time = key(first_path)
            if all(frame_path(args.root, demo, time, platform).exists() for platform in platforms):
                demo_times.setdefault(demo, []).append(time)

        args.contacts.mkdir(parents=True, exist_ok=True)
        demos = sorted(demo_times)
        for page_index in range(math.ceil(len(demos) / args.per_page)):
            page_demos = demos[page_index * args.per_page : (page_index + 1) * args.per_page]
            strips = [
                frame_strip(
                    args.root,
                    demo,
                    sorted(set(demo_times[demo])),
                    platforms,
                )
                for demo in page_demos
            ]
            concat(strips, horizontal=False, gap=8).save(
                args.contacts / f"{args.page_prefix}-{page_index + 1:03d}.png"
            )


if __name__ == "__main__":
    main()
