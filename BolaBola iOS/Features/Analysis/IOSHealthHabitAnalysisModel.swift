//
//  IOSHealthHabitAnalysisModel.swift
//  iPhone：分析页 HealthKit 授权与近 7 日序列（非医疗）。
//

import Combine
import Foundation
import HealthKit
import UIKit

@MainActor
final class IOSHealthHabitAnalysisModel: ObservableObject {
    enum AuthPhase: Equatable {
        case idle
        case healthUnavailable
        case needsPrompt
        case denied
        case loading
        case ready
    }

    @Published private(set) var authPhase: AuthPhase = .idle
    @Published private(set) var activeEnergyWeek: [IOSHealthKitWeekQueries.DayValue] = []
    @Published private(set) var exerciseMinutesWeek: [IOSHealthKitWeekQueries.DayValue] = []
    @Published private(set) var stepsWeek: [IOSHealthKitWeekQueries.DayValue] = []
    @Published private(set) var standMinutesWeek: [IOSHealthKitWeekQueries.DayValue] = []
    @Published private(set) var heartRateWeek: [IOSHealthKitWeekQueries.DayValue] = []
    @Published private(set) var sleepHoursWeek: [IOSHealthKitWeekQueries.DayValue] = []
    @Published private(set) var fetchError: String?

    private let store = HKHealthStore()

    /// 近 7 日是否至少有一项 HealthKit 读数大于 0（用于空状态说明）。
    var hasAnyChartData: Bool {
        activeEnergyWeek.contains { $0.value > 0 }
            || exerciseMinutesWeek.contains { $0.value > 0 }
            || stepsWeek.contains { $0.value > 0 }
            || standMinutesWeek.contains { $0.value > 0 }
            || heartRateWeek.contains { $0.value > 0 }
            || sleepHoursWeek.contains { $0.value > 0.01 }
    }

    /// 是否已在当前设备上走过一次「读取健康数据」系统授权流程。
    /// 注意：对**只读**类型，`authorizationStatus` 在授权后仍常为 `notDetermined`，不能用它判断是否可读，否则会永远卡在「请授权」。
    static let healthReadPromptCompletedKey = "bola_ios_health_read_prompt_completed"

    private static var readTypes: Set<HKObjectType> {
        var s = Set<HKObjectType>()
        if let t = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) { s.insert(t) }
        if let t = HKQuantityType.quantityType(forIdentifier: .appleExerciseTime) { s.insert(t) }
        if let t = HKQuantityType.quantityType(forIdentifier: .stepCount) { s.insert(t) }
        if let t = HKQuantityType.quantityType(forIdentifier: .heartRate) { s.insert(t) }
        if let t = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) { s.insert(t) }
        if let t = HKQuantityType.quantityType(forIdentifier: .appleStandTime) { s.insert(t) }
        if let t = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { s.insert(t) }
        return s
    }

    func onAppear() {
        Task { @MainActor in
            await refresh()
        }
    }

    func requestAccess() {
        Task { @MainActor in
            await refresh(requestIfNeeded: true)
        }
    }

    func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// 用户仅在「设置 › 隐私与安全性 › 健康」中开启、从未点过本页「允许访问」时，读状态仍常为 `notDetermined`；标记已处理后再拉数。
    func markHealthAccessHandledAndRefresh() {
        UserDefaults.standard.set(true, forKey: Self.healthReadPromptCompletedKey)
        Task { @MainActor in
            await refresh()
        }
    }

    func refresh(requestIfNeeded: Bool = false) async {
        fetchError = nil

        guard HKHealthStore.isHealthDataAvailable() else {
            authPhase = .healthUnavailable
            clearSeries()
            return
        }

        let types = Self.readTypes
        guard let probe = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            authPhase = .healthUnavailable
            return
        }

        let requestStatus = await readAuthorizationRequestStatus(types: types)
        if requestStatus == .unnecessary {
            UserDefaults.standard.set(true, forKey: Self.healthReadPromptCompletedKey)
        }

        let status = store.authorizationStatus(for: probe)
        var prompted = UserDefaults.standard.bool(forKey: Self.healthReadPromptCompletedKey)

        if status == .sharingAuthorized {
            UserDefaults.standard.set(true, forKey: Self.healthReadPromptCompletedKey)
            prompted = true
        }

        if status == .notDetermined {
            if requestIfNeeded, !prompted {
                await requestAuthorization(types: types)
                UserDefaults.standard.set(true, forKey: Self.healthReadPromptCompletedKey)
                prompted = true
            } else if !prompted {
                authPhase = .needsPrompt
                clearSeries()
                return
            }
        }

        // 仅读数据时 sharingDenied 不可靠；不在此处 return，避免误判后整段分析区「永远不更新」。

        authPhase = .loading

        let range = IOSHealthKitWeekQueries.lastSevenDayRange()
        let start = range.start
        let end = range.end

        do {
            async let m = fetchMoveWeek(start: start, end: end)
            async let e = fetchExerciseWeek(start: start, end: end)
            async let s = fetchStepsWeek(start: start, end: end)
            async let st = fetchStandWeek(start: start, end: end)
            async let h = fetchHeartWeek(start: start, end: end)
            async let sl = fetchSleepWeek(start: start, end: end)
            async let stepsTodayFallback = fetchTodayStepsFallback()
            let (mVal, eVal, sVal, stVal, hVal, slVal, stepsTodayFallbackVal) = try await (m, e, s, st, h, sl, stepsTodayFallback)

            activeEnergyWeek = IOSHealthKitWeekQueries.mergeIntoWeek(partial: mVal, start: start, end: end)
            exerciseMinutesWeek = IOSHealthKitWeekQueries.mergeIntoWeek(partial: eVal, start: start, end: end)
            stepsWeek = IOSHealthKitWeekQueries.mergeIntoWeek(partial: sVal, start: start, end: end)
            standMinutesWeek = IOSHealthKitWeekQueries.mergeIntoWeek(partial: stVal, start: start, end: end)
            heartRateWeek = IOSHealthKitWeekQueries.mergeIntoWeek(partial: hVal, start: start, end: end)
            sleepHoursWeek = IOSHealthKitWeekQueries.mergeIntoWeek(partial: slVal, start: start, end: end)
            applyTodayStepsFallbackIfNeeded(stepsTodayFallbackVal)

            authPhase = .ready
        } catch {
            fetchError = (error as NSError).localizedDescription
            authPhase = .ready
        }
    }

    private func fetchStepsWeek(start: Date, end: Date) async throws -> [IOSHealthKitWeekQueries.DayValue] {
        guard let t = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return [] }
        return try await IOSHealthKitWeekQueries.dailySum(
            store: store,
            quantityType: t,
            unit: .count(),
            start: start,
            end: end
        )
    }

    private func fetchTodayStepsFallback() async throws -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return 0 }
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let pred = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)

        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: pred, options: .cumulativeSum) { _, stats, _ in
                let v = stats?.sumQuantity()?.doubleValue(for: .count()) ?? 0
                DispatchQueue.main.async {
                    cont.resume(returning: v)
                }
            }
            store.execute(q)
        }
    }

    private func fetchMoveWeek(start: Date, end: Date) async throws -> [IOSHealthKitWeekQueries.DayValue] {
        try await IOSHealthKitWeekQueries.dailyMoveEnergy(store: store, start: start, end: end)
    }

    private func fetchExerciseWeek(start: Date, end: Date) async throws -> [IOSHealthKitWeekQueries.DayValue] {
        try await IOSHealthKitWeekQueries.dailyExerciseMinutes(store: store, start: start, end: end)
    }

    private func fetchStandWeek(start: Date, end: Date) async throws -> [IOSHealthKitWeekQueries.DayValue] {
        guard let t = HKQuantityType.quantityType(forIdentifier: .appleStandTime) else { return [] }
        return try await IOSHealthKitWeekQueries.dailySum(
            store: store,
            quantityType: t,
            unit: .minute(),
            start: start,
            end: end
        )
    }

    private func fetchHeartWeek(start: Date, end: Date) async throws -> [IOSHealthKitWeekQueries.DayValue] {
        guard let t = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return [] }
        return try await IOSHealthKitWeekQueries.dailyAverage(
            store: store,
            quantityType: t,
            unit: HKUnit.count().unitDivided(by: .minute()),
            start: start,
            end: end
        )
    }

    private func fetchSleepWeek(start: Date, end: Date) async throws -> [IOSHealthKitWeekQueries.DayValue] {
        try await IOSHealthKitWeekQueries.sleepHoursByDay(store: store, start: start, end: end)
    }

    private func clearSeries() {
        activeEnergyWeek = []
        exerciseMinutesWeek = []
        stepsWeek = []
        standMinutesWeek = []
        heartRateWeek = []
        sleepHoursWeek = []
    }

    private func applyTodayStepsFallbackIfNeeded(_ fallback: Double) {
        guard fallback > 0 else { return }
        let cal = Calendar.current
        if let idx = stepsWeek.firstIndex(where: { cal.isDateInToday($0.date) }) {
            guard stepsWeek[idx].value <= 0 else { return }
            let day = stepsWeek[idx].date
            stepsWeek[idx] = IOSHealthKitWeekQueries.DayValue(date: day, value: fallback)
        }
    }

    private func requestAuthorization(types: Set<HKObjectType>) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            store.requestAuthorization(toShare: [], read: types) { _, _ in
                DispatchQueue.main.async {
                    cont.resume()
                }
            }
        }
    }

    private func readAuthorizationRequestStatus(types: Set<HKObjectType>) async -> HKAuthorizationRequestStatus {
        await withCheckedContinuation { cont in
            store.getRequestStatusForAuthorization(toShare: [], read: types) { status, _ in
                DispatchQueue.main.async {
                    cont.resume(returning: status)
                }
            }
        }
    }
}
