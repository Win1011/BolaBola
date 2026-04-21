//
//  IOSWatchFaceHealthPreviewModel.swift
//  主界面表盘预览：心率、步数（HealthKit 只读，与系统健康数据一致）。
//

import Combine
import Foundation
import HealthKit

@MainActor
final class IOSWatchFaceHealthPreviewModel: ObservableObject {
    @Published private(set) var heartRateText: String = "—"
    @Published private(set) var stepsText: String = "—"

    private let store = HKHealthStore()

    func refresh() {
        guard HKHealthStore.isHealthDataAvailable() else {
            heartRateText = "—"
            stepsText = "—"
            return
        }
        guard BolaOnboardingState.isCompleted else {
            heartRateText = "—"
            stepsText = "—"
            return
        }
        var read = Set<HKObjectType>()
        if let t = HKQuantityType.quantityType(forIdentifier: .heartRate) { read.insert(t) }
        if let t = HKQuantityType.quantityType(forIdentifier: .stepCount) { read.insert(t) }
        store.getRequestStatusForAuthorization(toShare: [], read: read) { [weak self] status, _ in
            guard let self else { return }
            guard status == .unnecessary else {
                Task { @MainActor in
                    self.heartRateText = "—"
                    self.stepsText = "—"
                }
                return
            }
            Task { @MainActor in
                async let hr = Self.queryLatestHeartRateText(store: self.store)
                async let st = Self.queryTodayStepsText(store: self.store)
                self.heartRateText = await hr
                self.stepsText = await st
            }
        }
    }

    nonisolated private static func queryLatestHeartRateText(store: HKHealthStore) async -> String {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return "—" }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let samples: [HKSample] = await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, results, _ in
                cont.resume(returning: results ?? [])
            }
            store.execute(q)
        }
        guard let q = samples.first as? HKQuantitySample else { return "—" }
        let bpm = q.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        return "\(Int(bpm.rounded()))"
    }

    nonisolated private static func queryTodayStepsText(store: HKHealthStore) async -> String {
        guard let type = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return "—" }
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let pred = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        let sum: Double = await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: pred, options: .cumulativeSum) { _, stats, _ in
                let v = stats?.sumQuantity()?.doubleValue(for: .count()) ?? 0
                cont.resume(returning: v)
            }
            store.execute(q)
        }
        return "\(Int(sum))"
    }
}
