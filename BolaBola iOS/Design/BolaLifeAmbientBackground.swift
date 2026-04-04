//
//  BolaLifeAmbientBackground.swift
//  生活页与主界面共用的淡黄绿渐变 + 顶/底两颗呼吸光球（与原先 `IOSLifeContainerView.lifePageBackground` 一致）。
//

import Combine
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

/// 固定外包框 + 圆不变 `frame`、用 `scaleEffect` 呼吸；Timer 只刷新本 struct，避免整页随相位重布局。
/// 双层：内芯高不透明度 + 轻 blur（更亮），外晕略模糊（避免单层超大 blur 把颜色洗灰）。
/// 顶球：多频水平漂移 + 轻微随机游走，避免单一周期；底球保持简单呼吸。
struct LifeBreathingOrbLayer: View {
    /// 底部装饰球：更弱、略错位相位，避免与顶球完全同步。
    var isBottomAccent: Bool = false

    /// 底球：单一相位。顶球：呼吸与位移拆成两路，避免「缩放过快、漂移却慢」绑在同一 phase 上。
    @State private var phase: Double = 0
    @State private var breathPhase: Double = 0
    @State private var driftPhase: Double = 0
    /// 顶球专用：小幅随机横向漂移，与正弦组合后更「活」。
    @State private var wanderX: CGFloat = 0

    var body: some View {
        let pulse: Double
        let pulseAlt: Double
        if isBottomAccent {
            pulse = Self.smoothedPulse(phase: phase, isBottomAccent: true)
            pulseAlt = Self.altPulse(phase: phase)
        } else {
            pulse = Self.smoothedPulse(phase: breathPhase, isBottomAccent: false)
            pulseAlt = Self.altPulse(phase: breathPhase)
        }
        let pulseMix = Self.mixedPulse(pulse: pulse, pulseAlt: pulseAlt, isBottomAccent: isBottomAccent)
        let scale = Self.breathScale(pulseMix: pulseMix, isBottomAccent: isBottomAccent)
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
        let driftX = Self.horizontalDrift(phase: isBottomAccent ? phase : driftPhase, isBottomAccent: isBottomAccent)
        let driftY = Self.verticalDrift(phase: isBottomAccent ? phase : driftPhase, isBottomAccent: isBottomAccent)
        let outerSize: CGFloat = isBottomAccent ? 392 : 400
        let innerSize: CGFloat = isBottomAccent ? 254 : 260
        let boxW: CGFloat = isBottomAccent ? 505 : 860
        let boxH: CGFloat = isBottomAccent ? 458 : 540
        let blurOuter: Double
        let blurInner: Double
        if isBottomAccent {
            blurOuter = 18 + 10 * pulse
            blurInner = 5 + 3 * pulse
        } else {
            blurOuter = 10 + 6 * pulse
            blurInner = 2.2 + 1.1 * pulse
        }
        let offsetX = driftX + (isBottomAccent ? 0 : wanderX)

        return ZStack {
            Self.haloCircle(
                haloA: haloA,
                haloB: haloB,
                side: outerSize,
                blur: blurOuter
            )
            Self.coreCircle(
                coreA: coreA,
                coreB: coreB,
                side: innerSize,
                blur: blurInner
            )
            if !isBottomAccent {
                Self.hotHighlightCore(pulse: pulse)
            }
        }
        .scaleEffect(scale)
        .offset(x: offsetX, y: driftY)
        .frame(width: boxW, height: boxH)
        .allowsHitTesting(false)
        .onReceive(Timer.publish(every: 1.0 / 45.0, on: .main, in: .common).autoconnect()) { _ in
            if isBottomAccent {
                phase += 0.045
            } else {
                breathPhase += 0.009
                driftPhase += 0.026
                wanderX += CGFloat.random(in: -0.5 ... 0.5)
                wanderX *= 0.988
                wanderX = min(22, max(-22, wanderX))
            }
        }
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
        let amp: CGFloat = isBottomAccent ? 0.10 : 0.075
        return base + amp * CGFloat(pulseMix)
    }

    private static func horizontalDrift(phase: Double, isBottomAccent: Bool) -> CGFloat {
        guard !isBottomAccent else { return 0 }
        let p = phase
        let a = 28 * sin(p * 0.29)
        let b = 20 * sin(p * 0.48 + 0.9)
        let c = 14 * sin(p * 0.82 + 1.7)
        let d = 10 * sin(p * 1.18 + 0.2)
        return CGFloat(a + b + c + d)
    }

    private static func verticalDrift(phase: Double, isBottomAccent: Bool) -> CGFloat {
        guard !isBottomAccent else { return 0 }
        let p = phase
        return CGFloat(
            9 * sin(p * 0.25 + 0.4)
                + 6 * sin(p * 0.52 + 1.2)
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
