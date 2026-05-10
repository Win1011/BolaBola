//
//  IOSRhythmHRVModel.swift
//  今日 HRV（SDNN）按小时桶聚合，供节奏条展示；非医疗用途。
//

import Combine
import Foundation
import HealthKit

@MainActor
final class IOSRhythmHRVModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case unavailable
        case loading
        case empty
        case ready
    }

    /// HRV 节奏条个人基线：使用 Apple HealthKit SDNN（ms）最近历史日均值生成。
    struct HRVRhythmBaseline: Equatable {
        var medianSDNNMilliseconds: Double
        var lowerBalancedSDNNMilliseconds: Double
        var upperBalancedSDNNMilliseconds: Double
        var availableDays: Int
        var lookbackDays: Int
    }

    /// HRV 节奏阶段：基于归一化值（0–1）划分，参考 Garmin / Oura / Whoop 分层逻辑。
    enum HRVStage {
        /// 无数据 / 未授权
        case noData
        /// 低迷：身体可能处于较高压力或疲劳状态
        case depleted
        /// 偏低：节奏略低于自身基线，需要适当休息
        case low
        /// 平稳：处于正常波动范围内
        case balanced
        /// 良好：身体恢复状态不错
        case good
        /// 活力满满：今日节奏处于峰值区间
        case vibrant

        var imageName: String {
            switch self {
            case .noData, .balanced:
                return "GrowthHeroIsland"
            case .depleted, .low:
                return "RhythmBola_Low"
            case .good, .vibrant:
                return "RhythmBola_Good"
            }
        }

        var heroImageWidthMultiplier: Double {
            switch self {
            case .noData, .balanced:
                return 1
            case .good, .vibrant:
                return 1.5
            case .depleted, .low:
                return 1.99
            }
        }

        var heroImageYOffset: Double {
            switch self {
            case .depleted, .low:
                return 12
            default:
                return 0
            }
        }

        var heroImageXOffset: Double {
            switch self {
            case .noData, .balanced:
                return 3
            case .depleted, .low:
                return -5
            default:
                return 0
            }
        }

        /// 对应阶段的 Bola 口吻话语池，每次从中随机取一句
        var speechPool: [String] {
            switch self {
            case .noData:
                return [
                    "节奏还在读取中，稍等一下哦~",
                    "我正在帮你读今天的节奏~",
                    "节奏数据还没到，等等它~",
                ]
            case .depleted:
                return [
                    "节奏有点低迷，好好歇一歇吧~",
                    "节奏低迷也没关系，充个电就好~",
                    "节奏在谷底，今天慢慢来就行~",
                    "节奏低迷，允许自己放慢脚步~",
                ]
            case .low:
                return [
                    "节奏偏低，今天轻轻地过就好~",
                    "节奏稍微低了点，慢慢来没关系~",
                    "节奏偏低，记得多喝点水哦~",
                    "节奏在慢慢恢复，有我陪着你~",
                ]
            case .balanced:
                return [
                    "节奏挺稳的，继续保持哦~",
                    "节奏平稳，今天挺从容的嘛~",
                    "节奏稳稳的，是很不错的一天~",
                    "节奏平稳！你的状态真不错~",
                ]
            case .good:
                return [
                    "节奏不错！继续保持哦~",
                    "节奏良好！趁势多做点开心的事~",
                    "节奏在涨，好替你开心🌿",
                    "节奏良好，今天你好棒的~",
                ]
            case .vibrant:
                return [
                    "节奏满满！今天可以全力以赴~",
                    "节奏这么好，完全被你感染了！",
                    "节奏满满，今天是元气爆棚的一天🌟",
                    "节奏峰值！太替你骄傲啦~",
                ]
            }
        }

        var label: String {
            switch self {
            case .noData:   return "等待数据"
            case .depleted: return "节奏低迷"
            case .low:      return "节奏偏低"
            case .balanced: return "节奏平稳"
            case .good:     return "节奏良好"
            case .vibrant:  return "节奏满满"
            }
        }

        static func from(normalized value: Double) -> HRVStage {
            guard value > 0.001 else { return .noData }
            switch value {
            case ..<0.2:  return .depleted
            case ..<0.4:  return .low
            case ..<0.6:  return .balanced
            case ..<0.8:  return .good
            default:      return .vibrant
            }
        }
    }

    /// 24 个值，对应今天 0–23 时，0...1 用于条高；优先表示相对个人 HRV 基线的位置。
    @Published private(set) var hourlyNormalized: [Double] = Array(repeating: 0, count: 24)
    /// 24 个 Apple HealthKit SDNN 原始小时均值（ms），供后续 HRV 卡片复用。
    @Published private(set) var hourlyAverageSDNNMilliseconds: [Double] = Array(repeating: 0, count: 24)
    @Published private(set) var rhythmBaseline: HRVRhythmBaseline?
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var errorMessage: String?

    private static let rhythmBaselineLookbackDays = 28
    private static let minimumBaselineDays = 7

    private let store = HKHealthStore()

    func refresh() async {
        phase = .loading
        errorMessage = nil

        guard HKHealthStore.isHealthDataAvailable(),
              let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
            phase = .unavailable
            return
        }
        let types: Set<HKObjectType> = [hrvType]
        let requestStatus = await authorizationRequestStatus(types: types)
        guard requestStatus == .unnecessary else {
            phase = .empty
            errorMessage = "尚未授权健康读取"
            return
        }

        let cal = Calendar.current
        let now = Date()
        let start = cal.startOfDay(for: now)
        let pred = HKQuery.predicateForSamples(withStart: start, end: now)

        do {
            let samples = try await fetchHRVSamples(type: hrvType, predicate: pred)
            let buckets = Self.bucketAverageByHour(samples: samples, calendar: cal, dayStart: start)
            let recentSamples = try await fetchRecentHRVSamples(type: hrvType, daysBack: Self.rhythmBaselineLookbackDays, calendar: cal, now: now)
            let baseline = Self.makeRhythmBaseline(samples: recentSamples, calendar: cal, now: now)
            hourlyAverageSDNNMilliseconds = buckets
            rhythmBaseline = baseline
            hourlyNormalized = Self.normalizeBuckets(buckets, baseline: baseline)
            phase = buckets.allSatisfy { $0 <= 0 } ? .empty : .ready
            saveWeeklySummary(samples: Self.samplesFromRecentSevenDays(recentSamples, calendar: cal, now: now), calendar: cal, now: now)
        } catch {
            errorMessage = (error as NSError).localizedDescription
            phase = .empty
        }
    }

    @discardableResult
    func refreshWeeklySummaryCache() async -> HRVWeeklySummary? {
        guard HKHealthStore.isHealthDataAvailable(),
              let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
            let summary = Self.insufficientWeeklySummary()
            HRVWeeklySummaryStore.save(summary)
            return summary
        }
        let types: Set<HKObjectType> = [hrvType]
        let requestStatus = await authorizationRequestStatus(types: types)
        guard requestStatus == .unnecessary else {
            let summary = Self.insufficientWeeklySummary()
            HRVWeeklySummaryStore.save(summary)
            return summary
        }

        do {
            let now = Date()
            let calendar = Calendar.current
            let samples = try await fetchRecentHRVSamples(type: hrvType, daysBack: 6, calendar: calendar, now: now)
            let summary = Self.makeWeeklySummary(samples: samples, calendar: calendar, now: now)
            HRVWeeklySummaryStore.save(summary)
            return summary
        } catch {
            let summary = Self.insufficientWeeklySummary()
            HRVWeeklySummaryStore.save(summary)
            return summary
        }
    }

    private func authorizationRequestStatus(types: Set<HKObjectType>) async -> HKAuthorizationRequestStatus {
        await withCheckedContinuation { cont in
            store.getRequestStatusForAuthorization(toShare: [], read: types) { status, _ in
                DispatchQueue.main.async {
                    cont.resume(returning: status)
                }
            }
        }
    }

    private func fetchHRVSamples(type: HKQuantityType, predicate: NSPredicate) async throws -> [HKQuantitySample] {
        try await withCheckedThrowingContinuation { cont in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)
            let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, error in
                if let error {
                    DispatchQueue.main.async {
                        cont.resume(throwing: error)
                    }
                    return
                }
                let qty = (samples as? [HKQuantitySample]) ?? []
                DispatchQueue.main.async {
                    cont.resume(returning: qty)
                }
            }
            store.execute(q)
        }
    }

    private func fetchRecentHRVSamples(type: HKQuantityType, daysBack: Int, calendar: Calendar, now: Date) async throws -> [HKQuantitySample] {
        let todayStart = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -daysBack, to: todayStart) ?? todayStart
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now)
        return try await fetchHRVSamples(type: type, predicate: predicate)
    }

    private func saveWeeklySummary(samples: [HKQuantitySample], calendar: Calendar, now: Date) {
        HRVWeeklySummaryStore.save(Self.makeWeeklySummary(samples: samples, calendar: calendar, now: now))
    }

    private static func bucketAverageByHour(samples: [HKQuantitySample], calendar: Calendar, dayStart: Date) -> [Double] {
        var sums = Array(repeating: 0.0, count: 24)
        var counts = Array(repeating: 0, count: 24)
        let unit = HKUnit.secondUnit(with: .milli)
        for s in samples {
            let hour = calendar.component(.hour, from: s.endDate)
            guard hour >= 0, hour < 24 else { continue }
            let ms = s.quantity.doubleValue(for: unit)
            sums[hour] += ms
            counts[hour] += 1
        }
        return zip(sums, counts).map { s, c in
            c > 0 ? s / Double(c) : 0
        }
    }

    /// 将毫秒值转为 0...1：优先使用个人基线；基线不足时回到当天内部相对波动。
    private static func normalizeBuckets(_ raw: [Double], baseline: HRVRhythmBaseline?) -> [Double] {
        guard let baseline else {
            return normalizeBucketsWithinToday(raw)
        }
        return raw.map { value in
            rhythmPosition(for: value, baseline: baseline)
        }
    }

    private static func rhythmPosition(for value: Double, baseline: HRVRhythmBaseline) -> Double {
        guard value > 0 else { return 0 }
        if baseline.medianSDNNMilliseconds > 0 {
            let deviation = (value - baseline.medianSDNNMilliseconds) / baseline.medianSDNNMilliseconds
            return min(0.95, max(0.05, 0.5 + deviation))
        }
        return 0
    }

    /// 历史样本不足时回到当天内部相对波动，只表达今天样本之间的高低，不做个人状态判断。
    private static func normalizeBucketsWithinToday(_ raw: [Double]) -> [Double] {
        let positive = raw.filter { $0 > 0 }
        guard let maxV = positive.max(), maxV > 0 else {
            return raw.map { _ in 0 }
        }
        let minV = positive.min() ?? 0
        let span = max(maxV - minV, 1)
        return raw.map { value in
            guard value > 0 else { return 0 }
            return min(1, max(0, (value - minV) / span))
        }
    }

    private static func makeRhythmBaseline(samples: [HKQuantitySample], calendar: Calendar, now: Date) -> HRVRhythmBaseline? {
        let todayStart = calendar.startOfDay(for: now)
        let dailyAverages = dailyAverageSDNNMilliseconds(
            samples: samples,
            calendar: calendar,
            startOffset: -rhythmBaselineLookbackDays,
            endOffset: -1,
            todayStart: todayStart
        )
        guard dailyAverages.count >= minimumBaselineDays else { return nil }

        let median = percentile(dailyAverages, percentile: 0.5)
        let deviations = dailyAverages.map { abs($0 - median) }
        let robustSpread = percentile(deviations, percentile: 0.5) * 1.4826
        let balancedHalfWidth = max(median * 0.12, robustSpread)

        return HRVRhythmBaseline(
            medianSDNNMilliseconds: median,
            lowerBalancedSDNNMilliseconds: max(0, median - balancedHalfWidth),
            upperBalancedSDNNMilliseconds: median + balancedHalfWidth,
            availableDays: dailyAverages.count,
            lookbackDays: rhythmBaselineLookbackDays
        )
    }

    private static func dailyAverageSDNNMilliseconds(
        samples: [HKQuantitySample],
        calendar: Calendar,
        startOffset: Int,
        endOffset: Int,
        todayStart: Date
    ) -> [Double] {
        let unit = HKUnit.secondUnit(with: .milli)
        var averages: [Double] = []
        for offset in stride(from: startOffset, through: endOffset, by: 1) {
            guard let day = calendar.date(byAdding: .day, value: offset, to: todayStart) else { continue }
            let values = samples
                .filter { calendar.isDate($0.endDate, inSameDayAs: day) }
                .map { $0.quantity.doubleValue(for: unit) }
                .filter { $0 > 0 }
            guard !values.isEmpty else { continue }
            averages.append(values.reduce(0, +) / Double(values.count))
        }
        return averages
    }

    private static func percentile(_ values: [Double], percentile: Double) -> Double {
        let sorted = values.sorted()
        guard let first = sorted.first else { return 0 }
        guard sorted.count > 1 else { return first }
        let clampedPercentile = min(1, max(0, percentile))
        let rawIndex = clampedPercentile * Double(sorted.count - 1)
        let lowerIndex = Int(floor(rawIndex))
        let upperIndex = Int(ceil(rawIndex))
        guard lowerIndex != upperIndex else { return sorted[lowerIndex] }
        let fraction = rawIndex - Double(lowerIndex)
        return sorted[lowerIndex] + (sorted[upperIndex] - sorted[lowerIndex]) * fraction
    }

    private static func samplesFromRecentSevenDays(_ samples: [HKQuantitySample], calendar: Calendar, now: Date) -> [HKQuantitySample] {
        let todayStart = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -6, to: todayStart) else {
            return samples
        }
        return samples.filter { $0.endDate >= start }
    }

    private static func makeWeeklySummary(samples: [HKQuantitySample], calendar: Calendar, now: Date) -> HRVWeeklySummary {
        let unit = HKUnit.secondUnit(with: .milli)
        let todayStart = calendar.startOfDay(for: now)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"

        var daily: [HRVDailySummary] = []
        for offset in stride(from: -6, through: 0, by: 1) {
            guard let day = calendar.date(byAdding: .day, value: offset, to: todayStart) else { continue }
            let daySamples = samples.filter { calendar.isDate($0.endDate, inSameDayAs: day) }
            guard !daySamples.isEmpty else { continue }
            let values = daySamples.map { $0.quantity.doubleValue(for: unit) }.filter { $0 > 0 }
            guard !values.isEmpty else { continue }
            let avg = values.reduce(0, +) / Double(values.count)
            daily.append(HRVDailySummary(day: formatter.string(from: day), sampleCount: values.count, averageSDNNMilliseconds: avg))
        }

        guard daily.count >= 2 else {
            return HRVWeeklySummary(
                generatedAt: now,
                days: daily,
                sevenDayAverageSDNNMilliseconds: daily.first?.averageSDNNMilliseconds,
                latestDayAverageSDNNMilliseconds: daily.last?.averageSDNNMilliseconds,
                latestDeviationFromBaselinePercent: nil,
                dataCompleteness: Double(daily.count) / 7.0,
                status: .insufficientData
            )
        }

        let averages = daily.map(\.averageSDNNMilliseconds)
        let baseline = averages.reduce(0, +) / Double(averages.count)
        let latest = averages.last ?? baseline
        let deviation = baseline > 0 ? ((latest - baseline) / baseline) * 100 : nil
        let standardDeviation = sqrt(averages.map { pow($0 - baseline, 2) }.reduce(0, +) / Double(averages.count))
        let coefficientOfVariation = baseline > 0 ? standardDeviation / baseline : 0

        let status: HRVTrendStatus
        if daily.count < 3 {
            status = .insufficientData
        } else if daily.count >= 4 && coefficientOfVariation > 0.25 {
            status = .variable
        } else if let deviation, deviation <= -15 {
            status = .belowBaseline
        } else if let deviation, deviation >= 15 {
            status = .aboveBaseline
        } else {
            status = .nearBaseline
        }

        return HRVWeeklySummary(
            generatedAt: now,
            days: daily,
            sevenDayAverageSDNNMilliseconds: baseline,
            latestDayAverageSDNNMilliseconds: latest,
            latestDeviationFromBaselinePercent: deviation,
            dataCompleteness: Double(daily.count) / 7.0,
            status: status
        )
    }

    private static func insufficientWeeklySummary() -> HRVWeeklySummary {
        HRVWeeklySummary(
            generatedAt: Date(),
            days: [],
            sevenDayAverageSDNNMilliseconds: nil,
            latestDayAverageSDNNMilliseconds: nil,
            latestDeviationFromBaselinePercent: nil,
            dataCompleteness: 0,
            status: .insufficientData
        )
    }
}
