# How to Add a Watch Animation Feature

Guide for adding new animation-driven features (like "Eating") to the BolaBola Watch App.

## Overview

Adding an animation feature involves 4 files:

| File | What to add |
|------|-------------|
| `BolaBola Watch App/Pet/PetAnimation.swift` | Emotion cases, scale values, animation configs |
| `BolaBola Watch App/Views/ContentView.swift` | State logic, tap handling, animation mapping |
| `BolaBola Watch App/Pet/BolaDialogueLines.swift` | Dialogue text pools (optional) |
| `BolaBola Watch App/Views/WatchDrawerAndChrome.swift` | Debug button (optional) |

## Step 1: Add Assets

Place animation frames in `BolaBola Watch App/Assets.xcassets/<folderName>/`.

Each folder contains:
- `Contents.json` (standard Xcode folder marker)
- `<prefix><N>.imageset/` for each frame (N = 0, 1, 2, ...)

Each `.imageset/` contains:
- The PNG file (`<prefix><N>.png`)
- `Contents.json` referencing that file at 1x scale

Use `Scripts/convert_videos_to_assets.py` as reference for converting videos to this format.

**Naming convention**: asset prefix is all lowercase, no separators (e.g., `eatapple`, `idleapple`, `happyone`, `liketwo`).

## Step 2: PetAnimation.swift

### 2a. Add `PetEmotion` cases (~line 16)

```swift
enum PetEmotion {
    // ... existing cases ...
    case myFeatureWait    // looping state
    case myFeatureOnce    // play-once state
}
```

### 2b. Add `AnimationScale` values (~line 98)

```swift
enum AnimationScale {
    // ... existing ...
    static let myFeatureWait: CGFloat = 1.5
    static let myFeatureOnce: CGFloat = 1.5
}
```

Most animations use `1.5`. Adjust if the art needs different scaling on the watch face.

### 2c. Add `PetAnimations` configs (~line 226)

```swift
enum PetAnimations {
    // ... existing ...

    // Looping animation
    static let myFeatureWait: PetAnimation = PetAnimation(
        emotion: .myFeatureWait,
        displayScale: AnimationScale.myFeatureWait,
        source: .frames(
            frameNames: PetAnimationLoader.loadFrameNames(
                prefix: "assetprefix",      // must match asset folder naming
                maxFrames: 30,              // number of frames
                maxUniqueFrames: AnimationLimits.maxUniqueFrames
            ),
            fps: effectiveFPS(baseFPS: 8, maxFrames: 30),
            isLoop: true                    // true = loops, false = plays once
        )
    )

    // Play-once animation
    static let myFeatureOnce: PetAnimation = PetAnimation(
        emotion: .myFeatureOnce,
        displayScale: AnimationScale.myFeatureOnce,
        source: .frames(
            frameNames: PetAnimationLoader.loadFrameNames(
                prefix: "anotherasset",
                maxFrames: 30,
                maxUniqueFrames: AnimationLimits.maxUniqueFrames
            ),
            fps: effectiveFPS(baseFPS: 8, maxFrames: 30),
            isLoop: false
        )
    )
}
```

**Common FPS values**: idle = 7, most emotions = 8, jumps = 10.

## Step 3: ContentView.swift (PetViewModel)

### 3a. Add to `currentAnimation` switch (~line 306)

Every `PetEmotion` case **must** have a mapping here, or the app won't compile:

```swift
var currentAnimation: PetAnimation {
    switch currentEmotion {
    // ... existing cases ...
    case .myFeatureWait:
        return PetAnimations.myFeatureWait
    case .myFeatureOnce:
        return PetAnimations.myFeatureOnce
    }
}
```

### 3b. Add state tracking property

```swift
private(set) var isInMyFeatureState: Bool = false
```

### 3c. Add entry/trigger method

```swift
func enterMyFeatureState() {
    isInMyFeatureState = true
    isTapInteractionAnimating = true   // blocks normal tap handling
    currentEmotion = .myFeatureWait
    currentFrameIndex = 0
    showDialogue("waiting text", duration: 120)
}
```

### 3d. Handle tap during the feature state

Add at the **top** of `cycleEmotionOnTap()`, before the `die` check:

```swift
func cycleEmotionOnTap() {
    if isInMyFeatureState && currentEmotion == .myFeatureWait {
        // transition from waiting to action
        currentEmotion = .myFeatureOnce
        currentFrameIndex = 0
        dialogueDismissWorkItem?.cancel()
        dialogueLine = ""
        return
    }
    // ... rest of existing tap logic ...
}
```

### 3e. Handle play-once completion in `advanceFrame()`

In the `advanceFrame()` method, inside the `if next >= frameCount` / `if !isLoop` block, add your case **before** the `tapChainReturnsToRandomIdle` check:

```swift
if currentEmotion == .myFeatureOnce {
    finishMyFeatureAnimation()
    return
}
if tapChainReturnsToRandomIdle {
    // ... existing code ...
```

### 3f. Add finish method

```swift
private func finishMyFeatureAnimation() {
    // Play a follow-up animation (e.g., random happy)
    let happyEmotion: PetEmotion = [.happyIdle, .like1, .like2].randomElement() ?? .happyIdle
    currentEmotion = happyEmotion
    currentFrameIndex = 0
    showDialogue("completion text", duration: 5)

    // Return to default state after delay
    DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
        guard let self, self.isInMyFeatureState else { return }
        self.isInMyFeatureState = false
        self.isTapInteractionAnimating = false
        self.selectDefaultEmotion()
        self.applyDefaultEmotionDisplay()
        self.currentFrameIndex = 0
    }
}
```

### 3g. (Optional) Add to debug cycle list

In `tapCycleEmotions` array (~line 111), add the looping variant for tap-cycling in debug:

```swift
private let tapCycleEmotions: [PetEmotion] = [
    // ... existing ...
    .myFeatureWait
]
```

## Step 4: Debug Button (WatchDrawerAndChrome.swift)

Add a button in `WatchPanelSheetView` body, inside the `ScrollView > VStack`:

```swift
Button {
    viewModel.enterMyFeatureState()
    dismiss()
} label: {
    HStack {
        Image(systemName: "fork.knife")   // pick an SF Symbol
            .font(.caption2)
        Text("Debug Label")
            .font(.caption2.weight(.semibold))
    }
    .frame(maxWidth: .infinity, minHeight: 32)
}
.buttonStyle(.bordered)
.controlSize(.mini)
```

## Step 5: Dialogue (BolaDialogueLines.swift, optional)

If the feature needs randomized dialogue pools:

```swift
enum BolaDialogueLines {
    // ... existing ...

    static let myFeatureLines: [String] = [
        "Line 1", "Line 2", "Line 3"
    ]

    static func myFeatureLine() -> String {
        myFeatureLines.randomElement() ?? "Fallback"
    }
}
```

Then call `showDialogue(BolaDialogueLines.myFeatureLine())` from the ViewModel.

## Key Patterns to Remember

- **Looping animations** (`isLoop: true`): run forever until code changes `currentEmotion`
- **Play-once animations** (`isLoop: false`): trigger completion logic in `advanceFrame()` when last frame is reached
- **`isTapInteractionAnimating = true`**: blocks normal tap cycle; set to `false` when your feature ends
- **`currentFrameIndex = 0`**: must be reset whenever switching `currentEmotion`
- **`selectDefaultEmotion()` + `applyDefaultEmotionDisplay()`**: standard return-to-normal pattern
- **Transition chain**: waiting (loop) -> action (once) -> follow-up (existing loop) -> return to default
