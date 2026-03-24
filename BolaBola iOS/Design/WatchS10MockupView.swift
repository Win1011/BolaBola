//
//  WatchS10MockupView.swift
//  iPhone：GathXR 导出的整表 PNG + Face 屏区域；Face 用于内容蒙版与叠层。
//

import SwiftUI

struct WatchS10MockupView: View {
    var companion: Double
    /// 纵向最大高度（宽度随整图比例）。
    var maxHeight: CGFloat = 240

    /// 屏幕区相对整图归一化框（`Apple Watch S10 from GathXR.png` 约 1266×2048，对齐 Figma BodyWatch 内 Face）。
    private static let screenRectInFull = CGRect(
        x: 31.28 / 1265.29,
        y: (328.5 + 28.47) / 2048.0,
        width: 1140.93 / 1265.29,
        height: 1334.06 / 2048.0
    )

    var body: some View {
        Image("WatchS10Full")
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(maxHeight: maxHeight)
            .overlay {
                screenOverlay
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Apple Watch S10 示意，陪伴值 \(Int(companion.rounded()))")
    }

    private var screenOverlay: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let r = Self.screenRectInFull
            let sx = r.origin.x * w
            let sy = r.origin.y * h
            let sw = r.width * w
            let sh = r.height * h

            screenLabels
                .frame(width: sw, height: sh)
                .mask(
                    Image("WatchS10Face")
                        .renderingMode(.original)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: sw, height: sh)
                )
            .frame(width: sw, height: sh, alignment: .center)
            .position(x: sx + sw / 2, y: sy + sh / 2)
        }
    }

    private var screenLabels: some View {
        VStack(spacing: 6) {
            Text("Bola")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.92))
            Text("\(Int(companion.rounded()))")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
            Text("陪伴值")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.55))
        }
        .minimumScaleFactor(0.5)
        .padding(.vertical, 6)
    }
}

#Preview {
    WatchS10MockupView(companion: 67)
        .padding()
        .background(Color(.systemGroupedBackground))
}
