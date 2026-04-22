# PROJECT KNOWLEDGE BASE

**Generated:** 2026-04-22
**Commit:** 0ede300d
**Branch:** main

## OVERVIEW

Digital pet companion app — watchOS pet "Bola" reacts to health/voice/taps; iOS companion provides analytics, settings, LLM chat. Swift 6 / SwiftUI, SPM (FirebaseCore only).

## STRUCTURE

```
BolaBola/
├── BolaBola iOS/          # iPhone companion (iOS 17+)
├── BolaBola Watch App/    # watchOS pet UI (watchOS 10+) — PRIMARY UX
├── BolaBola Watch Widget/  # WidgetKit complication
├── Shared/                # Cross-target business logic (compiled into all 3)
├── Documentation/         # Design specs, PRD, state machine rules
├── Scripts/               # Animation processing, SPM resolution
└── Entitlements/          # App Group, HealthKit, WCSession
```

## WHERE TO LOOK

| Task | Location | Notes |
|------|----------|-------|
| iPhone↔Watch sync | `Shared/Sync/BolaWCSessionCoordinator.swift` | 1208-line WC singleton; heavy `#if os()` branching |
| Pet emotion state machine | `BolaBola Watch App/Views/ContentView.swift` | `PetViewModel` — 1862 lines, central ObservableObject |
| Animation mapping | `BolaBola Watch App/Pet/PetAnimation.swift` | `PetEmotion` enum → `PetAnimations` → frame/video |
| Companion value scoring | `BolaBola Watch App/Documentation/companion_value_rules.md` | ±1 per interaction, penalties, tier thresholds |
| LLM chat | `Shared/LLM/ConversationService.swift` + `LLMClient.swift` | OpenAI-compatible + Zhipu ASR |
| iOS tab structure | `BolaBola iOS/App/IOSRootView.swift` | Analysis / Home / Chat tabs |
| Widget | `BolaBola Watch Widget/BolaWidgetProvider.swift` | Reads companion value from App Group |
| Add new animation | `Documentation/how_to_add_watch_animation_feature.md` | 4-file pattern; every PetEmotion must map |
| Design tokens | `Documentation/design_core.md` | Colors, spacing, typography |
| App Group fallback | `Shared/Defaults/BolaSharedDefaults.swift` | Tries App Group → falls back to .standard |

## CODE MAP

| Symbol | Type | Location | Role |
|--------|------|----------|------|
| `PetViewModel` | Class | Watch App/Views/ContentView.swift:15 | Pet state machine, animation driver, dialogue |
| `BolaWCSessionCoordinator` | Class | Shared/Sync/BolaWCSessionCoordinator.swift:14 | WC singleton, all iPhone↔Watch comms |
| `LLMClient` | Struct | Shared/LLM/LLMClient.swift:43 | OpenAI-compatible HTTP + Zhipu ASR |
| `LLMKeychain` | Enum | Shared/LLM/LLMModels.swift:41 | Keychain key names for API credentials |
| `PetEmotion` | Enum | Watch App/Pet/PetAnimation.swift:16 | 40+ emotion cases, must all map to animations |
| `PetAnimations` | Enum | Watch App/Pet/PetAnimation.swift:256 | Frame/video definitions per emotion |
| `CompanionTier` | Enum | Shared/Companion/CompanionTier.swift:8 | Maps companion value 0–100 to relationship tier |
| `BolaSharedDefaults` | Enum | Shared/Defaults/BolaSharedDefaults.swift:12 | UserDefaults with App Group fallback |
| `IOSRootView` | Struct | iOS/App/IOSRootView.swift:10 | Tab structure (Analysis, Home, Chat) |
| `BolaWidgetProvider` | Struct | Watch Widget/BolaWidgetProvider.swift:4 | Widget timeline, reads companion value |
| `MealEngine` | — | Shared/Meals/MealEngine.swift | Meal scheduling + feeding logic |
| `ReminderListStore` | Enum | Shared/Reminders/ReminderListStore.swift:11 | JSON-persisted reminders |
| `DailyDigestUNScheduler` | — | Shared/Digest/DailyDigestUNScheduler.swift | 9 AM health summary notification |
| `WatchSpeechRelay` | — | Watch App/Speech/WatchSpeechRelay.swift | Voice → iPhone ASR → LLM → dialogue |

## CONVENTIONS

- Chinese comments in code (MARK sections, inline docs) — keep bilingual style
- `#if os(iOS)` / `#if os(watchOS)` guards in Shared/ for platform-specific code
- `Sendable` conformance required for all types crossing actor boundaries
- No linters/formatters configured
- No test targets exist — Xcode only

## ANTI-PATTERNS (THIS PROJECT)

- **NEVER** add Firebase imports to Watch/Shared/Widget targets (binary-incompatible with watchOS)
- **NEVER** leave real API keys in `LocalLLMDevSecrets.swift` at commit time
- **NEVER** use `TabView + .page` or `UIPageViewController` bridge for horizontal paging (use `ScrollView + scrollTargetBehavior(.paging)`)
- **NEVER** call `UIImage(named:)` on watchOS for existence probing (memory risk)
- Every `PetEmotion` case **MUST** have a mapping in `currentAnimation` or it won't compile
- Don't use primary accent color for small body text or text on primary backgrounds (insufficient contrast)

## COMMANDS

```bash
# Build iOS
xcodebuild build -scheme BolaBola -destination "generic/platform=iOS"
# Build watchOS
xcodebuild build -scheme "BolaBola Watch App" -destination "generic/platform=watchOS"
# SPM resolution (after DerivedData clear / new machine)
Scripts/resolve_xcode_packages.sh
# Process watch animation sprite sheets (resize 400px wide, rename frames)
python3 Scripts/process_watch_animations.py
```

## NOTES

**App Group**: `group.com.GathXRTeam.BolaBola`. Requires paid dev account; Personal Team → silent fallback to `UserDefaults.standard` (no cross-device sharing). Search `RESTORE_APP_GROUP_WHEN_PAID_DEV`.

**WC sync**: `updateApplicationContext` = companion value (latest-wins); `transferUserInfo` = chat deltas (FIFO); LLM config pulled by watch on demand via `requestSync: "llmKeychain"` (push unreliable).

**Watch animations**: Sprite sheets in `Assets.xcassets/`, processed by `Scripts/process_watch_animations.py`. 4-file pattern for adding new animations. See `BolaBola Watch App/Documentation/animation_list.md` for inventory.

**Large files**: `ContentView.swift` (1862), `IOSLifeContainerView.swift` (2151), `IOSGrowthView.swift` (1475), `IOSChatTestSection.swift` (1211), `IOSMainHomeView.swift` (1311), `BolaWCSessionCoordinator.swift` (1208), `PetAnimation.swift` (1072) — legitimate complexity (state machines, UI composition).

**Design docs**: `Documentation/` and `BolaBola Watch App/Documentation/` are authoritative specs — companion_value_rules, state_machine_list, bola_dialogue_rules, tap_interaction_rules.
