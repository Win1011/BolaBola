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

    /// 超过该 BPM 且样本足够「新」时在前台提醒（非诊断、非医疗）
    var heartRateAlertThreshold: Double = 100
    /// 偏高提醒：只信任最近这段时间内的心率样本，避免用陈旧数据误报
    var heartRateSampleMaxAgeSeconds: TimeInterval = 8 * 60
    /// 界面展示：允许更旧的「最近一次心率」（例如久坐后仍能看到上次读数）
    var heartRateDisplayMaxAgeSeconds: TimeInterval = 24 * 3600

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

    /// 主界面 / 面板数字：接受较旧的最近一条样本
    func fetchLatestHeartRateForDisplay(completion: @escaping (Double?) -> Void) {
        fetchLatestHeartRate(maxSampleAge: heartRateDisplayMaxAgeSeconds, completion: completion)
    }

    /// 偏高提醒：仅使用足够新的样本
    func fetchLatestHeartRateForAlert(completion: @escaping (Double?) -> Void) {
        fetchLatestHeartRate(maxSampleAge: heartRateSampleMaxAgeSeconds, completion: completion)
    }

    private func fetchLatestHeartRate(maxSampleAge: TimeInterval, completion: @escaping (Double?) -> Void) {
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
            let age = Date().timeIntervalSince(sample.endDate)
            guard age >= 0, age <= maxSampleAge else {
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
        fetchLatestHeartRateForAlert { [weak self] bpm in
            guard let self, let bpm, bpm >= self.heartRateAlertThreshold else {
                completion(nil)
                return
            }
            completion(BolaDialogueLines.heartRateFastLine(bpm: Int(bpm.rounded())))
        }
    }
}
