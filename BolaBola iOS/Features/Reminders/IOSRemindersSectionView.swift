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
    /// 宠物显示名（生活页标题第一行）；默认读 `CompanionDisplayNameStore`。
    var companionDisplayName: String = CompanionDisplayNameStore.resolved()
    var style: Style = .standard

    @State private var showEditor = false
    @State private var editorMode: IOSReminderEditorSheet.Mode = .create

    private var figmaRowHeight: CGFloat { 36 }
    private var figmaRowSpacing: CGFloat { 7 }
    private var figmaInnerCardCorner: CGFloat { 10 }

    var body: some View {
        content
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

    @ViewBuilder
    private var content: some View {
        if style == .figmaLife {
            figmaLifeCardBody
        } else {
            standardCardBody
        }
    }

    /// 生活页：白底铺满父级高度，与右侧健康卡列底端对齐。
    /// 使用 GeometryReader 锁定与父视图完全相同的宽高，避免白底比外层「短一截」。
    private var figmaLifeCardBody: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: BolaTheme.cornerLifePageCard, style: .continuous)
                    .fill(BolaTheme.surfaceBubble)
                RoundedRectangle(cornerRadius: BolaTheme.cornerLifePageCard, style: .continuous)
                    .stroke(Color(uiColor: .separator).opacity(0.25), lineWidth: 1)
                    .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(companionDisplayName)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.primary)
                            Text("正在关心的事")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.primary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
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
                            ZStack {
                                Circle()
                                    .fill(BolaTheme.accent)
                                    .frame(width: 30, height: 30)
                                LifeAccentChromePlusIcon()
                                    .scaleEffect(0.92)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("添加提醒")
                    }

                    if reminders.isEmpty {
                        Text("还没有提醒。点「添加」从模板选一条，或自定义时间。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                        Spacer(minLength: 0)
                    } else {
                        ScrollView(.vertical, showsIndicators: true) {
                            LazyVStack(spacing: figmaRowSpacing) {
                                ForEach(reminders) { r in
                                    reminderRow(r)
                                }
                            }
                        }
                        .frame(maxHeight: .infinity, alignment: .top)
                    }
                }
                .padding(12)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var standardCardBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(sectionTitle)
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

    private func rowTitleLine(for r: BolaReminder) -> String {
        "\(companionDisplayName) · \(r.title)"
    }

    private func reminderRow(_ r: BolaReminder) -> some View {
        HStack(alignment: style == .figmaLife ? .center : .top, spacing: style == .figmaLife ? 8 : 14) {
            Image(systemName: (r.kind ?? .custom).systemImageName)
                .font(style == .figmaLife ? .system(size: 12, weight: .semibold) : .title2)
                .foregroundStyle(BolaTheme.listRowIcon)
                .symbolRenderingMode(.monochrome)
                .frame(width: style == .figmaLife ? 14 : 36)

            VStack(alignment: .leading, spacing: style == .figmaLife ? 2 : 4) {
                Text(rowTitleLine(for: r))
                    .font(style == .figmaLife ? .system(size: 12, weight: .semibold) : .subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(r.scheduleSummary())
                    .font(style == .figmaLife ? .system(size: 10, weight: .regular) : .caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if style != .figmaLife {
                    Text(r.notificationBody)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            if style == .figmaLife {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            } else {
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
        }
        .padding(style == .figmaLife ? EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8) : EdgeInsets(
            top: BolaTheme.spacingItem,
            leading: BolaTheme.spacingItem,
            bottom: BolaTheme.spacingItem,
            trailing: BolaTheme.spacingItem
        ))
        .frame(height: style == .figmaLife ? figmaRowHeight : nil)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: style == .figmaLife ? figmaInnerCardCorner : BolaTheme.cornerCard, style: .continuous)
                .fill(style == .figmaLife ? Color(uiColor: .secondarySystemBackground) : BolaTheme.surfaceCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: style == .figmaLife ? figmaInnerCardCorner : BolaTheme.cornerCard, style: .continuous)
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
