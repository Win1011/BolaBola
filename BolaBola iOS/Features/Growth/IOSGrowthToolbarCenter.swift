//
//  IOSGrowthToolbarCenter.swift
//  「成长」黑粗 +「时光」灰（可点击切换）。
//

import SwiftUI

/// 成长 / 时光大号分段（用于导航栏 `principal`）。
struct IOSGrowthSegmentLarge: View {
    @Binding var growthSegment: IOSGrowthSubPage
    @Environment(\.colorScheme) private var colorScheme

    private var inactiveMoments: Color {
        Color(red: 0.48, green: 0.52, blue: 0.42)
    }

    private var selectedTitleColor: Color {
        colorScheme == .dark ? Color.white : Color.black
    }

    private var titleSize: CGFloat { 20 }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                growthSegment = .growth
            } label: {
                Text("成长")
                    .font(.system(size: titleSize, weight: growthSegment == .growth ? .bold : .semibold))
                    .foregroundStyle(growthSegment == .growth ? selectedTitleColor : inactiveMoments.opacity(0.62))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .layoutPriority(1)
            }
            .buttonStyle(.plain)

            Button {
                growthSegment = .timeMoments
            } label: {
                Text("时光")
                    .font(.system(size: titleSize, weight: growthSegment == .timeMoments ? .bold : .semibold))
                    .foregroundStyle(growthSegment == .timeMoments ? selectedTitleColor : inactiveMoments.opacity(0.62))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .layoutPriority(1)
            }
            .buttonStyle(.plain)
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("成长与时光")
    }
}
