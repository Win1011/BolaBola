//
//  IOSRemindersSectionView.swift
//  提醒列表（生活页「Bola正在关心的事」与分析页等复用）。
//

import SwiftUI

struct IOSRemindersSectionView: View {
    private struct EditorSheetState: Identifiable {
        let id = UUID()
        let mode: IOSReminderEditorSheet.Mode
    }

    private struct MealEditorSheetState: Identifiable {
        let id = UUID()
        let mealSlot: MealSlot?
    }

    enum Style {
        case standard
        /// Figma 生活页：白卡圆角 20、小粒「+添加」
        case figmaLife
        /// 仪表板横向紧凑版：用于可编辑 dashboard 中的提醒摘要卡
        case dashboardCompact
    }

    @Binding var reminders: [BolaReminder]
    @State private var mealSlots: [MealSlot] = MealSlotStore.load()
    var sectionTitle: String = "Bola正在关心的事"
    /// 宠物显示名（生活页标题第一行）；默认读 `CompanionDisplayNameStore`。
    var companionDisplayName: String = CompanionDisplayNameStore.resolved()
    var style: Style = .standard

    @State private var activeEditor: EditorSheetState?
    @State private var activeMealEditor: MealEditorSheetState?

    private var figmaRowHeight: CGFloat { 36 }
    private var figmaRowSpacing: CGFloat { 7 }
    private var figmaInnerCardCorner: CGFloat { 10 }

    var body: some View {
        content
            .sheet(item: $activeEditor) { sheet in
                IOSReminderEditorSheet(
                    mode: sheet.mode,
                    onSave: { saved in
                        switch sheet.mode {
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
                        if case .edit(let original) = sheet.mode {
                            reminders.removeAll { $0.id == original.id }
                            persistReminders()
                        }
                    }
                )
            }
            .sheet(item: $activeMealEditor) { sheet in
                IOSMealSlotEditorSheet(
                    mealSlot: sheet.mealSlot,
                    onSave: { slot in
                        if let idx = mealSlots.firstIndex(where: { $0.id == slot.id }) {
                            mealSlots[idx] = slot
                        }
                        persistMealSlots()
                    },
                    onDelete: {
                        if let slot = sheet.mealSlot {
                            mealSlots.removeAll { $0.id == slot.id }
                            persistMealSlots()
                        }
                    }
                )
            }
    }

    @ViewBuilder
    private var content: some View {
        if style == .figmaLife {
            figmaLifeCardBody
        } else if style == .dashboardCompact {
            dashboardCompactCardBody
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
                                activeEditor = EditorSheetState(mode: .create)
                            }
                            Button("+添加餐食") {
                                addNewMealSlot()
                            }
                            Section("模板") {
                                ForEach(ReminderTemplateLibrary.all) { t in
                                    Button(t.title) {
                                        activeEditor = EditorSheetState(mode: .createFromTemplate(t))
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

                    if reminders.isEmpty && mealSlots.isEmpty {
                        Text("还没有提醒。点「添加」从模板选一条，或自定义时间。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                        Spacer(minLength: 0)
                    } else {
                        ScrollView(.vertical, showsIndicators: true) {
                            LazyVStack(spacing: figmaRowSpacing) {
                                ForEach(mealSlots) { slot in
                                    mealSlotRow(slot)
                                }
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
                        activeEditor = EditorSheetState(mode: .create)
                    }
                    Section("模板") {
                        ForEach(ReminderTemplateLibrary.all) { t in
                            Button(t.title) {
                                activeEditor = EditorSheetState(mode: .createFromTemplate(t))
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

    private var dashboardCompactCardBody: some View {
        let primaryReminder = reminders.first

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Label("提醒", systemImage: "bell.badge.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(reminders.count) 条")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if let reminder = primaryReminder {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: (reminder.kind ?? .custom).systemImageName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(BolaTheme.listRowIcon)
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(reminder.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(reminder.scheduleSummary())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    if reminders.count > 1 {
                        Text("+\(reminders.count - 1)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color(uiColor: .secondarySystemBackground)))
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    activeEditor = EditorSheetState(mode: .edit(reminder))
                }
            } else {
                Button {
                    activeEditor = EditorSheetState(mode: .create)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(BolaTheme.accent)
                        Text("添加第一条提醒")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: BolaTheme.cornerLifePageCard, style: .continuous)
                .fill(BolaTheme.surfaceBubble)
        )
        .overlay(
            RoundedRectangle(cornerRadius: BolaTheme.cornerLifePageCard, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.25), lineWidth: 1)
        )
    }

    private func rowTitleLine(for r: BolaReminder) -> String {
        let rawTitle = r.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let escapedName = NSRegularExpression.escapedPattern(for: companionDisplayName)
        let prefixPattern = "^\(escapedName)\\s*·\\s*"
        let normalizedTitle: String
        if let regex = try? NSRegularExpression(pattern: prefixPattern) {
            let full = NSRange(rawTitle.startIndex..<rawTitle.endIndex, in: rawTitle)
            normalizedTitle = regex.stringByReplacingMatches(in: rawTitle, options: [], range: full, withTemplate: "")
        } else {
            normalizedTitle = rawTitle
        }
        return "\(companionDisplayName) · \(normalizedTitle)"
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
            activeEditor = EditorSheetState(mode: .edit(r))
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
        Task {
            await BolaReminderUNScheduler.sync(reminders: reminders)
            BolaWCSessionCoordinator.shared.pushReminderRefreshToWatchIfPossible()
        }
    }

    private func persistMealSlots() {
        MealSlotStore.save(mealSlots)
        BolaWCSessionCoordinator.shared.pushMealSlotsToWatchIfPossible()
        BolaDebugLog.shared.log(.meal, "iPhone meal slots saved & pushed count=\(mealSlots.count)")
    }

    private func addNewMealSlot() {
        let nextNum = (mealSlots.compactMap { Int($0.id.replacingOccurrences(of: "meal", with: "")) }.max() ?? 0) + 1
        let newSlot = MealSlot(id: "meal\(nextNum)", hour: 12, minute: 0)
        activeMealEditor = MealEditorSheetState(mealSlot: newSlot)
    }

    @ViewBuilder
    private func mealSlotRow(_ slot: MealSlot) -> some View {
        HStack(alignment: style == .figmaLife ? .center : .top, spacing: style == .figmaLife ? 8 : 14) {
            Image(systemName: "fork.knife")
                .font(style == .figmaLife ? .system(size: 12, weight: .semibold) : .title2)
                .foregroundStyle(Color.orange)
                .symbolRenderingMode(.monochrome)
                .frame(width: style == .figmaLife ? 14 : 36)

            VStack(alignment: .leading, spacing: style == .figmaLife ? 2 : 4) {
                Text("\(companionDisplayName) · 餐食")
                    .font(style == .figmaLife ? .system(size: 12, weight: .semibold) : .subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("每天 \(slot.timeString)")
                    .font(style == .figmaLife ? .system(size: 10, weight: .regular) : .caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if style == .figmaLife {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
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
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            activeMealEditor = MealEditorSheetState(mealSlot: slot)
        }
        .contextMenu {
            Button(role: .destructive) {
                mealSlots.removeAll { $0.id == slot.id }
                persistMealSlots()
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }
}

struct IOSMealSlotEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let mealSlot: MealSlot?
    let onSave: (MealSlot) -> Void
    var onDelete: (() -> Void)?

    @State private var hour: Int
    @State private var minute: Int
    @State private var isExistingSlot: Bool

    init(mealSlot: MealSlot?, onSave: @escaping (MealSlot) -> Void, onDelete: (() -> Void)? = nil) {
        self.mealSlot = mealSlot
        self.onSave = onSave
        self.onDelete = onDelete
        _hour = State(initialValue: mealSlot?.hour ?? 12)
        _minute = State(initialValue: mealSlot?.minute ?? 0)
        _isExistingSlot = State(initialValue: mealSlot != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("时间") {
                    DatePicker(
                        "餐食时间",
                        selection: Binding(
                            get: {
                                let cal = Calendar.current
                                let today = cal.startOfDay(for: Date())
                                return cal.date(bySettingHour: hour, minute: minute, second: 0, of: today) ?? Date()
                            },
                            set: { date in
                                hour = Calendar.current.component(.hour, from: date)
                                minute = Calendar.current.component(.minute, from: date)
                            }
                        ),
                        displayedComponents: [.hourAndMinute]
                    )
                    .datePickerStyle(.wheel)
                }

                if isExistingSlot, onDelete != nil {
                    Section {
                        Button(role: .destructive) {
                            onDelete?()
                            dismiss()
                        } label: {
                            Text("删除此餐食")
                        }
                    }
                }
            }
            .navigationTitle(isExistingSlot ? "编辑餐食" : "添加餐食")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let id = mealSlot?.id ?? "meal\(Date().timeIntervalSince1970)"
                        onSave(MealSlot(id: id, hour: hour, minute: minute))
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
