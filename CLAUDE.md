# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

BolaBola is a digital pet companion app — an iOS app paired with a watchOS app. The watch is the primary UX (animated pet "Bola" that reacts to health, voice, taps), and the iPhone companion provides analytics, settings, and LLM configuration.

**Targets:** BolaBola (iOS 17+), BolaBola Watch App (watchOS 10+)  
**Language:** Swift 6, SwiftUI  
**Dependencies:** Managed via Swift Package Manager (Firebase Analytics only; no other external frameworks)

## Build Commands

All building is done through Xcode. There are no automated test targets or CI scripts.

```bash
# Build iOS app
xcodebuild build -scheme BolaBola -destination "generic/platform=iOS"

# Build Watch app
xcodebuild build -scheme "BolaBola Watch App" -destination "generic/platform=watchOS"

# Process watch animation frames (when adding new sprite sheets)
python3 Scripts/process_watch_animations.py
```

No linters or formatters are configured.

## Architecture

### Folder Layout

```
BolaBola iOS/          iPhone companion (settings, analytics, LLM chat)
BolaBola Watch App/    watchOS pet UI (primary UX)
Shared/                Cross-platform code used by both targets
Documentation/         Design specs, PRD, state machine rules
```

### Shared/ — The Core Layer

All business logic lives in `Shared/` and is compiled into both targets:

- **`Sync/BolaWCSessionCoordinator`** — Singleton managing all iPhone↔Watch communication via `WCSession`. Uses `updateApplicationContext` for companion value (latest-wins) and `transferUserInfo` for ordered chat deltas and LLM config pulls.
- **`LLM/LLMClient`** — OpenAI-compatible HTTP client + Zhipu (`open.bigmodel.cn`) ASR for watch voice transcription. Loads credentials from Keychain; falls back to `LocalLLMDevSecrets.swift` (dev-only, should stay empty at commit time).
- **`LLM/ConversationService`** — Wraps `LLMClient` with the companion system prompt, adapted per `CompanionTier`.
- **`Defaults/BolaSharedDefaults`** — Unified `UserDefaults` access: tries App Group (`group.com.gathxr.BolaBola`) first, falls back to `.standard` (Personal Team provisioning breaks App Groups).
- **`Defaults/KeychainHelper`** — LLM API key + base URL storage; also the sync source for watch pulling credentials from iPhone.
- **`Companion/CompanionTier`** — Maps companion value (0–100 Double) to relationship tier, used in system prompts and animation selection.
- **`Reminders/ReminderListStore`** — JSON-persisted user reminders.
- **`Digest/DailyDigestUNScheduler`** — Schedules 9 AM local notification with health summary.

### Watch App — Pet State Machine

`PetViewModel` (in `BolaBola Watch App/Views/ContentView.swift`) is the central `ObservableObject` for the watch UI. It manages:

- Pet emotion state (idle, happy, angry, sleepy, …) mapped to sequential frame animations (`PetAnimation.swift`)
- Companion value delta accumulation and 5-minute sync ticks to iPhone via `BolaWCSessionCoordinator`
- Dialogue triggering and throttling (see `BolaDialogueLines.swift` and `/BolaBola Watch App/Documentation/bola_dialogue_rules.md`)
- Voice recording → `WatchSpeechRelay` → iPhone ASR (45-second timeout) → LLM reply → dialogue

### iOS App — Tab Structure

`IOSRootView.swift` hosts three tabs: Analysis (HealthKit charts), Home (pet mirror + reminders), Chat (LLM conversation). `IOSAppDelegate` initializes Firebase and `UNUserNotificationCenter`. `IOSNotificationRouter.shared` bridges notification taps to the active tab.

## Key Design Decisions & Gotchas

**App Group reliability:** App Group entitlements require a paid developer account. With a Personal Team, `BolaSharedDefaults` silently falls back to `UserDefaults.standard`, which breaks iPhone↔Watch shared defaults. See `Documentation/app_group_removal_and_restore.md` for history.

**WatchConnectivity timing:** `updateApplicationContext` is used for companion value (latest-wins, no queue). Chat turns use `transferUserInfo` (FIFO, survives app suspension). LLM config is pulled by the watch on demand via a `requestSync: "llmKeychain"` message — the push path is unreliable.

**Firebase on watchOS:** Firebase Analytics SDK is binary-incompatible with watchOS. Firebase is iOS-only (`IOSAppDelegate`). Do not add Firebase imports to Watch or Shared targets.

**Swift 6 concurrency:** `LLMClient`, `LLMModels`, and sync payloads are marked `Sendable`. When adding async code that crosses actor boundaries, maintain `Sendable` conformance and avoid data races.

**LocalLLMDevSecrets:** `Shared/LLM/LocalLLMDevSecrets.swift` is a dev-only credential fallback. Keep it empty (no real keys) at commit time.

**Animation assets:** Watch sprite sheets live in `BolaBola Watch App/Animations/` and `Assets.xcassets`. They are sequential PNG frames processed by `Scripts/process_watch_animations.py`. See `BolaBola Watch App/Documentation/animation_list.md` for the full inventory.

## Documentation References

The `Documentation/` and `BolaBola Watch App/Documentation/` folders contain the authoritative design specs:

- `Documentation/项目状态与后续工作_2026-03.md` — Current project status, known issues, and priority roadmap
- `Documentation/design_core.md` — Design tokens (colors, spacing, typography)
- `BolaBola Watch App/Documentation/companion_value_rules.md` — Scoring rules (±1 per interaction, penalties)
- `BolaBola Watch App/Documentation/state_machine_list.md` — Pet emotion states and their default animations
- `BolaBola Watch App/Documentation/bola_dialogue_rules.md` — Dialogue pool triggers and throttling rules
- `BolaBola Watch App/Documentation/tap_interaction_rules.md` — Tap combos and anger mechanics
