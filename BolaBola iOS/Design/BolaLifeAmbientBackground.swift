//
//  BolaLifeAmbientBackground.swift
//  生活页与主界面共用的淡黄绿渐变 + 顶/底两颗呼吸光球（与原先 `IOSLifeContainerView.lifePageBackground` 一致）。
//

import SwiftUI

struct BolaLifeAmbientBackground: View {
    var body: some View {
        ZStack {
            BolaTheme.backgroundGrouped
            LinearGradient(
                colors: [
                    BolaTheme.accent.opacity(BolaTheme.accentGlowTopOpacity),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: UnitPoint(x: 0.5, y: 0.42)
            )
        }
        .overlay(alignment: .top) {
            LifeBreathingOrbLayer()
                .offset(y: -255)
        }
        .overlay(alignment: .bottom) {
            GeometryReader { geo in
                LifeBreathingOrbLayer(isBottomAccent: true)
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
                    .offset(y: 200 - geo.safeAreaInsets.bottom)
            }
            .allowsHitTesting(false)
        }
    }
}

// MARK: - 背景呼吸球

/// 用 `TimelineView(.animation)` 替代 45Hz 主线程 Timer，与 VSync 协调，不干扰 tab 切换动画。
/// `drawingGroup()` 把模糊渐变球提交给 Metal 渲染，减少 CPU 工作量。
/// 所有相位值直接从 `Date.timeIntervalSinceReferenceDate` 推导，无需 @State。
struct LifeBreathingOrbLayer: View {
    /// 底部装饰球：更弱、略错位相位，避免与顶球完全同步。
    var isBottomAccent: Bool = false

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            OrbFrame(t: t, isBottomAccent: isBottomAccent)
        }
        // 将子视图树光栅化为 Metal 纹理，complex blur/gradient 由 GPU 处理
        .drawingGroup()
    }
}

// MARK: - OrbFrame（无状态，仅依赖 t）

/// 将所有动画参数从时间 `t` 推导，保持与原 Timer 逻辑等效的视觉效果。
/// 原 Timer 速率（45 Hz）× 每帧增量 = 弧度/秒：
///   底球: phase += 0.045/tick  → 2.025 rad/s
///   顶球呼吸: breathPhase += 0.009/tick → 0.405 rad/s
///   顶球漂移: driftPhase += 0.026/tick → 1.170 rad/s
///   wanderX: 用确定性多频正弦近似随机游走（视觉相当，无随机性）
private struct OrbFrame: View {
    let t: Double
    let isBottomAccent: Bool

    var body: some View {
        let phase      = t * 2.025                       // bottom & fallback
        let breathPhase = isBottomAccent ? phase : t * 0.405
        let driftPhase  = isBottomAccent ? phase : t * 1.170

        let pulse    = Self.smoothedPulse(phase: breathPhase, isBottomAccent: isBottomAccent)
        let pulseAlt = Self.altPulse(phase: breathPhase)
        let pulseMix = Self.mixedPulse(pulse: pulse, pulseAlt: pulseAlt, isBottomAccent: isBottomAccent)
        let scale    = Self.breathScale(pulseMix: pulseMix, isBottomAccent: isBottomAccent)

        let dim: Double = isBottomAccent ? 0.5 : 1.0
        let coreA: Double
        let coreB: Double
        let haloA: Double
        let haloB: Double
        if isBottomAccent {
            coreA = (0.72 + 0.22 * pulse) * dim
            coreB = (0.38 + 0.18 * pulse) * dim
            haloA = (0.32 + 0.18 * pulse) * dim
            haloB = (0.10 + 0.12 * pulse) * dim
        } else {
            coreA = 0.88 + 0.12 * pulse
            coreB = 0.55 + 0.22 * pulse
            haloA = 0.48 + 0.22 * pulse
            haloB = 0.18 + 0.18 * pulse
        }

        let driftX = Self.horizontalDrift(phase: driftPhase, isBottomAccent: isBottomAccent)
        let driftY = Self.verticalDrift(phase: driftPhase, isBottomAccent: isBottomAccent)
        // 顶球横向随机游走：多频正弦近似，视觉与原随机游走等效
        let wanderX: CGFloat = isBottomAccent ? 0 :
            CGFloat(18 * sin(t * 0.28) + 8 * cos(t * 0.43 + 0.9))

        let outerSize: CGFloat = isBottomAccent ? 392 : 400
        let innerSize: CGFloat = isBottomAccent ? 254 : 260
        let boxW: CGFloat = isBottomAccent ? 505 : 860
        let boxH: CGFloat = isBottomAccent ? 458 : 540
        let blurOuter: Double = isBottomAccent ? 18 + 10 * pulse : 10 + 6 * pulse
        let blurInner: Double = isBottomAccent ? 5 + 3 * pulse   : 2.2 + 1.1 * pulse
        let offsetX = driftX + wanderX

        return ZStack {
            Self.haloCircle(haloA: haloA, haloB: haloB, side: outerSize, blur: blurOuter)
            Self.coreCircle(coreA: coreA, coreB: coreB, side: innerSize, blur: blurInner)
            if !isBottomAccent {
                Self.hotHighlightCore(pulse: pulse)
            }
        }
        .scaleEffect(scale)
        .offset(x: offsetX, y: driftY)
        .frame(width: boxW, height: boxH)
        .allowsHitTesting(false)
    }

    private static func smoothedPulse(phase: Double, isBottomAccent: Bool) -> Double {
        let shifted = phase + (isBottomAccent ? 1.7 : 0)
        return (sin(shifted) + 1) * 0.5
    }

    private static func altPulse(phase: Double) -> Double {
        (sin(phase * 0.78 + 0.42) + 1) * 0.5
    }

    private static func mixedPulse(pulse: Double, pulseAlt: Double, isBottomAccent: Bool) -> Double {
        if isBottomAccent { return pulse }
        return pulse * 0.58 + pulseAlt * 0.42
    }

    private static func breathScale(pulseMix: Double, isBottomAccent: Bool) -> CGFloat {
        let base: CGFloat = isBottomAccent ? 0.88 : 0.94
        let amp: CGFloat  = isBottomAccent ? 0.10 : 0.075
        return base + amp * CGFloat(pulseMix)
    }

    private static func horizontalDrift(phase: Double, isBottomAccent: Bool) -> CGFloat {
        guard !isBottomAccent else { return 0 }
        let a = 28 * sin(phase * 0.29)
        let b = 20 * sin(phase * 0.48 + 0.9)
        let c = 14 * sin(phase * 0.82 + 1.7)
        let d = 10 * sin(phase * 1.18 + 0.2)
        return CGFloat(a + b + c + d)
    }

    private static func verticalDrift(phase: Double, isBottomAccent: Bool) -> CGFloat {
        guard !isBottomAccent else { return 0 }
        return CGFloat(
            9 * sin(phase * 0.25 + 0.4)
                + 6 * sin(phase * 0.52 + 1.2)
        )
    }

    private static func hotHighlightCore(pulse: Double) -> some View {
        let t = 0.9 + 0.1 * pulse
        return Circle()
            .fill(
                RadialGradient(
                    colors: [
                        BolaTheme.accent.opacity(t),
                        BolaTheme.accent.opacity(0.55),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 2,
                    endRadius: 88
                )
            )
            .frame(width: 150, height: 150)
            .blur(radius: 3)
    }

    private static func haloCircle(haloA: Double, haloB: Double, side: CGFloat, blur: Double) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        BolaTheme.accent.opacity(haloA),
                        BolaTheme.accent.opacity(haloB),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 40,
                    endRadius: 220
                )
            )
            .frame(width: side, height: side)
            .blur(radius: blur)
    }

    private static func coreCircle(coreA: Double, coreB: Double, side: CGFloat, blur: Double) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        BolaTheme.accent.opacity(coreA),
                        BolaTheme.accent.opacity(coreB),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 6,
                    endRadius: 130
                )
            )
            .frame(width: side, height: side)
            .blur(radius: blur)
    }
}
