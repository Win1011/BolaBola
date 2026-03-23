//
//  BolaReminder.swift
//

import Foundation

/// User-authored reminder shown as a card; scheduled with `UNUserNotificationCenter`.
public struct BolaReminder: Identifiable, Codable, Equatable, Sendable {
    public enum Schedule: Codable, Equatable, Sendable {
        /// Fires after `intervalSeconds` from enable / reschedule, repeating.
        case interval(TimeInterval)
        /// Hour 0–23, minute 0–59, weekdays 1...7 (Calendar weekday) empty = every day.
        case calendar(hour: Int, minute: Int, weekdays: [Int])
    }

    public var id: UUID
    public var title: String
    public var notificationBody: String
    public var schedule: Schedule
    public var isEnabled: Bool
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        notificationBody: String,
        schedule: Schedule,
        isEnabled: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.notificationBody = notificationBody
        self.schedule = schedule
        self.isEnabled = isEnabled
        self.createdAt = createdAt
    }
}

public enum ReminderStorageKeys {
    public static let remindersJSON = "bola_reminders_v1"
}
