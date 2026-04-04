#!/usr/bin/env python3
"""
Convert videos from ~/documents/BolaWatchVideo into Xcode asset catalog format
for the BolaBola Watch App.

Output: 400×283 px, 30 frames per video, as .imageset folders under Assets.xcassets.
"""

import json
import os
import subprocess
import sys

# Config
VIDEO_DIR = os.path.expanduser("~/documents/BolaWatchVideo")
ASSETS_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "BolaBola Watch App", "Assets.xcassets"
)

VIDEOS = {
    "BolaEatApple.mp4": "eatapple",
    "BolaAppleIdle.mp4": "idleapple",
}

WIDTH = 400
HEIGHT = -1  # keep aspect ratio; ffmpeg will compute automatically
TOTAL_FRAMES = 30


def make_imageset_contents(filename: str) -> dict:
    return {
        "images": [
            {"filename": filename, "idiom": "universal", "scale": "1x"},
            {"idiom": "universal", "scale": "2x"},
            {"idiom": "universal", "scale": "3x"},
        ],
        "info": {"author": "xcode", "version": 1},
    }


def make_folder_contents() -> dict:
    return {"info": {"author": "xcode", "version": 1}}


def convert_video(video_path: str, asset_name: str):
    group_dir = os.path.join(ASSETS_DIR, asset_name)
    os.makedirs(group_dir, exist_ok=True)

    # Write group Contents.json
    with open(os.path.join(group_dir, "Contents.json"), "w") as f:
        json.dump(make_folder_contents(), f, indent=2)
        f.write("\n")

    # Use ffmpeg to extract exactly 30 frames, scaled to 400x283
    # First, get video duration to calculate frame interval
    probe = subprocess.run(
        [
            "ffprobe", "-v", "error",
            "-select_streams", "v:0",
            "-show_entries", "stream=nb_frames,duration",
            "-of", "csv=p=0",
            video_path,
        ],
        capture_output=True, text=True,
    )
    print(f"  ffprobe output: {probe.stdout.strip()}")

    # Extract 30 evenly-spaced frames using fps filter based on duration
    # Get duration via format
    dur_probe = subprocess.run(
        [
            "ffprobe", "-v", "error",
            "-show_entries", "format=duration",
            "-of", "csv=p=0",
            video_path,
        ],
        capture_output=True, text=True,
    )
    duration = float(dur_probe.stdout.strip())
    fps = TOTAL_FRAMES / duration
    print(f"  duration={duration:.2f}s, extracting at fps={fps:.4f}")

    # Extract frames to a temp location, then move into imagesets
    tmp_dir = os.path.join(group_dir, "_tmp_frames")
    os.makedirs(tmp_dir, exist_ok=True)

    cmd = [
        "ffmpeg", "-y",
        "-i", video_path,
        "-vf", f"fps={fps},scale={WIDTH}:-2",
        "-frames:v", str(TOTAL_FRAMES),
        "-pix_fmt", "rgba",
        os.path.join(tmp_dir, f"{asset_name}%d.png"),
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"  ffmpeg error: {result.stderr}")
        sys.exit(1)

    # ffmpeg numbers from 1; create imagesets numbered from 0
    for i in range(TOTAL_FRAMES):
        src = os.path.join(tmp_dir, f"{asset_name}{i + 1}.png")
        if not os.path.exists(src):
            print(f"  WARNING: missing frame {src}")
            continue

        frame_name = f"{asset_name}{i}"
        png_name = f"{frame_name}.png"
        imageset_dir = os.path.join(group_dir, f"{frame_name}.imageset")
        os.makedirs(imageset_dir, exist_ok=True)

        os.rename(src, os.path.join(imageset_dir, png_name))

        with open(os.path.join(imageset_dir, "Contents.json"), "w") as f:
            json.dump(make_imageset_contents(png_name), f, indent=2)
            f.write("\n")

    # Cleanup temp dir
    os.rmdir(tmp_dir)
    print(f"  Created {TOTAL_FRAMES} imagesets in {group_dir}")


def main():
    for video_file, asset_name in VIDEOS.items():
        video_path = os.path.join(VIDEO_DIR, video_file)
        if not os.path.exists(video_path):
            print(f"ERROR: {video_path} not found")
            sys.exit(1)
        print(f"Converting {video_file} -> {asset_name}")
        convert_video(video_path, asset_name)
    print("Done!")


if __name__ == "__main__":
    main()
