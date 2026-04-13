# Transparent Background Animation Replacement (2026-04)

All watch animation assets have been replaced with transparent-background (alpha channel) versions. This document records what was done, the folder-to-animation mapping, the "not ready" list, and how to continue the work when more transparent versions become available.

## What Changed

Previously, every animation frame had a solid (non-transparent) background. The new frames come from pre-rendered video exports with the background keyed out, saved to:

```
~/documents/BolaWatchVideo/DONE/<animation>_transBGFrames/
```

The replacement script:

1. **Backed up** original PNG frames to `Scripts/animation_originals/<prefix>/`
2. **Sampled** 30 evenly-spaced frames from each source folder (sources had 121–145 frames each)
3. **Resized** each frame to **400 px wide** (proportional height, alpha preserved) using `sips`
4. **Wrote** new imagesets into the existing `Assets.xcassets` folder with the same asset prefix, overwriting the old non-transparent frames

`PetAnimation.swift` was updated to set `maxFrames: 30` for all replaced animations and to point "not ready" animations at their transparent fallbacks.

## Replaced Animations (29 total)

| Source folder | xcassets folder | Asset prefix |
|---|---|---|
| `blowbubble1_transBGFrames` | `blowbubble1` | `blowbubbleone` |
| `blowbubble2_transBGFrames` | `blowbubble2` | `blowbubbletwo` |
| `happy1_transBGFrames` | `happy1` | `happyone` |
| `happyfly_transBGFrames` | `开心晃悠` | `happyidle` |
| `idle4_transBGFrames` | `idle4` | `idlefour` |
| `idle5_transBGFrames` | `idle5` | `idlefive` |
| `idle6_transBGFrames` | `idle6` | `idlesix` |
| `idleone_transBGFrames` | `idleone` | `idleone` |
| `idlethree_transBGFrames` | `idlethree` | `idlethree` |
| `idletwo_transBGFrames` | `idletwo` | `idletwo` |
| `jump1_transBGFrames` | `jump1` | `jumpone` |
| `jump2_transBGFrames` | `跳跃2` | `jumptwo` |
| `letter_transBGFrames` | `信件` | `letter` |
| `like1_transBGFrames` | `like1` | `likeone` |
| `like2_transBGFrames` | `like2` | `liketwo` |
| `question1_transBGFrames` | `question1` | `questionone` |
| `question2_transBGFrames` | `question2` | `questiontwo` |
| `sad1_transBGFrames` | `sad1` | `sadone` |
| `sad2_transBGFrames` | `sad2` | `sadtwo` |
| `scale_transBGFrames` | `scale` | `scale` |
| `sleepy_transBGFrames` | `sleepy` | `sleepy` |
| `speak1_transBGFrames` | `speak1` | `speakone` |
| `speak2_transBGFrames` | `speak2` | `speaktwo` |
| `speak3_transBGFrames` | `speak3` | `speakthree` |
| `Surprise1_transBGFrames` | `惊喜1` | `surprisedone` |
| `think2_transBGFrames` | `思考2` | `thinktwo` |
| `unhappy1_transBGFrames` | `不高兴` | `unhappy` |
| `unhappy2_transBGFrames` | `不开心2` | `unhappytwo` |
| `upset_transBGFrames` | `委屈` | `hurt` |

## Not-Ready List

These animations have no transparent version yet. Each uses the nearest transparent animation as a fallback. When a transparent version becomes available, update `PetAnimations` in `PetAnimation.swift`: change the `prefix` back to the original and set `maxFrames: 30`.

| PetEmotion(s) | Original prefix | Current fallback prefix | Restore to |
|---|---|---|---|
| `.idle`, `.shakeOnce` | `shake` | `idleone` | `shake` |
| `.angry2`, `.angry2Once` | `angrytwo` | `unhappytwo` | `angrytwo` |
| `.thinkOne` | `thinkone` | `thinktwo` | `thinkone` |
| `.question3` | `questionthree` | `questionone` | `questionthree` |
| `.surprisedTwo` | `surprisetwo` | `surprisedone` | `surprisetwo` |
| `.eatingWait` | `idleapple` | `idleone` | `idleapple` |
| `.idleDrink1` | `idledrink1` | `idleone` | `idledrink1` |
| `.idleDrink2` | `idledrink2` | `idletwo` | `idledrink2` |

These animations have no suitable fallback and continue using their original non-transparent assets:

| PetEmotion | Prefix | Notes |
|---|---|---|
| `.die` | `die` | No equivalent transparent animation |
| `.fallAsleep` | `fallasleep` | Brief transition; acceptable as-is |
| `.sleepLoop` | `sleeploop` | Night sleep loop; acceptable as-is |
| `.drinkOnce` | `drink` | No equivalent transparent animation |

## Backup Location

Original (non-transparent) PNG frames are saved at:

```
Scripts/animation_originals/<prefix>/
```

for example:

```
Scripts/animation_originals/idleone/idleone0.png … idleone30.png
Scripts/animation_originals/surprisedone/surprisedone0.png … surprisedone30.png
```

These are raw PNGs, not imageset folders. They are not compiled into the app.

## Script

The replacement was performed by:

```
Scripts/replace_transparent_animations.py
```

Run from the repo root:

```bash
python3 Scripts/replace_transparent_animations.py
```

The script is idempotent — running it again will back up whatever is currently in the imageset folders and replace with fresh transparent frames from `~/documents/BolaWatchVideo/DONE`.

## How To Add a New Transparent Animation

When a transparent version of a "not ready" animation (e.g. `shake`) becomes available:

1. Place the rendered frames (PNG sequence, any count) in:
   ```
   ~/documents/BolaWatchVideo/DONE/shake_transBGFrames/
   ```

2. Add an entry to `JOBS` in `Scripts/replace_transparent_animations.py`:
   ```python
   ("shake_transBGFrames", "shake", "shake"),
   ```
   The second value is the xcassets folder name; the third is the asset prefix.

3. Run the script:
   ```bash
   python3 Scripts/replace_transparent_animations.py
   ```

4. In `PetAnimation.swift`, find the "not ready" entry and change the prefix back:
   ```swift
   // before
   frameNames: PetAnimationLoader.loadFrameNames(prefix: "idleone", maxFrames: 30, ...)
   // after
   frameNames: PetAnimationLoader.loadFrameNames(prefix: "shake", maxFrames: 30, ...)
   ```
   Remove it from the not-ready comment block.

## Asset Format Reference

Each animation lives in `BolaBola Watch App/Assets.xcassets/<folder>/`:

```
idleone/
  Contents.json                     ← folder-level ({"info":{"author":"xcode","version":1}})
  idleone0.imageset/
    Contents.json                   ← references idleone0.png at universal 1x
    idleone0.png                    ← 400 × 281 px RGBA PNG
  idleone1.imageset/
    …
  idleone29.imageset/
    …
```

Frame naming: `<prefix><index>` where index is zero-based (0–29).

`PetAnimationLoader.loadFrameNames(prefix:maxFrames:)` generates the name list `prefix0 … prefix(maxFrames-1)` at compile time; no file-system scanning is needed.

## Verification

After running the script, verify with:

```bash
# Frame count per folder
ls "BolaBola Watch App/Assets.xcassets/idleone/" | grep -c ".imageset"
# Expected: 30

# Alpha channel present
sips -g hasAlpha "BolaBola Watch App/Assets.xcassets/idleone/idleone0.imageset/idleone0.png"
# Expected: hasAlpha: yes

# Dimensions
sips -g pixelWidth -g pixelHeight "BolaBola Watch App/Assets.xcassets/idleone/idleone0.imageset/idleone0.png"
# Expected: pixelWidth: 400
```

Build check (no device signing needed):

```bash
xcodebuild build \
  -scheme "BolaBola Watch App" \
  -destination "generic/platform=watchOS" \
  CODE_SIGNING_ALLOWED=NO
```
