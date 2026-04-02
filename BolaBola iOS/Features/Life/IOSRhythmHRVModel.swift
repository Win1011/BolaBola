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
        await requestAuthorization(types: types)

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

    private func requestAuthorization(types: Set<HKObjectType>) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            store.requestAuthorization(toShare: [], read: types) { _, _ in
                DispatchQueue.main.async {
                    cont.resume()
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
