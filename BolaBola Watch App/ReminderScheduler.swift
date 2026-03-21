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

    /// 请求授权并注册默认定时提醒（喝水约 2h、站立约 3h，可后续改为 UserDefaults）
    func scheduleDefaultsIfAuthorized() {
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            guard granted, let self else { return }
            DispatchQueue.main.async {
                self.center.removeAllPendingNotificationRequests()
                self.scheduleWater(every: 2 * 3600)
                self.scheduleStandNudge(every: 3 * 3600)
            }
        }
    }

    private func scheduleWater(every interval: TimeInterval) {
        let content = UNMutableNotificationContent()
        content.title = "Bola"
        content.body = BolaDialogueLines.drinkWaterReminder.randomElement() ?? "该喝水啦。"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(60, interval), repeats: true)
        let req = UNNotificationRequest(identifier: "bola_water", content: content, trigger: trigger)
        center.add(req, withCompletionHandler: nil)
    }

    private func scheduleStandNudge(every interval: TimeInterval) {
        let content = UNMutableNotificationContent()
        content.title = "Bola"
        content.body = BolaDialogueLines.standUpNudge.randomElement() ?? "起来动一动吧。"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(120, interval), repeats: true)
        let req = UNNotificationRequest(identifier: "bola_stand", content: content, trigger: trigger)
        center.add(req, withCompletionHandler: nil)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
