# Agent Instructions

## Build
Use Xcode only. No automated test/lint/typecheck targets.

```bash
# Build iOS
xcodebuild build -scheme BolaBola -destination "generic/platform=iOS"

# Build Watch
xcodebuild build -scheme "BolaBola Watch App" -destination "generic/platform=watchOS"

# Process new watch animation sprite sheets
python3 Scripts/process_watch_animations.py
```

## Architecture

**Targets**: BolaBola (iOS 17+), BolaBola Watch App (watchOS 10+), Shared (code compiled into both)

**Key files**:
- `BolaBola iOS/App/IOSRootView.swift` - iOS entry, tab structure
- `BolaBola Watch App/Views/ContentView.swift` - Watch entry, PetViewModel (pet state machine)
- `Shared/Sync/BolaWCSessionCoordinator.swift` - iPhone↔Watch WC singleton
- `Shared/LLM/LLMClient.swift` - OpenAI-compatible HTTP client + Zhipu ASR
- `Shared/Defaults/BolaSharedDefaults.swift` - UserDefaults with App Group fallback

## Important Gotchas

**App Group**: `group.com.gathxr.BolaBola` requires paid dev account. With Personal Team, `BolaSharedDefaults.resolved()` silently falls back to `UserDefaults.standard` (no sharing). Search `RESTORE_APP_GROUP_WHEN_PAID_DEV` for related comments.

**Firebase**: Binary-incompatible with watchOS. Only iOS links Firebase (initialized in `IOSNotificationRouter.swift`/`IOSAppDelegate`). Never add Firebase imports to Watch/Shared targets.

**WC sync patterns**:
- `updateApplicationContext` → companion value (latest-wins, no queue)
- `transferUserInfo` → chat deltas, LLM config pull (FIFO, survives app suspension)

**LocalLLMDevSecrets**: Dev-only credential fallback in `Shared/LLM/LocalLLMDevSecrets.swift`. Keep `apiKey` empty at commit time.

**Swift 6**: `LLMClient`, `LLMModels`, and sync payloads are `Sendable`. Maintain `Sendable` conformance when adding async code crossing actor boundaries.

**Watch animations**: Sprite sheets in `BolaBola Watch App/Animations/` and `Assets.xcassets`. See `BolaBola Watch App/Documentation/animation_list.md` for inventory.
