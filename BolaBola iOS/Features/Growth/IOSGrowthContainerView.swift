//
//  IOSGrowthContainerView.swift
//  成长 Tab：`成长` 与 `时光` 分段切换（与生活 `IOSLifeContainerView` 同构）。
//

import SwiftUI

struct IOSGrowthContainerView: View {
    @Binding var growthSegment: IOSGrowthSubPage

    var body: some View {
        ZStack {
            switch growthSegment {
            case .growth:
                IOSGrowthView()
            case .timeMoments:
                growthTimeMomentsScroll
            }
        }
    }

    /// 单列滚动 + 透明底（由成长页渐变承担）。
    private var growthTimeMomentsScroll: some View {
        ZStack(alignment: .top) {
            BolaGrowthAmbientBackground()
                .ignoresSafeArea(edges: [.top, .bottom])

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    IOSLifeTimePageView(bubbleMode: false, useLifePageBackdrop: true)
                }
                .padding(.horizontal, BolaTheme.paddingHorizontal)
                .padding(.top, 14)
                .padding(.bottom, 24)
            }
            .background(Color.clear)
            .scrollIndicators(.hidden)
        }
    }
}
