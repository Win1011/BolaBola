//
//  IOSReminderEditorSheet.swift
//

import SwiftUI

struct IOSReminderEditorSheet: View {
    enum Mode {
        case create
        case createFromTemplate(ReminderTemplate)
        case edit(BolaReminder)
    }

    @Environment(\.dismiss) private var dismiss
    let mode: Mode
    let onSave: (BolaReminder) -> Void
    var onDelete: (() -> Void)?

    private enum RepeatShape: String, CaseIterable {
        case daily = "每天"
        case workweek = "工作日"
        case customWeekdays = "自定义星期"
        case interval = "固定间隔"
    }

    @State private var title: String
    @State private var bodyText: String
    @State private var timeDate: Date
    @State private var repeatShape: RepeatShape
    @State private var weekdaySelected: Set<Int>
    @State private var intervalHours: Int

    init(mode: Mode, onSave: @escaping (BolaReminder) -> Void, onDelete: (() -> Void)? = nil) {
        self.mode = mode
        self.onSave = onSave
        self.onDelete = onDelete

        let cal = Calendar.current
        let baseTime: Date
        var initialTitle = ""
        var initialBody = ""
        var initialRepeat: RepeatShape = .daily
        var initialWeekdays = Set<Int>()
        var initialIntervalH = 2

        switch mode {
        case .create:
            baseTime = cal.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
        case .createFromTemplate(let t):
            initialTitle = t.title
            initialBody = t.notificationBody
            switch t.schedule {
            case .interval(let sec):
                initialRepeat = .interval
                initialIntervalH = max(1, Int(sec / 3600))
                baseTime = cal.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
            case .calendar(let h, let m, let wd):
                baseTime = cal.date(bySettingHour: h, minute: m, second: 0, of: Date()) ?? Date()
                if wd.isEmpty {
                    initialRepeat = .daily
                } else if Set(wd) == Set([2, 3, 4, 5, 6]) {
                    initialRepeat = .workweek
                } else {
                    initialRepeat = .customWeekdays
                    initialWeekdays = Set(wd)
                }
            case .once(let d):
                baseTime = d
                initialRepeat = .daily
            }
        case .edit(let r):
            initialTitle = r.title
            initialBody = r.notificationBody
            switch r.schedule {
            case .interval(let sec):
                initialRepeat = .interval
                initialIntervalH = max(1, Int(sec / 3600))
                baseTime = cal.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
            case .calendar(let h, let m, let wd):
                baseTime = cal.date(bySettingHour: h, minute: m, second: 0, of: Date()) ?? Date()
                if wd.isEmpty {
                    initialRepeat = .daily
                } else if Set(wd) == Set([2, 3, 4, 5, 6]) {
                    initialRepeat = .workweek
                } else {
                    initialRepeat = .customWeekdays
                    initialWeekdays = Set(wd)
                }
            case .once(let d):
                baseTime = d
                initialRepeat = .daily
            }
        }

        _title = State(initialValue: initialTitle)
        _bodyText = State(initialValue: initialBody)
        _timeDate = State(initialValue: baseTime)
        _repeatShape = State(initialValue: initialRepeat)
        _weekdaySelected = State(initialValue: initialWeekdays)
        _intervalHours = State(initialValue: initialIntervalH)
    }

    private var editingReminderId: UUID? {
        if case .edit(let r) = mode { return r.id }
        return nil
    }

    private var resolvedKind: ReminderKind? {
        switch mode {
        case .create: return .custom
        case .createFromTemplate(let t): return t.kind
        case .edit(let r): return r.kind
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("标题", text: $title)
                    TextField("通知正文", text: $bodyText, axis: .vertical)
                        .lineLimit(3 ... 6)
                }

                Section {
                    Picker("重复方式", selection: $repeatShape) {
                        ForEach(RepeatShape.allCases, id: \.self) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                    .pickerStyle(.menu)
                } footer: {
                    Text(repeatShape == .interval
                         ? "固定间隔：从保存或重新打开通知权限后起算，每隔设定时长重复一次（与「每天几点」不同）。"
                         : "日历重复：在指定时间点提醒；可选工作日或自定义星期。")
                        .font(.caption)
                }

                if repeatShape != .interval {
                    Section("时间") {
                        DatePicker(
                            "提醒时间",
                            selection: $timeDate,
                            displayedComponents: [.hourAndMinute]
                        )
                        .datePickerStyle(.wheel)
                    }
                }

                if repeatShape == .customWeekdays {
                    Section("选择星期") {
                        ForEach(1 ... 7, id: \.self) { wd in
                            let symbols = Calendar.current.shortWeekdaySymbols
                            let name = (wd >= 1 && wd <= 7) ? symbols[wd - 1] : "?"
                            Toggle(isOn: Binding(
                                get: { weekdaySelected.contains(wd) },
                                set: { on in
                                    if on { weekdaySelected.insert(wd) } else { weekdaySelected.remove(wd) }
                                }
                            )) {
                                Text(name)
                            }
                        }
                    }
                }

                if repeatShape == .interval {
                    Section("间隔") {
                        Stepper("每 \(intervalHours) 小时", value: $intervalHours, in: 1 ... 12)
                    }
                }

                if onDelete != nil, editingReminderId != nil {
                    Section {
                        Button(role: .destructive) {
                            onDelete?()
                            dismiss()
                        } label: {
                            Text("删除此提醒")
                        }
                    }
                }
            }
            .navigationTitle(navigationTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private var navigationTitle: String {
        switch mode {
        case .create, .createFromTemplate: return "新提醒"
        case .edit: return "编辑提醒"
        }
    }

    private func save() {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        let b = bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "到点啦～" : bodyText

        let schedule: BolaReminder.Schedule
        let cal = Calendar.current
        switch repeatShape {
        case .interval:
            let sec = TimeInterval(intervalHours * 3600)
            schedule = .interval(max(60, sec))
        case .daily:
            let h = cal.component(.hour, from: timeDate)
            let m = cal.component(.minute, from: timeDate)
            schedule = .calendar(hour: h, minute: m, weekdays: [])
        case .workweek:
            let h = cal.component(.hour, from: timeDate)
            let m = cal.component(.minute, from: timeDate)
            schedule = .calendar(hour: h, minute: m, weekdays: [2, 3, 4, 5, 6])
        case .customWeekdays:
            let h = cal.component(.hour, from: timeDate)
            let m = cal.component(.minute, from: timeDate)
            let wd = weekdaySelected.sorted()
            guard !wd.isEmpty else { return }
            schedule = .calendar(hour: h, minute: m, weekdays: wd)
        }

        let id = editingReminderId ?? UUID()
        let created: Date
        if case .edit(let r) = mode {
            created = r.createdAt
        } else {
            created = Date()
        }

        let reminder = BolaReminder(
            id: id,
            title: t,
            notificationBody: b,
            schedule: schedule,
            kind: resolvedKind,
            isEnabled: true,
            createdAt: created
        )
        if case .edit(let r) = mode {
            var copy = reminder
            copy.isEnabled = r.isEnabled
            onSave(copy)
        } else {
            onSave(reminder)
        }
        dismiss()
    }
}
