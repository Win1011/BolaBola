//
//  IOSLifeTimePageView.swift
//  时光：示例时间轴（本地假数据）。
//

import SwiftUI

struct IOSLifeTimeMoment: Identifiable {
    let id = UUID()
    let timeText: String
    let title: String
    let detail: String
}

struct IOSLifeTimePageView: View {
    var bubbleMode: Bool
    /// 嵌入生活 Tab 时底层由 `lifePageBackground` 提供，此处勿再铺不透明灰底。
    var useLifePageBackdrop: Bool = false

    private let samples: [IOSLifeTimeMoment] = [
        IOSLifeTimeMoment(timeText: "08:30", title: "晨间记录", detail: "和 Bola 问好了，今天从一杯水开始。"),
        IOSLifeTimeMoment(timeText: "12:10", title: "午间走动", detail: "起来活动了几分钟，节奏不错。"),
        IOSLifeTimeMoment(timeText: "18:45", title: "傍晚小结", detail: "心情有点小起伏，晚点想再聊聊。")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(samples) { m in
                row(m)
            }
        }
        .padding(.top, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(useLifePageBackdrop ? Color.clear : BolaTheme.backgroundGrouped)
    }

    private func row(_ m: IOSLifeTimeMoment) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 4) {
                Text(m.timeText)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(BolaTheme.accent)
                Capsule()
                    .fill(Color(uiColor: .separator).opacity(0.55))
                    .frame(width: 3, height: 36)
            }
            .frame(width: 44)

            VStack(alignment: .leading, spacing: 6) {
                Text(m.title)
                    .font(.subheadline.weight(.semibold))
                Text(m.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(BolaTheme.spacingItem)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: BolaTheme.cornerLifePageCard, style: .continuous)
                    .fill(BolaTheme.surfaceElevated)
                    .shadow(
                        color: Color.black.opacity(BolaTheme.cardShadowOpacity(bubbleMode: bubbleMode)),
                        radius: bubbleMode ? 12 : 6,
                        y: 3
                    )
            )
        }
    }
}
