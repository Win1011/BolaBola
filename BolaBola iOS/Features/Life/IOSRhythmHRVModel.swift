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
            case .noData:    return "GrowthHeroIsland"
            case .depleted:  return "RhythmBola_Depleted"
            case .low:       return "RhythmBola_Low"
            case .balanced:  return "RhythmBola_Balanced"
            case .good:      return "RhythmBola_Good"
            case .vibrant:   return "RhythmBola_Vibrant"
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

    /// 24 个值，对应今天 0–23 时，0...1 用于条高
    @Published private(set) var hourlyNormalized: [Double] = Array(repeating: 0, count: 24)
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var errorMessage: String?

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
            hourlyNormalized = Self.normalizeBuckets(buckets)
            phase = hourlyNormalized.allSatisfy { $0 < 0.02 } ? .empty : .ready
        } catch {
            errorMessage = (error as NSError).localizedDescription
            phase = .empty
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

    /// 将毫秒值转为 0...1，使用当日最大/最小拉伸；全 0 则保持 0
    private static func normalizeBuckets(_ raw: [Double]) -> [Double] {
        let positive = raw.filter { $0 > 0 }
        guard let maxV = positive.max(), maxV > 0 else {
            return raw.map { _ in 0 }
        }
        let minV = positive.min() ?? 0
        let span = max(maxV - minV, 1)
        return raw.map { v in
            guard v > 0 else { return 0 }
            return min(1, max(0, (v - minV) / span))
        }
    }
}
