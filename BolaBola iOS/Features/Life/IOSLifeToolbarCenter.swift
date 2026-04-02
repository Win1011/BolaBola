//
//  IOSLifeToolbarCenter.swift
//  Figma：「生活」黑粗 +「时光」灰（可点击切换）。
//

import SwiftUI

/// 生活 / 时光大号分段（用于导航栏 `principal`，需外层 `.frame(maxWidth: .infinity)` 居中）。
struct IOSLifeSegmentLarge: View {
    @Binding var lifeSegment: IOSLifeSubPage
    @Environment(\.colorScheme) private var colorScheme

    private var inactiveMoments: Color {
        Color(red: 0.48, green: 0.52, blue: 0.42)
    }

    private var selectedTitleColor: Color {
        colorScheme == .dark ? Color.white : Color.black
    }

    /// 导航栏 principal 宽度有限；需在可读性与避免「…」之间折中。
    private var titleSize: CGFloat { 22 }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                lifeSegment = .dailyLife
            } label: {
                Text("生活")
                    .font(.system(size: titleSize, weight: lifeSegment == .dailyLife ? .bold : .semibold))
                    .foregroundStyle(lifeSegment == .dailyLife ? selectedTitleColor : inactiveMoments)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .layoutPriority(1)
            }
            .buttonStyle(.plain)

            Button {
                lifeSegment = .timeMoments
            } label: {
                Text("时光")
                    .font(.system(size: titleSize, weight: lifeSegment == .timeMoments ? .bold : .semibold))
                    .foregroundStyle(lifeSegment == .timeMoments ? selectedTitleColor : inactiveMoments)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .layoutPriority(1)
            }
            .buttonStyle(.plain)
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("生活与时光")
    }
}

struct IOSLifeToolbarCenter: View {
    @Binding var lifeSegment: IOSLifeSubPage

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(BolaTheme.accent)
                .accessibilityHidden(true)

            HStack(spacing: 18) {
                Button {
                    lifeSegment = .dailyLife
                } label: {
                    Text("生活")
                        .font(.system(size: 14, weight: lifeSegment == .dailyLife ? .bold : .regular))
                        .foregroundStyle(lifeSegment == .dailyLife ? Color.primary : Color.secondary)
                }
                .buttonStyle(.plain)

                Button {
                    lifeSegment = .timeMoments
                } label: {
                    Text("时光")
                        .font(.system(size: 14, weight: lifeSegment == .timeMoments ? .bold : .regular))
                        .foregroundStyle(lifeSegment == .timeMoments ? Color.primary : Color.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("生活与时光")
    }
}
