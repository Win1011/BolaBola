Complete Meal/Feeding Trigger Flow Analysis
Architecture Overview
Both iPhone and Watch run independent MealEngine.shared singletons. The engine manages MealSlot configuration and generates daily MealRecord entries with statuses: pending -> hungryActive -> (fedAfterHungry / autoFed), or pending -> fedBeforeHungry. The two devices sync meal slot configuration via Watch Connectivity, but each independently detects meal times and triggers the "hungry" state locally.
Data Flow Diagram
iPhone (IOSRemindersSectionView)
  |-- user edits meal slot
  |-- persistMealSlots() -> MealSlotStore.save() + pushMealSlotsToWatchIfPossible()
  |                            |
  |                            +--> Watch WC didReceiveUserInfo
  |                                 +--> ingestMealSlotsIfPresent()
  |                                      +--> MealSlotStore.save()
  |                                      +--> post .bolaMealSlotsDidUpdate
  |                                           +--> PetViewModel.configureMealEngine observer
  |                                                +--> mealEngine.updateSlots()
  |                                                +--> scheduleMealHungryTimerIfNeeded()
  |
  |-- IOSMealCoordinator.start() [on onAppear]
  |     +--> configureMealEngine()
  |     +--> mealEngine.refreshMealState()
  |     +--> scheduleMealHungryTimerIfNeeded()
  |     +--> startMilestoneTimer() [60s poll]
  |     +--> observe .bolaMealSlotsDidUpdate [NEVER FIRES on iOS]
---
BUGS FOUND
BUG 1 (CRITICAL - iOS): New meal slots are never added to the array
File: /Users/limingchendev/Documents/BolaWatch/BolaBola/BolaBola iOS/Features/Reminders/IOSRemindersSectionView.swift
Lines 65-81
.sheet(item: $activeMealEditor) { sheet in
    IOSMealSlotEditorSheet(
        mealSlot: sheet.mealSlot,
        onSave: { slot in
            if let idx = mealSlots.firstIndex(where: { $0.id == slot.id }) {
                mealSlots[idx] = slot    // only handles EDIT of existing slot
            }
            // BUG: no `else { mealSlots.append(slot) }` for NEW slots!
            persistMealSlots()
        },
When the user taps "+添加餐食", addNewMealSlot() (line 390-393) creates a MealSlot with a new ID (e.g. "meal4") and opens the editor. When the user saves, the onSave callback searches mealSlots for a matching ID, but the new slot has never been added to the array. The if let idx branch is NOT taken, the slot is silently dropped, and persistMealSlots() saves the unchanged array.
Impact: The new meal time is never persisted to UserDefaults on the iPhone. It IS pushed to the Watch (via pushMealSlotsToWatchIfPossible), but the Watch's MealSlotStore.save() also writes the pushed data -- so the Watch gets the slot but the iPhone does not.
Fix: Add an else branch:
onSave: { slot in
    if let idx = mealSlots.firstIndex(where: { $0.id == slot.id }) {
        mealSlots[idx] = slot
    } else {
        mealSlots.append(slot)   // <-- missing
    }
    persistMealSlots()
},
---
BUG 2 (CRITICAL - iOS): .bolaMealSlotsDidUpdate notification never posted on iOS side
File: /Users/limingchendev/Documents/BolaWatch/BolaBola/BolaBola iOS/Features/Reminders/IOSRemindersSectionView.swift, line 384-388
File: /Users/limingchendev/Documents/BolaWatch/BolaBola/Shared/Sync/BolaWCSessionCoordinator.swift, line 948-957
The persistMealSlots() method on iOS:
private func persistMealSlots() {
    MealSlotStore.save(mealSlots)
    BolaWCSessionCoordinator.shared.pushMealSlotsToWatchIfPossible()
    // BUG: no NotificationCenter.default.post(name: .bolaMealSlotsDidUpdate, ...)
}
The .bolaMealSlotsDidUpdate notification is only posted by ingestMealSlotsIfPresent() which is compiled under #if os(watchOS):
// BolaWCSessionCoordinator.swift line 948-957
#if os(watchOS)
@discardableResult
private static func ingestMealSlotsIfPresent(_ dict: [String: Any]) -> Bool {
    ...
    MealSlotStore.save(slots)
    NotificationCenter.default.post(name: .bolaMealSlotsDidUpdate, object: nil)  // only on watchOS!
    return true
}
#endif
Meanwhile, IOSMealCoordinator registers for this notification (line 28-38):
NotificationCenter.default.addObserver(
    forName: .bolaMealSlotsDidUpdate,
    object: nil,
    queue: .main
) { [weak self] _ in
    let updatedSlots = MealSlotStore.load(from: BolaSharedDefaults.resolved())
    self.mealEngine.updateSlots(updatedSlots, now: Date())
    self.scheduleMealHungryTimerIfNeeded(now: Date())
}
This observer will never fire on iOS because the notification is only posted on watchOS. So even if Bug 1 is fixed and the slot IS saved to UserDefaults, the IOSMealCoordinator's MealEngine instance still has stale in-memory slots and will never trigger hungry for the new meal time.
Impact: After any meal slot edit on iPhone, IOSMealCoordinator.mealEngine has stale data. The one-shot timer targets the wrong (old) date. Even the 60-second milestone timer polls refreshMealState with stale records.
Fix: Add notification posting to persistMealSlots():
private func persistMealSlots() {
    MealSlotStore.save(mealSlots)
    BolaWCSessionCoordinator.shared.pushMealSlotsToWatchIfPossible()
    NotificationCenter.default.post(name: .bolaMealSlotsDidUpdate, object: nil)
}
---
BUG 3 (HIGH - Watch): scheduleMealHungryTimerIfNeeded never called during Watch init
File: /Users/limingchendev/Documents/BolaWatch/BolaBola/BolaBola Watch App/Views/ContentView.swift, lines 923-951
private func configureMealEngine() {
    mealEngine.onTriggerHungry = { [weak self] in ... }
    mealEngine.onExitHungry = { [weak self] in ... }
    mealEngine.refreshMealState(now: Date())   // <-- catch-up only
    // BUG: no scheduleMealHungryTimerIfNeeded(now: Date()) here!
    
    NotificationCenter.default.addObserver(
        forName: .bolaMealSlotsDidUpdate, ...
    ) { [weak self] _ in
        ...
        self.mealEngine.updateSlots(updatedSlots, now: Date())
        self.scheduleMealHungryTimerIfNeeded(now: Date())  // only here
    }
}
configureMealEngine() is called in PetViewModel.init() (line 214). It calls refreshMealState for catch-up (past meals) but does NOT call scheduleMealHungryTimerIfNeeded for future meals. This means no precise one-shot timer is set on Watch startup. The only fallback is the 60-second milestone timer (line 1605-1613), which has up to 60 seconds of delay.
Impact: When the Watch app is opened and a meal is scheduled, say, 2 minutes in the future, the pet may not enter the hungry state until up to 60 seconds after the meal time has passed.
Fix: Add scheduleMealHungryTimerIfNeeded(now: Date()) to configureMealEngine():
private func configureMealEngine() {
    mealEngine.onTriggerHungry = { ... }
    mealEngine.onExitHungry = { ... }
    mealEngine.refreshMealState(now: Date())
    scheduleMealHungryTimerIfNeeded(now: Date())   // <-- missing
    
    NotificationCenter.default.addObserver(...)
}
---
BUG 4 (HIGH - Watch): scheduleMealHungryTimerIfNeeded not called on foreground return
File: /Users/limingchendev/Documents/BolaWatch/BolaBola/BolaBola Watch App/Views/ContentView.swift, lines 1522-1529
case .active:
    isForegroundActive = true
    beginOpenAppGrowthSessionIfNeeded()
    #if os(watchOS)
    BolaWCSessionCoordinator.shared.reapplyLatestReceivedContext()
    #endif
    applyWallClockCompanionDeltaFromLastCredit()
    mealEngine.refreshMealState(now: Date())   // <-- catch-up only
    // BUG: no scheduleMealHungryTimerIfNeeded(now: Date()) here!
    speakForegroundGreetingIfNeeded()
    ...
On iOS, IOSMealCoordinator.handleScenePhaseActive() correctly calls both refreshMealState AND scheduleMealHungryTimerIfNeeded (line 41-43). On the Watch, only refreshMealState is called. After returning to the foreground, no one-shot timer is scheduled for the next pending meal.
Impact: After the Watch app goes to background and returns, the precise one-shot timer is not re-scheduled. The 60-second poll is the only fallback.
Fix: Add scheduleMealHungryTimerIfNeeded(now: Date()) to the .active case in handleScenePhaseChange.
---
BUG 5 (MEDIUM - Both): One-shot timer not rescheduled after it fires
File (Watch): /Users/limingchendev/Documents/BolaWatch/BolaBola/BolaBola Watch App/Views/ContentView.swift, lines 1006-1014
File (iOS): /Users/limingchendev/Documents/BolaWatch/BolaBola/BolaBola iOS/Features/Home/IOSMealCoordinator.swift, lines 110-118
Both platforms have the same issue:
mealHungryScheduleCancellable = Timer
    .publish(every: delay, on: .main, in: .common)
    .autoconnect()
    .sink { [weak self] _ in
        guard let self else { return }
        self.mealHungryScheduleCancellable?.cancel()
        self.mealHungryScheduleCancellable = nil
        self.mealEngine.refreshMealState(now: Date())
        // BUG: no self.scheduleMealHungryTimerIfNeeded(now: Date()) here!
    }
After the one-shot timer fires and refreshMealState runs (which may trigger hungry or auto-feed), the timer is cancelled but never rescheduled for the next pending meal. If there are multiple meals per day, only the first one gets a precise trigger; subsequent meals rely on the 60-second poll.
Impact: For multi-meal schedules, only the soonest meal gets a precise one-shot timer. All subsequent meals have up to 60 seconds of delay from the milestone timer.
Fix: Add self.scheduleMealHungryTimerIfNeeded(now: Date()) after self.mealEngine.refreshMealState(now: Date()) in both timer handlers.
---
BUG 6 (MEDIUM - Both): onTriggerHungry / onExitHungry callbacks don't reschedule the next timer
File (Watch): /Users/limingchendev/Documents/BolaWatch/BolaBola/BolaBola Watch App/Views/ContentView.swift, lines 924-936
File (iOS): /Users/limingchendev/Documents/BolaWatch/BolaBola/BolaBola iOS/Features/Home/IOSMealCoordinator.swift, lines 65-77
When refreshMealState detects a meal transition (pending -> hungryActive, or hungryActive -> autoFed), it calls onTriggerHungry or onExitHungry. Neither callback calls scheduleMealHungryTimerIfNeeded. This is related to Bug 5 but distinct -- even if Bug 5 is fixed by adding a reschedule in the one-shot timer handler, the 60-second milestone timer's refreshMealState can also trigger these callbacks without any rescheduling.
---
Complete File Reference with Key Line Numbers
File	Lines	What
Shared/Meals/MealEngine.swift	15-33	Singleton init, loadSlots() + generateTodayRecordsIfNeeded()
Shared/Meals/MealEngine.swift	42-48	updateSlots() - saves + regenerates records + refreshes
Shared/Meals/MealEngine.swift	91-128	refreshMealState() - catch-up reconciliation, calls onTriggerHungry/onExitHungry
Shared/Meals/MealEngine.swift	132-160	resolveFeedAction() - feed resolution
Shared/Meals/MealEngine.swift	162-175	findValidMealTarget() - early window (-2h to scheduled) for pending, any time for hungryActive
Shared/Meals/MealEngine.swift	187-192	nextPendingTriggerDate() - returns earliest future pending date
Shared/Meals/MealEngine.swift	212-252	regenerateRecordsAfterSlotUpdate() - rebuilds records after slot change
Shared/Meals/MealSlot.swift	8-28	MealSlot model with id/hour/minute
Shared/Meals/MealSlot.swift	30-48	MealSlotStore load/save (UserDefaults)
Shared/Meals/MealRecord.swift	8-21	MealRecordStatus enum (pending/fedBeforeHungry/hungryActive/fedAfterHungry/autoFed)
Shared/Meals/MealRecord.swift	23-28	MealRecord model
Shared/Meals/MealRecord.swift	30-48	MealRecordStore load/save
Shared/Sync/WCSyncPayload.swift	56-57	mealSlotsB64 key
Shared/Sync/BolaWCSessionCoordinator.swift	464-474	pushMealSlotsToWatchIfPossible() - transferUserInfo
Shared/Sync/BolaWCSessionCoordinator.swift	948-957	ingestMealSlotsIfPresent() - watchOS only, posts .bolaMealSlotsDidUpdate
Shared/Sync/BolaWCSessionCoordinator.swift	851-910	ingest() - processes received data, early-returns on meal slots
Shared/Sync/BolaWCSessionCoordinator.swift	1084-1127	didReceiveUserInfo - dispatches to specialized ingestors
Shared/Sync/PetCoreState.swift	11-17	PetCoreState enum (idle/hungry/thirsty/sleepWait/sleeping)
Shared/Sync/ChatTurn.swift	24	.bolaMealSlotsDidUpdate notification name definition
BolaBola iOS/Features/Reminders/IOSRemindersSectionView.swift	65-81	BUG 1: onSave missing append for new slots
BolaBola iOS/Features/Reminders/IOSRemindersSectionView.swift	384-388	BUG 2: persistMealSlots() doesn't post .bolaMealSlotsDidUpdate
BolaBola iOS/Features/Reminders/IOSRemindersSectionView.swift	390-394	addNewMealSlot() - creates new slot, opens editor
BolaBola iOS/Features/Reminders/IOSRemindersSectionView.swift	453-519	IOSMealSlotEditorSheet - time picker + save/delete
BolaBola iOS/Features/Home/IOSMealCoordinator.swift	9-121	Full iOS meal coordinator
BolaBola iOS/Features/Home/IOSMealCoordinator.swift	20-38	start() - configure engine + schedule timer + register observer
BolaBola iOS/Features/Home/IOSMealCoordinator.swift	64-77	configureMealEngine() - sets onTriggerHungry/onExitHungry callbacks
BolaBola iOS/Features/Home/IOSMealCoordinator.swift	94-102	startMilestoneTimer() - 60-second poll
BolaBola iOS/Features/Home/IOSMealCoordinator.swift	104-120	scheduleMealHungryTimerIfNeeded() - one-shot timer (BUG 5: no reschedule after fire)
BolaBola iOS/Features/Home/IOSMainHomeView.swift	40	@StateObject private var mealCoordinator = IOSMealCoordinator.shared
BolaBola iOS/Features/Home/IOSMainHomeView.swift	111	mealCoordinator.start() on .onAppear
BolaBola iOS/Features/Home/IOSMainHomeView.swift	126	mealCoordinator.handleScenePhaseActive() on scene phase active
BolaBola iOS/Features/Home/IOSMainHomeView.swift	228-232	"喂食" button shown when coordinator.currentPetCoreState == .hungry
BolaBola iOS/Features/Home/IOSMainHomeView.swift	248-251	triggerEat() -> mealCoordinator.performMealFeed() + animation
BolaBola iOS/Features/Home/IOSMainHomeView.swift	337-363	mirrorCoreStateToController() - maps PetCoreState to animation
BolaBola Watch App/Views/ContentView.swift	87	let mealEngine = MealEngine.shared in PetViewModel
BolaBola Watch App/Views/ContentView.swift	139	mealHungryScheduleCancellable: AnyCancellable?
BolaBola Watch App/Views/ContentView.swift	214	configureMealEngine() called in init
BolaBola Watch App/Views/ContentView.swift	910-914	enterEatingState()
BolaBola Watch App/Views/ContentView.swift	923-951	configureMealEngine() - BUG 3: no scheduleMealHungryTimerIfNeeded after init
BolaBola Watch App/Views/ContentView.swift	953-976	performMealFeed() - resolve feed on Watch
BolaBola Watch App/Views/ContentView.swift	988-998	exitHungryStateSilently() - returns to idle
BolaBola Watch App/Views/ContentView.swift	1000-1016	scheduleMealHungryTimerIfNeeded() (BUG 5: no reschedule after fire)
BolaBola Watch App/Views/ContentView.swift	1513-1549	handleScenePhaseChange(.active) - BUG 4: no scheduleMealHungryTimerIfNeeded
BolaBola Watch App/Views/ContentView.swift	1605-1617	60-second milestone timer calls refreshMealState
Documentation/iphone_meal_scheduling_plan.md	1-143	Architecture plan documenting the move to independent MealEngine on both devices
---
Root Cause for the User's Report
The user says: "Setting a meal time to 2 minutes from now doesn't trigger the 'hungry' state on either device."
On iPhone, two bugs compound:
1. BUG 1: The new meal slot is never added to the mealSlots array (the onSave callback only replaces existing slots, never appends new ones). So the slot is never saved to UserDefaults at all.
2. BUG 2: Even if Bug 1 were fixed, IOSMealCoordinator would never learn about the new slot because .bolaMealSlotsDidUpdate is only posted on watchOS. The MealEngine singleton has stale in-memory data.
On Watch, two bugs compound:
1. BUG 3: scheduleMealHungryTimerIfNeeded is not called during configureMealEngine(), so no precise one-shot timer is set on Watch startup.
2. BUG 4: scheduleMealHungryTimerIfNeeded is not called when the Watch returns to the foreground.
However, the Watch should still eventually trigger hungry via the 60-second milestone timer, assuming the Watch received the meal slots from the iPhone via WC. But there can be up to 60 seconds of delay, and the WC delivery itself may take additional time.
Priority Fix Order
1. BUG 1 (iOS) - Add mealSlots.append(slot) in the else branch of onSave
2. BUG 2 (iOS) - Post .bolaMealSlotsDidUpdate notification in persistMealSlots()
3. BUG 3 (Watch) - Add scheduleMealHungryTimerIfNeeded(now: Date()) to configureMealEngine()
4. BUG 4 (Watch) - Add scheduleMealHungryTimerIfNeeded(now: Date()) to handleScenePhaseChange(.active)
5. BUG 5 (Both) - Add scheduleMealHungryTimerIfNeeded(now: Date()) after refreshMealState in the one-shot timer handler on both platforms