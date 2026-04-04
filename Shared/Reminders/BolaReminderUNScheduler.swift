//
//  BolaReminderUNScheduler.swift
//

import Foundation
#if canImport(UserNotifications)
import UserNotifications

/// Registers local notifications for `BolaReminder` list; removes previous `bola_r_*` requests first.
public enum BolaReminderUNScheduler {
    private static let idPrefix = "bola_r_"

    public static func sync(reminders: [BolaReminder]) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let toRemove = pending.map(\.identifier).filter { $0.hasPrefix(idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: toRemove)

        for rem in reminders where rem.isEnabled {
            await schedule(rem, center: center)
        }
    }

    private static func schedule(_ rem: BolaReminder, center: UNUserNotificationCenter) async {
        let content = UNMutableNotificationContent()
        content.title = rem.title
        content.body = rem.notificationBody
        content.sound = .default

        switch rem.schedule {
        case .interval(let seconds):
            let interval = max(60, seconds)
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: true)
            let req = UNNotificationRequest(identifier: "\(idPrefix)\(rem.id.uuidString)", content: content, trigger: trigger)
            _ = try? await center.add(req)

        case .calendar(let hour, let minute, let weekdays):
            if weekdays.isEmpty {
                var dc = DateComponents()
                dc.hour = hour
                dc.minute = minute
                let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)
                let req = UNNotificationRequest(identifier: "\(idPrefix)\(rem.id.uuidString)_daily", content: content, trigger: trigger)
                _ = try? await center.add(req)
            } else {
                for wd in weekdays {
                    var dc = DateComponents()
                    dc.weekday = wd
                    dc.hour = hour
                    dc.minute = minute
                    let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)
                    let req = UNNotificationRequest(
                        identifier: "\(idPrefix)\(rem.id.uuidString)_w\(wd)",
                        content: content,
                        trigger: trigger
                    )
                    _ = try? await center.add(req)
                }
            }

        case .once(let date):
            let interval = date.timeIntervalSinceNow
            guard interval > 0 else { return }
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, interval), repeats: false)
            content.sound = UNNotificationSound.defaultCritical
            let req = UNNotificationRequest(identifier: "\(idPrefix)\(rem.id.uuidString)_once", content: content, trigger: trigger)
            _ = try? await center.add(req)
        }
    }
}
#endif
