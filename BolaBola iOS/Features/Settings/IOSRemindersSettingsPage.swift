//
//  IOSRemindersSettingsPage.swift
//

import SwiftUI

struct IOSRemindersSettingsPage: View {
    @State private var reminders: [BolaReminder] = ReminderListStore.load()
    @State private var mealSlots: [MealSlot] = MealSlotStore.load()
    @State private var activeEditor: EditorSheetState?
    @State private var activeMealEditor: MealEditorSheetState?

    private struct EditorSheetState: Identifiable {
        let id = UUID()
        let mode: IOSReminderEditorSheet.Mode
    }
    private struct MealEditorSheetState: Identifiable {
        let id = UUID()
        let slot: MealSlot?
    }

    // 固定健康提醒种类的展示顺序
    private let healthKinds: [(kind: ReminderKind, templateId: String, label: String, tint: Color)] = [
        (.water,  "water",  "喝水",   .blue),
        (.move,   "move",   "站立活动", .green),
        (.sleep,  "sleep",  "睡眠",   .indigo),
        (.heart,  "heart",  "心率",   .red),
        (.meal,   "meal",   "餐食",   .orange),
    ]

    var body: some View {
        List {
            // MARK: 健康提醒
            Section {
                ForEach(healthKinds.filter { $0.kind != .meal }, id: \.templateId) { item in
                    let existing = reminders.first(where: { $0.kind == item.kind })
                    healthKindRow(item: item, existing: existing)
                }
            } header: {
                Text("健康提醒")
            } footer: {
                Text("点击条目可修改时间和内容；未添加的提醒点右侧「+」创建。")
            }

            // MARK: 餐食提醒
            Section {
                ForEach(mealSlots) { slot in
                    mealSlotRow(slot)
                }
                Button {
                    activeMealEditor = MealEditorSheetState(slot: nil)
                } label: {
                    Label("添加餐食时间", systemImage: "plus.circle.fill")
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("餐食提醒")
            } footer: {
                Text("Bola 会在设定时间提醒你记录用餐，手表端同步显示。")
            }
        }
        .navigationTitle("提醒管理")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $activeEditor) { sheet in
            IOSReminderEditorSheet(
                mode: sheet.mode,
                onSave: { saved in
                    if case .edit(let original) = sheet.mode {
                        if let idx = reminders.firstIndex(where: { $0.id == original.id }) {
                            reminders[idx] = saved
                        }
                    } else {
                        reminders.append(saved)
                    }
                    persist()
                },
                onDelete: {
                    if case .edit(let original) = sheet.mode {
                        reminders.removeAll { $0.id == original.id }
                        persist()
                    }
                }
            )
        }
        .sheet(item: $activeMealEditor) { sheet in
            IOSMealSlotEditorSheet(
                mealSlot: sheet.slot,
                onSave: { slot in
                    if let idx = mealSlots.firstIndex(where: { $0.id == slot.id }) {
                        mealSlots[idx] = slot
                    } else {
                        mealSlots.append(slot)
                    }
                    persistMealSlots()
                },
                onDelete: {
                    if let slot = sheet.slot {
                        mealSlots.removeAll { $0.id == slot.id }
                        persistMealSlots()
                    }
                }
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .bolaRemindersDidChange)) { _ in
            reminders = ReminderListStore.load()
        }
    }

    // MARK: - Row Builders

    @ViewBuilder
    private func healthKindRow(
        item: (kind: ReminderKind, templateId: String, label: String, tint: Color),
        existing: BolaReminder?
    ) -> some View {
        if let r = existing {
            HStack(spacing: 14) {
                Image(systemName: r.kind?.systemImageName ?? "bell.fill")
                    .foregroundStyle(item.tint)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.label)
                        .font(.subheadline.weight(.semibold))
                    Text(r.scheduleSummary())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { r.isEnabled },
                    set: { newVal in
                        guard let idx = reminders.firstIndex(where: { $0.id == r.id }) else { return }
                        reminders[idx].isEnabled = newVal
                        persist()
                    }
                ))
                .labelsHidden()
                .tint(BolaTheme.accent)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                activeEditor = EditorSheetState(mode: .edit(r))
            }
        } else {
            HStack(spacing: 14) {
                Image(systemName: item.kind.systemImageName)
                    .foregroundStyle(item.tint.opacity(0.4))
                    .frame(width: 28)
                Text(item.label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    let template = ReminderTemplateLibrary.all.first(where: { $0.id == item.templateId })
                    if let t = template {
                        activeEditor = EditorSheetState(mode: .createFromTemplate(t))
                    } else {
                        activeEditor = EditorSheetState(mode: .create)
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(item.tint)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func mealSlotRow(_ slot: MealSlot) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "fork.knife")
                .foregroundStyle(.orange)
                .frame(width: 28)
            Text(mealSlotLabel(slot))
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text(slot.timeString)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            activeMealEditor = MealEditorSheetState(slot: slot)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                mealSlots.removeAll { $0.id == slot.id }
                persistMealSlots()
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    // MARK: - Helpers

    private func mealSlotLabel(_ slot: MealSlot) -> String {
        switch slot.id {
        case "meal1": return "早餐"
        case "meal2": return "午餐"
        case "meal3": return "晚餐"
        default: return "餐食"
        }
    }

    private func persist() {
        ReminderListStore.save(reminders)
        Task { await BolaReminderUNScheduler.sync(reminders: reminders) }
    }

    private func persistMealSlots() {
        MealSlotStore.save(mealSlots)
        BolaWCSessionCoordinator.shared.pushMealSlotsToWatchIfPossible()
        Task { await BolaReminderUNScheduler.sync(reminders: reminders, mealSlots: mealSlots) }
        NotificationCenter.default.post(name: .bolaMealSlotsDidUpdate, object: nil)
    }
}
