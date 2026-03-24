//
//  IOSHealthHabitDetailViews.swift
//  健康习惯：各分类详情（圆环 / 近 7 日图表）。
//

import Charts
import SwiftUI

// MARK: - 列表摘要文案（与 model 同步）

enum IOSHealthHabitSnapshot {
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
        let cal = Calendar.current
        let v = model.sleepHoursWeek.first(where: { cal.isDateInToday($0.date) })?.value
            ?? model.sleepHoursWeek.last(where: { $0.value > 0 })?.value
        if let v, v > 0 {
            return "昨夜约 \(String(format: "%.1f", v)) 小时（估算）"
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
        let cal = Calendar.current
        return model.sleepHoursWeek.first(where: { cal.isDateInToday($0.date) })?.value
            ?? model.sleepHoursWeek.last(where: { $0.value > 0 })?.value ?? 0
    }
}

// MARK: - 图表刻度

enum IOSHealthChartScales {
    static let chartHeight: CGFloat = 168

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

// MARK: - 轴样式（ViewModifier，避免自定义 AxisContent 兼容性）

private struct IOSHealthChartWeekdayXModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(.secondary.opacity(0.25))
                AxisValueLabel(format: .dateTime.weekday(.narrow))
            }
        }
    }
}

private struct IOSHealthChartIntYModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(.secondary.opacity(0.2))
                AxisValueLabel {
                    if let n = value.as(Double.self) {
                        Text("\(Int(n))")
                            .font(.caption2)
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
                    .foregroundStyle(.secondary.opacity(0.2))
                AxisValueLabel {
                    if let n = value.as(Double.self) {
                        Text(String(format: "%.1f", n))
                            .font(.caption2)
                    }
                }
            }
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

                Text("圆环为今日相对内置目标的完成度（步数 1 万、站立 180 分、睡眠 8 小时），仅作习惯参考，非医疗指标。")
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
                stepsProgress: ringProgressSteps,
                standProgress: ringProgressStand,
                sleepProgress: ringProgressSleep
            )
            .animation(.easeOut(duration: 0.5), value: ringProgressSteps)

            VStack(alignment: .leading, spacing: 8) {
                Text("今日数据")
                    .font(.subheadline.weight(.semibold))
                ringRow("步数", IOSHealthHabitSnapshot.intString(from: todaySteps), "步", "\(Int(IOSHealthRingGoals.stepsPerDay)) 步")
                ringRow("站立", "\(Int(todayStand))", "分钟", "\(Int(IOSHealthRingGoals.standMinutesPerDay)) 分")
                ringRow("睡眠", ringSleep > 0 ? String(format: "%.1f", ringSleep) : "—", ringSleep > 0 ? "小时" : "", "\(Int(IOSHealthRingGoals.sleepHoursTarget)) 小时")
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
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                if !unit.isEmpty, value != "—" {
                    Text(unit).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var todaySteps: Double {
        let cal = Calendar.current
        return model.stepsWeek.first(where: { cal.isDateInToday($0.date) })?.value
            ?? model.stepsWeek.last?.value ?? 0
    }

    private var todayStand: Double {
        let cal = Calendar.current
        return model.standMinutesWeek.first(where: { cal.isDateInToday($0.date) })?.value
            ?? model.standMinutesWeek.last?.value ?? 0
    }

    private var ringSleep: Double {
        let cal = Calendar.current
        return model.sleepHoursWeek.first(where: { cal.isDateInToday($0.date) })?.value
            ?? model.sleepHoursWeek.last(where: { $0.value > 0 })?.value ?? 0
    }

    private var ringProgressSteps: Double {
        min(1, todaySteps / IOSHealthRingGoals.stepsPerDay)
    }

    private var ringProgressStand: Double {
        min(1, todayStand / IOSHealthRingGoals.standMinutesPerDay)
    }

    private var ringProgressSleep: Double {
        guard ringSleep > 0 else { return 0 }
        return min(1, ringSleep / IOSHealthRingGoals.sleepHoursTarget)
    }
}

// MARK: - 活动与站立

struct IOSHealthActivityDetailView: View {
    @ObservedObject var model: IOSHealthHabitAnalysisModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("步数")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Chart(model.stepsWeek) { item in
                    BarMark(
                        x: .value("日", item.date, unit: .day),
                        y: .value("步", item.value)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 1, green: 0.38, blue: 0.45),
                                Color(red: 1, green: 0.38, blue: 0.45).opacity(0.42)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .cornerRadius(7)
                }
                .iosHealthWeekdayXAxis()
                .iosHealthIntYAxis()
                .chartYScale(domain: IOSHealthChartScales.yPositive(model.stepsWeek))
                .frame(height: IOSHealthChartScales.chartHeight)

                Text("站立（分钟 · 多来自 Apple Watch）")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Chart(model.standMinutesWeek) { item in
                    BarMark(
                        x: .value("日", item.date, unit: .day),
                        y: .value("分钟", item.value)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 0.5, green: 0.9, blue: 0.32),
                                Color(red: 0.5, green: 0.9, blue: 0.32).opacity(0.4)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .cornerRadius(7)
                }
                .iosHealthWeekdayXAxis()
                .iosHealthIntYAxis()
                .chartYScale(domain: IOSHealthChartScales.yPositive(model.standMinutesWeek))
                .frame(height: IOSHealthChartScales.chartHeight)

                Text("若未佩戴手表，站立可能长期为 0。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(BolaTheme.paddingHorizontal)
            .padding(.vertical, 12)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("活动与站立")
        .navigationBarTitleDisplayMode(.inline)
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

    var body: some View {
        ScrollView {
            Chart(model.sleepHoursWeek) { item in
                BarMark(
                    x: .value("日", item.date, unit: .day),
                    y: .value("小时", item.value)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 0.35, green: 0.55, blue: 0.98),
                            Color(red: 0.55, green: 0.4, blue: 0.95).opacity(0.55)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .cornerRadius(7)
            }
            .iosHealthWeekdayXAxis()
            .iosHealthFloatYAxis()
            .chartYScale(domain: IOSHealthChartScales.ySleep(model.sleepHoursWeek))
            .frame(height: IOSHealthChartScales.chartHeight + 24)
            .padding(BolaTheme.paddingHorizontal)
            .padding(.top, 12)

            Text("估算睡眠时长来自「睡眠」分析；仅供参考，不能替代医疗建议。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, BolaTheme.paddingHorizontal)
                .padding(.bottom, 24)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("睡眠节奏")
        .navigationBarTitleDisplayMode(.inline)
    }
}
