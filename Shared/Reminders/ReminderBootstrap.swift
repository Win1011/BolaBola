//
//  ReminderBootstrap.swift
//

import Foundation

public enum ReminderBootstrap {
    private static let bootKey = "bola_reminders_bootstrapped_v1"

    /// 首次安装时写入两条「墙钟时间」示例提醒（与 interval 倒计时式区分）。
    public static func ensureDefaults(in defaults: UserDefaults = BolaSharedDefaults.resolved()) {
        guard !defaults.bool(forKey: bootKey) else { return }
        var list = ReminderListStore.load(from: defaults)
        if list.isEmpty {
            list = [
                BolaReminder(
                    title: "Bola · 喝水",
                    notificationBody: "该喝水啦，小口慢饮～",
                    schedule: .calendar(hour: 10, minute: 0, weekdays: []),
                    kind: .water
                ),
                BolaReminder(
                    title: "Bola · 动一动",
                    notificationBody: "起来伸展一下，眼睛也休息一下。",
                    schedule: .calendar(hour: 15, minute: 0, weekdays: []),
                    kind: .move
                )
            ]
            ReminderListStore.save(list, to: defaults)
        }
        defaults.set(true, forKey: bootKey)
    }
}
