//
//  ReminderTemplates.swift
//

import Foundation

public struct ReminderTemplate: Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let notificationBody: String
    public let schedule: BolaReminder.Schedule
    public let kind: ReminderKind

    public init(
        id: String,
        title: String,
        notificationBody: String,
        schedule: BolaReminder.Schedule,
        kind: ReminderKind
    ) {
        self.id = id
        self.title = title
        self.notificationBody = notificationBody
        self.schedule = schedule
        self.kind = kind
    }

    public func makeReminder() -> BolaReminder {
        BolaReminder(title: title, notificationBody: notificationBody, schedule: schedule, kind: kind)
    }
}

public enum ReminderTemplateLibrary {
    public static let all: [ReminderTemplate] = [
        ReminderTemplate(
            id: "water",
            title: "Bola · 喝水",
            notificationBody: "该喝水啦，小口慢饮～",
            schedule: .calendar(hour: 10, minute: 0, weekdays: []),
            kind: .water
        ),
        ReminderTemplate(
            id: "move",
            title: "Bola · 站立动动",
            notificationBody: "起来站一站、伸个懒腰，眼睛也休息一下。",
            schedule: .calendar(hour: 11, minute: 30, weekdays: []),
            kind: .move
        ),
        ReminderTemplate(
            id: "meal",
            title: "Bola · 吃饭",
            notificationBody: "到点吃饭啦，别饿着自己～",
            schedule: .calendar(hour: 12, minute: 30, weekdays: []),
            kind: .meal
        ),
        ReminderTemplate(
            id: "sleep",
            title: "Bola · 准备休息",
            notificationBody: "该慢慢收工啦，睡前少刷会儿手机哦。",
            schedule: .calendar(hour: 22, minute: 30, weekdays: []),
            kind: .sleep
        ),
        ReminderTemplate(
            id: "heart",
            title: "Bola · 心率关注",
            notificationBody: "今天也留意一下心率变化，不舒服要及时休息或就医。",
            schedule: .calendar(hour: 15, minute: 0, weekdays: []),
            kind: .heart
        )
    ]
}
