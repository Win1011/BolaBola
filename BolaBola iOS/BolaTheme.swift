//
//  BolaTheme.swift
//  iOS DesignTokens — 与 Documentation/design_core.md 一致。
//

import SwiftUI
import UIKit

public enum BolaTheme {
    /// #E5FF00
    public static let accent = Color(red: 229 / 255, green: 1, blue: 0)

    public static let surfaceElevated = Color(uiColor: .secondarySystemBackground)
    public static let surfaceCard = Color(uiColor: .tertiarySystemBackground)

    public static let cornerCard: CGFloat = 18
    public static let cornerCompact: CGFloat = 12
    public static let spacingSection: CGFloat = 24
    public static let spacingItem: CGFloat = 16
    public static let paddingHorizontal: CGFloat = 20

    /// 主色按钮上的文字（保证与 #E5FF00 对比度）
    public static let onAccentForeground = Color.black
}
