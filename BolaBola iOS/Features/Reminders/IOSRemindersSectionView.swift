//
//  IOSRemindersSectionView.swift
//  提醒列表（生活页「Bola正在关心的事」与分析页等复用）。
//

import SwiftUI

struct IOSRemindersSectionView: View {
    enum Style {
        case standard
        /// Figma 生活页：白卡圆角 20、小粒「+添加」
        case figmaLife
    }

    @Binding var reminders: [BolaReminder]
    var sectionTitle: String = "Bola正在关心的事"
    var style: Style = .standard

    @State private var showEditor = false
    @State private var editorMode: IOSReminderEditorSheet.Mode = .create

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(sectionTitle)
                    .font(style == .figmaLife ? .system(size: 17, weight: .semibold) : .headline)
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
                    if style == .figmaLife {
                        HStack(spacing: 5) {
                            LifeAccentChromePlusIcon()
                            Text("添加")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(BolaTheme.onAccentForeground)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(BolaTheme.accent))
                    } else {
                        Label("添加", systemImage: "plus.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(BolaTheme.onAccentForeground)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(BolaTheme.accent))
                    }
                }
            }

            if reminders.isEmpty {
                Text("还没有提醒。点「添加」从模板选一条，或自定义时间。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: style == .figmaLife ? 8 : 12) {
                    ForEach(reminders) { r in
                        reminderRow(r)
                    }
                }
            }
        }
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

    private func reminderRow(_ r: BolaReminder) -> some View {
        HStack(alignment: .top, spacing: style == .figmaLife ? 10 : 14) {
            Image(systemName: (r.kind ?? .custom).systemImageName)
                .font(style == .figmaLife ? .body : .title2)
                .foregroundStyle(BolaTheme.listRowIcon)
                .symbolRenderingMode(.monochrome)
                .frame(width: style == .figmaLife ? 28 : 36)

            VStack(alignment: .leading, spacing: style == .figmaLife ? 2 : 4) {
                Text("Bola · \(r.title)")
                    .font(.subheadline.weight(.semibold))
                Text(r.scheduleSummary())
                    .font(style == .figmaLife ? .caption2 : .caption)
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
        .padding(style == .figmaLife ? EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12) : EdgeInsets(
            top: BolaTheme.spacingItem,
            leading: BolaTheme.spacingItem,
            bottom: BolaTheme.spacingItem,
            trailing: BolaTheme.spacingItem
        ))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: style == .figmaLife ? BolaTheme.cornerLifePageCard : BolaTheme.cornerCard, style: .continuous)
                .fill(style == .figmaLife ? BolaTheme.surfaceBubble : BolaTheme.surfaceCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: style == .figmaLife ? BolaTheme.cornerLifePageCard : BolaTheme.cornerCard, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(style == .figmaLife ? 0.25 : 0.45), lineWidth: 1)
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
