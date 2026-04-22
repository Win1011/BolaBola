# 餐食触发 Bug 修复记录

Date: 2026-04-22

## 用户反馈

在手机上修改一个餐食的时间到当前时间的 2 分钟之后，2 分钟后手机和手表都没有触发 hungry 状态。

---

## Bug 1（致命 - iOS）：新增餐食从未被保存

**文件**: `BolaBola iOS/Features/Reminders/IOSRemindersSectionView.swift:68-73`

**原因**: `onSave` 回调只处理编辑已有 slot（`if let idx` 分支），缺少 `else { mealSlots.append(slot) }`。用户新增餐食后，新 slot 被静默丢弃，从未写入 UserDefaults。

**修复**:
```swift
// Before
onSave: { slot in
    if let idx = mealSlots.firstIndex(where: { $0.id == slot.id }) {
        mealSlots[idx] = slot
    }
    persistMealSlots()
}

// After
onSave: { slot in
    if let idx = mealSlots.firstIndex(where: { $0.id == slot.id }) {
        mealSlots[idx] = slot
    } else {
        mealSlots.append(slot)
    }
    persistMealSlots()
}
```

---

## Bug 2（致命 - iOS）：`.bolaMealSlotsDidUpdate` 通知在 iOS 端从未发出

**文件**: `BolaBola iOS/Features/Reminders/IOSRemindersSectionView.swift:384-388`

**原因**: `persistMealSlots()` 只保存到 UserDefaults + 推送 Watch，没有发 `NotificationCenter` 通知。而该通知仅在 `BolaWCSessionCoordinator.swift` 的 `#if os(watchOS)` 分支中发出。`IOSMealCoordinator` 注册了 `.bolaMealSlotsDidUpdate` 观察者（第 28 行），但永远收不到。即使 Bug 1 修好了，`MealEngine` 内存中的 slot 仍是旧数据。

**修复**: 在 `persistMealSlots()` 中新增通知发送：
```swift
private func persistMealSlots() {
    MealSlotStore.save(mealSlots)
    BolaWCSessionCoordinator.shared.pushMealSlotsToWatchIfPossible()
    NotificationCenter.default.post(name: .bolaMealSlotsDidUpdate, object: nil)  // ← 新增
    BolaDebugLog.shared.log(.meal, "iPhone meal slots saved & pushed count=\(mealSlots.count)")
}
```

---

## Bug 3（高 - Watch）：`configureMealEngine()` 未调用 `scheduleMealHungryTimerIfNeeded`

**文件**: `BolaBola Watch App/Views/ContentView.swift:923-951`

**原因**: Watch 初始化 `MealEngine` 时只调了 `refreshMealState`（处理过去餐食的 catch-up），没有为未来餐食设置一次性精确定时器。Watch 启动后只能靠 60 秒轮询兜底。

**修复**: 在 `configureMealEngine()` 中 `refreshMealState` 之后新增：
```swift
mealEngine.refreshMealState(now: Date())
scheduleMealHungryTimerIfNeeded(now: Date())  // ← 新增
```

---

## Bug 4（高 - Watch）：前台恢复时未重新调度定时器

**文件**: `BolaBola Watch App/Views/ContentView.swift:1522-1529`

**原因**: `handleScenePhaseChange(.active)` 只调了 `refreshMealState`，没有 `scheduleMealHungryTimerIfNeeded`。iOS 端的 `handleScenePhaseActive()` 正确调了两者，Watch 端遗漏。Watch 从后台回到前台后，一次性定时器不会被重建。

**修复**: 在 `.active` 分支中新增：
```swift
mealEngine.refreshMealState(now: Date())
scheduleMealHungryTimerIfNeeded(now: Date())  // ← 新增
```

---

## Bug 5（中 - 双端）：一次性定时器触发后未重新调度

**文件**: 
- `BolaBola Watch App/Views/ContentView.swift:1006-1014`
- `BolaBola iOS/Features/Home/IOSMealCoordinator.swift:110-118`

**原因**: 一次性定时器触发后只调了 `refreshMealState` 并 cancel 自身，没有为下一个 pending 餐食重新调度。多餐场景下，只有最近的一餐能精确触发，后续餐食依赖 60 秒轮询（最多延迟 60 秒）。

**修复**: 在双端定时器回调末尾新增重新调度：
```swift
// Watch
.sink { [weak self] _ in
    guard let self else { return }
    self.mealHungryScheduleCancellable?.cancel()
    self.mealHungryScheduleCancellable = nil
    self.mealEngine.refreshMealState(now: Date())
    self.scheduleMealHungryTimerIfNeeded(now: Date())  // ← 新增
}

// iOS
.sink { [weak self] _ in
    guard let self else { return }
    self.mealHungryScheduleCancellable?.cancel()
    self.mealHungryScheduleCancellable = nil
    self.mealEngine.refreshMealState(now: Date())
    self.scheduleMealHungryTimerIfNeeded(now: Date())  // ← 新增
}
```

---

## 根因分析

用户报告的「修改餐食时间 2 分钟后双端都不触发 hungry」的直接原因：

- **iPhone 不触发**：Bug 1 + Bug 2 叠加 — 新餐食 slot 根本没保存到本地（Bug 1），且 MealEngine 永远不知道有新 slot（Bug 2）
- **Watch 不触发**：Bug 3 + Bug 4 — 即使 Watch 通过 WC 收到了 slot 数据，也没有为未来餐食设置精确定时器，只能靠 60 秒轮询兜底（最多延迟 60 秒）
