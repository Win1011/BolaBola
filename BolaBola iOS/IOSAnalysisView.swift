//
//  IOSAnalysisView.swift
//  分析：HealthKit 习惯图表 + 提醒列表。
//

import SwiftUI

struct IOSAnalysisView: View {
    @Binding var reminders: [BolaReminder]

    @StateObject private var healthHabits = IOSHealthHabitAnalysisModel()
    @State private var showEditor = false
    @State private var editorMode: IOSReminderEditorSheet.Mode = .create

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BolaTheme.spacingSection) {
                remindersBlock
                IOSHealthHabitAnalysisSection(model: healthHabits)
            }
            .padding(.horizontal, BolaTheme.paddingHorizontal)
            .padding(.top, 0)
            .padding(.bottom, 24)
        }
        .refreshable {
            await healthHabits.refresh()
        }
        .task {
            await healthHabits.refresh()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .sheet(isPresented: $showEditor) {
            IOSReminderEditorSheet(
                mode: editorMode,
                onSave: { saved in
                    switch editorMode {
                    case .edit(let original):
                        if let idx = reminders.firstIndex(where: { $0.id == original.id }) {
                            reminders[idx] = saved
                        }
                    default:
                        reminders.append(saved)
                    }
                    persistReminders()
                },
                onDelete: {
                    if case .edit(let original) = editorMode {
                        reminders.removeAll { $0.id == original.id }
                        persistReminders()
                    }
                }
            )
        }
    }

    private var remindersBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("提醒")
                    .font(.headline)
                Spacer()
                Menu {
                    Button("+创建新提醒") {
                        editorMode = .create
                        showEditor = true
                    }
                    Section("模板") {
                        ForEach(ReminderTemplateLibrary.all) { t in
                            Button(t.title) {
                                editorMode = .createFromTemplate(t)
                                showEditor = true
                            }
                        }
                    }
                } label: {
                    Label("添加", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BolaTheme.onAccentForeground)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(BolaTheme.accent))
                }
            }

            if reminders.isEmpty {
                Text("还没有提醒。点「添加」从模板选一条，或自定义时间。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 12) {
                    ForEach(reminders) { r in
                        reminderRow(r)
                    }
                }
            }
        }
    }

    private func reminderRow(_ r: BolaReminder) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: (r.kind ?? .custom).systemImageName)
                .font(.title2)
                .foregroundStyle(Color(uiColor: .tertiaryLabel))
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(r.title)
                    .font(.subheadline.weight(.semibold))
                Text(r.scheduleSummary())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(r.notificationBody)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Toggle("", isOn: Binding(
                get: { r.isEnabled },
                set: { newVal in
                    guard let idx = reminders.firstIndex(where: { $0.id == r.id }) else { return }
                    reminders[idx].isEnabled = newVal
                    persistReminders()
                }
            ))
            .labelsHidden()
            .tint(BolaTheme.accent)
        }
        .padding(BolaTheme.spacingItem)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: BolaTheme.cornerCard, style: .continuous)
                .fill(BolaTheme.surfaceCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: BolaTheme.cornerCard, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.45), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            editorMode = .edit(r)
            showEditor = true
        }
        .contextMenu {
            Button(role: .destructive) {
                reminders.removeAll { $0.id == r.id }
                persistReminders()
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    private func persistReminders() {
        ReminderListStore.save(reminders)
        Task { await BolaReminderUNScheduler.sync(reminders: reminders) }
    }
}
