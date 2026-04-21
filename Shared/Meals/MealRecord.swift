//
//  MealRecord.swift
//  Shared — daily meal record + status
//

import Foundation

enum MealRecordStatus: String, Codable, Sendable {
    case pending
    case fedBeforeHungry
    case hungryActive
    case fedAfterHungry
    case autoFed

    var isFinalized: Bool {
        switch self {
        case .pending, .hungryActive: return false
        case .fedBeforeHungry, .fedAfterHungry, .autoFed: return true
        }
    }
}

struct MealRecord: Codable, Equatable, Sendable {
    var recordId: String
    var mealId: String
    var scheduledDate: Date
    var status: MealRecordStatus
}

enum MealRecordStore {
    private static let recordsKey = "bola_meal_records_v1"
    private static let dateKey = "bola_meal_records_date_v1"

    static func load(from defaults: UserDefaults = BolaSharedDefaults.resolved()) -> (dateStr: String, records: [MealRecord])? {
        guard let dateStr = defaults.string(forKey: dateKey),
              let data = defaults.data(forKey: recordsKey),
              let records = try? JSONDecoder().decode([MealRecord].self, from: data) else {
            return nil
        }
        return (dateStr, records)
    }

    static func save(dateStr: String, records: [MealRecord], to defaults: UserDefaults = BolaSharedDefaults.resolved()) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: recordsKey)
        defaults.set(dateStr, forKey: dateKey)
        BolaDebugLog.shared.log(.meal, "meal records saved date=\(dateStr) count=\(records.count)")
    }
}
