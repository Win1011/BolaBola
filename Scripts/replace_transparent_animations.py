#!/usr/bin/env python3
"""
Replace watch animation assets with transparent-background versions.

For each animation in JOBS:
  1. Back up original PNG frames to Scripts/animation_originals/<prefix>/
  2. Evenly sample TARGET_FRAMES frames from the source folder
  3. Resize each to TARGET_WIDTH px wide (proportional height, alpha preserved)
  4. Write new imagesets into Assets.xcassets, overwriting the old ones

Run from repo root:
    python3 Scripts/replace_transparent_animations.py
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
DONE_DIR = Path.home() / "documents" / "BolaWatchVideo" / "DONE"
BACKUP_DIR = REPO / "Scripts" / "animation_originals"

TARGET_FRAMES = 90
TARGET_WIDTH   = 400

# (done_folder_name, xcassets_folder_name, asset_prefix)
JOBS: list[tuple[str, str, str]] = [
    ("blowbubble1_transBGFrames", "blowbubble1",  "blowbubbleone"),
    ("blowbubble2_transBGFrames", "blowbubble2",  "blowbubbletwo"),
    ("happy1_transBGFrames",      "happy1",        "happyone"),
    ("happyfly_transBGFrames",    "开心晃悠",       "happyidle"),
    ("idle4_transBGFrames",       "idle4",          "idlefour"),
    ("idle5_transBGFrames",       "idle5",          "idlefive"),
    ("idle6_transBGFrames",       "idle6",          "idlesix"),
    ("idleone_transBGFrames",     "idleone",        "idleone"),
    ("idlethree_transBGFrames",   "idlethree",      "idlethree"),
    ("idletwo_transBGFrames",     "idletwo",        "idletwo"),
    ("jump1_transBGFrames",       "jump1",          "jumpone"),
    ("jump2_transBGFrames",       "跳跃2",           "jumptwo"),
    ("letter_transBGFrames",      "信件",            "letter"),
    ("like1_transBGFrames",       "like1",          "likeone"),
    ("like2_transBGFrames",       "like2",          "liketwo"),
    ("question1_transBGFrames",   "question1",      "questionone"),
    ("question2_transBGFrames",   "question2",      "questiontwo"),
    ("sad1_transBGFrames",        "sad1",           "sadone"),
    ("sad2_transBGFrames",        "sad2",           "sadtwo"),
    ("scale_transBGFrames",       "scale",          "scale"),
    ("sleepy_transBGFrames",      "sleepy",         "sleepy"),
    ("speak1_transBGFrames",      "speak1",         "speakone"),
    ("speak2_transBGFrames",      "speak2",         "speaktwo"),
    ("speak3_transBGFrames",      "speak3",         "speakthree"),
    ("Surprise1_transBGFrames",   "惊喜1",           "surprisedone"),
    ("think2_transBGFrames",      "思考2",           "thinktwo"),
    ("unhappy1_transBGFrames",    "不高兴",           "unhappy"),
    ("unhappy2_transBGFrames",    "不开心2",          "unhappytwo"),
    ("upset_transBGFrames",       "委屈",            "hurt"),
]

FOLDER_CONTENTS_JSON = {"info": {"author": "xcode", "version": 1}}

IMAGESET_CONTENTS_TEMPLATE = {
    "images": [
        {"filename": None, "idiom": "universal", "scale": "1x"},
        {"idiom": "universal", "scale": "2x"},
        {"idiom": "universal", "scale": "3x"},
    ],
    "info": {"author": "xcode", "version": 1},
}


def frame_sort_key(p: Path) -> int:
    m = re.search(r"(\d+)", p.stem)
    return int(m.group(1)) if m else 0


def sample_frames(paths: list[Path], n: int) -> list[Path]:
    """Select n evenly-spaced frames from paths."""
    if len(paths) <= n:
        return paths[:]
    step = len(paths) / n
    return [paths[round(i * step)] for i in range(n)]


def backup_existing(xcassets_folder: Path, prefix: str) -> None:
    """Copy original PNGs from every imageset into BACKUP_DIR/<prefix>/."""
    backup = BACKUP_DIR / prefix
    backup.mkdir(parents=True, exist_ok=True)
    imagesets = sorted(
        [p for p in xcassets_folder.iterdir() if p.is_dir() and p.suffix == ".imageset"],
        key=frame_sort_key,
    )
    copied = 0
    for iset in imagesets:
        for png in iset.glob("*.png"):
            dst = backup / png.name
            if not dst.exists():
                shutil.copy2(png, dst)
                copied += 1
    print(f"    Backed up {copied} PNGs → {backup.relative_to(REPO)}")


def clear_imagesets(xcassets_folder: Path) -> None:
    """Remove all .imageset directories from the given folder."""
    removed = 0
    for p in list(xcassets_folder.iterdir()):
        if p.is_dir() and p.suffix == ".imageset":
            shutil.rmtree(p)
            removed += 1
    print(f"    Removed {removed} old imagesets")


def resize_png(src: Path, dst: Path, width: int) -> None:
    """Resize src PNG to given width, writing to dst. Alpha is preserved."""
    subprocess.run(
        ["sips", "--resampleWidth", str(width), str(src), "--out", str(dst)],
        check=True,
        capture_output=True,
    )


def process_job(done_folder: str, xcassets_name: str, prefix: str) -> bool:
    src_dir     = DONE_DIR / done_folder
    dst_folder  = ASSETS / xcassets_name

    if not src_dir.is_dir():
        print(f"  [SKIP] source missing: {src_dir}", file=sys.stderr)
        return False
    if not dst_folder.is_dir():
        print(f"  [SKIP] xcassets folder missing: {dst_folder}", file=sys.stderr)
        return False

    # Collect source frames
    src_frames = sorted(
        [p for p in src_dir.iterdir() if p.suffix.lower() == ".png"],
        key=frame_sort_key,
    )
    if not src_frames:
        print(f"  [ERROR] no PNG frames in {src_dir}", file=sys.stderr)
        return False

    print(f"  {len(src_frames)} source frames → sample {TARGET_FRAMES} → {prefix}0..{prefix}{TARGET_FRAMES-1}")

    # 1. Backup
    backup_existing(dst_folder, prefix)

    # 2. Remove old imagesets
    clear_imagesets(dst_folder)

    # 3. Ensure folder-level Contents.json
    folder_json = dst_folder / "Contents.json"
    if not folder_json.exists():
        folder_json.write_text(
            json.dumps(FOLDER_CONTENTS_JSON, indent=2) + "\n", encoding="utf-8"
        )

    # 4. Sample + resize + write imagesets
    selected = sample_frames(src_frames, TARGET_FRAMES)
    for i, src_png in enumerate(selected):
        new_name  = f"{prefix}{i}"
        iset_dir  = dst_folder / f"{new_name}.imageset"
        iset_dir.mkdir(parents=True)
        dst_png   = iset_dir / f"{new_name}.png"

        resize_png(src_png, dst_png, TARGET_WIDTH)

        cj = json.loads(json.dumps(IMAGESET_CONTENTS_TEMPLATE))
        cj["images"][0]["filename"] = dst_png.name
        (iset_dir / "Contents.json").write_text(
            json.dumps(cj, indent=2) + "\n", encoding="utf-8"
        )

    print(f"    Written {TARGET_FRAMES} transparent imagesets ✓")
    return True


def main() -> None:
    if not DONE_DIR.is_dir():
        print(f"ERROR: DONE_DIR not found: {DONE_DIR}", file=sys.stderr)
        sys.exit(1)

    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    ok = fail = 0

    for done_folder, xcassets_name, prefix in JOBS:
        print(f"\n[{prefix}]  {done_folder}")
        if process_job(done_folder, xcassets_name, prefix):
            ok += 1
        else:
            fail += 1

    print(f"\n{'='*50}")
    print(f"Done: {ok} replaced, {fail} skipped/failed")
    print(f"Originals saved in: {BACKUP_DIR.relative_to(REPO)}")


if __name__ == "__main__":
    main()
