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

            // 日记列表自带 `List` 滚动，外层勿再包 `ScrollView`，否则与左滑删除手势冲突。
            IOSLifeTimePageView(bubbleMode: false, useLifePageBackdrop: true)
                // 左侧略留呼吸；右侧再收一截，主卡才能明显「往屏右缘」变长（对称 padding 会吃满右侧观感）。
                .padding(.leading, 16)
                .padding(.trailing, 8)
                .padding(.top, 14)
                .padding(.bottom, 24)
                .background(Color.clear)
        }
    }
}
