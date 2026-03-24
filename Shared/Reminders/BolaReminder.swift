//
//  BolaReminder.swift
//

import Foundation

/// 用于 UI 图标与模板；不参与通知调度逻辑。
public enum ReminderKind: String, Codable, Equatable, Sendable, CaseIterable {
    case water
    case move
    case meal
    case sleep
    case heart
    case custom

    public var systemImageName: String {
        switch self {
        case .water: return "drop.fill"
        case .move: return "figure.walk"
        case .meal: return "fork.knife"
        case .sleep: return "bed.double.fill"
        case .heart: return "heart.fill"
        case .custom: return "bell.fill"
        }
    }
}

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
    /// 可选；旧数据无此字段时解码为 `nil`。
    public var kind: ReminderKind?
    public var isEnabled: Bool
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        notificationBody: String,
        schedule: Schedule,
        kind: ReminderKind? = nil,
        isEnabled: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.notificationBody = notificationBody
        self.schedule = schedule
        self.kind = kind
        self.isEnabled = isEnabled
        self.createdAt = createdAt
    }
}

public extension BolaReminder {
    /// 简短中文说明，用于列表副标题。
    func scheduleSummary() -> String {
        switch schedule {
        case .interval(let seconds):
            let h = max(1, Int(seconds / 3600))
            let m = max(1, Int(seconds / 60))
            if seconds >= 3600 {
                return "每 \(h) 小时（自保存后起算）"
            }
            return "每 \(m) 分钟（自保存后起算）"
        case .calendar(let hour, let minute, let weekdays):
            let t = String(format: "%02d:%02d", hour, minute)
            if weekdays.isEmpty {
                return "每天 \(t)"
            }
            let workweek = Set(weekdays) == Set([2, 3, 4, 5, 6])
            if workweek {
                return "工作日 \(t)"
            }
            let symbols = Calendar.current.shortWeekdaySymbols
            let names = weekdays.sorted().map { wd in
                guard wd >= 1, wd <= 7 else { return "?" }
                return symbols[wd - 1]
            }
            return "\(names.joined(separator: "、")) \(t)"
        }
    }
}

public enum ReminderStorageKeys {
    public static let remindersJSON = "bola_reminders_v1"
}
