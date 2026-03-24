//
//  ReminderScheduler.swift
//  BolaBola Watch App
//
//  本地通知：喝水、活动等（非医疗结论，仅提醒）。
//

import Foundation
import UserNotifications

final class ReminderScheduler: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ReminderScheduler()

    private let center = UNUserNotificationCenter.current()

    private override init() {
        super.init()
        center.delegate = self
    }

    /// 请求授权；用共享存储中的提醒卡片 + 每日总结调度通知。
    func scheduleDefaultsIfAuthorized() {
        let digestCategory = UNNotificationCategory(
            identifier: "bola_digest",
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([digestCategory])

        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            Task { @MainActor in
                ReminderBootstrap.ensureDefaults()
                let list = ReminderListStore.load()
                await BolaReminderUNScheduler.sync(reminders: list)
                let digest = DailyDigestStore.load()
                await DailyDigestUNScheduler.sync(config: digest)
            }
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let id = response.notification.request.identifier
        if id == "bola_digest_daily" {
            BolaSharedDefaults.resolved().set(true, forKey: BolaNotificationBridgeKeys.digestTapOpen)
        }
        completionHandler()
    }
}
