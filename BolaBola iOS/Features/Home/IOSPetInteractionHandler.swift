import Foundation
import Combine
import SwiftUI

final class IOSPetInteractionHandler: ObservableObject {
    @Published var actionToastText: String?
    /// 主界面手表预览上的对话气泡临时文案（与 `PetCoreState.localDialogue` 叠加显示，优先本字段）。
    @Published var watchPreviewBubbleText: String?
    let interactionController = PetAnimationController()

    private let coordinator = BolaWCSessionCoordinator.shared
    private let mealCoordinator = IOSMealCoordinator.shared
    private var cancellables = Set<AnyCancellable>()
    private var watchPreviewBubbleClearWorkItem: DispatchWorkItem?

    init() {
        interactionController.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    func handleDrinkButton() {
        coordinator.markCompanionInteractionLocally()
        interactionController.enterThirsty()
        coordinator.pushPetCoreState(.thirsty)
    }

    func handleFeedButton(companion: inout Double) {
        coordinator.markCompanionInteractionLocally(pushToWatch: false)
        // 与 `MealEngine.hasFeedableMeal` / 主界面 `isFeedWindowActive` 一致（餐前早喂窗口见 `MealEngine.earlyWindowSeconds`）。
        let now = Date()
        MealEngine.shared.refreshMealState(now: now)
        if MealEngine.shared.hasFeedableMeal(now: now) {
            interactionController.enterHungry()
            if mealCoordinator.performMealFeed(companion: &companion) {
                interactionController.applyEatCommand()
            }
        } else {
            showWatchPreviewBubble("还没到吃饭时间哦")
        }
    }

    func handleSleepButton() {
        coordinator.markCompanionInteractionLocally()
        if isPastBedtime() {
            interactionController.enterSleepWait()
            interactionController.applySleepCommand()
            BolaTimelineRecorder.recordPetActivity(.sleep)
        } else {
            showActionToast("还没到睡觉时间哦")
        }
    }

    func triggerEat(companion: inout Double) {
        coordinator.markCompanionInteractionLocally(pushToWatch: false)
        if mealCoordinator.performMealFeed(companion: &companion) {
            interactionController.applyEatCommand()
        }
    }

    func triggerDrink() {
        coordinator.markCompanionInteractionLocally()
        interactionController.applyDrinkCommand()
        coordinator.sendPetCommand(PetCommandKind.drink)
        DailyInteractionTaskStore.recordDrink()
        BolaTimelineRecorder.recordPetActivity(.water)
    }

    func triggerSleep() {
        coordinator.markCompanionInteractionLocally()
        interactionController.applySleepCommand()
        coordinator.sendPetCommand(PetCommandKind.sleep)
        BolaTimelineRecorder.recordPetActivity(.sleep)
    }

    func wakeUpFromSleep() {
        coordinator.markCompanionInteractionLocally()
        interactionController.returnToIdle()
        coordinator.pushPetCoreState(.idle)
    }

    func handleIdleTap(companion: inout Double) -> Bool {
        guard interactionController.handleIdleTap(companionValue: companion) else { return false }
        BolaWCSessionCoordinator.shared.incrementCompanionValueLocally(by: 1)
        companion = BolaSharedDefaults.resolved().double(forKey: CompanionPersistenceKeys.companionValue)
        return true
    }

    func configureInteractionControllerSync() {
        interactionController.onTransition = { [weak self] reason, _ in
            guard let self else { return }
            switch reason {
            case .eatingStarted, .drinkingStarted:
                self.coordinator.pushPetCoreState(.idle)
            case .fallingAsleepStarted:
                self.coordinator.pushPetCoreState(.sleeping)
            default:
                break
            }
        }
    }

    func mirrorCoreStateToController(_ state: PetCoreState) {
        let active = interactionController.activeInteraction
        switch state {
        case .idle:
            if isInWaitingLoop(active) {
                interactionController.returnToIdle()
            }
        case .hungry:
            if !isInEatingFlow(active) {
                interactionController.enterHungry()
            }
        case .thirsty:
            if !isInDrinkingFlow(active) {
                interactionController.enterThirsty()
            }
        case .sleepWait:
            if !isInSleepFlow(active) {
                interactionController.enterSleepWait()
            }
        case .sleeping:
            if isInWaitingLoop(active) {
                interactionController.enterSleeping()
            } else if active == nil {
                interactionController.enterSleeping()
            }
        }
    }

    // 与手表端 23:30–08:30 睡眠窗口对齐
    private func isPastBedtime() -> Bool {
        let cal = Calendar.current
        let h = cal.component(.hour, from: Date())
        let m = cal.component(.minute, from: Date())
        if h == 23 && m >= 30 { return true }
        if h < 8 { return true }
        if h == 8 && m < 30 { return true }
        return false
    }

    private func showActionToast(_ text: String) {
        withAnimation(.easeInOut(duration: 0.25)) {
            actionToastText = text
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeInOut(duration: 0.25)) {
                self.actionToastText = nil
            }
        }
    }

    /// 手表预览对话气泡：短时提示，避免与底部 `actionToastText` 叠两层同类文案。
    private func showWatchPreviewBubble(_ text: String, duration: TimeInterval = 2.6) {
        watchPreviewBubbleClearWorkItem?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) {
            watchPreviewBubbleText = text
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                self.watchPreviewBubbleText = nil
            }
        }
        watchPreviewBubbleClearWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    private func isInWaitingLoop(_ emotion: PetInteractionEmotion?) -> Bool {
        switch emotion {
        case .eatingWait, .idleDrinkOne, .idleDrinkTwo, .nightSleepWait, .sleepLoop:
            return true
        default:
            return false
        }
    }

    private func isInEatingFlow(_ emotion: PetInteractionEmotion?) -> Bool {
        switch emotion {
        case .eatingWait, .eatingOnce, .eatingHappyIdle, .eatingLikeOne, .eatingLikeTwo:
            return true
        default:
            return false
        }
    }

    private func isInDrinkingFlow(_ emotion: PetInteractionEmotion?) -> Bool {
        switch emotion {
        case .idleDrinkOne, .idleDrinkTwo, .drinkOnce, .blowbubbleOne, .blowbubbleTwo:
            return true
        default:
            return false
        }
    }

    private func isInSleepFlow(_ emotion: PetInteractionEmotion?) -> Bool {
        switch emotion {
        case .nightSleepWait, .fallAsleep, .sleepLoop:
            return true
        default:
            return false
        }
    }
}
