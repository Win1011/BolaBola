import Foundation
import Combine
import SwiftUI

final class IOSPetInteractionHandler: ObservableObject {
    @Published var actionToastText: String?
    let interactionController = PetAnimationController()

    private let coordinator = BolaWCSessionCoordinator.shared
    private let mealCoordinator = IOSMealCoordinator.shared

    func handleDrinkButton() {
        interactionController.enterThirsty()
        coordinator.pushPetCoreState(.thirsty)
    }

    func handleFeedButton() {
        if isWithinOneHourOfMeal() {
            interactionController.enterHungry()
            coordinator.pushPetCoreState(.hungry)
        } else {
            showActionToast("暂无可喂餐食")
        }
    }

    func handleSleepButton() {
        if isPastBedtime() {
            interactionController.enterSleepWait()
            interactionController.applySleepCommand()
        } else {
            showActionToast("还没到睡觉时间哦")
        }
    }

    func triggerEat(companion: inout Double) {
        mealCoordinator.performMealFeed(companion: &companion)
        interactionController.applyEatCommand()
    }

    func triggerDrink() {
        interactionController.applyDrinkCommand()
        coordinator.sendPetCommand(PetCommandKind.drink)
    }

    func triggerSleep() {
        interactionController.applySleepCommand()
        coordinator.sendPetCommand(PetCommandKind.sleep)
    }

    func handleIdleTap(companion: inout Double) -> Bool {
        guard interactionController.handleIdleTap() else { return false }
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

    private func isWithinOneHourOfMeal() -> Bool {
        let engine = MealEngine.shared
        let now = Date()
        engine.generateTodayRecordsIfNeeded(now: now)
        let oneHourFromNow = now.addingTimeInterval(3600)

        return engine.todayRecords.contains { record in
            switch record.status {
            case .pending:
                return record.scheduledDate > now && record.scheduledDate <= oneHourFromNow
            case .hungryActive:
                return true
            default:
                return false
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
