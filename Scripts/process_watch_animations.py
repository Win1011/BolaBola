#!/usr/bin/env python3
"""
Resize PNGs to width 400px (match idleone) and rename frame_* imagesets to prefix0..prefixN.
Run from repo root: python3 Scripts/process_watch_animations.py
"""
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
ASSETS = REPO / "BolaBola Watch App" / "Assets.xcassets"

# (folder_name_in_assets, asset_name_prefix, expected_frame_count)
JOBS: list[tuple[str, str, int]] = [
    ("idle4", "idlefour", 30),
    ("idle5", "idlefive", 30),
    ("idle6", "idlesix", 36),
    ("不开心2", "unhappytwo", 30),
    ("开心晃悠", "happyidle", 36),
    ("思考1", "thinkone", 30),
    ("思考2", "thinktwo", 30),
]

CONTENTS_TEMPLATE = {
    "images": [
        {"filename": None, "idiom": "universal", "scale": "1x"},
        {"idiom": "universal", "scale": "2x"},
        {"idiom": "universal", "scale": "3x"},
    ],
    "info": {"author": "xcode", "version": 1},
}


def frame_sort_key(name: str) -> int:
    m = re.search(r"(\d+)", name)
    return int(m.group(1)) if m else 0


def main() -> None:
    for folder, prefix, expected in JOBS:
        folder_path = ASSETS / folder
        if not folder_path.is_dir():
            print(f"Skip missing: {folder_path}", file=sys.stderr)
            continue

        frame_sets = sorted(
            [p for p in folder_path.iterdir() if p.is_dir() and p.name.startswith("frame_") and p.suffix == ".imageset"],
            key=lambda p: frame_sort_key(p.name),
        )
        if len(frame_sets) != expected:
            print(f"ERROR {folder}: expected {expected} frame imagesets, found {len(frame_sets)}", file=sys.stderr)
            sys.exit(1)

        tmp_root = folder_path / f".rebuild_{prefix}"
        if tmp_root.exists():
            shutil.rmtree(tmp_root)
        tmp_root.mkdir(parents=True)

        for i, old_set in enumerate(frame_sets):
            pngs = list(old_set.glob("*.png"))
            if len(pngs) != 1:
                print(f"ERROR {old_set}: expected 1 png, got {pngs}", file=sys.stderr)
                sys.exit(1)
            src_png = pngs[0]
            new_name = f"{prefix}{i}.imageset"
            new_set = tmp_root / new_name
            new_set.mkdir(parents=True)
            dst_png = new_set / f"{prefix}{i}.png"

            subprocess.run(
                ["sips", "--resampleWidth", "400", str(src_png), "--out", str(dst_png)],
                check=True,
                capture_output=True,
            )

            cj = json.loads(json.dumps(CONTENTS_TEMPLATE))
            cj["images"][0]["filename"] = dst_png.name
            (new_set / "Contents.json").write_text(json.dumps(cj, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

        # Remove old frame_* imagesets
        for old_set in frame_sets:
            shutil.rmtree(old_set)

        # Move new imagesets up
        for p in tmp_root.iterdir():
            shutil.move(str(p), str(folder_path / p.name))
        tmp_root.rmdir()
        print(f"OK {folder} -> {prefix}0..{prefix}{expected - 1} ({expected} frames)")


if __name__ == "__main__":
    main()
