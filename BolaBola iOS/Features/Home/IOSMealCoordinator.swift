//
//  IOSMealCoordinator.swift
//  iOS — independent meal scheduling, hunger, feeding, reward
//

import Foundation
import Combine

final class IOSMealCoordinator: ObservableObject {
    static let shared = IOSMealCoordinator()
    private init() {}
    private let mealEngine = MealEngine.shared
    private let coordinator = BolaWCSessionCoordinator.shared
    private let defaults = BolaSharedDefaults.resolved()

    private var milestoneTimerCancellable: AnyCancellable?
    private var mealHungryScheduleCancellable: AnyCancellable?
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        configureMealEngine()
        mealEngine.refreshMealState(now: Date())
        scheduleMealHungryTimerIfNeeded(now: Date())
        startMilestoneTimer()

        NotificationCenter.default.addObserver(
            forName: .bolaMealSlotsDidUpdate,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            BolaDebugLog.shared.log(.meal, "iOS: received meal slots update")
            let updatedSlots = MealSlotStore.load(from: BolaSharedDefaults.resolved())
            self.mealEngine.updateSlots(updatedSlots, now: Date())
            self.scheduleMealHungryTimerIfNeeded(now: Date())
        }
    }

    func handleScenePhaseActive() {
        mealEngine.refreshMealState(now: Date())
        scheduleMealHungryTimerIfNeeded(now: Date())
    }

    func performMealFeed(companion: inout Double) {
        guard let result = mealEngine.resolveFeedAction(now: Date()) else {
            BolaDebugLog.shared.log(.meal, "iOS: performMealFeed — no valid meal to feed")
            return
        }

        let newCompanion = addCompanionRewardLocally(result.reward)
        companion = newCompanion

        coordinator.currentPetCoreState = .idle

        coordinator.sendPetCommand(PetCommandKind.feed)

        BolaDebugLog.shared.log(.meal, "iOS: feed resolved → \(result.newStatus.rawValue), reward +\(result.reward), companion \(Int(newCompanion))")
    }

    // MARK: - Private

    private func configureMealEngine() {
        mealEngine.onTriggerHungry = { [weak self] in
            guard let self else { return }
            guard self.coordinator.currentPetCoreState != .hungry else { return }
            BolaDebugLog.shared.log(.meal, "iOS: meal engine → trigger hungry")
            self.coordinator.currentPetCoreState = .hungry
        }

        mealEngine.onExitHungry = { [weak self] in
            guard let self else { return }
            guard self.coordinator.currentPetCoreState == .hungry else { return }
            BolaDebugLog.shared.log(.meal, "iOS: meal engine → exit hungry (auto-feed)")
            self.coordinator.currentPetCoreState = .idle
        }
    }

    private func addCompanionRewardLocally(_ amount: Double) -> Double {
        var v: Double
        if defaults.object(forKey: CompanionPersistenceKeys.companionValue) != nil {
            v = defaults.double(forKey: CompanionPersistenceKeys.companionValue)
        } else {
            v = 50
        }
        v = min(max(v + amount, 0), 100)
        defaults.set(v, forKey: CompanionPersistenceKeys.companionValue)
        defaults.set(Date().timeIntervalSince1970, forKey: CompanionPersistenceKeys.companionWCUpdatedAt)
        BolaDebugLog.shared.log(.meal, "iOS: companion reward +\(amount) → \(Int(v.rounded()))")
        return v
    }

    private func startMilestoneTimer() {
        milestoneTimerCancellable?.cancel()
        milestoneTimerCancellable = Timer
            .publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.mealEngine.refreshMealState(now: Date())
            }
    }

    private func scheduleMealHungryTimerIfNeeded(now: Date) {
        mealHungryScheduleCancellable?.cancel()
        mealHungryScheduleCancellable = nil
        guard let triggerDate = mealEngine.nextPendingTriggerDate(now: now) else { return }
        let delay = triggerDate.timeIntervalSince(now)
        guard delay > 0 else { return }
        mealHungryScheduleCancellable = Timer
            .publish(every: delay, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                self.mealHungryScheduleCancellable?.cancel()
                self.mealHungryScheduleCancellable = nil
                self.mealEngine.refreshMealState(now: Date())
            }
        BolaDebugLog.shared.log(.meal, "iOS: scheduled hungry timer in \(Int(delay))s")
    }
}
