//
//  DailyDigestUNScheduler.swift
//

import Foundation
#if canImport(UserNotifications)
import UserNotifications

public enum DailyDigestUNScheduler {
    private static let digestId = "bola_digest_daily"

    public static func sync(config: DailyDigestConfig) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [digestId])
        guard config.isEnabled else { return }

        let defaults = BolaSharedDefaults.resolved()
        let body = defaults.string(forKey: DailyDigestStorageKeys.lastDigestBody).flatMap { $0.isEmpty ? nil : $0 }
            ?? "今天的信准备好啦，点进来让 Bola 读给你听～"

        var dc = DateComponents()
        dc.hour = config.hour
        dc.minute = config.minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)

        let content = UNMutableNotificationContent()
        content.title = "Bola 每日总结"
        content.body = body
        content.sound = .default
        content.categoryIdentifier = "bola_digest"

        let req = UNNotificationRequest(identifier: digestId, content: content, trigger: trigger)
        _ = try? await center.add(req)
    }
}
#endif
