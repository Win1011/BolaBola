//
//  ReminderListStore.swift
//

import Foundation

public extension Notification.Name {
    static let bolaRemindersDidChange = Notification.Name("bolaRemindersDidChange")
}

public enum ReminderListStore {
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    public static func load(from defaults: UserDefaults = BolaSharedDefaults.resolved()) -> [BolaReminder] {
        guard let data = defaults.data(forKey: ReminderStorageKeys.remindersJSON),
              let list = try? decoder.decode([BolaReminder].self, from: data) else {
            return []
        }
        return list
    }

    public static func save(_ reminders: [BolaReminder], to defaults: UserDefaults = BolaSharedDefaults.resolved()) {
        guard let data = try? encoder.encode(reminders) else { return }
        defaults.set(data, forKey: ReminderStorageKeys.remindersJSON)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .bolaRemindersDidChange, object: nil)
        }
    }
}
