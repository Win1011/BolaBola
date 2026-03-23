//
//  ReminderBootstrap.swift
//

import Foundation

public enum ReminderBootstrap {
    private static let bootKey = "bola_reminders_bootstrapped_v1"

    /// Seeds two template reminders when the store is empty (first install).
    public static func ensureDefaults(in defaults: UserDefaults = BolaSharedDefaults.resolved()) {
        guard !defaults.bool(forKey: bootKey) else { return }
        var list = ReminderListStore.load(from: defaults)
        if list.isEmpty {
            list = [
                BolaReminder(
                    title: "Bola · 喝水",
                    notificationBody: "该喝水啦，小口慢饮～",
                    schedule: .interval(2 * 3600)
                ),
                BolaReminder(
                    title: "Bola · 动一动",
                    notificationBody: "起来伸展一下，眼睛也休息一下。",
                    schedule: .interval(3 * 3600)
                )
            ]
            ReminderListStore.save(list, to: defaults)
        }
        defaults.set(true, forKey: bootKey)
    }
}
