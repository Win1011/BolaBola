//
//  DailyInteractionTaskStore.swift
//  成长页每日互动任务：记录真实触摸 / 喂食 / 喂水事件。
//

import Foundation

public enum DailyInteractionTaskStore {
    public static let touchGoal = 5

    public static func recordTouch(defaults: UserDefaults = BolaSharedDefaults.resolved()) {
        syncPeriodIfNeeded(defaults: defaults)
        let next = max(0, defaults.integer(forKey: CompanionPersistenceKeys.dailyTouchBolaCount)) + 1
        defaults.set(next, forKey: CompanionPersistenceKeys.dailyTouchBolaCount)
        postGrowthRefresh()
    }

    public static func recordFeed(defaults: UserDefaults = BolaSharedDefaults.resolved()) {
        syncPeriodIfNeeded(defaults: defaults)
        let next = max(0, defaults.integer(forKey: CompanionPersistenceKeys.dailyFeedBolaCount)) + 1
        defaults.set(next, forKey: CompanionPersistenceKeys.dailyFeedBolaCount)
        postGrowthRefresh()
    }

    public static func recordDrink(defaults: UserDefaults = BolaSharedDefaults.resolved()) {
        syncPeriodIfNeeded(defaults: defaults)
        let next = max(0, defaults.integer(forKey: CompanionPersistenceKeys.dailyDrinkBolaCount)) + 1
        defaults.set(next, forKey: CompanionPersistenceKeys.dailyDrinkBolaCount)
        postGrowthRefresh()
    }

    public static func touchProgress(defaults: UserDefaults = BolaSharedDefaults.resolved()) -> Double {
        syncPeriodIfNeeded(defaults: defaults)
        let count = defaults.integer(forKey: CompanionPersistenceKeys.dailyTouchBolaCount)
        return min(1, max(0, Double(count) / Double(touchGoal)))
    }

    public static func feedProgress(defaults: UserDefaults = BolaSharedDefaults.resolved()) -> Double {
        syncPeriodIfNeeded(defaults: defaults)
        return defaults.integer(forKey: CompanionPersistenceKeys.dailyFeedBolaCount) > 0 ? 1 : 0
    }

    public static func drinkProgress(defaults: UserDefaults = BolaSharedDefaults.resolved()) -> Double {
        syncPeriodIfNeeded(defaults: defaults)
        return defaults.integer(forKey: CompanionPersistenceKeys.dailyDrinkBolaCount) > 0 ? 1 : 0
    }

    private static func syncPeriodIfNeeded(defaults: UserDefaults) {
        let current = GrowthDayBoundary.currentPeriodStart().timeIntervalSince1970
        let stored = defaults.double(forKey: CompanionPersistenceKeys.dailyInteractionPeriodStart)
        guard abs(stored - current) > 0.5 else { return }
        defaults.set(current, forKey: CompanionPersistenceKeys.dailyInteractionPeriodStart)
        defaults.set(0, forKey: CompanionPersistenceKeys.dailyTouchBolaCount)
        defaults.set(0, forKey: CompanionPersistenceKeys.dailyFeedBolaCount)
        defaults.set(0, forKey: CompanionPersistenceKeys.dailyDrinkBolaCount)
    }

    private static func postGrowthRefresh() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .bolaGrowthStateDidChange, object: nil)
        }
    }
}
