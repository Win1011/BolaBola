//
//  IOSHealthHubMiniVisuals.swift
//  分析页健康入口卡片内的轻量可视化（圆环、条形、折线等），数据来自 IOSHealthHabitAnalysisModel。
//

import SwiftUI

// MARK: - 摘要：单环 + 两行进度条

struct IOSHealthHubSummaryVisual: View {
    let model: IOSHealthHabitAnalysisModel

    private var score: Double { IOSHealthHabitSnapshot.combinedScoreProgress(model) }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack {
                IOSHealthSingleRing(
                    progress: score,
                    lineWidth: 7,
                    trackColor: Color.primary.opacity(0.08),
                    progressColors: [BolaTheme.accent, BolaTheme.accent.opacity(0.75)]
                )
                .frame(width: 54, height: 54)
                Text("\(Int((score * 100).rounded()))%")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.primary)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: 58)

            VStack(alignment: .leading, spacing: 8) {
                progressLabel(
                    "步数",
                    IOSHealthHabitSnapshot.stepsGoalProgress(model),
                    IOSHealthHabitSnapshot.intString(from: IOSHealthHabitSnapshot.todayStepsValue(model))
                )
                progressLabel(
                    "站立",
                    IOSHealthHabitSnapshot.standGoalProgress(model),
                    "\(Int(IOSHealthHabitSnapshot.todayStandMinutesValue(model).rounded()))分"
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func progressLabel(_ title: String, _ progress: Double, _ valueText: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(valueText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            GeometryReader { g in
                let w = g.size.width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 4)
                    Capsule()
                        .fill(BolaTheme.accent)
                        .frame(width: max(4, w * CGFloat(min(1, progress))), height: 4)
                }
            }
            .frame(height: 4)
        }
    }
}

// MARK: - 活动：7 日步数小柱

struct IOSHealthHubActivityBarsVisual: View {
    let values: [Double]

    var body: some View {
        let vals = values.count >= 7 ? Array(values.suffix(7)) : values
        let maxV = max(vals.max() ?? 0, 1)
        VStack(alignment: .leading, spacing: 6) {
            Text("近 7 日步数")
                .font(.caption2)
                .foregroundStyle(.secondary)
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .frame(height: 38)
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(0 ..< 7, id: \.self) { i in
                        let v = i < vals.count ? vals[i] : 0
                        let h = CGFloat(v / maxV) * 32
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(BolaTheme.accent.opacity(0.9))
                            .frame(width: 9, height: max(4, h))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 心率：迷你折线

struct IOSHealthHubHeartSparklineVisual: View {
    let values: [Double]

    var body: some View {
        let vals = values.count >= 7 ? Array(values.suffix(7)) : values
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let pts = normalizedPoints(values: vals, width: w, height: h)
            ZStack(alignment: .bottomLeading) {
                if pts.count >= 2 {
                    Path { path in
                        path.move(to: pts[0])
                        for p in pts.dropFirst() {
                            path.addLine(to: p)
                        }
                    }
                    .stroke(BolaTheme.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                } else {
                    Capsule()
                        .fill(BolaTheme.accent.opacity(0.35))
                        .frame(height: 3)
                        .frame(maxHeight: .infinity, alignment: .center)
                }
            }
        }
        .frame(height: 36)
    }

    private func normalizedPoints(values: [Double], width: CGFloat, height: CGFloat) -> [CGPoint] {
        guard !values.isEmpty else { return [] }
        let maxV = values.map { $0 }.max() ?? 1
        let minV = values.map { $0 }.min() ?? 0
        let span = max(maxV - minV, 1)
        let n = values.count
        return values.enumerated().map { i, v in
            let x = n == 1 ? width / 2 : CGFloat(i) / CGFloat(n - 1) * width
            let t = CGFloat((v - minV) / span)
            let y = height - 4 - t * (height - 8)
            return CGPoint(x: x, y: y)
        }
    }
}

// MARK: - 睡眠：时长 + 标签

struct IOSHealthHubSleepVisual: View {
    let hours: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(formattedDuration(hours))
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
                    .minimumScaleFactor(0.85)
                Text("昨夜")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("睡眠时长来自健康数据估算")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formattedDuration(_ h: Double) -> String {
        guard h > 0 else { return "—" }
        let total = Int((h * 60).rounded())
        let hh = total / 60
        let mm = total % 60
        return "\(hh)小时\(mm)分"
    }
}
