//
//  BolaGrowthAmbientBackground.swift
//  成长页：在生活/主界面同款双呼吸球之上叠加顶部半圆光晕。
//

import SwiftUI

struct BolaGrowthAmbientBackground: View {
    var body: some View {
        ZStack(alignment: .top) {
            BolaLifeAmbientBackground()

            GeometryReader { geo in
                let w = geo.size.width
                let domeH = w * 0.58
                Ellipse()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.98),
                                BolaTheme.accent.opacity(0.32),
                                BolaTheme.accent.opacity(0.12),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: UnitPoint(x: 0.5, y: 0.72)
                        )
                    )
                    .frame(width: w * 1.5, height: domeH)
                    .position(x: w * 0.5, y: domeH * 0.32)
            }
            .allowsHitTesting(false)
        }
    }
}
