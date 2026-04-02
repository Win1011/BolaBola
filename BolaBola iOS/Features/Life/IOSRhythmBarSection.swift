//
//  IOSRhythmBarSection.swift
//

import SwiftUI

struct IOSRhythmBarSection: View {
    @ObservedObject var model: IOSRhythmHRVModel
    var bubbleMode: Bool
    @State private var showInfo = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("节奏条")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                Button {
                    showInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关于节奏条")
            }

            VStack(alignment: .leading, spacing: 6) {
                rhythmBars
                    .frame(height: bubbleMode ? 36 : 28)
                    .padding(.horizontal, 4)

                if model.phase == .empty {
                    Text("今日暂无 HRV 样本，佩戴 Apple Watch 并授权健康读取后可见。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, BolaTheme.spacingItem)
            .padding(.vertical, bubbleMode ? 10 : 8)
            .background(cardBackground)
        }
        .alert("节奏条", isPresented: $showInfo) {
            Button("好的", role: .cancel) {}
        } message: {
            Text("基于今日心率变异性（HRV）样本按小时汇总，仅作状态参考，非医疗诊断。")
        }
    }

    private var rhythmBars: some View {
        GeometryReader { geo in
            let n = 24
            let gap: CGFloat = 2
            let barW = max(1, (geo.size.width - gap * CGFloat(n - 1)) / CGFloat(n))
            HStack(alignment: .bottom, spacing: gap) {
                ForEach(0 ..< n, id: \.self) { i in
                    let h = model.hourlyNormalized.indices.contains(i) ? model.hourlyNormalized[i] : 0
                    let barH = max(3, CGFloat(h) * geo.size.height)
                    let isDark = h > 0 && h < 0.35
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(isDark ? BolaTheme.rhythmBarContrast : (h < 0.02 ? BolaTheme.rhythmBarMuted : BolaTheme.rhythmBarStrong))
                        .frame(width: barW, height: barH)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: BolaTheme.cornerLifePageCard, style: .continuous)
            .fill(BolaTheme.surfaceBubble)
            .shadow(
                color: bubbleMode ? Color.black.opacity(BolaTheme.cardShadowOpacity(bubbleMode: true)) : .clear,
                radius: bubbleMode ? 16 : 0,
                y: bubbleMode ? 6 : 0
            )
    }
}
