# How To Convert Videos Into Watch Animations

This documents the exact workflow used to turn source videos into watch animation assets for BolaBola.

Use this when you have `.mp4` files and want:

- raw extracted frames in an external folder for inspection
- Xcode `Assets.xcassets` frame animations for the watch app

This matches the asset format used by the watch animation system described in:

- `Documentation/how_to_add_watch_animation_feature.md`
- `BolaBola Watch App/Pet/PetAnimation.swift`

## Output Format

Each watch animation lives in:

- `BolaBola Watch App/Assets.xcassets/<assetName>/`

Inside that folder:

- `Contents.json`
- one `.imageset` per frame

Example:

```text
BolaBola Watch App/Assets.xcassets/idledrink1/
  Contents.json
  idledrink10.imageset/
    idledrink10.png
    Contents.json
  idledrink11.imageset/
    idledrink11.png
    Contents.json
  ...
  idledrink129.imageset/
    idledrink129.png
    Contents.json
```

Important conventions:

- Asset prefix should be lowercase and compact, for example `drink`, `idledrink1`, `eatapple`
- Frames are zero-based inside the asset catalog: `drink0`, `drink1`, `drink2`, ...
- The watch app currently expects 30 frames for this workflow
- Images are generated at width `400` and proportional height via `scale=400:-2`

## Source Video Assumptions

For the drink animation work, the source videos were:

```text
~/documents/BolaWatchVideo/Drink/drink.mp4
~/documents/BolaWatchVideo/Drink/idledrink1.mp4
~/documents/BolaWatchVideo/Drink/idledrink2.mp4
```

Each video was about `4.041667` seconds long, and we sampled:

- `30` frames total
- evenly across the full clip

The extracted raw frames were written to:

```text
~/documents/BolaWatchVideo/DrinkFrames/
```

## One-Off Python Script

This is the exact Python script pattern used for the drink animations. You can copy it, change the input/output mapping, and run it again for new animations.

```python
import json
import shutil
import subprocess
from pathlib import Path

repo = Path('/Users/limingchendev/Documents/BolaWatch/BolaBola')
video_dir = Path.home() / 'documents' / 'BolaWatchVideo' / 'Drink'
frames_root = Path.home() / 'documents' / 'BolaWatchVideo' / 'DrinkFrames'
assets_root = repo / 'BolaBola Watch App' / 'Assets.xcassets'

videos = {
    'idledrink1.mp4': 'idledrink1',
    'idledrink2.mp4': 'idledrink2',
    'drink.mp4': 'drink',
}

fps = 30 / 4.041667

folder_contents = {'info': {'author': 'xcode', 'version': 1}}

def imageset_contents(filename: str):
    return {
        'images': [
            {'filename': filename, 'idiom': 'universal', 'scale': '1x'},
            {'idiom': 'universal', 'scale': '2x'},
            {'idiom': 'universal', 'scale': '3x'},
        ],
        'info': {'author': 'xcode', 'version': 1},
    }

frames_root.mkdir(parents=True, exist_ok=True)

for video_name, asset_name in videos.items():
    video_path = video_dir / video_name
    if not video_path.exists():
        raise SystemExit(f'missing video: {video_path}')

    out_frames_dir = frames_root / asset_name
    if out_frames_dir.exists():
        shutil.rmtree(out_frames_dir)
    out_frames_dir.mkdir(parents=True)

    subprocess.run([
        'ffmpeg', '-y', '-i', str(video_path),
        '-vf', f'fps={fps},scale=400:-2',
        '-frames:v', '30',
        '-pix_fmt', 'rgba',
        str(out_frames_dir / f'{asset_name}%d.png')
    ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    asset_group_dir = assets_root / asset_name
    if asset_group_dir.exists():
        shutil.rmtree(asset_group_dir)
    asset_group_dir.mkdir(parents=True)
    (asset_group_dir / 'Contents.json').write_text(json.dumps(folder_contents, indent=2) + '\n')

    for i in range(30):
        src = out_frames_dir / f'{asset_name}{i+1}.png'
        if not src.exists():
            raise SystemExit(f'missing extracted frame: {src}')
        frame_name = f'{asset_name}{i}'
        imageset_dir = asset_group_dir / f'{frame_name}.imageset'
        imageset_dir.mkdir(parents=True)
        dst_png = imageset_dir / f'{frame_name}.png'
        shutil.copy2(src, dst_png)
        (imageset_dir / 'Contents.json').write_text(json.dumps(imageset_contents(dst_png.name), indent=2) + '\n')

print('done')
```

## How To Run It Next Time

1. Put the source videos in a folder such as:

```text
~/documents/BolaWatchVideo/<FeatureName>/
```

2. Edit these values in the script:

- `video_dir`
- `frames_root`
- `videos`
- `fps` if duration changes

3. Run it from the repo root:

```bash
python3 your_script_name.py
```

Or paste it into:

```bash
python3
```

and run it from a temporary file or heredoc if needed.

## How To Compute FPS

If you want 30 evenly sampled frames across the whole video:

```text
fps = total_frames / duration_seconds
```

For example:

```text
30 / 4.041667 = 7.422679...
```

You can inspect duration with:

```bash
ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 path/to/video.mp4
```

## Hooking The New Assets Into The Watch App

After conversion, wire the asset names into the watch animation system:

1. Add new `PetEmotion` cases in `BolaBola Watch App/Pet/PetAnimation.swift`
2. Add `AnimationScale` entries
3. Add `PetAnimations` entries using the exact frame prefix
4. Map them in `BolaBola Watch App/Views/ContentView.swift`
5. Add the feature state machine and tap/completion handling
6. Optionally add a debug button in `BolaBola Watch App/Views/WatchDrawerAndChrome.swift`

For the drink feature, the mapping was:

- `idledrink1.mp4` -> asset prefix `idledrink1`
- `idledrink2.mp4` -> asset prefix `idledrink2`
- `drink.mp4` -> asset prefix `drink`

## Verification

Useful checks:

```bash
find 'BolaBola Watch App/Assets.xcassets/idledrink1' -maxdepth 1 -type d | wc -l
find ~/documents/BolaWatchVideo/DrinkFrames/idledrink1 -maxdepth 1 -type f | wc -l
```

Expected for this workflow:

- asset folder count: `31` because it includes the root folder plus `30` frame `.imageset` folders
- raw frame file count: `30`

Compile-only watch build:

```bash
xcodebuild build -scheme 'BolaBola Watch App' -destination 'generic/platform=watchOS' -derivedDataPath /tmp/BolaBolaDerivedDrink CODE_SIGNING_ALLOWED=NO
```

That is enough to verify:

- Swift compiles
- assets compile
- animation names are valid

It does not produce a signed app for device installation.
