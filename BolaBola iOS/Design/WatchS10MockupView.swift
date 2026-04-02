//
//  WatchS10MockupView.swift
//  iPhone：GathXR 导出的整表 PNG + Face 屏区域；Face 用于内容蒙版与叠层。
//

import SwiftUI

struct WatchS10MockupView: View {
    var companion: Double
    /// 纵向最大高度（宽度随整图比例）。
    var maxHeight: CGFloat = 240
    /// 主界面「表盘」布局：决定屏幕区内占位预览（后续可替换为真实小组件）。
    var layout: HomeWatchFaceLayout = .minimal

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
        ZStack {
            switch layout {
            case .minimal:
                companionStack
            case .modular:
                ZStack {
                    VStack {
                        HStack {
                            widgetSlotSmall
                            Spacer(minLength: 0)
                            widgetSlotSmall
                        }
                        Spacer(minLength: 0)
                        companionStack.scaleEffect(0.92)
                        Spacer(minLength: 0)
                        HStack(spacing: 8) {
                            widgetSlotWide
                            widgetSlotWide
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
            case .corners:
                ZStack {
                    companionStack
                    VStack {
                        HStack {
                            widgetSlotDot
                            Spacer()
                            widgetSlotDot
                        }
                        Spacer()
                        HStack {
                            widgetSlotDot
                            Spacer()
                            widgetSlotDot
                        }
                    }
                    .padding(10)
                }
            case .focus:
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                        .padding(18)
                    companionStack.scaleEffect(0.88)
                }
            }
        }
    }

    private var companionStack: some View {
        VStack(spacing: 6) {
            Text("Bola")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.92))
            Text("\(Int(companion.rounded()))")
                .font(.system(size: 34, weight: .heavy))
                .foregroundStyle(.white)
                .monospacedDigit()
            Text("陪伴值")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.55))
        }
        .minimumScaleFactor(0.5)
        .padding(.vertical, 6)
    }

    private var widgetSlotSmall: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .stroke(Color.white.opacity(0.4), lineWidth: 1)
            .frame(width: 36, height: 22)
            .overlay {
                Text("组件")
                    .font(.system(size: 7, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            }
    }

    private var widgetSlotWide: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .stroke(Color.white.opacity(0.4), lineWidth: 1)
            .frame(height: 26)
            .frame(maxWidth: .infinity)
            .overlay {
                Text("组件")
                    .font(.system(size: 7, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            }
    }

    private var widgetSlotDot: some View {
        Circle()
            .stroke(Color.white.opacity(0.45), lineWidth: 1)
            .frame(width: 22, height: 22)
            .overlay {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
            }
    }
}

#Preview {
    WatchS10MockupView(companion: 67, layout: .modular)
        .padding()
        .background(Color(.systemGroupedBackground))
}
