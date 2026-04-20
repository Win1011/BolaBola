//
//  MealEngine.swift
//  Watch-only — authoritative meal scheduling, hunger, feeding, reward engine
//

import Foundation

struct FeedResult {
    let reward: Double
    let newStatus: MealRecordStatus
    let coreState: PetCoreState
    let mealId: String
}

final class MealEngine {
    static let shared = MealEngine()

    private(set) var mealSlots: [MealSlot] = []
    private(set) var todayRecords: [MealRecord] = []
    private var todayDateStr: String = ""

    private let earlyWindowSeconds: TimeInterval = 2 * 3600
    private let autoFeedAfterSeconds: TimeInterval = 3600

    private let defaults = BolaSharedDefaults.resolved()

    var onTriggerHungry: (() -> Void)?
    var onExitHungry: (() -> Void)?

    private init() {
        loadSlots()
        generateTodayRecordsIfNeeded(now: Date())
    }

    // MARK: - Slot management

    func loadSlots() {
        mealSlots = MealSlotStore.load(from: defaults)
        BolaDebugLog.shared.log(.meal, "slots loaded: \(mealSlots.map { "\($0.id)=\($0.timeString)" }.joined(separator: ", "))")
    }

    func updateSlots(_ slots: [MealSlot], now: Date = Date()) {
        mealSlots = slots
        MealSlotStore.save(slots, to: defaults)
        BolaDebugLog.shared.log(.meal, "slots updated: \(slots.map { "\($0.id)=\($0.timeString)" }.joined(separator: ", "))")
        regenerateRecordsAfterSlotUpdate(now: now)
        refreshMealState(now: now)
    }

    // MARK: - Record generation

    private func dateStr(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    func generateTodayRecordsIfNeeded(now: Date) {
        let ds = dateStr(now)
        guard ds != todayDateStr else { return }

        if let saved = MealRecordStore.load(from: defaults), saved.dateStr == ds {
            todayRecords = saved.records
            todayDateStr = ds
            BolaDebugLog.shared.log(.meal, "records restored for \(ds): \(todayRecords.count)")
            return
        }

        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        todayRecords = mealSlots.map { slot in
            let scheduled = cal.date(bySettingHour: slot.hour, minute: slot.minute, second: 0, of: today) ?? today
            return MealRecord(
                recordId: "\(ds)-\(slot.id)",
                mealId: slot.id,
                scheduledDate: scheduled,
                status: .pending
            )
        }
        todayDateStr = ds
        persistRecords()
        BolaDebugLog.shared.log(.meal, "records generated for \(ds): \(todayRecords.count)")
    }

    private func persistRecords() {
        MealRecordStore.save(dateStr: todayDateStr, records: todayRecords, to: defaults)
    }

    // MARK: - Catch-up / reconciliation

    func refreshMealState(now: Date = Date()) {
        generateTodayRecordsIfNeeded(now: now)

        var didTriggerHungry = false
        var didAutoFeed = false

        for i in todayRecords.indices {
            switch todayRecords[i].status {
            case .pending:
                if now >= todayRecords[i].scheduledDate {
                    todayRecords[i].status = .hungryActive
                    didTriggerHungry = true
                    BolaDebugLog.shared.log(.meal, "reconciliation: \(todayRecords[i].recordId) → hungryActive")
                }
            case .hungryActive:
                let autoFeedTime = todayRecords[i].scheduledDate.addingTimeInterval(autoFeedAfterSeconds)
                if now >= autoFeedTime {
                    todayRecords[i].status = .autoFed
                    didAutoFeed = true
                    BolaDebugLog.shared.log(.meal, "reconciliation: \(todayRecords[i].recordId) → autoFed (1h timeout)")
                }
            default:
                break
            }
        }

        if didTriggerHungry || didAutoFeed {
            persistRecords()
        }

        if didAutoFeed {
            onExitHungry?()
        }

        if didTriggerHungry {
            onTriggerHungry?()
        }
    }

    // MARK: - Feed resolution

    func resolveFeedAction(now: Date = Date()) -> FeedResult? {
        generateTodayRecordsIfNeeded(now: now)

        guard let target = findValidMealTarget(now: now) else {
            BolaDebugLog.shared.log(.meal, "resolveFeedAction: no valid target")
            return nil
        }

        guard let idx = todayRecords.indices.first(where: { $0 == todayRecords.firstIndex(where: { $0.recordId == target.recordId }) }) else {
            return nil
        }

        switch target.status {
        case .pending:
            todayRecords[idx].status = .fedBeforeHungry
            persistRecords()
            BolaDebugLog.shared.log(.meal, "feed resolved: \(target.recordId) → fedBeforeHungry, reward +10")
            return FeedResult(reward: 10, newStatus: .fedBeforeHungry, coreState: .idle, mealId: target.mealId)

        case .hungryActive:
            todayRecords[idx].status = .fedAfterHungry
            persistRecords()
            BolaDebugLog.shared.log(.meal, "feed resolved: \(target.recordId) → fedAfterHungry, reward +5")
            return FeedResult(reward: 5, newStatus: .fedAfterHungry, coreState: .idle, mealId: target.mealId)

        default:
            return nil
        }
    }

    private func findValidMealTarget(now: Date) -> MealRecord? {
        let validRecords = todayRecords.filter { record in
            switch record.status {
            case .pending:
                let windowStart = record.scheduledDate.addingTimeInterval(-earlyWindowSeconds)
                return now >= windowStart && now < record.scheduledDate
            case .hungryActive:
                return true
            default:
                return false
            }
        }
        return validRecords.sorted { $0.scheduledDate < $1.scheduledDate }.first
    }

    // MARK: - Query

    func hasFeedableMeal(now: Date = Date()) -> Bool {
        findValidMealTarget(now: now) != nil
    }

    func hasActiveHungry() -> Bool {
        todayRecords.contains { $0.status == .hungryActive }
    }

    func nextMealInfo(now: Date = Date()) -> (mealId: String, timeString: String, isFeedable: Bool)? {
        generateTodayRecordsIfNeeded(now: now)
        guard let slot = mealSlots.sorted(by: { timeFromDate($0, now: now) < timeFromDate($1, now: now) }).first(where: { slot in
            guard let record = todayRecords.first(where: { $0.mealId == slot.id }) else { return false }
            return !record.status.isFinalized
        }) else { return nil }
        let isFeedable = findValidMealTarget(now: now) != nil
        return (slot.id, slot.timeString, isFeedable)
    }

    private func timeFromDate(_ slot: MealSlot, now: Date) -> Date {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        return cal.date(bySettingHour: slot.hour, minute: slot.minute, second: 0, of: today) ?? now
    }

    // MARK: - Slot update with record regeneration

    private func regenerateRecordsAfterSlotUpdate(now: Date) {
        let ds = dateStr(now)
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)

        var newRecords: [MealRecord] = []

        for slot in mealSlots {
            let recordId = "\(ds)-\(slot.id)"
            let scheduled = cal.date(bySettingHour: slot.hour, minute: slot.minute, second: 0, of: today) ?? today

            if let existing = todayRecords.first(where: { $0.mealId == slot.id }) {
                if existing.status.isFinalized || existing.status == .hungryActive {
                    newRecords.append(existing)
                } else {
                    newRecords.append(MealRecord(
                        recordId: recordId,
                        mealId: slot.id,
                        scheduledDate: scheduled,
                        status: .pending
                    ))
                }
            } else {
                newRecords.append(MealRecord(
                    recordId: recordId,
                    mealId: slot.id,
                    scheduledDate: scheduled,
                    status: .pending
                ))
            }
        }

        todayRecords = newRecords
        todayDateStr = ds
        persistRecords()
        BolaDebugLog.shared.log(.meal, "records regenerated after slot update: \(todayRecords.count)")
    }
}
