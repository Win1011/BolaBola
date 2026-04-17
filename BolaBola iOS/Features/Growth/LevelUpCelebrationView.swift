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

    private var titleText: String {
        presentation.toLevel - presentation.fromLevel > 1
            ? "连续升级!"
            : "升级成功!"
    }

    private var subtitleText: String {
        "\(companionDisplayName) 又成长啦，这次解锁的奖励如下。"
    }

    var body: some View {
        ZStack {
            LevelUpCelebrationBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        headerBadge
                            .padding(.top, 16)

                        heroSection

                        rewardsCard
                            .opacity(cardVisible ? 1 : 0)
                            .offset(y: cardVisible ? 0 : 22)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 128)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                onContinue()
                dismiss()
            } label: {
                Text("继续")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
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
            .background(Color.black.opacity(0.001))
        }
        .onAppear {
            withAnimation(.spring(response: 0.62, dampingFraction: 0.82)) {
                heroVisible = true
            }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.88).delay(0.08)) {
                cardVisible = true
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
                        .frame(maxWidth: 500)
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
            .frame(height: 500)

            VStack(spacing: 6) {
                Text("Lv.\(presentation.toLevel)")
                    .font(.system(size: 46, weight: .black, design: .rounded))
                    .foregroundStyle(BolaTheme.accent)
                    .shadow(color: BolaTheme.accent.opacity(0.18), radius: 14, x: 0, y: 6)
                    .padding(.top, -116)

                Text(titleText)
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .foregroundStyle(Color.white)

                Text(subtitleText)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.76))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
            }
            .offset(y: -50)
        }
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
