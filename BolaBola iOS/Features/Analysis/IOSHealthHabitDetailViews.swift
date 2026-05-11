//
//  IOSHealthHabitDetailViews.swift
//  健康习惯：各分类详情（圆环 / 近 7 日图表）。
//

import Charts
import SwiftUI

// MARK: - 列表摘要文案（与 model 同步）

enum IOSHealthHabitSnapshot {
    private static func latestSleepValue(_ model: IOSHealthHabitAnalysisModel) -> Double {
        let cal = Calendar.current
        let todayValue = model.sleepHoursWeek.first(where: { cal.isDateInToday($0.date) })?.value ?? 0
        if todayValue > 0.01 {
            return todayValue
        }
        return model.sleepHoursWeek.last(where: { $0.value > 0.01 })?.value ?? 0
    }

    static func intString(from value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "0"
    }

    static func summarySubtitle(_ model: IOSHealthHabitAnalysisModel) -> String {
        let s = todaySteps(model)
        let st = todayStand(model)
        let sl = ringSleep(model)
        let ss = intString(from: s)
        if sl > 0 {
            return "\(ss) 步 · 站立 \(Int(st)) 分 · 睡眠 \(String(format: "%.1f", sl)) 时"
        }
        return "\(ss) 步 · 站立 \(Int(st)) 分"
    }

    static func activitySubtitle(_ model: IOSHealthHabitAnalysisModel) -> String {
        let cal = Calendar.current
        let steps = model.stepsWeek.first(where: { cal.isDateInToday($0.date) })?.value
            ?? model.stepsWeek.last?.value ?? 0
        return "今日 \(intString(from: steps)) 步 · 查看近 7 日趋势"
    }

    static func heartSubtitle(_ model: IOSHealthHabitAnalysisModel) -> String {
        let cal = Calendar.current
        let v = model.heartRateWeek.first(where: { cal.isDateInToday($0.date) })?.value
            ?? model.heartRateWeek.last(where: { $0.value > 0 })?.value
        if let v, v > 0 {
            return "今日平均约 \(Int(v.rounded())) 次/分"
        }
        return "近 7 日按日平均心率"
    }

    static func sleepSubtitle(_ model: IOSHealthHabitAnalysisModel) -> String {
        let value = latestSleepValue(model)
        if value > 0.01 {
            return "昨夜约 \(String(format: "%.1f", value)) 小时（估算）"
        }
        return "近 7 日睡眠时长趋势"
    }

    private static func todaySteps(_ model: IOSHealthHabitAnalysisModel) -> Double {
        let cal = Calendar.current
        return model.stepsWeek.first(where: { cal.isDateInToday($0.date) })?.value
            ?? model.stepsWeek.last?.value ?? 0
    }

    private static func todayStand(_ model: IOSHealthHabitAnalysisModel) -> Double {
        let cal = Calendar.current
        return model.standMinutesWeek.first(where: { cal.isDateInToday($0.date) })?.value
            ?? model.standMinutesWeek.last?.value ?? 0
    }

    private static func ringSleep(_ model: IOSHealthHabitAnalysisModel) -> Double {
        latestSleepValue(model)
    }

    // MARK: - 分析页网格卡片可视化（0…1 进度等）

    static func todayStepsValue(_ model: IOSHealthHabitAnalysisModel) -> Double {
        let cal = Calendar.current
        return model.stepsWeek.first(where: { cal.isDateInToday($0.date) })?.value
            ?? model.stepsWeek.last?.value ?? 0
    }

    static func todayMoveEnergyValue(_ model: IOSHealthHabitAnalysisModel) -> Double {
        let cal = Calendar.current
        return model.activeEnergyWeek.first(where: { cal.isDateInToday($0.date) })?.value
            ?? model.activeEnergyWeek.last?.value ?? 0
    }

    static func todayExerciseMinutesValue(_ model: IOSHealthHabitAnalysisModel) -> Double {
        let cal = Calendar.current
        return model.exerciseMinutesWeek.first(where: { cal.isDateInToday($0.date) })?.value
            ?? model.exerciseMinutesWeek.last?.value ?? 0
    }

    static func todayStandMinutesValue(_ model: IOSHealthHabitAnalysisModel) -> Double {
        let cal = Calendar.current
        return model.standMinutesWeek.first(where: { cal.isDateInToday($0.date) })?.value
            ?? model.standMinutesWeek.last?.value ?? 0
    }

    static func todaySleepHoursValue(_ model: IOSHealthHabitAnalysisModel) -> Double {
        latestSleepValue(model)
    }

    static func todayHeartRateValue(_ model: IOSHealthHabitAnalysisModel) -> Double? {
        let cal = Calendar.current
        let v = model.heartRateWeek.first(where: { cal.isDateInToday($0.date) })?.value
            ?? model.heartRateWeek.last(where: { $0.value > 0 })?.value
        guard let v, v > 0 else { return nil }
        return v
    }

    static func stepsGoalProgress(_ model: IOSHealthHabitAnalysisModel) -> Double {
        min(1, max(0, todayStepsValue(model) / IOSHealthRingGoals.stepsPerDay))
    }

    static func moveGoalProgress(_ model: IOSHealthHabitAnalysisModel) -> Double {
        min(1, max(0, todayMoveEnergyValue(model) / IOSHealthRingGoals.moveKilocaloriesPerDay))
    }

    static func exerciseGoalProgress(_ model: IOSHealthHabitAnalysisModel) -> Double {
        min(1, max(0, todayExerciseMinutesValue(model) / IOSHealthRingGoals.exerciseMinutesPerDay))
    }

    static func standGoalProgress(_ model: IOSHealthHabitAnalysisModel) -> Double {
        min(1, max(0, todayStandMinutesValue(model) / IOSHealthRingGoals.standMinutesPerDay))
    }

    static func sleepGoalProgress(_ model: IOSHealthHabitAnalysisModel) -> Double {
        min(1, max(0, todaySleepHoursValue(model) / IOSHealthRingGoals.sleepHoursTarget))
    }

    /// 三项进度的简单平均，用作「今日摘要」中心百分比（仅展示用）。
    static func combinedScoreProgress(_ model: IOSHealthHabitAnalysisModel) -> Double {
        let a = stepsGoalProgress(model)
        let b = standGoalProgress(model)
        let c = sleepGoalProgress(model)
        return min(1, max(0, (a + b + c) / 3))
    }

    static func weekStepValuesForBars(_ model: IOSHealthHabitAnalysisModel) -> [Double] {
        model.stepsWeek.map(\.value)
    }

    static func weekHeartValuesForSparkline(_ model: IOSHealthHabitAnalysisModel) -> [Double] {
        model.heartRateWeek.map(\.value)
    }
}

// MARK: - 图表刻度

enum IOSHealthChartScales {
    static let chartHeight: CGFloat = 168
    static let chartCardVerticalPadding: CGFloat = 16
    static let chartCardHorizontalPadding: CGFloat = 16

    static func yPositive(_ values: [IOSHealthKitWeekQueries.DayValue]) -> ClosedRange<Double> {
        let m = values.map(\.value).max() ?? 0
        return 0...(m > 0 ? max(m * 1.12, m + 1) : 1)
    }

    static func yHeart(_ values: [IOSHealthKitWeekQueries.DayValue]) -> ClosedRange<Double> {
        let m = values.map(\.value).max() ?? 0
        if m <= 0 { return 0...120 }
        return 0...max(120, m * 1.12)
    }

    static func ySleep(_ values: [IOSHealthKitWeekQueries.DayValue]) -> ClosedRange<Double> {
        let m = values.map(\.value).max() ?? 0
        return 0...(m > 0 ? max(m * 1.15, m + 0.5) : 8)
    }
}

// MARK: - 图表范围

enum IOSHealthChartRange: String, CaseIterable, Identifiable {
    case week = "Week"
    case month = "Month"
    case year = "Year"

    var id: String { rawValue }
}

// MARK: - 轴样式（ViewModifier，避免自定义 AxisContent 兼容性）

private struct IOSHealthChartWeekdayXModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.chartXAxis {
            AxisMarks(values: .stride(by: .day)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.primary.opacity(0.07))
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date, format: .dateTime.weekday(.narrow))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct IOSHealthChartIntYModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.primary.opacity(0.07))
                AxisValueLabel {
                    if let n = value.as(Double.self) {
                        Text("\(Int(n))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct IOSHealthChartFloatYModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.primary.opacity(0.07))
                AxisValueLabel {
                    if let n = value.as(Double.self) {
                        Text(String(format: "%.1f", n))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - 图表卡片

private struct IOSHealthChartCard<Content: View>: View {
    let title: String
    let assetName: String
    let tint: Color
    let imageOpacity: Double
    let imageAlignment: Alignment
    let imageWidth: CGFloat
    let chartHeight: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(BolaTheme.accent)
                    .frame(width: 6, height: 18)

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }

            ZStack(alignment: imageAlignment) {
                RoundedRectangle(cornerRadius: BolaTheme.cornerCompact, style: .continuous)
                    .fill(Color.primary.opacity(0.025))

                Image(assetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: imageWidth)
                    .opacity(imageOpacity)
                    .padding(.trailing, 8)
                    .padding(.bottom, 4)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                content()
                    .chartPlotStyle { plotArea in
                        plotArea
                            .background(.clear)
                    }
                    .padding(8)
                    .frame(height: chartHeight)
            }
            .overlay(alignment: .topTrailing) {
                Capsule()
                    .fill(tint.opacity(0.14))
                    .frame(width: 46, height: 6)
                    .padding(.top, 10)
                    .padding(.trailing, 12)
            }
            .clipShape(RoundedRectangle(cornerRadius: BolaTheme.cornerCompact, style: .continuous))
        }
        .padding(.horizontal, IOSHealthChartScales.chartCardHorizontalPadding)
        .padding(.vertical, IOSHealthChartScales.chartCardVerticalPadding)
        .background(chartBackground)
        .overlay {
            RoundedRectangle(cornerRadius: BolaTheme.cornerCard, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.4), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 3)
    }

    private var chartBackground: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: BolaTheme.cornerCard, style: .continuous)
                .fill(BolaTheme.surfaceCard)

            RoundedRectangle(cornerRadius: BolaTheme.cornerCard, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            BolaTheme.accent.opacity(0.10),
                            tint.opacity(0.045),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }
}

private struct IOSHealthChartRangePicker: View {
    @Binding var selection: IOSHealthChartRange

    var body: some View {
        HStack(spacing: 4) {
            ForEach(IOSHealthChartRange.allCases) { range in
                Button {
                    withAnimation(.snappy(duration: 0.18)) {
                        selection = range
                    }
                } label: {
                    Text(range.rawValue)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.black.opacity(range == selection ? 0.9 : 0.62))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .background {
                    if range == selection {
                        Capsule()
                            .fill(BolaTheme.accent.opacity(0.92))
                    }
                }
            }
        }
        .padding(4)
        .background {
            Capsule()
                .fill(BolaTheme.surfaceElevated)
        }
        .overlay {
            Capsule()
                .stroke(Color(uiColor: .separator).opacity(0.35), lineWidth: 0.5)
        }
    }
}

private extension View {
    func iosHealthWeekdayXAxis() -> some View {
        modifier(IOSHealthChartWeekdayXModifier())
    }

    func iosHealthIntYAxis() -> some View {
        modifier(IOSHealthChartIntYModifier())
    }

    func iosHealthFloatYAxis() -> some View {
        modifier(IOSHealthChartFloatYModifier())
    }
}

// MARK: - 今日摘要（圆环）

struct IOSHealthSummaryDetailView: View {
    @ObservedObject var model: IOSHealthHabitAnalysisModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let err = model.fetchError, !err.isEmpty {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
                if !model.hasAnyChartData {
                    Text("暂无读数时圆环可能为空，请检查健康权限与数据源。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ringsBlock

                Text("圆环为今日相对内置目标的完成度（Move 400 kcal、Exercise 30 分、Stand 180 分），仅作习惯参考，非医疗指标。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(BolaTheme.paddingHorizontal)
            .padding(.vertical, 12)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("今日摘要")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var ringsBlock: some View {
        HStack(alignment: .center, spacing: 18) {
            IOSHealthTodayRingsBlock(
                moveProgress: ringProgressMove,
                exerciseProgress: ringProgressExercise,
                standProgress: ringProgressStand
            )
            .animation(.easeOut(duration: 0.5), value: ringProgressMove)

            VStack(alignment: .leading, spacing: 8) {
                Text("今日数据")
                    .font(.subheadline.weight(.semibold))
                ringRow("Move", IOSHealthHabitSnapshot.intString(from: todayMove), "kcal", "\(Int(IOSHealthRingGoals.moveKilocaloriesPerDay)) kcal")
                ringRow("Exercise", "\(Int(todayExercise))", "分钟", "\(Int(IOSHealthRingGoals.exerciseMinutesPerDay)) 分")
                ringRow("站立", "\(Int(todayStand))", "分钟", "\(Int(IOSHealthRingGoals.standMinutesPerDay)) 分")
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private func ringRow(_ title: String, _ value: String, _ unit: String, _ goal: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.caption2).foregroundStyle(.tertiary)
                Spacer(minLength: 8)
                Text("目标 \(goal)").font(.caption2).foregroundStyle(.secondary.opacity(0.65))
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 21, weight: .semibold))
                    .monospacedDigit()
                if !unit.isEmpty, value != "—" {
                    Text(unit).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var todayMove: Double {
        IOSHealthHabitSnapshot.todayMoveEnergyValue(model)
    }

    private var todayExercise: Double {
        IOSHealthHabitSnapshot.todayExerciseMinutesValue(model)
    }

    private var todayStand: Double {
        let cal = Calendar.current
        return model.standMinutesWeek.first(where: { cal.isDateInToday($0.date) })?.value
            ?? model.standMinutesWeek.last?.value ?? 0
    }

    private var ringProgressMove: Double {
        min(1, todayMove / IOSHealthRingGoals.moveKilocaloriesPerDay)
    }

    private var ringProgressExercise: Double {
        min(1, todayExercise / IOSHealthRingGoals.exerciseMinutesPerDay)
    }

    private var ringProgressStand: Double {
        min(1, todayStand / IOSHealthRingGoals.standMinutesPerDay)
    }
}

// MARK: - 活动与站立

struct IOSHealthActivityDetailView: View {
    @ObservedObject var model: IOSHealthHabitAnalysisModel
    @State private var selectedRange: IOSHealthChartRange = .week

    var body: some View {
        ZStack {
            BolaLifeAmbientBackground()
                .ignoresSafeArea(edges: [.top, .bottom])

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    IOSHealthChartRangePicker(selection: $selectedRange)

                    IOSHealthChartCard(
                        title: "步数",
                        assetName: "BolaRunning",
                        tint: Color(red: 0.92, green: 0.45, blue: 0.22),
                        imageOpacity: 0.18,
                        imageAlignment: .bottomTrailing,
                        imageWidth: 104,
                        chartHeight: IOSHealthChartScales.chartHeight
                    ) {
                        Chart(stepsValues) { item in
                            BarMark(
                                x: .value("日", item.date, unit: .day),
                                y: .value("步", item.value)
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.92, green: 0.45, blue: 0.22).opacity(0.88),
                                        BolaTheme.accent.opacity(0.42)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .cornerRadius(8)
                        }
                        .iosHealthWeekdayXAxis()
                        .iosHealthIntYAxis()
                        .chartYScale(domain: IOSHealthChartScales.yPositive(stepsValues))
                        .id(selectedRange)
                    }

                    IOSHealthChartCard(
                        title: "站立（分钟 · 多来自 Apple Watch）",
                        assetName: "BolaRunning",
                        tint: Color.green,
                        imageOpacity: 0.16,
                        imageAlignment: .trailing,
                        imageWidth: 98,
                        chartHeight: IOSHealthChartScales.chartHeight
                    ) {
                        Chart(standValues) { item in
                            BarMark(
                                x: .value("日", item.date, unit: .day),
                                y: .value("分钟", item.value)
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [
                                        Color.green.opacity(0.62),
                                        BolaTheme.accent.opacity(0.34)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .cornerRadius(8)
                        }
                        .iosHealthWeekdayXAxis()
                        .iosHealthIntYAxis()
                        .chartYScale(domain: IOSHealthChartScales.yPositive(standValues))
                        .id(selectedRange)
                    }

                    Text("若未佩戴手表，站立可能长期为 0。")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(BolaTheme.paddingHorizontal)
                .padding(.vertical, 12)
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("活动与站立")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var stepsValues: [IOSHealthKitWeekQueries.DayValue] {
        switch selectedRange {
        case .week:
            return model.stepsWeek
        case .month, .year:
            // TODO: 接入 HealthKit 月 / 年聚合后替换为对应粒度数据；当前保留近 7 日安全回退。
            return model.stepsWeek
        }
    }

    private var standValues: [IOSHealthKitWeekQueries.DayValue] {
        switch selectedRange {
        case .week:
            return model.standMinutesWeek
        case .month, .year:
            // TODO: 接入 HealthKit 月 / 年聚合后替换为对应粒度数据；当前保留近 7 日安全回退。
            return model.standMinutesWeek
        }
    }
}

// MARK: - 心率

struct IOSHealthHeartDetailView: View {
    @ObservedObject var model: IOSHealthHabitAnalysisModel

    var body: some View {
        ScrollView {
            Chart(model.heartRateWeek) { item in
                AreaMark(
                    x: .value("日", item.date, unit: .day),
                    y: .value("BPM", item.value)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.pink.opacity(0.28), Color.pink.opacity(0.06)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)
                LineMark(
                    x: .value("日", item.date, unit: .day),
                    y: .value("BPM", item.value)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.pink, Color.red.opacity(0.75)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.catmullRom)
            }
            .iosHealthWeekdayXAxis()
            .iosHealthIntYAxis()
            .chartYScale(domain: IOSHealthChartScales.yHeart(model.heartRateWeek))
            .frame(height: IOSHealthChartScales.chartHeight + 24)
            .padding(BolaTheme.paddingHorizontal)
            .padding(.top, 12)

            Text("按日平均心率（次/分），无采样日显示为 0。非医疗用途。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, BolaTheme.paddingHorizontal)
                .padding(.bottom, 24)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("心率")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 睡眠

struct IOSHealthSleepDetailView: View {
    @ObservedObject var model: IOSHealthHabitAnalysisModel
    @State private var selectedRange: IOSHealthChartRange = .week

    var body: some View {
        ZStack {
            BolaLifeAmbientBackground()
                .ignoresSafeArea(edges: [.top, .bottom])

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    IOSHealthChartRangePicker(selection: $selectedRange)

                    IOSHealthChartCard(
                        title: "近 7 日睡眠",
                        assetName: "BolaSleeping",
                        tint: Color(red: 0.42, green: 0.48, blue: 0.82),
                        imageOpacity: 0.18,
                        imageAlignment: .bottomTrailing,
                        imageWidth: 112,
                        chartHeight: IOSHealthChartScales.chartHeight + 24
                    ) {
                        Chart(sleepValues) { item in
                            BarMark(
                                x: .value("日", item.date, unit: .day),
                                y: .value("小时", item.value)
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.42, green: 0.48, blue: 0.82).opacity(0.78),
                                        Color(red: 0.62, green: 0.56, blue: 0.86).opacity(0.38)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .cornerRadius(8)
                        }
                        .iosHealthWeekdayXAxis()
                        .iosHealthFloatYAxis()
                        .chartYScale(domain: IOSHealthChartScales.ySleep(sleepValues))
                        .id(selectedRange)
                    }

                    Text("估算睡眠时长来自「睡眠」分析；仅供参考，不能替代医疗建议。")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.bottom, 24)
                }
                .padding(BolaTheme.paddingHorizontal)
                .padding(.top, 12)
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("睡眠节奏")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var sleepValues: [IOSHealthKitWeekQueries.DayValue] {
        switch selectedRange {
        case .week:
            return model.sleepHoursWeek
        case .month, .year:
            // TODO: 接入 HealthKit 月 / 年聚合后替换为对应粒度数据；当前保留近 7 日安全回退。
            return model.sleepHoursWeek
        }
    }
}
