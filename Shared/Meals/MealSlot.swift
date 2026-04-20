//
//  MealSlot.swift
//  Shared — configurable daily meal slot
//

import Foundation

public struct MealSlot: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var hour: Int
    public var minute: Int

    public init(id: String, hour: Int, minute: Int) {
        self.id = id
        self.hour = hour
        self.minute = minute
    }

    public static let defaults: [MealSlot] = [
        MealSlot(id: "meal1", hour: 8, minute: 30),
        MealSlot(id: "meal2", hour: 12, minute: 30),
        MealSlot(id: "meal3", hour: 18, minute: 30)
    ]

    public var timeString: String {
        String(format: "%02d:%02d", hour, minute)
    }
}

public enum MealSlotStore {
    private static let key = "bola_meal_slots_v1"

    public static func load(from defaults: UserDefaults = BolaSharedDefaults.resolved()) -> [MealSlot] {
        guard let data = defaults.data(forKey: key),
              let slots = try? JSONDecoder().decode([MealSlot].self, from: data) else {
            let initial = MealSlot.defaults
            save(initial, to: defaults)
            return initial
        }
        return slots
    }

    public static func save(_ slots: [MealSlot], to defaults: UserDefaults = BolaSharedDefaults.resolved()) {
        guard let data = try? JSONEncoder().encode(slots) else { return }
        defaults.set(data, forKey: key)
        BolaDebugLog.shared.log(.meal, "meal slots saved count=\(slots.count)")
    }
}
