//
//  BolaTheme.swift
//  iOS DesignTokens — 与 Documentation/design_core.md 一致。
//

import SwiftUI
import UIKit

public enum BolaTheme {
    /// #E5FF00（与 `AccentColor`、`Documentation/design_core.md` 一致）
    public static let accent = Color(red: 229 / 255, green: 1, blue: 0)

    /// 页面分组底色（浅色下灰底），对应设计文档「表面 / 分组背景」
    public static let backgroundGrouped = Color(uiColor: .systemGroupedBackground)

    public static let surfaceElevated = Color(uiColor: .secondarySystemBackground)
    public static let surfaceCard = Color(uiColor: .tertiarySystemBackground)

    /// 气泡/高亮白层级（如对话气泡），浅色下接近白卡
    public static let surfaceBubble = Color(uiColor: .systemBackground)

    /// 主卡片圆角（分析页健康网格、提醒行等统一略加大，更接近参考图的大圆角卡片）
    public static let cornerCard: CGFloat = 22

    /// 生活 Tab 主卡片圆角（节奏条 / 提醒 / 记录格 / 时光行 / 今日区块等统一）
    public static let cornerLifePageCard: CGFloat = 22

    public static let cornerCompact: CGFloat = 14
    public static let spacingSection: CGFloat = 24
    public static let spacingItem: CGFloat = 16
    public static let paddingHorizontal: CGFloat = 20

    /// 主色按钮上的文字（保证与 #E5FF00 对比度）
    public static let onAccentForeground = Color.black

    /// Bola 占位剪影（与主色眼睛对比，固定深黑）
    public static let mascotSilhouette = Color.black.opacity(0.92)

    /// 列表/卡片左侧 SF Symbol，与「提醒」等行内图标一致（系统 tertiary，避免与健康数据强调色混用）
    public static let listRowIcon = Color(uiColor: .tertiaryLabel)

    // MARK: - 生活页渐变（仅用主色透明度叠在 `backgroundGrouped` 上，符合文档「淡黄绿晕影」）

    public static let accentGlowTopOpacity: Double = 0.22
    public static let accentGlowBottomOpacity: Double = 0.12

    // MARK: - 节奏条（主色 + 正文黑，不用游离 hex）

    /// 无样本/弱样本竖条
    public static let rhythmBarMuted = accent.opacity(0.2)
    /// 有样本主色竖条
    public static let rhythmBarStrong = accent.opacity(0.95)
    /// 低分位强调竖条（与正文对比一致）
    public static let rhythmBarContrast = Color.primary.opacity(0.88)

    // MARK: - 卡片投影（浅色）

    public static func cardShadowOpacity(bubbleMode: Bool) -> Double {
        bubbleMode ? 0.14 : 0.06
    }

    // MARK: - Figma 生活页（6068:3708）圆角与字色

    public static let cornerFigmaRhythm: CGFloat = cornerLifePageCard
    public static let cornerFigmaReminder: CGFloat = cornerLifePageCard
    public static let cornerFigmaLifeRecord: CGFloat = cornerLifePageCard

    /// 要点列表小字（#3e3e3e 量级）
    public static let figmaMutedBody = Color(red: 62 / 255, green: 62 / 255, blue: 62 / 255)
    /// 「和Bola聊聊」辅助字
    public static let figmaSubtleCaption = Color(red: 135 / 255, green: 136 / 255, blue: 125 / 255)
}

