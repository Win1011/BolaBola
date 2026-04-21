//
//  Color+Hex.swift
//  用法：Color(hex: 0xFF6164)  或  Color(hex: 0xFF6164, opacity: 0.8)
//

import SwiftUI

extension Color {
    /// 从 24-bit 十六进制整数初始化颜色，例如 Color(hex: 0xFF6164)。
    init(hex: UInt32, opacity: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8)  & 0xFF) / 255.0
        let b = Double(hex         & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, opacity: opacity)
    }
}
