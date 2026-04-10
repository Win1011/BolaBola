//
//  IOSLifeTimePageView.swift
//  时光：Bola 口吻的本地日记时间线。
//

import SwiftUI

extension Notification.Name {
    static let bolaDiaryOpenCalendarRequested = Notification.Name("bolaDiaryOpenCalendarRequested")
}

struct IOSLifeTimePageView: View {
    var bubbleMode: Bool
    /// 嵌入生活 Tab 时底层由 `lifePageBackground` 提供，此处勿再铺不透明灰底。
    var useLifePageBackdrop: Bool = false

    @State private var diaryEntries: [BolaDiaryEntry] = BolaDiaryStore.load()
    @State private var showDiaryCalendar = false
    @State private var selectedDiaryDate = Date()
    @State private var activeDayFilter: Date?

    private var groupedRecords: [(title: String, records: [BolaDiaryEntry])] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEEE"

        let filteredEntries = diaryEntries
            .filter { entry in
                guard let activeDayFilter else { return true }
                return Calendar.current.isDate(entry.createdAt, inSameDayAs: activeDayFilter)
            }
            .sorted { $0.createdAt > $1.createdAt }

        let grouped = Dictionary(grouping: filteredEntries) { entry in
            Calendar.current.startOfDay(for: entry.createdAt)
        }

        return grouped.keys
            .sorted(by: >)
            .map { day in
                (formatter.string(from: day), grouped[day]?.sorted { $0.createdAt > $1.createdAt } ?? [])
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("波拉日记")
                    .font(.headline)
                Spacer()
                if activeDayFilter != nil {
                    Button("显示全部") {
                        activeDayFilter = nil
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                    .tint(.secondary)
                }
            }

            if groupedRecords.isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(groupedRecords, id: \.title) { section in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(section.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ForEach(section.records) { record in
                                row(record)
                            }
                        }
                    }
                }
            }
        }
        .padding(.top, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(useLifePageBackdrop ? Color.clear : BolaTheme.backgroundGrouped)
        .onAppear {
            reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .bolaDiaryEntriesDidChange)) { _ in
            reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .bolaDiaryOpenCalendarRequested)) { _ in
            selectedDiaryDate = activeDayFilter ?? diaryEntries.first?.createdAt ?? Date()
            showDiaryCalendar = true
        }
        .sheet(isPresented: $showDiaryCalendar) {
            DiaryCalendarSheet(
                selectedDate: $selectedDiaryDate,
                entries: diaryEntries,
                onComplete: { date in
                    activeDayFilter = date
                    showDiaryCalendar = false
                }
            )
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("还没有时光记录")
                .font(.subheadline.weight(.semibold))
            Text(activeDayFilter == nil ? "和 Bola 聊聊今天发生了什么，它会把适合留下来的片段自动整理成日记。生活记录请在生活页添加。" : "这一天还没有波拉日记。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private func row(_ entry: BolaDiaryEntry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 4) {
                Text(Self.timeFormatter.string(from: entry.createdAt))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Capsule()
                    .fill(Color(uiColor: .separator).opacity(0.55))
                    .frame(width: 3, height: 36)
            }
            .frame(width: 52)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(entry.emoji)
                    Text("Bola 日记")
                        .font(.subheadline.weight(.semibold))
                }
                Text(entry.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(BolaTheme.spacingItem)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: BolaTheme.cornerLifePageCard, style: .continuous)
                    .fill(BolaTheme.surfaceElevated)
                    .shadow(
                        color: Color.black.opacity(BolaTheme.cardShadowOpacity(bubbleMode: bubbleMode)),
                        radius: bubbleMode ? 12 : 6,
                        y: 3
                    )
            )
        }
    }

    private func reload() {
        diaryEntries = BolaDiaryStore.load()
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

private struct DiaryCalendarSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedDate: Date

    let entries: [BolaDiaryEntry]
    let onComplete: (Date) -> Void

    @State private var visibleMonth = Calendar.current.startOfDay(for: Date())

    private let weekdaySymbols = ["日", "一", "二", "三", "四", "五", "六"]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                monthHeader
                weekdayHeader
                calendarGrid
                Text(selectedDateHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(18)
            .background(BolaTheme.backgroundGrouped)
            .navigationTitle("波拉日记日历")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        onComplete(selectedDate)
                    }
                }
            }
            .onAppear {
                visibleMonth = monthStart(for: selectedDate)
            }
        }
    }

    private var monthHeader: some View {
        HStack {
            Button {
                moveMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)

            Spacer()

            Text(monthTitle(for: visibleMonth))
                .font(.headline.weight(.bold))

            Spacer()

            Button {
                moveMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }

    private var weekdayHeader: some View {
        LazyVGrid(columns: calendarColumns, spacing: 8) {
            ForEach(weekdaySymbols, id: \.self) { day in
                Text(day)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var calendarGrid: some View {
        LazyVGrid(columns: calendarColumns, spacing: 12) {
            ForEach(Array(monthCells.enumerated()), id: \.offset) { _, date in
                if let date {
                    dayButton(for: date)
                } else {
                    Color.clear
                        .frame(height: 38)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }

    private func dayButton(for date: Date) -> some View {
        let hasEntry = hasDiary(on: date)
        let isSelected = Calendar.current.isDate(date, inSameDayAs: selectedDate)

        return Button {
            selectedDate = date
        } label: {
            Text("\(Calendar.current.component(.day, from: date))")
                .font(.subheadline.weight(hasEntry ? .bold : .medium))
                .foregroundStyle(hasEntry ? Color.black : Color.primary.opacity(0.72))
                .frame(width: 38, height: 38)
                .background(
                    Circle()
                        .fill(hasEntry ? BolaTheme.accent : Color.clear)
                )
                .overlay(
                    Circle()
                        .stroke(isSelected ? Color.black.opacity(0.72) : Color.clear, lineWidth: 1.4)
                )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    private var selectedDateHint: String {
        hasDiary(on: selectedDate)
            ? "这一天有波拉日记，点完成查看。"
            : "有日记的日期会显示主题色圆形。"
    }

    private var calendarColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)
    }

    private var monthCells: [Date?] {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: visibleMonth),
              let days = calendar.range(of: .day, in: .month, for: visibleMonth) else {
            return []
        }
        let firstWeekday = calendar.component(.weekday, from: interval.start)
        let leadingEmptyCount = max(0, firstWeekday - 1)
        let dates = days.compactMap { day -> Date? in
            calendar.date(byAdding: .day, value: day - 1, to: interval.start)
        }
        return Array(repeating: nil, count: leadingEmptyCount) + dates
    }

    private func hasDiary(on date: Date) -> Bool {
        entries.contains { Calendar.current.isDate($0.createdAt, inSameDayAs: date) }
    }

    private func moveMonth(by value: Int) {
        guard let next = Calendar.current.date(byAdding: .month, value: value, to: visibleMonth) else { return }
        visibleMonth = monthStart(for: next)
    }

    private func monthStart(for date: Date) -> Date {
        Calendar.current.dateInterval(of: .month, for: date)?.start ?? date
    }

    private func monthTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年 M月"
        return formatter.string(from: date)
    }
}
