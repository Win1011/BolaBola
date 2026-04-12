//
//  IOSHealthActivityRingsView.swift
//  今日活动摘要：三环进度（参考系统「健身记录」圆环形态；纯 SwiftUI，无第三方库）。
//  实现思路同常见教程：Circle + trim + round lineCap（如 Sarunw / CodeWithChris / ActivityRings 等）。
//

import SwiftUI

/// 单条圆环：底层轨道 + 进度弧（0…1，超过 1 时夹紧显示满环）。
struct IOSHealthSingleRing: View {
    var progress: Double
    var lineWidth: CGFloat
    var trackColor: Color
    var progressColors: [Color]

    var body: some View {
        let clamped = min(1, max(0, progress))
        ZStack {
            Circle()
                .stroke(trackColor, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(clamped))
                .stroke(
                    AngularGradient(
                        colors: progressColors,
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .accessibilityLabel("进度 \(Int(clamped * 100))%")
    }
}

/// 三环同心圆：外→内 Move / Exercise / Stand，交互语言更接近系统健身圆环。
struct IOSHealthTodayRingsBlock: View {
    /// 相对各自目标的 0…1
    var moveProgress: Double
    var exerciseProgress: Double
    var standProgress: Double

    private let outerDiameter: CGFloat = 120
    private let midDiameter: CGFloat = 98
    private let innerDiameter: CGFloat = 76
    private let lineOuter: CGFloat = 10
    private let lineMid: CGFloat = 9
    private let lineInner: CGFloat = 8

    var body: some View {
        ZStack {
            IOSHealthSingleRing(
                progress: moveProgress,
                lineWidth: lineOuter,
                trackColor: Color.primary.opacity(0.07),
                progressColors: [
                    Color(red: 0.98, green: 0.28, blue: 0.38),
                    Color(red: 1, green: 0.45, blue: 0.52)
                ]
            )
            .frame(width: outerDiameter, height: outerDiameter)

            IOSHealthSingleRing(
                progress: exerciseProgress,
                lineWidth: lineMid,
                trackColor: Color.primary.opacity(0.07),
                progressColors: [
                    Color(red: 0.45, green: 0.88, blue: 0.28),
                    Color(red: 0.62, green: 0.95, blue: 0.42)
                ]
            )
            .frame(width: midDiameter, height: midDiameter)

            IOSHealthSingleRing(
                progress: standProgress,
                lineWidth: lineInner,
                trackColor: Color.primary.opacity(0.07),
                progressColors: [
                    Color(red: 0.18, green: 0.82, blue: 0.96),
                    Color(red: 0.39, green: 0.92, blue: 0.99)
                ]
            )
            .frame(width: innerDiameter, height: innerDiameter)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("今日活动圆环摘要")
    }
}

enum IOSHealthRingGoals {
    /// 与「健身」常见默认量级同数量级，仅作可视化目标，非医疗建议。
    static let moveKilocaloriesPerDay: Double = 400
    static let exerciseMinutesPerDay: Double = 30
    static let stepsPerDay: Double = 10_000
    /// 站立时间（分钟）日汇总，偏保守目标。
    static let standMinutesPerDay: Double = 180
    static let sleepHoursTarget: Double = 8
}
