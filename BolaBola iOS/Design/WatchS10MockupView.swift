//
//  WatchS10MockupView.swift
//  iPhone：整表 PNG + 表镜内时间、麦克风、三角落组件预览；组件槽支持拖放分配。
//

import SwiftUI

struct WatchS10MockupView: View {
    /// `HH:mm`，无 AM/PM，等宽数字。
    private static let timeOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.timeZone = .current
        f.dateFormat = "HH:mm"
        return f
    }()

    @Binding var slots: WatchFaceSlotsConfiguration
    /// 与 `HealthKit` / 天气预览一致的数据文案。
    var heartRateText: String
    var stepsText: String
    /// WeatherKit / Open-Meteo 的 SF Symbol 名（与系统天气图标体系一致）。
    var weatherSystemImageName: String
    var weatherTempText: String
    var titleText: String = ""
    var titleFrameAssetName: String? = nil
    var showsTitle: Bool = true

    private var titleForegroundColor: Color {
        switch titleFrameAssetName {
        case "TitleFrame0to5":
            return Color.black.opacity(0.68)
        case "TitleFrame5to10":
            return Color(red: 254 / 255, green: 214 / 255, blue: 189 / 255)
        default:
            return .white.opacity(0.88)
        }
    }

    private var watchPreviewTitleBadgeMetrics: (fontSize: CGFloat, horizontalPadding: CGFloat, verticalPadding: CGFloat, height: CGFloat, minWidth: CGFloat) {
        TitleBadgeLayout.metrics(compact: false)
    }

    private var watchPreviewTitleBadgeScale: CGFloat { 0.57 }

    private var watchPreviewTitleFontSize: CGFloat {
        if titleText.count < 6 { return 9 }
        if titleText.count < 8 { return 8.5 }
        return watchPreviewTitleBadgeMetrics.fontSize * watchPreviewTitleBadgeScale
    }

    private var watchPreviewTitleTracking: CGFloat {
        if titleText.count < 6 { return 0.25 }
        return 0
    }

    /// 当前正在播放的宠物动画帧前缀（如 "idleone"），由 BolaWCSessionCoordinator 从手表同步而来。
    var petAnimationPrefix: String = "idleone"

    var maxHeight: CGFloat = 310
    /// 表冠在右侧时视觉会偏一侧；正值向右、负值向左（与导航标题对齐时可微调）。
    var horizontalNudgePoints: CGFloat = 0
    /// 仅表镜内叠层（黄绿 frame、时间/麦克风、三槽）相对整图水平微调；**整表 PNG 不动**。负值向左、正值向右。
    var screenContentNudgeX: CGFloat = 0
    /// 仅表镜叠层相对整图垂直微调；**整表 PNG 不动**。正值向下、负值向上。
    var screenContentNudgeY: CGFloat = 0
    /// 在「表镜」蒙版内绘制光学中心十字；与 `WatchS10PreviewGeometry` 一致（主界面默认关）。
    var showScreenCenterCrosshair: Bool = false
    /// 绘制三角槽外接正方形（青色虚线，调试用）。
    var showComplicationSlotsBoundingRect: Bool = false
    /// 绘制三枚槽位圆圈（调位置 / 尺寸时用）。
    var showComplicationSlotGuideCircles: Bool = false
    /// 叠加绘制与 `.mask` 同形状、同位置的圆角矩形描边（调试对照）；默认关。
    var showScreenMaskOutline: Bool = false

    // MARK: - 表镜内布局（相对 `WatchS10PreviewGeometry`；已标定）

    /// 黄绿 frame：相对「几何十字与 safe 求交后的可见矩形」的宽度倍数。
    var opticalFrameHorizontalHalfScale: CGFloat = 1.34
    /// 黄绿 frame：相对上述可见矩形的高度倍数。
    var opticalFrameVerticalHalfScale: CGFloat = 0.79
    /// 黄绿十字与中心点：相对表镜几何中心 `(w/2,h/2)` 的偏移（表镜局部 pt）。
    var opticalFrameCenterOffsetX: CGFloat = 0
    var opticalFrameCenterOffsetY: CGFloat = 0
    /// 三槽：相对几何的「离中心」半径倍数（外接正方形半边长）。
    var complicationSlotsRadialScale: CGFloat = 1.30
    /// 三槽整体：相对表镜中心的平移（表镜局部 pt）。
    var complicationSlotsOffsetX: CGFloat = 0
    var complicationSlotsOffsetY: CGFloat = 0
    /// 三槽内容整体放大倍数（图标/文案/槽位直径一起变）。
    var complicationContentScale: CGFloat = 1.12
    /// 调试圆圈相对槽位直径的放大倍数。
    var complicationGuideCircleScale: CGFloat = 1.14

    /// 表镜内时间：字号（无 AM/PM）。
    var timeLabelFontSize: CGFloat = 16
    /// 时间行顶部 inset（表镜局部 pt）。
    var timeLabelTopPadding: CGFloat = 14
    var timeLabelPaddingLeading: CGFloat = 4
    var timeLabelPaddingTrailing: CGFloat = 10
    /// 时间块相对右上区域的平移（表镜局部 pt）；负值向左、正值向下。
    var timeLabelOffsetX: CGFloat = -17
    var timeLabelOffsetY: CGFloat = 8
    /// `true`：三槽显示圆圈并接受拖放（编辑表盘）；`false`：仅展示已放置内容，无空槽圆圈。
    var isEditingSlots: Bool = false
    var onTapPlacedSlot: ((WatchFaceSlotPosition, WatchFaceComplicationKind) -> Void)? = nil

    var body: some View {
        Image("WatchS10Full")
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(maxHeight: maxHeight)
            .overlay {
                screenOverlay
            }
            // 必须放在 overlay **之后**：否则只有 PNG 会随 offset 移动，表镜内 frame / 三槽仍按未偏移布局对齐。
            .offset(x: horizontalNudgePoints)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Apple Watch 表盘预览")
    }

    private var screenOverlay: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let r = WatchS10PreviewGeometry.screenRectInFull
            let sw = r.width * w
            let sh = r.height * h
            let pos = WatchS10PreviewGeometry.screenOverlayPositionInFullImage(width: w, height: h)
            let cornerR = WatchS10PreviewGeometry.screenCornerRadius(sw: sw, sh: sh)
            let cx = pos.x + screenContentNudgeX
            let cy = pos.y + screenContentNudgeY

            ZStack {
                screenLabels
                    .frame(width: sw, height: sh)
                    .mask {
                        RoundedRectangle(cornerRadius: cornerR, style: .continuous)
                    }
                    .frame(width: sw, height: sh, alignment: .center)
                    .position(x: cx, y: cy)

                if showScreenMaskOutline {
                    RoundedRectangle(cornerRadius: cornerR, style: .continuous)
                        .stroke(Color.orange.opacity(0.95), lineWidth: 2)
                        .frame(width: sw, height: sh)
                        .position(x: cx, y: cy)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private var screenLabels: some View {
        ZStack {
            PetFramePlayer(prefix: petAnimationPrefix)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)

            if showScreenCenterCrosshair {
                screenCenterCrosshairLayer
                    .allowsHitTesting(false)
            }
            VStack(spacing: 0) {
                HStack {
                    Spacer(minLength: 0)
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text(Self.timeOnlyFormatter.string(from: context.date))
                            .font(.system(size: timeLabelFontSize, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.92))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .frame(maxWidth: 88, alignment: .trailing)
                }
                .padding(.leading, timeLabelPaddingLeading)
                .padding(.trailing, timeLabelPaddingTrailing)
                .padding(.top, timeLabelTopPadding)
                .offset(x: timeLabelOffsetX, y: timeLabelOffsetY)

                Spacer(minLength: 0)

                Image("WatchS10MicButton")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 85, height: 85)
                    .accessibilityLabel("麦克风")
                    .padding(.bottom, 0)
                    .offset(y: -26)
            }

            if showsTitle, !titleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack {
                    ZStack {
                        if let titleFrameAssetName {
                            Image(titleFrameAssetName)
                                .resizable()
                                .scaledToFit()
                        } else {
                            Capsule()
                                .fill(Color.black.opacity(0.14))
                                .overlay(
                                    Capsule()
                                        .stroke(Color.white.opacity(0.14), lineWidth: 0.6)
                                )
                        }

                        Text(titleText)
                            .font(.system(size: watchPreviewTitleFontSize, weight: .semibold, design: .rounded))
                            .tracking(watchPreviewTitleTracking)
                            .foregroundStyle(titleForegroundColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.48)
                            .padding(.horizontal, watchPreviewTitleBadgeMetrics.horizontalPadding * watchPreviewTitleBadgeScale)
                            .padding(.vertical, watchPreviewTitleBadgeMetrics.verticalPadding * watchPreviewTitleBadgeScale)
                    }
                    .frame(
                        width: watchPreviewTitleBadgeMetrics.minWidth * watchPreviewTitleBadgeScale,
                        height: watchPreviewTitleBadgeMetrics.height * watchPreviewTitleBadgeScale
                    )
                    .offset(y: 18)

                    Spacer(minLength: 0)
                }
            }

            complicationSlotsAxisLayer
        }
    }

    /// 三角槽：外接正方形三只角点落槽；尺寸/位置可由 `complicationSlotsRadialScale` 与 offset 微调。
    private var complicationSlotsAxisLayer: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let sh = WatchS10PreviewGeometry.complicationSlotCornerHalfExtent(screenWidth: w, screenHeight: h) * complicationSlotsRadialScale
            let cx = w / 2 + complicationSlotsOffsetX
            let cy = h / 2 + complicationSlotsOffsetY
            let rect = CGRect(x: cx - sh, y: cy - sh, width: 2 * sh, height: 2 * sh)

            ZStack {
                if showComplicationSlotsBoundingRect {
                    Path { p in
                        p.addRect(rect)
                    }
                    .stroke(
                        Color.cyan.opacity(0.78),
                        style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [5, 4])
                    )
                    .allowsHitTesting(false)
                }
                cornerSlot(position: .topLeft)
                    .position(x: rect.minX, y: rect.minY)
                cornerSlot(position: .bottomLeft)
                    .position(x: rect.minX, y: rect.maxY)
                cornerSlot(position: .bottomRight)
                    .position(x: rect.maxX, y: rect.maxY)
            }
            .frame(width: w, height: h)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 表镜局部：**frame** = 黄绿闭合矩形。几何上 `opticalCross*` 半长很大，与 `safeBounds` 求交后尺寸常被安全区「顶满」；横向/竖向 **scale** 在求交之后施加，滑块才能改变可见长宽。
    private var screenCenterCrosshairLayer: some View {
        GeometryReader { g in
            let w = g.size.width
            let h = g.size.height
            let hh = WatchS10PreviewGeometry.opticalCrossHorizontalHalfExtent(screenWidth: w, screenHeight: h)
            let vh = WatchS10PreviewGeometry.opticalCrossVerticalHalfExtent(screenWidth: w, screenHeight: h)
            let cx0 = w / 2 + opticalFrameCenterOffsetX
            let cy0 = h / 2 + opticalFrameCenterOffsetY
            let frameRect = CGRect(x: cx0 - hh, y: cy0 - vh, width: 2 * hh, height: 2 * vh)
            let frameLineWidth: CGFloat = 1.5
            let safeBounds = WatchS10PreviewGeometry.opticalCrossDrawableSafeBounds(screenWidth: w, screenHeight: h)
            let clipped = frameRect.intersection(safeBounds)
            let anchor = CGPoint(x: clipped.midX, y: clipped.midY)
            let sw = max(0, clipped.width * opticalFrameHorizontalHalfScale)
            let sh = max(0, clipped.height * opticalFrameVerticalHalfScale)
            let drawRect = CGRect(x: anchor.x - sw * 0.5, y: anchor.y - sh * 0.5, width: sw, height: sh)
                .intersection(safeBounds)
            let cx = drawRect.midX
            let cy = drawRect.midY
            ZStack {
                if drawRect.width > frameLineWidth + 2, drawRect.height > frameLineWidth + 2 {
                    Path { p in
                        p.move(to: CGPoint(x: cx, y: drawRect.minY))
                        p.addLine(to: CGPoint(x: cx, y: drawRect.maxY))
                        p.move(to: CGPoint(x: drawRect.minX, y: cy))
                        p.addLine(to: CGPoint(x: drawRect.maxX, y: cy))
                    }
                    .stroke(BolaTheme.accent.opacity(0.9), lineWidth: 0.75)
                    Circle()
                        .fill(BolaTheme.accent.opacity(0.95))
                        .frame(width: 4, height: 4)
                        .position(x: cx, y: cy)
                    let lw = frameLineWidth
                    let r = drawRect.insetBy(dx: lw * 0.5, dy: lw * 0.5)
                    if r.width > 0, r.height > 0 {
                        Path { p in
                            p.move(to: CGPoint(x: r.minX, y: r.minY))
                            p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
                            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
                            p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
                            p.closeSubpath()
                        }
                        .stroke(BolaTheme.accent.opacity(0.95), style: StrokeStyle(lineWidth: lw, lineJoin: .miter))
                    }
                }
            }
        }
    }

    private func cornerSlot(position: WatchFaceSlotPosition) -> some View {
        let kind = slots.kind(at: position)
        let d = WatchS10PreviewGeometry.complicationSlotCellWidth * complicationContentScale
        let guideD = d * complicationGuideCircleScale
        let iconSize: CGFloat = (kind == .weather ? 11 : 12) * complicationContentScale
        let stickerImageSize = 29 * complicationContentScale * kind.stickerSlotScaleMultiplier

        let filledContent = VStack(spacing: kind == .stickerHeart ? 2 : 1) {
            if kind == .stickerHeart {
                Text(heartRateText)
                    .font(.system(size: max(7, 6 * complicationContentScale), weight: .bold))
                    .foregroundStyle(Color.red.opacity(0.72))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .offset(y: 6)
            }

            Group {
                if let stickerAssetName = kind.stickerAssetName {
                    Image(stickerAssetName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: stickerImageSize, height: stickerImageSize)
                } else if kind == .weather, !weatherSystemImageName.isEmpty {
                    Image(systemName: weatherSystemImageName)
                        .font(.system(size: iconSize, weight: .semibold))
                } else {
                    Image(systemName: Self.symbolName(for: kind))
                        .font(.system(size: iconSize, weight: .semibold))
                }
            }
            .foregroundStyle(Color.white.opacity(0.92))
            if kind.stickerAssetName == nil {
                Text(valueLine(for: kind))
                    .font(.system(size: 6, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                    .minimumScaleFactor(0.35)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: d - 8)
            }
        }
        .padding(.vertical, kind == .stickerHeart ? 2 : 4)

        return Group {
            if isEditingSlots {
                ZStack {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                        .background(Circle().fill(Color.white.opacity(0.07)))
                    if kind == .none {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.32))
                    } else {
                        filledContent
                    }
                }
                .frame(width: d, height: d)
                .dropDestination(for: String.self) { items, _ in
                    guard let raw = items.first, let k = WatchFaceComplicationKind(rawValue: raw) else { return false }
                    slots.set(position, kind: k)
                    return true
                }
            } else if kind != .none {
                ZStack {
                    if showComplicationSlotGuideCircles {
                        Circle()
                            .stroke(Color.cyan.opacity(0.9), lineWidth: 1.5)
                            .background(
                                Circle()
                                    .fill(Color.cyan.opacity(0.08))
                            )
                            .frame(width: guideD, height: guideD)
                    }
                    filledContent
                }
                .frame(width: d, height: d)
                .contentShape(Circle())
                .onTapGesture {
                    onTapPlacedSlot?(position, kind)
                }
            } else if showComplicationSlotGuideCircles {
                Circle()
                    .stroke(Color.cyan.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .background(
                        Circle()
                            .fill(Color.cyan.opacity(0.06))
                    )
                    .frame(width: guideD, height: guideD)
            } else {
                EmptyView()
            }
        }
    }

    private func valueLine(for kind: WatchFaceComplicationKind) -> String {
        switch kind {
        case .none: return " "
        case .heartRate: return heartRateText
        case .weather: return weatherTempText
        case .steps: return stepsText
        case .stickerApple, .stickerBottle, .stickerHeart, .stickerBola, .stickerBadge:
            return " "
        }
    }

    private static func symbolName(for kind: WatchFaceComplicationKind) -> String {
        switch kind {
        case .none: return "plus"
        case .heartRate: return "heart.fill"
        case .weather: return "cloud.sun.fill"
        case .steps: return "figure.walk"
        case .stickerApple, .stickerBottle, .stickerHeart, .stickerBola, .stickerBadge:
            return "circle.fill"
        }
    }
}

#Preview {
    WatchS10MockupView(
        slots: .constant(.default),
        heartRateText: "72",
        stepsText: "4021",
        weatherSystemImageName: "cloud.sun.fill",
        weatherTempText: "22°",
        showScreenCenterCrosshair: true,
        isEditingSlots: true
    )
    .padding()
    .background(Color(.systemGroupedBackground))
}
