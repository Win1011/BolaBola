//
//  LevelUpCelebrationView.swift
//  升级庆祝全屏页，便于独立预览和迭代。
//

import SwiftUI
import UIKit

struct LevelUpCelebrationView: View {
    let presentation: LevelUpPresentation
    let companionDisplayName: String
    let onContinue: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var heroVisible = false
    @State private var cardVisible = false
    @State private var levelGlowPulsing = false

    private var titleText: String {
        presentation.toLevel - presentation.fromLevel > 1
            ? "连续升级!"
            : "升级成功!"
    }

    private var subtitleText: String {
        "\(companionDisplayName) 又成长啦，此次解锁的奖励如下。"
    }

    var body: some View {
        ZStack {
            LevelUpCelebrationBackground()
                .ignoresSafeArea()

            LevelUpStarShower()
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 2) {
                        headerBadge
                            .padding(.top, 2)

                        heroSection

                        rewardsCard
                            .opacity(cardVisible ? 1 : 0)
                            .offset(y: cardVisible ? -280 : -130)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 128)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            dismissKeyboard()
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                onContinue()
                dismiss()
            } label: {
                Text("继续")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .kerning(1.8)
                    .foregroundStyle(BolaTheme.onAccentForeground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        Capsule(style: .continuous)
                            .fill(BolaTheme.accent)
                            .shadow(color: BolaTheme.accent.opacity(0.28), radius: 18, x: 0, y: 10)
                    )
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .background {
                ZStack {
                    LinearGradient(
                        colors: [
                            Color.clear,
                            Color.black.opacity(0.01),
                            Color.black.opacity(0.7),
                            Color.black.opacity(0.98)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    Rectangle()
                        .fill(.ultraThinMaterial.opacity(0.38))
                        .mask(
                            LinearGradient(
                                colors: [
                                    Color.clear,
                                    Color.white.opacity(0.10),
                                    Color.white.opacity(0.45),
                                    Color.white
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                .ignoresSafeArea()
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.62, dampingFraction: 0.82)) {
                heroVisible = true
            }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.88).delay(0.08)) {
                cardVisible = true
            }
            dismissKeyboard()
            guard !levelGlowPulsing else { return }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                levelGlowPulsing = true
            }
        }
    }

    private var headerBadge: some View {
        Text("LEVEL UP")
            .font(.system(size: 12, weight: .black, design: .rounded))
            .kerning(2.2)
            .foregroundStyle(Color.white.opacity(0.92))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.12))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )
            )
    }

    private var heroSection: some View {
        VStack(spacing: 0) {
            ZStack {
                if UIImage(named: "LevelUpHero") != nil {
                    Image("LevelUpHero")
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 820)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .scaleEffect(heroVisible ? 1 : 0.88)
                        .opacity(heroVisible ? 1 : 0)
                } else {
                    Circle()
                        .fill(Color.white.opacity(0.55))
                        .frame(width: 250, height: 250)
                        .overlay(
                            Image(systemName: "crown.fill")
                                .font(.system(size: 78, weight: .black))
                                .foregroundStyle(BolaTheme.accent)
                        )
                        .scaleEffect(heroVisible ? 1 : 0.88)
                        .opacity(heroVisible ? 1 : 0)
                }
            }
            .frame(height: 680)
            .offset(x: -5, y: -50)

            VStack(spacing: 6) {
                Text("Lv.\(presentation.toLevel)")
                    .font(.system(size: 46, weight: .black, design: .rounded))
                    .foregroundStyle(BolaTheme.accent)
                    .shadow(
                        color: BolaTheme.accent.opacity(levelGlowPulsing ? 0.92 : 0.45),
                        radius: levelGlowPulsing ? 30 : 14,
                        x: 0,
                        y: 0
                    )
                    .shadow(
                        color: Color.white.opacity(levelGlowPulsing ? 0.42 : 0.18),
                        radius: levelGlowPulsing ? 14 : 6,
                        x: 0,
                        y: 0
                    )
                    .padding(.top, -157)
                    .offset(y: -53)

                VStack(spacing: 6) {
                    Text(titleText)
                        .font(.system(size: 36, weight: .black, design: .rounded))
                        .foregroundStyle(Color.white)

                    Text(subtitleText)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.76))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 18)
                }
                .offset(y: -80)
            }
            .offset(y: -120)
        }
        .offset(y: -95)
    }

    private var rewardsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("本次奖励")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white)

            ForEach(presentation.rewards) { reward in
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.10))
                            .frame(width: 44, height: 44)
                        Image(systemName: reward.iconSystemName)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(BolaTheme.accent)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(reward.title)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.96))
                        Text(reward.detail)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.68))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LevelUpCardBackground())
    }
}

private func dismissKeyboard() {
    UIApplication.shared.sendAction(
        #selector(UIResponder.resignFirstResponder),
        to: nil,
        from: nil,
        for: nil
    )
}

private struct LevelUpStarShower: View {
    private let stars: [LevelUpStarParticle] = [
        .init(x: 0.14, delay: 0.00, duration: 4.4, size: 15, rotation: -10, drift: 16, range: 0.34, group: .a),
        .init(x: 0.22, delay: 0.30, duration: 5.0, size: 11, rotation: 16, drift: -12, range: 0.28, group: .b),
        .init(x: 0.31, delay: 0.55, duration: 4.2, size: 16, rotation: -22, drift: 15, range: 0.36, group: .a),
        .init(x: 0.43, delay: 0.12, duration: 3.9, size: 12, rotation: 12, drift: -18, range: 0.30, group: .b),
        .init(x: 0.55, delay: 0.42, duration: 4.8, size: 14, rotation: -16, drift: 14, range: 0.32, group: .a),
        .init(x: 0.66, delay: 0.22, duration: 4.1, size: 11, rotation: 22, drift: -14, range: 0.26, group: .b),
        .init(x: 0.77, delay: 0.70, duration: 5.2, size: 16, rotation: -18, drift: 18, range: 0.35, group: .a),
        .init(x: 0.86, delay: 0.46, duration: 4.3, size: 12, rotation: 14, drift: -16, range: 0.28, group: .b),
        .init(x: 0.26, delay: 0.88, duration: 4.6, size: 10, rotation: -12, drift: 10, range: 0.24, group: .a),
        .init(x: 0.72, delay: 0.64, duration: 4.5, size: 10, rotation: 18, drift: -10, range: 0.24, group: .b)
    ]

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { context in
                let time = context.date.timeIntervalSinceReferenceDate

                ZStack {
                    ForEach(stars) { star in
                        let progress = star.progress(at: time)
                        let twinklePhase = star.group == .a ? progress : (progress + 0.5).truncatingRemainder(dividingBy: 1)
                        let pulse = 0.5 - 0.5 * cos(twinklePhase * .pi * 2)
                        let alpha = (0.18 + star.range * pulse) * min(1, (1 - progress) / 0.16) * min(1, progress / 0.16)
                        let scale = 0.88 + 0.22 * pulse
                        let y = -40 + progress * (geo.size.height * 0.78)
                        let x = geo.size.width * star.x + sin(progress * .pi * 2) * star.drift

                        Image(systemName: "sparkle")
                            .font(.system(size: star.size, weight: .bold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [
                                        Color(red: 1.0, green: 0.97, blue: 0.76),
                                        BolaTheme.accent,
                                        Color(red: 1.0, green: 0.84, blue: 0.34)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .shadow(color: BolaTheme.accent.opacity(alpha * 0.8), radius: 10 + 8 * pulse, x: 0, y: 0)
                            .rotationEffect(.degrees(star.rotation + progress * 160))
                            .scaleEffect(scale)
                            .opacity(alpha)
                            .position(x: x, y: y)
                    }
                }
            }
        }
    }
}

private struct LevelUpStarParticle: Identifiable {
    let id = UUID()
    let x: CGFloat
    let delay: Double
    let duration: Double
    let size: CGFloat
    let rotation: Double
    let drift: CGFloat
    let range: Double
    let group: Group

    func progress(at time: TimeInterval) -> Double {
        let local = (time + delay).truncatingRemainder(dividingBy: duration)
        return local / duration
    }

    enum Group {
        case a
        case b
    }
}

private struct LevelUpCelebrationBackground: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.black.opacity(0.87))

            Circle()
                .fill(BolaTheme.accent.opacity(0.24))
                .frame(width: 360, height: 360)
                .blur(radius: 52)
                .offset(x: 0, y: -230)

            Circle()
                .fill(Color(red: 1, green: 0.72, blue: 0.87).opacity(0.10))
                .frame(width: 340, height: 340)
                .blur(radius: 50)
                .offset(x: -90, y: -30)

            Circle()
                .fill(Color.white.opacity(0.04))
                .frame(width: 220, height: 220)
                .blur(radius: 44)
                .offset(x: 130, y: 160)
        }
    }
}

private struct LevelUpCardBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(Color.black.opacity(0.34))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.24), radius: 22, x: 0, y: 14)
    }
}

#Preview("升级页") {
    LevelUpCelebrationView(
        presentation: .build(from: 2, to: 5),
        companionDisplayName: "Bola",
        onContinue: {}
    )
}
