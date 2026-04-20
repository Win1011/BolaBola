# Phone-Watch Communication Architecture

This document is the complete reference for how the BolaBola iPhone and Watch apps communicate. It covers every sync path, transport choice, merge rule, and session lifecycle detail.

The previous document (`iphone_watch_mirror.md`) focused on the pet mirror system. This document supersedes it by covering **all 17 communication paths** end-to-end.

---

## 1. Architecture Overview

### Source of truth

The **Watch is the authoritative source** for companion value and pet core state. The iPhone mirrors these values. All other sync domains (LLM config, reminders, home screen layout, chat) have their own ownership rules described per-path below.

### Coordinator singleton

All Watch Connectivity traffic passes through `BolaWCSessionCoordinator.shared` (`Shared/Sync/BolaWCSessionCoordinator.swift`). It:

- Owns the `WCSession.default` activation lifecycle
- Publishes `@Published currentPetCoreState` and `@Published currentPetEmotionLabel`
- Provides `onReceiveCompanionValue: ((Double) -> Void)?` callback for both platforms
- Queues payloads when the session is not yet activated, and flushes them on activation
- Routes incoming payloads through a chain of specialized ingestors

### Session activation

| Platform | Where | When |
|----------|-------|------|
| iOS | `IOSNotificationRouter.swift` (app delegate) + `IOSRootView.swift` (.task) | App launch |
| watchOS | `BolaBolaApp.swift` (init) | App launch |

Calling `activate()` when already active only replays `receivedApplicationContext` rather than re-activating the session.

---

## 2. Transport Layer

The app uses four `WCSession` transport methods. Each has different delivery guarantees:

| Transport | Delivery | Queueing | Survives suspension | Used by |
|-----------|----------|----------|---------------------|---------|
| `updateApplicationContext` | Latest-wins (overwrites previous) | None — only the most recent dict is kept | Yes | Companion value + pet core state + home screen payload |
| `transferUserInfo` | FIFO queue | Yes — all dicts delivered in order | Yes | Most discrete payloads (LLM config, chat deltas, reminders, snapshots, emotion labels, speech relay replies) |
| `sendMessage` | Immediate (if counterpart reachable) | None — fails if not reachable | No | Pet commands (with `transferUserInfo` fallback) |
| `transferFile` | File transfer | FIFO queue | Yes | Speech relay audio (only file-transfer path) |

### Dual-send strategy

For companion value + pet core state, the coordinator issues **both** `updateApplicationContext` and `transferUserInfo` in parallel (`sendPayload`). This belt-and-suspenders approach compensates for environments where `receivedApplicationContext` callbacks are unreliable.

---

## 3. Payload Keys

All keys are defined as static constants in `WCSyncPayload` (`Shared/Sync/WCSyncPayload.swift`).

### Core sync

| Key | Type | Direction | Purpose |
|-----|------|-----------|---------|
| `companionValue` | Double | Bidirectional | Pet companion score (0–100) |
| `companionValueUpdatedAt` | Double (Unix ts) | Bidirectional | Timestamp for merge conflict resolution |
| `companionSyncForcedFromPhone` | Bool | iPhone→Watch | Bypass timestamp guard |
| `petCoreState` | String | Bidirectional | `PetCoreState.rawValue` (idle/hungry/thirsty/sleepWait/sleeping) |
| `petEmotionLabel` | String | Watch→iPhone | Current emotion animation name (debug only) |
| `petCommandKind` | String | iPhone→Watch | "eat" / "drink" / "sleep" |
| `petCommandId` | String (UUID) | iPhone→Watch | Dedup key for commands |

### Home screen payload (piggybacked on companion value)

| Key | Type | Direction | Purpose |
|-----|------|-----------|---------|
| `watchFaceSlotsB64` | String (Base64 JSON) | iPhone→Watch | `WatchFaceSlotsConfiguration` |
| `titleSelectionB64` | String (Base64 JSON) | iPhone→Watch | `BolaTitleSelection` |
| `personalitySelectionRaw` | String | iPhone→Watch | Personality selection rawValue |
| `growthStateB64` | String (Base64 JSON) | iPhone→Watch | `BolaGrowthState` |
| `titleUnlockedIdsB64` | String (Base64 JSON) | iPhone→Watch | Unlocked title word IDs |
| `maxEverCompanionValue` | Double | iPhone→Watch | Historical max companion value |

### Game state snapshot

| Key | Type | Direction | Purpose |
|-----|------|-----------|---------|
| `companionSnapshotKind` | String | Watch→iPhone | Format marker: "csV1" |
| `companionSnapshotB64` | String (Base64 binary plist) | Watch→iPhone | Full game state from `CompanionPersistenceKeys` |

### LLM configuration

| Key | Type | Direction | Purpose |
|-----|------|-----------|---------|
| `llmApiKey` | String | iPhone→Watch | API key for Watch Keychain |
| `llmBaseURL` | String | iPhone→Watch | Base URL |
| `llmModelId` | String | iPhone→Watch | Model identifier |
| `llmAuthBearer` | String | iPhone→Watch | Bearer auth flag ("1"/"0") |
| `requestSync` | String | Watch→iPhone | Request marker; value "llmKeychain" triggers LLM config push back |

### Speech relay

| Key | Type | Direction | Purpose |
|-----|------|-----------|---------|
| `speechRelayRequestId` | String (UUID) | Bidirectional | Correlates request ↔ reply |
| `speechRelayKind` | String | Bidirectional | "speechRelay" (file metadata) or "speechRelayReply" (userInfo) |
| `speechRelayTranscript` | String | iPhone→Watch | Transcription result |
| `speechRelayError` | String | iPhone→Watch | Error description if transcription failed |

### Chat

| Key | Type | Direction | Purpose |
|-----|------|-----------|---------|
| `chatDeltaKind` | String | Bidirectional | Version marker: "v1" |
| `chatDeltaDataB64` | String (Base64 JSON) | Bidirectional | `[ChatTurn]` JSON |

### Reminders

| Key | Type | Direction | Purpose |
|-----|------|-----------|---------|
| `remindersListB64` | String (Base64 JSON) | iPhone→Watch | `[BolaReminder]` JSON |

---

## 4. Sync Paths

### 4.1 Pet Core State

**Direction**: Bidirectional (Watch→iPhone is the primary flow; iPhone debug panel can also push)

**Transport**: Piggybacked on companion value payload via `updateApplicationContext` + `transferUserInfo`

**How it works**:

1. Watch's `PetViewModel` detects a state transition via `PetAnimationController.onTransition`
2. `applyInteractionTransition` calls `BolaWCSessionCoordinator.shared.pushPetCoreState(.hungry)` (or other state)
3. `pushPetCoreState` sets `currentPetCoreState` synchronously on the main thread, then calls `pushCompanionValue` which builds and sends the payload
4. iPhone's `ingest(_:)` applies `petCoreState` **before** the companion-value timestamp guard (since pet state is independent of companion value merge conflicts)
5. Additionally, `didReceiveUserInfo` and `didReceiveMessage` both extract `petCoreState` early, before any specialized ingestor can return early and skip it
6. `IOSMainHomeView` observes `coordinator.currentPetCoreState` via `.onChange` and calls `mirrorCoreStateToController(_:)` to update the local animation controller

**Push sites on Watch**:

| Transition reason | State pushed |
|-------------------|-------------|
| `.hungryStarted` | `.hungry` |
| `.eatingStarted` | `.idle` |
| `.thirstyStarted` | `.thirsty` |
| `.drinkingStarted` | `.idle` |
| `.sleepWaitStarted` | `.sleepWait` |
| `.fallingAsleepStarted` | `.sleeping` |
| Wake up from sleep | `.idle` |

**iPhone mirror logic** (`mirrorCoreStateToController`):

| Incoming state | Condition | Action |
|----------------|-----------|--------|
| `.hungry` | Not already in eating flow | `interactionController.enterHungry()` |
| `.thirsty` | Not already in drinking flow | `interactionController.enterThirsty()` |
| `.sleepWait` | Not already in sleep flow | `interactionController.enterSleepWait()` |
| `.sleeping` | In waiting loop or no active interaction | `interactionController.enterSleeping()` |
| `.idle` | Currently in a waiting loop | `interactionController.returnToIdle()` |

When the iPhone is in a one-shot transition animation (eating, drinking, falling asleep), the `.idle` mirror does **not** interrupt it — the local animation plays to completion.

**Design principle**: Only core states (idle/hungry/thirsty/sleepWait/sleeping) cross the wire. Transition animations (eating, drinking, fallingAsleep) are driven locally on each device.

---

### 4.2 Companion Value

**Direction**: Bidirectional

**Transport**: `updateApplicationContext` + `transferUserInfo` (dual-send)

**How it works**:

1. **Watch→iPhone**: `pushCompanionValue` builds `{companionValue, companionValueUpdatedAt, petCoreState}` and calls `sendPayload`. On watchOS, if debug mode is enabled, also includes `petEmotionLabel`.
2. **iPhone→Watch**: Same method, but also appends the home screen payload (slots, title, personality, growth, unlocks) via `appendWatchHomeScreenPayload`. When triggered by the sync button or foreground return, `pushLocalCompanionTowardWatchFromDefaults()` uses `forcedForWatch: true`.
3. **Receive**: `ingest(_:)` performs timestamp-based merge conflict resolution:
   - If `forcedFromPhone == true`: always apply
   - Otherwise: only apply if `remoteTs > localTs`
   - If remote timestamp is 0 and local timestamp is 0 (first sync), apply with current time
   - If remote timestamp is 0 and local timestamp > 0 and not forced: **return early** (discard stale packet)
4. On apply: writes `companionValue` + `companionWCUpdatedAt` to `BolaSharedDefaults`, calls `onReceiveCompanionValue` callback

**Merge rule**: Last-write-wins by `companionWCUpdatedAt` timestamp. `forcedFromPhone` flag bypasses the guard for explicit user-initiated syncs.

**iPhone companion tap**: `incrementCompanionValueLocally(by: 1)` reads from defaults, adds +1, and pushes via `pushCompanionValue`. This is an optimistic local update that syncs to the Watch.

---

### 4.3 Pet Commands (iPhone→Watch)

**Direction**: iPhone → Watch only

**Transport**: `sendMessage` if reachable; `transferUserInfo` fallback

**Payload**: `{petCommandKind: "eat"/"drink"/"sleep", petCommandId: UUID}`

**How it works**:

1. User taps Feed/Drink/Sleep button on iPhone (or taps mockup while in a wait state)
2. iPhone calls `interactionController.applyEatCommand()` (local animation) + `BolaWCSessionCoordinator.shared.sendPetCommand(PetCommandKind.eat)`
3. Watch receives via `didReceiveMessage` or `didReceiveUserInfo`
4. `ingestPetCommandIfPresent` checks `petCommandId` against a rolling buffer of last 16 IDs (dedup)
5. Posts `.bolaPetCommandReceived` notification with the command kind
6. `PetViewModel.handleRemotePetCommand` dispatches:

| Command | Handler | Precondition |
|---------|---------|--------------|
| `eat` | `handleEatingTap()` | `isInEatingState && currentEmotion == .eatingWait` |
| `drink` | `handleDrinkWaterTap()` | `isInDrinkWaterState && currentEmotion in [.idleDrink1, .idleDrink2]` |
| `sleep` | `handleNightSleepWaitTap()` | `isInNightSleepState && !isNightSleepAsleep && currentEmotion == .nightSleepWait` |

Commands that don't match the current state are silently ignored.

7. After the watch processes the command, the resulting state transition triggers a `pushPetCoreState` back to iPhone, completing the round-trip.

---

### 4.4 Pet Emotion Label (Debug Only, Watch→iPhone)

**Direction**: Watch → iPhone

**Transport**: `transferUserInfo` only

**Payload**: `{petEmotionLabel: String, petCoreState: String}`

**How it works**:

1. `PetViewModel` subscribes to `$currentEmotion` and calls `updatePetEmotionLabel(_:)` on each change
2. Only sent when `BolaDebugLog.shared.isEnabled == true`
3. Debounced 300ms to batch rapid emotion changes
4. iPhone receives via `ingestPetEmotionLabelIfPresent`, which only handles payloads **without** a `companionValue` key (to avoid intercepting the main companion sync path)
5. Sets `currentPetEmotionLabel` for display in debug UI

---

### 4.5 Companion Game State Snapshot (Watch→iPhone)

**Direction**: Watch → iPhone

**Transport**: `transferUserInfo`

**Payload**: `{companionSnapshotKind: "csV1", companionSnapshotB64: <binary plist Base64>}`

**Purpose**: Transfers the full set of companion game state keys when there is no App Group shared UserDefaults available (e.g., Personal Team without paid dev account).

**How it works**:

1. Watch calls `schedulePushCompanionGameStateSnapshotToPhoneDebounced()` — debounced 1.5 seconds
2. Serializes all `CompanionPersistenceKeys.wcGameStateSnapshotKeys` into a binary plist, Base64 encodes it
3. iPhone receives via `ingestCompanionGameStateSnapshotFromWatchIfPresent`:
   - Writes all keys except `companionValue` unconditionally
   - `companionValue` is only overwritten if `remoteWC >= localWC - 0.0001`
   - Posts `.bolaCompanionStateDidMergeFromWatch`
   - Calls `onReceiveCompanionValue`

**Snapshot keys**: `companionValue`, `lastCompanionWallClock`, `lastTickTimestamp`, `totalActiveSeconds`, `activeCarrySeconds`, `lastSurpriseAtHours`, `companionWCUpdatedAt`

---

### 4.6 LLM Configuration (iPhone→Watch)

**Direction**: iPhone → Watch

**Transport**: `transferUserInfo`

**Payload**: `{llmApiKey, llmBaseURL, llmModelId, llmAuthBearer}`

**How it works**:

1. User saves LLM settings on iPhone → `pushLLMConfigurationToWatch(apiKey:baseURL:model:useBearerAuth:)`
2. Also triggered automatically on: session activation, reachability change, foreground return, manual sync
3. Watch receives via `ingestLLMConfigurationIfPresent` → writes each field to Keychain via `KeychainHelper`
4. Empty strings remove the corresponding Keychain entry

---

### 4.7 LLM Keychain Request (Watch→iPhone→Watch)

**Direction**: Watch → iPhone (triggers a response via Path 4.6)

**Transport**: `transferUserInfo`

**Payload**: `{requestSync: "llmKeychain"}`

**How it works**:

1. On session activation or companion state change, Watch checks if its Keychain has an API key
2. If missing, sends `{requestSync: "llmKeychain"}` to iPhone
3. Throttled to once per 45 seconds
4. iPhone receives, recognizes the request, and calls `pushStoredLLMConfigurationToWatchIfConfigured()` (Path 4.6)

---

### 4.8 Chat Delta Sync (Bidirectional)

**Direction**: Bidirectional

**Transport**: `transferUserInfo`

**Payload**: `{chatDeltaKind: "v1", chatDeltaDataB64: <Base64 [ChatTurn] JSON>}`

**How it works**:

1. After generating a chat reply, the originating device calls `pushChatDelta([turn])`
2. If session not ready, payloads queue in `pendingChatDeltaPayloads` (max 32), flushed on activation
3. Receiver calls `ingestChatDeltaIfPresent` → `ChatHistoryStore.mergeRemoteTurns()`:
   - Deduplicates by `ChatTurn.id` (UUID)
   - Sorts by `createdAt`
   - Caps at 24 turns
4. Posts `.bolaChatHistoryDidMerge`

**What gets mirrored**: Only substantive dialogue — daily digest letters and voice assistant replies. Ephemeral dialogue (tap reactions, greetings, health alerts, eat/drink/sleep prompts) is NOT mirrored to avoid churning the 24-turn cap.

**Sources**: `ConversationService` on iPhone (LLM replies), `playDailyDigestLetter` on Watch.

---

### 4.9 Speech Relay — File Transfer (Watch→iPhone)

**Direction**: Watch → iPhone

**Transport**: `transferFile` (the only file-transfer path in the app)

**File metadata**: `{speechRelayRequestId: UUID, speechRelayKind: "speechRelay"}`

**How it works**:

1. Watch captures audio (WAV, 16kHz, mono, 16-bit PCM)
2. Before transferring, Watch calls `prepareSpeechRelay(requestId:completion:)` to register a pending callback with a 45-second timeout
3. Watch calls `WCSession.default.transferFile(url, metadata:)`
4. iPhone receives via `session(_:didReceive:)`:
   - Copies file to temp directory
   - Transcribes using Apple Speech framework (zh-CN locale) via `IOSpeechRelayTranscriber`
   - Sends transcript back via Path 4.10

---

### 4.10 Speech Relay — Transcript Reply (iPhone→Watch)

**Direction**: iPhone → Watch

**Transport**: `transferUserInfo`

**Payload**: `{speechRelayRequestId, speechRelayKind: "speechRelayReply", speechRelayTranscript (or speechRelayError)}`

**How it works**:

1. iPhone sends reply via `sendSpeechRelayReplyToWatch(_:session:)`
2. Watch receives via `ingestSpeechRelayReplyIfPresent`
3. Matches `speechRelayRequestId` to the pending callback
4. Calls the registered completion with transcript string (or nil on error)
5. Cancels the 45-second timeout

---

### 4.11–4.16 Home Screen Payload (iPhone→Watch, Piggybacked)

These six sync domains are **not sent independently** — they are appended to every companion value push from iPhone via `appendWatchHomeScreenPayload`. They arrive in the same `applicationContext` / `transferUserInfo` as the companion value.

**Ingest**: `ingestWatchHomeScreenPayloadIfPresent(_:)` on watchOS handles all six keys, then posts `.bolaWatchHomeScreenPayloadDidUpdate`.

| # | Key | Data | Merge rule |
|---|-----|------|-----------|
| 4.11 | `watchFaceSlotsB64` | `WatchFaceSlotsConfiguration` JSON | Overwrite |
| 4.12 | `titleSelectionB64` | `BolaTitleSelection` JSON | Overwrite |
| 4.13 | `personalitySelectionRaw` | Personality rawValue string | Overwrite |
| 4.14 | `growthStateB64` | `BolaGrowthState` JSON | `mergeFromRemote` — takes max `totalXP` |
| 4.15 | `titleUnlockedIdsB64` | `[String]` JSON | `mergeFromRemote` — set union |
| 4.16 | `maxEverCompanionValue` | Double | Overwrite (used for title unlock conditions on Watch) |

---

### 4.17 Reminders (iPhone→Watch)

**Direction**: iPhone → Watch

**Transport**: `transferUserInfo`

**Payload**: `{remindersListB64: <Base64 [BolaReminder] JSON>}`

**How it works**:

1. Triggered by: reminder list mutation in `IOSRemindersSectionView`, LLM alarm intent in `ConversationService`, session lifecycle events
2. Watch receives via `ingestRemindersIfPresent`:
   - Saves via `ReminderListStore.save()`
   - Reschedules local notifications via `BolaReminderUNScheduler.sync()`
3. **Notable**: `ingestRemindersIfPresent` returns `true` and short-circuits `ingest()`. A reminders-only payload will NOT also process companion value or pet core state. However, `petCoreState` is already extracted early in `didReceiveUserInfo` before the specialized ingestor runs.

---

## 5. Receive Dispatch Map

### `session(_:didReceiveApplicationContext:)`

All platforms → `ingest(applicationContext)` directly. No specialized routing needed because `applicationContext` always carries companion value.

### `session(_:didReceiveUserInfo:)`

Dispatch order on the main queue:

```
1. Apply petCoreState early (always, before any ingestor can return early)
   ↓
2. [iOS] Check requestSync == "llmKeychain" → pushStoredLLMConfigurationToWatchIfConfigured() + return
   ↓
3. [watchOS] ingestSpeechRelayReplyIfPresent → return if handled
   ↓
4. [watchOS] ingestPetCommandIfPresent → return if handled
   ↓
5. ingestChatDeltaIfPresent → return if handled
   ↓
6. [iOS] ingestCompanionGameStateSnapshotFromWatchIfPresent → return if handled
   ↓
7. [iOS] ingestPetEmotionLabelIfPresent → return if handled
   ↓
8. ingestLLMConfigurationIfPresent → return if handled
   ↓
9. Fall through to ingest(userInfo)
```

### `session(_:didReceiveMessage:)`

```
1. Apply petCoreState early
   ↓
2. [watchOS] ingestSpeechRelayReplyIfPresent → return if handled
   ↓
3. [watchOS] ingestPetCommandIfPresent → return if handled
   ↓
4. ingestChatDeltaIfPresent → return if handled
   ↓
5. Fall through to ingest(message)
```

### `session(_:didReceive:)` (iOS only)

```
1. Check speechRelayKind == "speechRelay" in metadata
2. Copy file to temp directory
3. Transcribe via IOSpeechRelayTranscriber
4. Send reply via sendSpeechRelayReplyToWatch (Path 4.10)
```

---

## 6. Merge & Conflict Resolution

### Companion value (last-write-wins)

```
if forcedFromPhone {
    always apply
} else if remoteTs > localTs {
    apply
} else {
    discard
}
```

When `forcedFromPhone`, the stored timestamp is set to `Date().timeIntervalSince1970` (current time) rather than the remote timestamp. This prevents a stale remote timestamp from losing to a delayed packet in a subsequent round-trip.

### Pet core state (always apply)

`petCoreState` is extracted and applied **before** the companion-value timestamp guard. It is also extracted early in `didReceiveUserInfo` and `didReceiveMessage` before any specialized ingestor can return early. This ensures that watch→iPhone core state changes are always applied immediately, regardless of companion value merge conflicts.

### Growth state (max-wins)

`BolaGrowthStore.mergeFromRemote` takes the maximum `totalXP` from local and remote.

### Title unlocks (union)

`TitleUnlockStore.mergeFromRemote` takes the set union of local and remote unlocked IDs.

### Game state snapshot (timestamp-guarded)

The snapshot's `companionValue` is only applied if `remoteWC >= localWC - 0.0001` (with epsilon tolerance). All other keys in the snapshot are applied unconditionally.

---

## 7. Session Lifecycle & Recovery

### Activation flow

```
activate()
  └─ WCSession.default.activate()
  └─ on activationDidCompleteWith:
       ├─ ingest(receivedApplicationContext)  // replay latest context
       ├─ flushPendingPayloadsIfReady()
       ├─ flushPendingChatDeltasIfReady()
       ├─ [iOS] pushStoredLLMConfigurationToWatchIfConfigured()
       ├─ [iOS] pushLocalCompanionTowardWatchFromDefaults()
       ├─ [iOS] pushReminderRefreshToWatchIfPossible()
       ├─ [iOS] postWatchInstallabilityChanged()
       └─ [watchOS] requestLLMKeychainFromPhoneIfMissing()
```

### Pending payloads

When the session is not yet activated or the counterpart app is not installed, payloads are stored in:

- `pendingPayload: [String: Any]?` — single latest companion value payload
- `pendingChatDeltaPayloads: [[String: Any]]` — FIFO queue, max 32 entries

Both are flushed when the session activates and the counterpart is ready.

### Foreground recovery

- **iOS**: `IOSRootView` calls `reapplyLatestReceivedContext()` and `pushLocalCompanionTowardWatchFromDefaults()` on `scenePhase == .active`
- **Watch**: `PetViewModel` calls `reapplyLatestReceivedContext()` on foreground return

`reapplyLatestReceivedContext()` reads `session.receivedApplicationContext` and ingests it, providing a safety net for any missed updates.

### Reachability change

On `sessionReachabilityDidChange`, if the counterpart is now reachable and the watch is installed:
1. Flush pending chat deltas
2. Push stored LLM configuration
3. Push companion value from defaults
4. Push reminders

### Watch companion state change (watchOS-only delegate)

When `sessionCompanionStateDidChange` fires on the Watch (iPhone app installed/removed or reachability changed):
1. Push current companion value to iPhone
2. Schedule game state snapshot debounce
3. Request LLM keychain if missing

---

## 8. Callback Wiring

### iOS

```
IOSRootView.swift
  └─ .task { coordinator.onReceiveCompanionValue = { v in companion = v } }
  └─ .onReceive(.bolaCompanionStateDidMergeFromWatch) { refresh from defaults }

IOSMainHomeView.swift
  └─ @ObservedObject coordinator
  └─ .onChange(of: coordinator.currentPetCoreState) { mirrorCoreStateToController($1) }
  └─ .onAppear { mirrorCoreStateToController(coordinator.currentPetCoreState) }
```

### watchOS

```
PetViewModel.init()
  └─ coordinator.onReceiveCompanionValue = { [weak self] v in applyRemoteCompanionValue(v) }
  └─ NotificationCenter.addObserver(forName: .bolaPetCommandReceived) { handleRemotePetCommand(kind) }
  └─ $currentEmotion.sink { coordinator.updatePetEmotionLabel($0) }
```

---

## 9. Widget Relationship

Watch widgets (`BolaBola Watch Widget`) do **not** use WCSession. They read companion value directly from App Group UserDefaults:

```swift
UserDefaults(suiteName: "group.com.gathxr.BolaBola")
    .integer(forKey: "bola_companionValue")
```

When companion value changes on the Watch, `persistCompanionSnapshot` calls `WidgetCenter.shared.reloadAllTimelines()` to trigger a widget refresh. The widget timeline policy is `.after(15 minutes)`.

Without a paid dev account, `BolaSharedDefaults.resolved()` falls back to `UserDefaults.standard`, and widgets cannot read the companion value. Search `RESTORE_APP_GROUP_WHEN_PAID_DEV` for related comments.

---

## 10. Debug Controls

### Watch debug panel (`WatchPanelSheetView`)

| Button | Action |
|--------|--------|
| 播放全部动画 | `debugPlayAllAnimations()` |
| 调试吃东西 | `enterEatingState()` → triggers `.hungry` → `pushPetCoreState(.hungry)` |
| 模拟喝水提醒 | `debugSimulateWaterReminderFire()` → triggers `.thirsty` |
| DebugSleepTime | `debugEnterNightSleep()` → triggers `.sleepWait` |
| DebugWakeUp | `debugSimulateMorningWake()` → triggers `.idle` |

### iPhone debug panel (`IOSDebugLogSheet`)

| Button | Action |
|--------|--------|
| Enter Hungry | `coord.pushPetCoreState(.hungry)` |
| Enter Thirsty | `coord.pushPetCoreState(.thirsty)` |
| Enter Sleepy | `coord.pushPetCoreState(.sleepWait)` |

These debug triggers use the exact same `pushPetCoreState` → `pushCompanionValue` path as normal state transitions, ensuring the sync behavior is identical.

---

## 11. Notification Names

| Name | Posted by | Consumed by |
|------|-----------|-------------|
| `.bolaPetCommandReceived` | `ingestPetCommandIfPresent` (watchOS) | `PetViewModel` — dispatches eat/drink/sleep handlers |
| `.bolaChatHistoryDidMerge` | `ingestChatDeltaIfPresent` | Chat list UI on both platforms |
| `.bolaCompanionStateDidMergeFromWatch` | `ingestCompanionGameStateSnapshotFromWatchIfPresent` (iOS) | `IOSRootView` — refreshes companion from defaults |
| `.bolaWatchInstallabilityDidChange` | `postWatchInstallabilityChanged()` (iOS) | `IOSMainHomeView` — shows/hides install hint |
| `.bolaWatchHomeScreenPayloadDidUpdate` | `ingestWatchHomeScreenPayloadIfPresent` (watchOS) | Complication overlay |
| `.bolaOpenSettingsRequested` | Various iOS views | `IOSRootView` — navigation |
| `.bolaLLMConfigurationDidChange` | `IOSLLMSettingsSection` | `IOSChatTestSection` |

---

## 12. Sequence Diagrams

### Watch enters hungry → iPhone shows Feed button → user feeds → return to idle

```
Watch                                         iPhone
  |                                             |
  | enterEatingState()                          |
  |   interactionController.enterHungry()       |
  |   → .hungryStarted transition               |
  |   → pushPetCoreState(.hungry)               |
  |     currentPetCoreState = .hungry           |
  |     pushCompanionValue(value)               |
  |-------------------------------------------->|
  |   applicationContext + transferUserInfo     |
  |   {petCoreState: "hungry",                  |
  |    companionValue, companionValueUpdatedAt} |
  |                                             |
  |                              ingest() → currentPetCoreState = .hungry
  |                              mirrorCoreStateToController(.hungry)
  |                              interactionController.enterHungry()
  |                              Shows "idleapple" animation + "喂食" button
  |                                             |
  |<--------------------------------------------|
  |   sendPetCommand("eat")                     |
  |   (user taps 喂食)                          |
  |                                             |
  | ingestPetCommandIfPresent()                 |
  |   → .bolaPetCommandReceived                 |
  |   → handleRemotePetCommand("eat")           |
  |   → handleEatingTap()                       |
  |   → interactionController.applyEatCommand()  |
  |   → .eatingStarted transition               |
  |   → pushPetCoreState(.idle)                 |
  |     currentPetCoreState = .idle             |
  |     pushCompanionValue(value)               |
  |-------------------------------------------->|
  |                              ingest() → currentPetCoreState = .idle
  |                              mirrorCoreStateToController(.idle)
  |                              interactionController.returnToIdle()
  |                              Hides "喂食" button, returns to idle animation
```

### Speech relay round-trip

```
Watch                                         iPhone
  |                                             |
  | prepareSpeechRelay(requestId, completion)   |
  | transferFile(audio.wav, metadata)           |
  |-------------------------------------------->|
  |                                             |
  |                              session(_:didReceive:)
  |                              Copy file → transcribe (zh-CN)
  |                                             |
  |<--------------------------------------------|
  |   transferUserInfo                          |
  |   {speechRelayKind: "speechRelayReply",     |
  |    speechRelayRequestId,                    |
  |    speechRelayTranscript: "..."}            |
  |                                             |
  | ingestSpeechRelayReplyIfPresent()           |
  |   Match requestId → call completion(text)   |
  |   Cancel 45s timeout                        |
```

### LLM keychain pull (Watch has no API key)

```
Watch                                         iPhone
  |                                             |
  | requestLLMKeychainFromPhoneIfMissing()      |
  |   transferUserInfo                          |
  |   {requestSync: "llmKeychain"}              |
  |-------------------------------------------->|
  |                                             |
  |                              Recognize "llmKeychain" request
  |                              pushStoredLLMConfigurationToWatchIfConfigured()
  |                                             |
  |<--------------------------------------------|
  |   transferUserInfo                          |
  |   {llmApiKey, llmBaseURL, llmModelId,       |
  |    llmAuthBearer}                           |
  |                                             |
  | ingestLLMConfigurationIfPresent()           |
  |   Write to Keychain                         |
```

---

## 13. CompanionPersistenceKeys

| Key constant | UserDefaults key | Purpose |
|--------------|-----------------|---------|
| `companionValue` | `bola_companionValue` | Main companion score |
| `lastCompanionWallClock` | `bola_lastCompanionWallClock` | Last wall-clock timestamp |
| `lastTickTimestamp` | `bola_lastTickTimestamp` | Legacy timestamp (migrated) |
| `totalActiveSeconds` | `bola_totalActiveSeconds` | Cumulative active time |
| `activeCarrySeconds` | `bola_activeCarrySeconds` | Fractional carry for bonus |
| `lastSurpriseAtHours` | `bola_lastSurpriseAtHours` | Surprise milestone tracker |
| `companionWCUpdatedAt` | `bola_companion_wc_updated_at` | WC merge conflict timestamp |
| `migratedToAppGroupMarker` | `bola_migrated_to_app_group` | One-time migration flag |
| `companionDisplayName` | `bola_companion_display_name_v1` | User-chosen pet name |

`allCompanionKeys` returns keys 1–6. `wcGameStateSnapshotKeys` returns keys 1–7.

---

## 14. App Group & Shared Defaults

`BolaSharedDefaults.resolved()` returns `UserDefaults(suiteName: "group.com.gathxr.BolaBola")` when the App Group is available, or `UserDefaults.standard` as fallback.

With a **paid dev account**, the App Group entitlement works and both platforms share UserDefaults. With a **Personal Team**, the entitlement is silently unavailable, and `BolaSharedDefaults.resolved()` falls back to `UserDefaults.standard` (no cross-device sharing). In that case, the game state snapshot path (4.5) serves as the alternative sync mechanism.

Search `RESTORE_APP_GROUP_WHEN_PAID_DEV` for all related comments.

---

## 15. Gotchas

| Issue | Details |
|-------|---------|
| **Firebase + watchOS** | Firebase is binary-incompatible with watchOS. Only iOS links Firebase. Never add Firebase imports to Watch or Shared targets. |
| **App Group fallback** | With Personal Team, `BolaSharedDefaults.resolved()` silently falls back to `UserDefaults.standard`. The game state snapshot path compensates. |
| **Reminders ingest short-circuits** | `ingestRemindersIfPresent` returns `true` and prevents `ingest()` from running. But `petCoreState` is already applied early in `didReceiveUserInfo` before reminders are checked. |
| **Emotion label ingest guard** | `ingestPetEmotionLabelIfPresent` only handles payloads **without** `companionValue`. It won't intercept the main companion sync path. |
| **Dual-send ordering** | `updateApplicationContext` overwrites the previous context (latest-wins). If `transferUserInfo` from an older push arrives after a newer `applicationContext`, the older data is already superseded. |
| **`petCoreState` independence** | Pet core state is always applied immediately, regardless of companion value timestamp conflicts. This was a deliberate fix: previously, `petCoreState` was behind the timestamp guard and could be silently dropped. |
