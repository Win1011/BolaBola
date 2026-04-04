//
//  WatchS10PreviewGeometry.swift
//  iPhone 表盘预览图 `WatchS10Full` 与表镜叠层的统一几何锚点（光学中心）。
//  自定义组件、表盘上方装饰等均以本文件中的中心与表镜矩形为准，避免各处硬编码分叉。
//

import CoreGraphics

/// `Assets.xcassets` 中 `WatchS10Full` 的归一化几何与已标定的「表镜光学中心」。
/// 坐标系：与 `Image("WatchS10Full").resizable().scaledToFit()` 在父布局中给出的 **整图** 像素尺寸一致（`width`×`height`）。
enum WatchS10PreviewGeometry {

    /// 资源逻辑像素（与切图一致，用于文档与比例换算）。
    static let assetLogicalSize = CGSize(width: 270, height: 297)

    /// 黑屏区域相对整图的归一化外接框（未含光学中心微调）。
    /// 与 `WatchS10Full` 切图里黑玻璃对齐（已标定）。
    static let screenRectInFull = CGRect(
        x: 54.0 / 270.0,
        y: 39.0 / 297.0,
        width: 191.0 / 270.0,
        height: 273.0 / 297.0
    )

    /// 相对 `screenRectInFull` **几何中心** 的校准比例（量纲为表镜局部宽/高）。
    /// 真机黑玻璃的视觉中心与矩形几何中心不完全重合，以下为已确认的标定值；**勿在业务视图里再抄一套数字**。
    static let opticalCenterShiftXFractionOfScreen: CGFloat = -0.079
    static let opticalCenterShiftYFractionOfScreen: CGFloat = -1.0 / 8.0

    /// 表镜圆角（与 `WatchS10MockupView` 蒙版一致）。
    static func screenCornerRadius(sw: CGFloat, sh: CGFloat) -> CGFloat {
        min(sw, sh) * 0.22
    }

    /// 主 frame 与蒙版求交时用的轴对齐安全矩形（略小于 `0…w × 0…h`），避免描边被圆角裁切。
    /// **竖向边距小于横向**：若与横向相同，`opticalCrossFrameRect` 会过早与「安全区」**等高**，之后调 `opticalCrossVerticalExtentMultiplier` 高度不再变化（交集高度被顶死）。
    static func opticalCrossDrawableSafeBounds(screenWidth w: CGFloat, screenHeight h: CGFloat) -> CGRect {
        let cornerR = screenCornerRadius(sw: w, sh: h)
        let padX = max(4, cornerR * 0.35)
        // 竖向越小 → 安全区高度越大；过小可能贴圆角裁切，可略回调。
        let padY = max(0.5, cornerR * 0.06)
        return CGRect(
            x: padX,
            y: padY,
            width: max(0, w - 2 * padX),
            height: max(0, h - 2 * padY)
        )
    }

    /// 整图坐标系中的表镜轴对齐外接矩形（未平移光学中心）。
    static func screenRectInFullImage(width: CGFloat, height: CGFloat) -> CGRect {
        let r = screenRectInFull
        let sx = r.origin.x * width
        let sy = r.origin.y * height
        let sw = r.size.width * width
        let sh = r.size.height * height
        return CGRect(x: sx, y: sy, width: sw, height: sh)
    }

    /// 整图坐标系中的 **光学中心**（表盘视觉上认定的中心点；时间与三角槽布局均相对此点收敛）。
    static func opticalScreenCenterInFullImage(width: CGFloat, height: CGFloat) -> CGPoint {
        let rect = screenRectInFullImage(width: width, height: height)
        let sw = rect.width
        let sh = rect.height
        let cx = rect.midX + opticalCenterShiftXFractionOfScreen * sw
        let cy = rect.midY + opticalCenterShiftYFractionOfScreen * sh
        return CGPoint(x: cx, y: cy)
    }

    /// 表镜叠层 `.position(x:y:)` 所用中心（与 `opticalScreenCenterInFullImage` 相同）。
    static func screenOverlayPositionInFullImage(width: CGFloat, height: CGFloat) -> CGPoint {
        opticalScreenCenterInFullImage(width: width, height: height)
    }

    // MARK: - 光学十字（预览叠层调参入口）

    /// **调横线长度**：改此方法体。值为从光学中心向 **左/右** 各延伸的半长（表镜局部坐标）。
    static func opticalCrossHorizontalHalfExtent(screenWidth w: CGFloat, screenHeight h: CGFloat) -> CGFloat {
        baselineOpticalCrossHalfExtent(screenWidth: w, screenHeight: h)
    }

    /// **调竖线长度 / frame 高度**：默认在 `baseline` 上乘 `opticalCrossVerticalExtentMultiplier`；也可改方法体写死公式。
    static func opticalCrossVerticalHalfExtent(screenWidth w: CGFloat, screenHeight h: CGFloat) -> CGFloat {
        baselineOpticalCrossHalfExtent(screenWidth: w, screenHeight: h) * opticalCrossVerticalExtentMultiplier
    }

    /// 横/竖不等长时，较长一侧的「整段线长」（用于槽位与十字联动的保守尺度）。
    static func opticalCrossSegmentLength(screenWidth w: CGFloat, screenHeight h: CGFloat) -> CGFloat {
        2 * max(
            opticalCrossHorizontalHalfExtent(screenWidth: w, screenHeight: h),
            opticalCrossVerticalHalfExtent(screenWidth: w, screenHeight: h)
        )
    }

    private static func baselineOpticalCrossHalfExtent(screenWidth w: CGFloat, screenHeight h: CGFloat) -> CGFloat {
        let segmentLen = w >= h
            ? h + (w - h) * 0.38
            : w + (h - w) * 0.38
        return segmentLen / 2
    }

    /// 主 frame **高度**（竖线半长）相对 `baseline` 的倍数；要再变长/变短只改这里。
    /// 若调大却看不出变高：多半是 `drawRect = frameRect ∩ opticalCrossDrawableSafeBounds` 已在竖向顶满，见 `opticalCrossDrawableSafeBounds` 的 `padY`。
    private static let opticalCrossVerticalExtentMultiplier: CGFloat = 8

    /// 光学十字 **外接矩形**（横线/竖线端点落在四条边上；预览里与主题色「绿线」共边）。
    /// 表镜局部坐标，中心为 `(w/2, h/2)`（光学中心）。后续自定义布局优先相对此 **主 frame** 对齐。
    static func opticalCrossFrameRect(screenWidth w: CGFloat, screenHeight h: CGFloat) -> CGRect {
        let cx = w / 2
        let cy = h / 2
        let hh = opticalCrossHorizontalHalfExtent(screenWidth: w, screenHeight: h)
        let vh = opticalCrossVerticalHalfExtent(screenWidth: w, screenHeight: h)
        return CGRect(x: cx - hh, y: cy - vh, width: 2 * hh, height: 2 * vh)
    }

    /// 三角槽三只角所在轴对齐 **正方形**（表镜局部坐标，以光学中心为 `screenLabels` 的 `(w/2, h/2)`）。
    /// 边长为 `2 * complicationSlotCornerHalfExtent`；槽位图标中心落在外接正方形的三只角点上。
    static func complicationSlotsBoundingRect(screenWidth w: CGFloat, screenHeight h: CGFloat) -> CGRect {
        let cx = w / 2
        let cy = h / 2
        let sh = complicationSlotCornerHalfExtent(screenWidth: w, screenHeight: h)
        return CGRect(x: cx - sh, y: cy - sh, width: 2 * sh, height: 2 * sh)
    }

    /// 三角槽中心相对光学中心的半偏移（左上/左下/右下仍与坐标轴对齐）。
    /// **调槽离中心远近**：改 `fromCrossRatio` / `capShortSideFraction`（取较小值防贴圆角裁切）。
    static func complicationSlotCornerHalfExtent(screenWidth w: CGFloat, screenHeight h: CGFloat) -> CGFloat {
        let crossHalf = max(
            opticalCrossHorizontalHalfExtent(screenWidth: w, screenHeight: h),
            opticalCrossVerticalHalfExtent(screenWidth: w, screenHeight: h)
        )
        let fromCross = crossHalf * complicationSlotCornerFromCrossRatio
        let cap = min(w, h) * complicationSlotCornerCapShortSideFraction
        return min(fromCross, cap)
    }

    private static let complicationSlotCornerFromCrossRatio: CGFloat = 0.78
    private static let complicationSlotCornerCapShortSideFraction: CGFloat = 0.27

    /// 单个槽位外接框（与圆直径一致，便于角点与圆心对齐）。
    static let complicationSlotCellWidth: CGFloat = 44
    static let complicationSlotCellHeight: CGFloat = 44
}
