# Extract Pet Interaction + Action Bar from IOSMainHomeView

## TL;DR
> **Summary**: Extract pet interaction logic and action bar UI from the 1389-line `IOSMainHomeView.swift` into two new files: `IOSPetInteractionHandler` (ObservableObject) and `IOSPetActionBarView` (subview).
> **Deliverables**: 2 new Swift files, 1 modified file
> **Effort**: Short
> **Parallel**: YES - 2 waves
> **Critical Path**: Handler → View update

## Context

### Original Request
User observed "我感觉现在所有的功能全写在一个script里" — all pet interaction logic (button handlers, state machine sync, condition checks, toast) lives in the massive `IOSMainHomeView.swift`. Chose to extract Pet interaction handler + Action Bar view.

### Interview Summary
- Scope: Pet interaction + Action Bar only. Table face, title, companion sections stay in IOSMainHomeView for now.
- `interactionController` ownership: moves to `IOSPetInteractionHandler`. View accesses via `petHandler.interactionController`.
- `companion` binding: stays as view's `@Binding`. `triggerEat(companion:)` takes `inout Double` param.

### Metis Review
(Not consulted — this is a mechanical extraction with no ambiguity.)

## Work Objectives

### Core Objective
Move all pet interaction logic into `IOSPetInteractionHandler` and the action bar UI into `IOSPetActionBarView`, reducing `IOSMainHomeView` by ~120 lines of logic + ~40 lines of UI.

### Deliverables
1. `BolaBola iOS/Features/Home/IOSPetInteractionHandler.swift` — ObservableObject owning interactionController + all pet interaction methods
2. `BolaBola iOS/Features/Home/IOSPetActionBarView.swift` — standalone action bar subview
3. Updated `IOSMainHomeView.swift` — uses handler + subview

### Definition of Done
- `xcodebuild build -scheme BolaBola -destination "generic/platform=iOS"` succeeds
- All 22 references to `interactionController` in IOSMainHomeView updated to `petHandler.interactionController`
- No pet interaction logic (handlers, triggers, mirror, condition helpers, toast) remains directly in IOSMainHomeView

### Must Have
- Handler owns `interactionController: PetAnimationController`
- Handler owns `actionToastText: String?` and `showActionToast()`
- Action Bar view takes handler as `@ObservedObject`
- `triggerEat(companion:)` takes `inout Double` to support existing `performMealFeed` API

### Must NOT Have
- Do NOT modify `IOSMealCoordinator`, `PetAnimationController`, or any Shared/ code
- Do NOT extract table face, title, companion sections — out of scope
- Do NOT change the visual appearance or behavior of any UI

## Verification Strategy
- Test decision: none (no test targets exist)
- QA policy: Build succeeds, LSP diagnostics clean
- Evidence: Build output

## Execution Strategy

### Parallel Execution Waves

Wave 1: [handler + action bar view — can be created in parallel]
- Task 1: Create IOSPetInteractionHandler.swift (category: quick)
- Task 2: Create IOSPetActionBarView.swift (category: quick)

Wave 2: [depends on Wave 1]
- Task 3: Update IOSMainHomeView.swift to use handler + subview (category: quick)
- Task 4: Build verification (category: quick)

### Dependency Matrix
| Task | Blocks | Blocked By |
|------|--------|------------|
| 1 | 3 | — |
| 2 | 3 | — |
| 3 | 4 | 1, 2 |
| 4 | — | 3 |

### Agent Dispatch Summary
Wave 1: 2 tasks → quick × 2
Wave 2: 2 tasks → quick × 2

## TODOs

- [ ] 1. Create IOSPetInteractionHandler.swift

  **What to do**: Create `BolaBola iOS/Features/Home/IOSPetInteractionHandler.swift` with an `@MainActor final class IOSPetInteractionHandler: ObservableObject`.

  **Must NOT do**: Do NOT modify any existing files. Do NOT change any API signatures in Shared/ code.

  **Recommended Agent Profile**:
  - Category: `quick` — Reason: Single new file, mechanical extraction
  - Skills: [] — No special skills needed
  - Omitted: [] — N/A

  **Parallelization**: Can Parallel: YES | Wave 1 | Blocks: 3 | Blocked By: —

  **References**:
  - Source of methods to extract: `BolaBola iOS/Features/Home/IOSMainHomeView.swift` lines 246-322 (triggerEat through showActionToast), lines 399-421 (mirrorCoreStateToController, isInWaitingLoop/EatingFlow/DrinkingFlow/SleepFlow), lines 466-477 (configureInteractionControllerSync)
  - `PetAnimationController`: `Shared/Animation/PetAnimationController.swift` — all public methods
  - `BolaWCSessionCoordinator.shared`: `Shared/Sync/BolaWCSessionCoordinator.swift:311` — pushPetCoreState
  - `IOSMealCoordinator.shared`: `BolaBola iOS/Features/Home/IOSMealCoordinator.swift:46` — performMealFeed(companion:)
  - `MealEngine.shared`: `Shared/Meals/MealEngine.swift` — todayRecords, generateTodayRecordsIfNeeded
  - `PetInteractionEmotion`: `Shared/Animation/PetAnimationController.swift:43` — enum cases for isInWaitingLoop etc.
  - `CompanionPersistenceKeys`: used in `handlePetMockupTap` for reading companion value

  Class structure:
  ```
  @MainActor
  final class IOSPetInteractionHandler: ObservableObject {
      @Published var actionToastText: String?
      let interactionController = PetAnimationController()

      private let coordinator = BolaWCSessionCoordinator.shared
      private let mealCoordinator = IOSMealCoordinator.shared

      // Interaction handlers (called by action bar buttons)
      func handleDrinkButton() { ... }
      func handleFeedButton() { ... }
      func handleSleepButton() { ... }

      // Tap handlers (called by mockup tap)
      func triggerEat(companion: inout Double) { ... }
      func triggerDrink() { ... }
      func triggerSleep() { ... }
      func handleIdleTap(companion: inout Double) -> Bool { ... }
          // Returns Bool like PetAnimationController.handleIdleTap, 
          // also updates companion value if tap succeeded

      // State sync
      func configureInteractionControllerSync() { ... }
      func mirrorCoreStateToController(_ state: PetCoreState) { ... }

      // Condition helpers
      func isWithinOneHourOfMeal() -> Bool { ... }
      func isPastBedtime() -> Bool { ... }

      // Toast
      func showActionToast(_ text: String) { ... }

      // Internal helpers (private)
      private func isInWaitingLoop(_ emotion: PetInteractionEmotion?) -> Bool { ... }
      private func isInEatingFlow(_ emotion: PetInteractionEmotion?) -> Bool { ... }
      private func isInDrinkingFlow(_ emotion: PetInteractionEmotion?) -> Bool { ... }
      private func isInSleepFlow(_ emotion: PetInteractionEmotion?) -> Bool { ... }
  }
  ```

  Key implementation details:
  - `handleIdleTap(companion:)` combines the current `interactionController.handleIdleTap()` + the companion update logic from IOSMainHomeView line 385-394:
    ```swift
    func handleIdleTap(companion: inout Double) -> Bool {
        guard interactionController.handleIdleTap() else { return false }
        BolaWCSessionCoordinator.shared.incrementCompanionValueLocally(by: 1)
        companion = BolaSharedDefaults.resolved().double(forKey: CompanionPersistenceKeys.companionValue)
        return true
    }
    ```
  - `mirrorCoreStateToController` logic stays exactly the same, just references `interactionController` as `self.interactionController`
  - `configureInteractionControllerSync` sets `interactionController.onTransition` — same logic as current lines 466-477
  - `triggerEat(companion:)` wraps `mealCoordinator.performMealFeed(companion:)` + `interactionController.applyEatCommand()`
  - `isWithinOneHourOfMeal()` and `isPastBedtime()` are copied verbatim from current IOSMainHomeView
  - Import Foundation and SwiftUI (for @MainActor, @Published, ObservableObject)

  **Acceptance Criteria**:
  - [ ] File exists at `BolaBola iOS/Features/Home/IOSPetInteractionHandler.swift`
  - [ ] Class has all methods listed above
  - [ ] No compilation errors in the new file (LSP clean)

  **QA Scenarios**:
  ```
  Scenario: New file compiles
    Tool: Bash
    Steps: xcodebuild build -scheme BolaBola -destination "generic/platform=iOS"
    Expected: BUILD SUCCEEDED
    Evidence: .sisyphus/evidence/task-1-handler-build.txt
  ```

  **Commit**: YES | Message: `refactor(ios): extract IOSPetInteractionHandler from IOSMainHomeView` | Files: [new file path]

- [ ] 2. Create IOSPetActionBarView.swift

  **What to do**: Create `BolaBola iOS/Features/Home/IOSPetActionBarView.swift` with a standalone SwiftUI view.

  **Must NOT do**: Do NOT duplicate business logic. All logic lives in the handler.

  **Recommended Agent Profile**:
  - Category: `quick` — Reason: Single new file, UI extraction
  - Skills: [] — No special skills needed
  - Omitted: [] — N/A

  **Parallelization**: Can Parallel: YES | Wave 1 | Blocks: 3 | Blocked By: —

  **References**:
  - Source of UI: `BolaBola iOS/Features/Home/IOSMainHomeView.swift` lines 227-244 (petActionBar), lines 324-343 (petActionButton helper)
  - Handler: Task 1 output — `IOSPetInteractionHandler`

  View structure:
  ```swift
  import SwiftUI

  struct IOSPetActionBarView: View {
      @ObservedObject var handler: IOSPetInteractionHandler

      var body: some View {
          VStack(spacing: 6) {
              HStack(spacing: 14) {
                  petActionButton(title: "喂食", systemImage: "leaf.fill", tint: .green) {
                      handler.handleFeedButton()
                  }
                  petActionButton(title: "喝水", systemImage: "drop.fill", tint: .blue) {
                      handler.handleDrinkButton()
                  }
                  petActionButton(title: "睡觉", systemImage: "moon.zzz.fill", tint: .purple) {
                      handler.handleSleepButton()
                  }
              }
              .frame(maxWidth: .infinity)

              if let text = handler.actionToastText {
                  Text(text)
                      .font(.system(size: 13, weight: .medium))
                      .foregroundStyle(.secondary)
                      .transition(.opacity)
                      .animation(.easeInOut(duration: 0.25), value: handler.actionToastText)
              }
          }
      }

      private func petActionButton(title: String, systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
          Button(action: action) {
              HStack(spacing: 6) {
                  Image(systemName: systemImage)
                      .font(.system(size: 14, weight: .semibold))
                  Text(title)
                      .font(.system(size: 14, weight: .semibold))
              }
              .foregroundStyle(tint)
              .padding(.horizontal, 14)
              .padding(.vertical, 8)
              .background(
                  Capsule().fill(tint.opacity(0.14))
              )
              .overlay(
                  Capsule().stroke(tint.opacity(0.45), lineWidth: 1)
              )
          }
          .buttonStyle(.plain)
      }
  }
  ```

  **Acceptance Criteria**:
  - [ ] File exists at `BolaBola iOS/Features/Home/IOSPetActionBarView.swift`
  - [ ] View renders 3 buttons + conditional toast
  - [ ] All button actions delegate to handler methods

  **QA Scenarios**:
  ```
  Scenario: New file compiles
    Tool: Bash
    Steps: xcodebuild build -scheme BolaBola -destination "generic/platform=iOS"
    Expected: BUILD SUCCEEDED
    Evidence: .sisyphus/evidence/task-2-actionbar-build.txt
  ```

  **Commit**: YES | Message: (combined with task 1) | Files: [new file path]

- [ ] 3. Update IOSMainHomeView.swift to use handler + subview

  **What to do**: Rewrite `IOSMainHomeView.swift` to use the new handler and action bar subview.

  **Must NOT do**: Do NOT change visual behavior. Do NOT modify Shared/ code. Do NOT remove any existing functionality.

  **Recommended Agent Profile**:
  - Category: `quick` — Reason: Mechanical find-and-replace + deletion
  - Skills: [] — No special skills needed
  - Omitted: [] — N/A

  **Parallelization**: Can Parallel: NO | Wave 2 | Blocks: 4 | Blocked By: 1, 2

  **References**:
  - All 22 references to `interactionController`: see grep results above (lines 39, 216, 248, 252, 257, 262, 268, 277, 278, 385, 399, 403, 407, 411, 415, 419, 421, 466, 525, 532, 536, 540)
  - Handler: Task 1 output
  - ActionBar: Task 2 output

  Specific changes:
  1. **Properties** (around line 39-41):
     - REMOVE: `@StateObject private var interactionController = PetAnimationController()`
     - REMOVE: `@State private var actionToastText: String? = nil`
     - ADD: `@StateObject private var petHandler = IOSPetInteractionHandler()`

  2. **shouldShowWaitDialogue** (line 216):
     - `interactionController.activeInteraction` → `petHandler.interactionController.activeInteraction`

  3. **petActionBar** (lines 227-244):
     - REPLACE entire `petActionBar` computed property with: `IOSPetActionBarView(handler: petHandler)`

  4. **Remove methods** now in handler:
     - REMOVE: `triggerEat()`, `triggerDrink()`, `triggerSleep()` (lines 246-259)
     - REMOVE: `handleDrinkButton()`, `handleFeedButton()`, `handleSleepButton()` (lines 261-282)
     - REMOVE: `isWithinOneHourOfMeal()`, `isPastBedtime()`, `showActionToast()` (lines 284-322)
     - REMOVE: `petActionButton()` helper (lines 324-343) — moved to IOSPetActionBarView

  5. **handlePetMockupTap** (lines 369-394):
     - `triggerEat()` → `petHandler.triggerEat(companion: &companion)`
     - `triggerDrink()` → `petHandler.triggerDrink()`
     - `triggerSleep()` → `petHandler.triggerSleep()`
     - `interactionController.handleIdleTap()` block → `petHandler.handleIdleTap(companion: &companion)` (this replaces lines 385-394)

  6. **mirrorCoreStateToController** (lines 399-421):
     - REMOVE entire method — now `petHandler.mirrorCoreStateToController(_:)`
     - All calls update: `mirrorCoreStateToController(state)` → `petHandler.mirrorCoreStateToController(state)`

  7. **isInWaitingLoop/EatingFlow/DrinkingFlow/SleepFlow** (lines 352-386):
     - REMOVE all four — now private in handler

  8. **configureInteractionControllerSync** (lines 466-477):
     - REMOVE — now `petHandler.configureInteractionControllerSync()`
     - Call in onAppear updates: `petHandler.configureInteractionControllerSync()`

  9. **Animation computed properties** (lines 525-541):
     - `interactionController.activeInteraction` → `petHandler.interactionController.activeInteraction` (4 occurrences)

  10. **onAppear** (line ~112):
      - `configureInteractionControllerSync()` → `petHandler.configureInteractionControllerSync()`

  11. **onChange(of: coordinator.currentPetCoreState)** (line ~114):
      - `mirrorCoreStateToController(newState)` → `petHandler.mirrorCoreStateToController(newState)`

  **Acceptance Criteria**:
  - [ ] No `interactionController` references remain in IOSMainHomeView (only `petHandler.interactionController`)
  - [ ] No `actionToastText` remains in IOSMainHomeView
  - [ ] No handler/trigger/condition methods remain in IOSMainHomeView
  - [ ] `petActionBar` is just `IOSPetActionBarView(handler: petHandler)`

  **QA Scenarios**:
  ```
  Scenario: Build succeeds after refactor
    Tool: Bash
    Steps: xcodebuild build -scheme BolaBola -destination "generic/platform=iOS"
    Expected: BUILD SUCCEEDED
    Evidence: .sisyphus/evidence/task-3-refactor-build.txt

  Scenario: No leftover references
    Tool: Bash
    Steps: grep -c "interactionController" "BolaBola iOS/Features/Home/IOSMainHomeView.swift"
    Expected: 0 (all moved to petHandler.interactionController)
    Evidence: .sisyphus/evidence/task-3-no-leftovers.txt
  ```

  **Commit**: YES | Message: `refactor(ios): wire IOSMainHomeView to extracted handler + action bar` | Files: [IOSMainHomeView.swift path]

- [ ] 4. Build verification

  **What to do**: Full clean build + LSP diagnostics to confirm zero regressions.

  **Must NOT do**: Do NOT modify any code.

  **Recommended Agent Profile**:
  - Category: `quick` — Reason: Verification only
  - Skills: [] — No special skills needed
  - Omitted: [] — N/A

  **Parallelization**: Can Parallel: NO | Wave 2 | Blocks: — | Blocked By: 3

  **References**: N/A

  **Acceptance Criteria**:
  - [ ] `xcodebuild build -scheme BolaBola -destination "generic/platform=iOS"` → BUILD SUCCEEDED
  - [ ] LSP diagnostics on all 3 files → zero errors
  - [ ] `grep -c "interactionController" IOSMainHomeView.swift` → 0 (or only `petHandler.interactionController` references)

  **QA Scenarios**:
  ```
  Scenario: Clean build
    Tool: Bash
    Steps: xcodebuild clean build -scheme BolaBola -destination "generic/platform=iOS"
    Expected: BUILD SUCCEEDED
    Evidence: .sisyphus/evidence/task-4-clean-build.txt
  ```

  **Commit**: NO — verification only

## Final Verification Wave
- [ ] F1. Plan Compliance Audit — oracle
- [ ] F2. Code Quality Review — unspecified-high
- [ ] F3. Real Manual QA — unspecified-high
- [ ] F4. Scope Fidelity Check — deep

## Commit Strategy
- Commit 1: `refactor(ios): extract IOSPetInteractionHandler from IOSMainHomeView` (Tasks 1+2)
- Commit 2: `refactor(ios): wire IOSMainHomeView to extracted handler + action bar` (Task 3)
- Task 4: no commit (verification only)

## Success Criteria
- IOSMainHomeView.swift reduced by ~160 lines
- All pet interaction logic in IOSPetInteractionHandler.swift
- Action bar UI in IOSPetActionBarView.swift
- Zero behavior changes — same buttons, same animations, same toast
- iOS build succeeds with zero errors
