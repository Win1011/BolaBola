# iPhone Meal Scheduling — Architecture & Implementation Plan

Date: 2026-04-22

## Problem

iPhone 端 Bola 在饭点没有任何反应。根本原因：所有餐食调度逻辑（`MealEngine`）仅在 Watch 端运行，iPhone 完全被动依赖 Watch 推送的 `PetCoreState.hungry`。当 Watch 离线或未连接时，iPhone 上的宠物不会进入饥饿状态。

### 原有架构

```
iPhone (编辑餐时) → WC transferUserInfo → Watch (MealEngine) → 检测饭点 → 推 PetCoreState.hungry → iPhone (镜像动画)
```

### 问题清单

1. **iPhone 无独立餐食调度**：Watch 离线时 iPhone 宠物不触发饥饿
2. **Watch 同步路径 bug**：iPhone 修改餐时后 Watch 只调 `loadSlots()` + `refreshMealState()`，不重建 pending 记录的 `scheduledDate`（已修复：改为 `updateSlots()`）
3. **60 秒轮询延迟**：饭点到后最多等 60 秒才触发饥饿（已修复：增加一次性饥饿定时器）
4. **`.hungryActive` 记录 `scheduledDate` 不随 slot 更新**：auto-feed 截止时间仍基于旧餐时

## Solution

### 新架构

```
iPhone (MealEngine 独立运行) ←→ WC ←→ Watch (MealEngine 独立运行)
     ↓                                    ↓
  本地触发 hungry                       本地触发 hungry
     ↓                                    ↓
  pushPetCoreState → WC → 镜像       pushPetCoreState → WC → 镜像
```

两端各自运行 `MealEngine`，独立检测饭点。WC 推送的状态作为补充/覆盖。先到的先生效，后到的同状态 no-op。

---

## Implementation Steps

### Step 1: Move MealEngine & MealRecord to Shared Target

| File | From | To |
|---|---|---|
| `MealEngine.swift` | `BolaBola Watch App/Meals/` | `Shared/Meals/` |
| `MealRecord.swift` | `BolaBola Watch App/Meals/` | `Shared/Meals/` |

- Update file header comments (remove "Watch-only")
- Xcode target membership: Watch → Shared (both iOS + Watch compile)
- Code itself needs no modification

### Step 2: Fix `.hungryActive` scheduledDate Update in `regenerateRecordsAfterSlotUpdate`

**File**: `MealEngine.swift:216-218`

**Current** (`.hungryActive` records keep old `scheduledDate`):
```swift
if existing.status.isFinalized || existing.status == .hungryActive {
    newRecords.append(existing)
}
```

**Fixed** (`.hungryActive` records get updated `scheduledDate`, auto-feed deadline = new time + 1h):
```swift
if existing.status.isFinalized {
    newRecords.append(existing)
} else if existing.status == .hungryActive {
    var updated = existing
    updated.scheduledDate = scheduled
    newRecords.append(updated)
}
```

### Step 3: Create `IOSMealCoordinator`

**New file**: `BolaBola iOS/Features/Home/IOSMealCoordinator.swift`

An `ObservableObject` that runs `MealEngine` on iPhone independently.

**Properties**:
- `mealEngine: MealEngine` instance
- `milestoneTimerCancellable: AnyCancellable?` (60s poll)
- `mealHungryScheduleCancellable: AnyCancellable?` (one-shot hungry timer)
- `coordinator` = `BolaWCSessionCoordinator.shared`

**Methods**:

| Method | Purpose |
|---|---|
| `start()` | Configure engine callbacks, start timers, register for notifications |
| `handleScenePhaseActive()` | Called when app enters foreground; refresh + reschedule |
| `performMealFeed(companion:)` | Resolve feed locally, add reward, set `.idle`, send `.feed` to Watch if reachable |

**Callback logic**:
- `onTriggerHungry` → Set `coordinator.currentPetCoreState = .hungry` (if not already in eating/drink/sleep state)
- `onExitHungry` → Set `coordinator.currentPetCoreState = .idle`

**Feed reward strategy**:
- **Watch reachable**: iPhone resolves feed locally (updates MealRecord), plays animation, sets `.idle`, sends `.feed` command to Watch. Watch also resolves and adds reward. Both sides add the same reward amount from the same base → Watch pushes back companion value with updated timestamp → iPhone's value gets overwritten with the same correct result. No double-reward risk.
- **Watch unreachable**: iPhone resolves feed locally, adds companion reward to UserDefaults directly, updates `companionWCUpdatedAt` timestamp. `.feed` command queued via `transferUserInfo` for delivery on reconnect.

### Step 4: Update `IOSMainHomeView`

- Add `@StateObject private var mealCoordinator = IOSMealCoordinator()`
- `.onAppear`: call `mealCoordinator.start()`
- `.onChange(of: scenePhase)` active: call `mealCoordinator.handleScenePhaseActive()`
- Modify `triggerEat()`:
  - Current: `interactionController.applyEatCommand()` + `sendPetCommand(.feed)`
  - New: `mealCoordinator.performMealFeed(companion: &companion)` + `interactionController.applyEatCommand()`
- "Feed" button visibility: `coordinator.currentPetCoreState == .hungry` (unchanged)

### Step 5: Update Xcode Project

- Remove `MealEngine.swift` and `MealRecord.swift` from Watch target membership
- Add both to Shared target membership
- Add `IOSMealCoordinator.swift` to iOS target

---

## Edge Cases

| Scenario | Behavior |
|---|---|
| Watch online + iPhone hungry + feed | iPhone resolves locally + sends `.feed` to Watch. Both add reward from same base. Watch pushes back companion with updated timestamp → correct single reward. |
| Watch offline + iPhone hungry + feed | iPhone resolves locally + adds reward directly. `.feed` queued via `transferUserInfo`. |
| Watch pushes `.hungry` but iPhone already hungry | Same state, no-op |
| Watch pushes `.idle` but iPhone still hungry | `mirrorCoreStateToController(.idle)` exits hunger |
| Both sides independently auto-feed | First one wins, second is idle→idle no-op |
| Meal time changed + `.hungryActive` record | Step 2 fix: `scheduledDate` updated, auto-feed deadline = new time + 1h |
| Meal time changed + `.pending` record | `regenerateRecordsAfterSlotUpdate` rebuilds with new `scheduledDate` (existing behavior, now also called from iPhone sync path) |
| Meal time changed + `.finalized` record | Preserved as-is (already fed, time change irrelevant) |

---

## Files Changed

| File | Change |
|---|---|
| `Shared/Meals/MealEngine.swift` | Moved from Watch; fix `.hungryActive` scheduledDate update |
| `Shared/Meals/MealRecord.swift` | Moved from Watch |
| `BolaBola iOS/Features/Home/IOSMealCoordinator.swift` | New file |
| `BolaBola iOS/Features/Home/IOSMainHomeView.swift` | Integrate IOSMealCoordinator |
| `BolaBola Watch App/Views/ContentView.swift` | Already fixed: sync path uses `updateSlots()` + `scheduleMealHungryTimerIfNeeded()` |
| `BolaBola.xcodeproj/project.pbxproj` | Target membership updates |
