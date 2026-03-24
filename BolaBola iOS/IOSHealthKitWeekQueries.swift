//
//  IOSHealthKitWeekQueries.swift
//  iPhone：按日聚合 HealthKit 查询（近 7 日），供分析页图表使用。
//

import Foundation
import HealthKit

enum IOSHealthKitWeekQueries {

    /// HealthKit 回调常在后台队列；continuation 必须在主线程 resume，否则 `@MainActor` + SwiftUI 可能不刷新界面。
    private static func resumeOnMain<T, E: Error>(_ cont: CheckedContinuation<T, E>, returning value: T) {
        DispatchQueue.main.async {
            cont.resume(returning: value)
        }
    }

    private static func resumeOnMain<T, E: Error>(_ cont: CheckedContinuation<T, E>, throwing error: E) {
        DispatchQueue.main.async {
            cont.resume(throwing: error)
        }
    }

    struct DayValue: Identifiable, Equatable, Sendable {
        let date: Date
        let value: Double
        var id: Date { date }
    }

    /// 过去 7 个自然日（含今天），从「最早那天 0 点」到「此刻」。
    static func lastSevenDayRange(reference: Date = Date()) -> (start: Date, end: Date) {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: reference)
        let start = cal.date(byAdding: .day, value: -6, to: todayStart) ?? todayStart
        return (start, reference)
    }

    static func dailySum(
        store: HKHealthStore,
        quantityType: HKQuantityType,
        unit: HKUnit,
        start: Date,
        end: Date
    ) async throws -> [DayValue] {
        try await withCheckedThrowingContinuation { cont in
            let cal = Calendar.current
            let anchor = cal.startOfDay(for: end)
            let day = DateComponents(day: 1)
            // 不用 .strictStartDate：否则部分跨日/边界样本进不了桶，容易出现「全空」。
            let pred = HKQuery.predicateForSamples(withStart: start, end: end)
            let q = HKStatisticsCollectionQuery(
                quantityType: quantityType,
                quantitySamplePredicate: pred,
                options: .cumulativeSum,
                anchorDate: anchor,
                intervalComponents: day
            )
            q.initialResultsHandler = { _, collection, error in
                if let error {
                    resumeOnMain(cont, throwing: error)
                    return
                }
                guard let collection else {
                    resumeOnMain(cont, returning: [])
                    return
                }
                var rows: [DayValue] = []
                collection.enumerateStatistics(from: start, to: end) { stats, _ in
                    if let sum = stats.sumQuantity() {
                        rows.append(DayValue(date: stats.startDate, value: sum.doubleValue(for: unit)))
                    }
                }
                resumeOnMain(cont, returning: rows)
            }
            store.execute(q)
        }
    }

    static func dailyAverage(
        store: HKHealthStore,
        quantityType: HKQuantityType,
        unit: HKUnit,
        start: Date,
        end: Date
    ) async throws -> [DayValue] {
        try await withCheckedThrowingContinuation { cont in
            let cal = Calendar.current
            let anchor = cal.startOfDay(for: end)
            let day = DateComponents(day: 1)
            let pred = HKQuery.predicateForSamples(withStart: start, end: end)
            let q = HKStatisticsCollectionQuery(
                quantityType: quantityType,
                quantitySamplePredicate: pred,
                options: .discreteAverage,
                anchorDate: anchor,
                intervalComponents: day
            )
            q.initialResultsHandler = { _, collection, error in
                if let error {
                    resumeOnMain(cont, throwing: error)
                    return
                }
                guard let collection else {
                    resumeOnMain(cont, returning: [])
                    return
                }
                var rows: [DayValue] = []
                collection.enumerateStatistics(from: start, to: end) { stats, _ in
                    if let avg = stats.averageQuantity() {
                        rows.append(DayValue(date: stats.startDate, value: avg.doubleValue(for: unit)))
                    }
                }
                resumeOnMain(cont, returning: rows)
            }
            store.execute(q)
        }
    }

    /// 按入睡日汇总「实际睡眠」时长（小时），与系统睡眠分析分类一致。
    static func sleepHoursByDay(
        store: HKHealthStore,
        start: Date,
        end: Date
    ) async throws -> [DayValue] {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return []
        }
        let samples: [HKCategorySample] = try await withCheckedThrowingContinuation { cont in
            let pred = HKQuery.predicateForSamples(withStart: start, end: end)
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let q = HKSampleQuery(
                sampleType: sleepType,
                predicate: pred,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, results, error in
                if let error {
                    resumeOnMain(cont, throwing: error)
                    return
                }
                resumeOnMain(cont, returning: (results as? [HKCategorySample]) ?? [])
            }
            store.execute(q)
        }

        let cal = Calendar.current
        var secondsByDayStart: [Date: TimeInterval] = [:]
        for s in samples {
            guard sleepCategoryCountsAsAsleep(s.value) else { continue }
            let day = cal.startOfDay(for: s.startDate)
            let sec = s.endDate.timeIntervalSince(s.startDate)
            guard sec > 0 else { continue }
            secondsByDayStart[day, default: 0] += sec
        }

        var ordered: [DayValue] = []
        var d = cal.startOfDay(for: start)
        let last = cal.startOfDay(for: end)
        while d <= last {
            let hrs = (secondsByDayStart[d] ?? 0) / 3600
            ordered.append(DayValue(date: d, value: hrs))
            guard let next = cal.date(byAdding: .day, value: 1, to: d) else { break }
            d = next
        }
        return ordered
    }

    private static func sleepCategoryCountsAsAsleep(_ raw: Int) -> Bool {
        guard let v = HKCategoryValueSleepAnalysis(rawValue: raw) else { return false }
        switch v {
        case .inBed, .awake:
            return false
        default:
            // asleep* 各态及历史 raw 值均计入睡时长；inBed/awake 已排除。
            return true
        }
    }

    static func mergeIntoWeek(
        partial: [DayValue],
        start: Date,
        end: Date
    ) -> [DayValue] {
        let cal = Calendar.current
        var dict: [Date: Double] = [:]
        for p in partial {
            dict[cal.startOfDay(for: p.date)] = p.value
        }
        var out: [DayValue] = []
        var d = cal.startOfDay(for: start)
        let last = cal.startOfDay(for: end)
        while d <= last {
            out.append(DayValue(date: d, value: dict[d] ?? 0))
            guard let next = cal.date(byAdding: .day, value: 1, to: d) else { break }
            d = next
        }
        return out
    }
}
