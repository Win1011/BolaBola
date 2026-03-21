//
//  HealthKitManager.swift
//  BolaBola Watch App
//
//  只读 HealthKit：心率、步数（可选）。非医疗用途；前台查询为主。
//

import Foundation
import HealthKit

final class HealthKitManager {
    static let shared = HealthKitManager()

    private let store = HKHealthStore()

    /// 静息以上视为「偏快」时可提示（非诊断）
    var heartRateAlertThreshold: Double = 100

    private init() {}

    var isHealthDataAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    /// 请求读取心率（及可选步数）
    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        guard isHealthDataAvailable else {
            completion(false)
            return
        }
        var types = Set<HKObjectType>()
        if let hr = HKObjectType.quantityType(forIdentifier: .heartRate) {
            types.insert(hr)
        }
        if let steps = HKObjectType.quantityType(forIdentifier: .stepCount) {
            types.insert(steps)
        }

        store.requestAuthorization(toShare: nil, read: types) { ok, _ in
            DispatchQueue.main.async {
                completion(ok)
            }
        }
    }

    /// 查询最近一次心率样本（手表上多为最近几分钟）
    func fetchLatestHeartRate(completion: @escaping (Double?) -> Void) {
        guard isHealthDataAvailable,
              let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            completion(nil)
            return
        }

        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let query = HKSampleQuery(
            sampleType: type,
            predicate: nil,
            limit: 1,
            sortDescriptors: [sort]
        ) { _, samples, error in
            guard error == nil,
                  let sample = samples?.first as? HKQuantitySample else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let bpm = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            DispatchQueue.main.async { completion(bpm) }
        }
        store.execute(query)
    }

    /// 若心率高于阈值则返回一句文案（用于界面气泡）；否则 nil
    func elevatedHeartRateDialogueLineIfNeeded(completion: @escaping (String?) -> Void) {
        fetchLatestHeartRate { [weak self] bpm in
            guard let self, let bpm, bpm >= self.heartRateAlertThreshold else {
                completion(nil)
                return
            }
            completion(BolaDialogueLines.heartRateFast(Int(bpm.rounded())))
        }
    }
}
