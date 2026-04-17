# iPhone-Watch Pet Mirror System

This document describes the bidirectional mirror between the iPhone companion app and the watchOS pet. The watch is the **authoritative source of truth** for all pet state; the iPhone acts as a remote display + remote control.

---

## Overview

The mirror system synchronizes **core state only** — no animation prefixes or dialogue text cross the wire. Each device independently derives its own animations and dialogue from the shared state.

| Channel | Direction | What syncs | Transport |
|---------|-----------|------------|-----------|
| **Core state + companion value** | Watch -> iPhone | `PetCoreState` enum + companion value (Double) | `applicationContext` + `transferUserInfo` |
| **Pet commands** | iPhone -> Watch | `eat` / `drink` / `sleep` intents | `sendMessage` (if reachable) / `transferUserInfo` (fallback) |
| **Companion value (tap)** | iPhone local | +1 optimistic increment, then sync | `applicationContext` + `transferUserInfo` |
| **Chat history sync** | Bidirectional | `[ChatTurn]` deltas | `transferUserInfo` (FIFO) |

All transport goes through the singleton `BolaWCSessionCoordinator.shared` (`Shared/Sync/BolaWCSessionCoordinator.swift`).

### Key principle: "Heavy state is synchronized, light reactions are local"

- **Synchronized**: companion value, `PetCoreState` (idle/hungry/thirsty/sleepWait/sleeping)
- **Local**: animations, dialogue bubbles, haptic feedback, tap reactions

---

## File Index

| File | Role |
|------|------|
| `Shared/Sync/PetCoreState.swift` | Shared enum (`idle`/`hungry`/`thirsty`/`sleepWait`/`sleeping`) + iPhone-side animation derivation + local dialogue |
| `Shared/Sync/WCSyncPayload.swift` | String-key constants for all WCSession payload fields |
| `Shared/Sync/BolaWCSessionCoordinator.swift` | Singleton that owns WCSession, sends/receives all payloads, publishes `@Published currentPetCoreState` |
| `Shared/Sync/ChatTurn.swift` | `ChatTurn` data model, `ChatHistoryStore` (load/save/merge), `PetCommandKind` + notification name constants |
| `Shared/Animation/PetFramePlayer.swift` | Standalone SwiftUI frame-sequence player, used in both targets |
| `BolaBola Watch App/Views/ContentView.swift` | `PetViewModel` — the watch-side pet state machine; pushes `PetCoreState` at transitions |
| `BolaBola iOS/Design/WatchS10MockupView.swift` | Watch PNG mockup with screen overlay; hosts `PetFramePlayer` inside a masked ZStack |
| `BolaBola iOS/Features/Home/IOSMainHomeView.swift` | Home tab; derives animation from core state, shows local dialogue, handles tap + action buttons |

---

## Channel 1: Watch -> iPhone (Core State Sync)

### How it works

1. **Trigger.** When the watch enters a new pet state (eating, drinking, sleeping, or returns to idle), `PetViewModel` calls `BolaWCSessionCoordinator.shared.pushPetCoreState(.hungry)` (or `.thirsty`, `.sleepWait`, `.sleeping`, `.idle`).

2. **Payload.** `pushPetCoreState` sets `currentPetCoreState` on the coordinator, reads the current companion value from `UserDefaults`, and delegates to `pushCompanionValue(...)`, which builds a dict containing:
   - `companionValue` + `companionValueUpdatedAt` (always present)
   - `petCoreState` (the `PetCoreState.rawValue` string)

3. **Transport.** `sendPayload` issues both `updateApplicationContext` (latest-wins) and `transferUserInfo` (FIFO queue) in parallel, for redundancy.

4. **Receive (iOS).** The coordinator's `ingest(_:)` method runs on the main thread. It reads `petCoreState` rawValue and updates `@Published currentPetCoreState`.

5. **Render.** `IOSMainHomeView` observes `coordinator` via `@ObservedObject`. It derives the animation prefix locally:
   ```swift
   coordinator.currentPetCoreState.animationPrefix(companionValue: companion)
   ```
   This prefix is passed to `WatchS10MockupView` -> `PetFramePlayer`. Dialogue is also derived locally via `coordinator.currentPetCoreState.localDialogue`.

### What changed from Phase 1 (animation sync)

Previously, the watch pushed `currentAnimationPrefix`, `currentDialogueLine`, and `currentDialogueGeneration` over WC. This created tight coupling and latency issues. Now:
- No animation prefix crosses the wire
- No dialogue text crosses the wire
- Each device maps `PetCoreState` + `companionValue` -> local visuals independently
- iPhone sees state changes instantly (the enum arrives, local rendering starts)

### Push sites in PetViewModel

| Method | State pushed |
|--------|-------------|
| `enterEatingState()` | `.hungry` |
| `finishEatingHappyAnimation()` | `.idle` |
| `enterDrinkWaterState()` | `.thirsty` |
| `finishDrinkWaterAnimation()` (delayed) | `.idle` |
| `enterNightSleepWaitState()` | `.sleepWait` |
| `finishFallAsleepAnimation()` | `.sleeping` |
| `wakeUpFromNightSleep()` | `.idle` |

---

## Channel 2: iPhone -> Watch (Pet Commands)

### How it works

1. **Tap.** Tapping the iPhone mockup is handled entirely locally:
   - Haptic feedback + scale animation (immediate)
   - `BolaWCSessionCoordinator.shared.incrementCompanionValueLocally(by: 1)` — reads companion from UserDefaults, adds +1, writes back, pushes to watch via `pushCompanionValue`
   - No command is sent to the watch — taps don't trigger watch-side animations

2. **Action bar buttons.** Contextual Feed/Drink/Sleep buttons appear based on `coordinator.currentPetCoreState`:

   | Core state | Button | Command |
   |------------|--------|---------|
   | `.hungry` | Feed | `PetCommandKind.eat` |
   | `.thirsty` | Drink | `PetCommandKind.drink` |
   | `.sleepWait` | Sleep | `PetCommandKind.sleep` |

3. **Transport.** `sendPetCommand(_ kind:)` on the coordinator builds `[petCommandKind: kind, petCommandId: UUID().uuidString]`. If `session.isReachable`, it uses `sendMessage` (immediate delivery); otherwise it falls back to `transferUserInfo` (queued, delivered on next wake).

4. **Receive (watchOS).** `didReceiveMessage` and `didReceiveUserInfo` both call `ingestPetCommandIfPresent(_:)`, which:
   - Reads `petCommandKind` and `petCommandId`.
   - Checks `petCommandId` against a ring buffer of the last 16 processed ids. If duplicate, skips.
   - Posts `NotificationCenter.default.post(name: .bolaPetCommandReceived, ...)`.

5. **Dispatch.** `PetViewModel` subscribes in `init()` via `petCommandObserver`. `handleRemotePetCommand(_:)` dispatches:

   | Command | Watch handler | Precondition |
   |---------|--------------|--------------|
   | `eat` | `handleEatingTap()` | `isInEatingState && currentEmotion == .eatingWait` |
   | `drink` | `handleDrinkWaterTap()` | `isInDrinkWaterState && currentEmotion in [.idleDrink1, .idleDrink2]` |
   | `sleep` | `handleNightSleepWaitTap()` | `isInNightSleepState && !isNightSleepAsleep && currentEmotion == .nightSleepWait` |

   Commands that don't match the current state are silently ignored.

6. **Round-trip.** After the watch processes the command, the state transition triggers a `pushPetCoreState(.idle)` (or similar), which updates the iPhone's local rendering.

---

## Channel 3: Chat History Mirror

### Scope

Only **substantive** dialogue is mirrored to chat history:
- **Daily digest letters** (`playDailyDigestLetter`) — explicitly appended via `ChatHistoryStore.appendAssistantOnly(body)` + `pushChatDelta([turn])`.
- **Voice assistant replies** — already flow through `ConversationService.appendUserThenAssistant()` + `pushChatDelta()`.

Ephemeral dialogue (tap reactions, greetings, heart-rate alerts, eat/drink/sleep prompts) is **not** mirrored to chat. The rationale: the 24-turn cap in `ChatHistoryStore` would churn quickly, evicting substantive content.

### How it works

1. Watch calls `ChatHistoryStore.appendAssistantOnly(text)` -> creates a `ChatTurn(role: "assistant", content: text)`, persists to `UserDefaults`.
2. Watch calls `BolaWCSessionCoordinator.shared.pushChatDelta([turn])` -> encodes as Base64 JSON, sends via `transferUserInfo`.
3. iPhone receives in `ingestChatDeltaIfPresent()` -> decodes, calls `ChatHistoryStore.mergeRemoteTurns()` (deduplicates by UUID, sorts by timestamp, caps at 24), posts `.bolaChatHistoryDidMerge`.
4. `IOSChatTestSection` and `WatchChatHistoryView` both observe `.bolaChatHistoryDidMerge` and reload. No UI changes are needed.

---

## `PetCoreState` — The Shared State Enum

Defined in `Shared/Sync/PetCoreState.swift`. This is the only pet-related data that crosses devices.

```swift
public enum PetCoreState: String, Codable, Sendable {
    case idle, hungry, thirsty, sleepWait, sleeping
}
```

### iPhone-side derivation

`PetCoreState` provides two computed helpers for the iPhone:

- `animationPrefix(companionValue:)` — maps state + companion value to a `PetFramePlayer` prefix string. For `.idle`, it mirrors the watch's `selectDefaultEmotion` tier logic (companion value buckets).
- `localDialogue` — returns a fixed dialogue string for wait states (hungry/thirsty/sleepWait), `nil` for idle/sleeping.

---

## `PetFramePlayer` — The Animation Engine

`PetFramePlayer` (`Shared/Animation/PetFramePlayer.swift`) is used on both platforms. On the watch it is embedded in `ContentView`; on iPhone it renders inside `WatchS10MockupView`'s screen overlay.

### How it plays frames

- Starts a `Timer.publish(every: 1/30s)` — an internal 30 Hz polling loop.
- Each tick, it compares `elapsed` time against `1.0 / fps` (the target frame duration). If enough time has passed, it advances `frameIndex = (frameIndex + 1) % maxFrames`.
- The displayed `Image` is `Image("\(prefix)\(frameIndex)")` from the Asset Catalog.
- `.id(frameName)` forces a full SwiftUI `Image` node rebuild each frame.
- `.transaction { $0.animation = nil }` suppresses any implicit crossfade.

### When the prefix changes

`.onChange(of: prefix) { resetAndStart() }` immediately resets `frameIndex = 0`, cancels the old timer, and starts a fresh timer. When `PetCoreState` changes, the iPhone derives a new prefix, and the player switches animations.

---

## Making Future Changes

### Adding a new core state

1. Add a case to `PetCoreState` in `Shared/Sync/PetCoreState.swift`.
2. Add the animation prefix mapping in `animationPrefix(companionValue:)`.
3. Add the local dialogue string in `localDialogue` (or `nil` if no bubble).
4. On the watch, call `BolaWCSessionCoordinator.shared.pushPetCoreState(.yourState)` at the transition point.
5. On the watch, call `pushPetCoreState(.idle)` when the state ends.
6. If the state should have an action button on iPhone, add a case in `petActionBar` in `IOSMainHomeView`.

### Adding a new iPhone -> Watch command

1. Add a new constant to `PetCommandKind` in `ChatTurn.swift`.
2. Add a case in `PetViewModel.handleRemotePetCommand(_:)`.
3. Add a trigger in `IOSMainHomeView` (action bar button or gesture) that calls `BolaWCSessionCoordinator.shared.sendPetCommand(PetCommandKind.yourCommand)`.

### Adding a new animation set

1. Place the imageset folders under `Shared/AnimationAssets.xcassets/<groupName>/` following the naming convention `<prefix><frameIndex>.imageset`.
2. Add a corresponding `PetEmotion` case and `PetAnimation` entry in `BolaBola Watch App/Pet/PetAnimation.swift`.
3. Wire it into `PetViewModel.currentAnimation`.
4. If the frame count differs from 90, pass the correct `maxFrames` where `PetFramePlayer` is instantiated.

### Mirroring additional dialogue to chat history

At the call site on the watch, after `showDialogue(...)`, add:
```swift
let turn = ChatHistoryStore.appendAssistantOnly(text)
BolaWCSessionCoordinator.shared.pushChatDelta([turn])
```
Be mindful of the 24-turn cap.

---

## Sequence Diagrams

### Tap on iPhone (local reaction + companion sync)

```
iPhone                                Watch
  |                                     |
  |-- handlePetMockupTap()              |
  |   haptic + scale animation          |
  |   incrementCompanionValueLocally(+1)|
  |   companion = read from defaults    |
  |                                     |
  |-- pushCompanionValue -------------->|
  |   (applicationContext +             |
  |    transferUserInfo)                |
  |                                     |
  |   (no animation/command sent —      |
  |    tap is local-only)               |
```

### Watch enters eating state -> iPhone shows Feed button

```
Watch                                        iPhone
  |                                            |
  |-- enterEatingState()                       |
  |   currentEmotion = .eatingWait             |
  |   showDialogue("有点饿，想吃东西啦")         |
  |   pushPetCoreState(.hungry)                |
  |                                            |
  |-- pushCompanionValue ---------------------->|
  |   petCoreState="hungry"                    |
  |                                            |
  |                    currentPetCoreState = .hungry
  |                    animationPrefix -> "idleapple"
  |                    localDialogue -> "有点饿，想吃东西啦"
  |                    Feed button appears      |
  |                                            |
  |<------- sendPetCommand("eat") -------------|
  |   (user taps Feed button)                  |
  |                                            |
  |-- handleRemotePetCommand("eat")            |
  |   -> handleEatingTap()                     |
  |   ... eating animation plays ...           |
  |   -> finishEatingHappyAnimation()          |
  |   -> pushPetCoreState(.idle)               |
  |                                            |
  |-- pushCompanionValue ---------------------->|
  |   petCoreState="idle"                      |
  |                                            |
  |                    currentPetCoreState = .idle
  |                    animationPrefix -> "idleone"
  |                    localDialogue -> nil     |
  |                    Feed button hides        |
```

---

## Troubleshooting

| Symptom | Likely cause | Check |
|---------|-------------|-------|
| iPhone mockup stuck on wrong animation | `currentPetCoreState` not updating | Console: search `sendPayload` — are pushes happening? Is the watch sim paired? |
| Tap on iPhone has no visual feedback | `handlePetMockupTap` not wired | Verify `.simultaneousGesture(TapGesture())` is on `watchMockupCore` in `IOSMainHomeView` |
| Action bar buttons don't appear | Core state doesn't match | Print `coordinator.currentPetCoreState`. Verify the watch called `pushPetCoreState` at the transition. |
| iPhone shows wrong idle animation | Companion value out of sync | Check that `companion` binding is up to date. `PetCoreState.animationPrefix(companionValue:)` uses tier buckets. |
| Chat history has too many ephemeral lines | Code is calling `appendAssistantOnly` from `showDialogue` | Only `playDailyDigestLetter` should call it. Verify no other call site was added. |
| "Cannot find X in scope" in Xcode | SourceKit false positives for cross-file symbols | These are pre-existing. The `xcodebuild` command line build is the source of truth. |
