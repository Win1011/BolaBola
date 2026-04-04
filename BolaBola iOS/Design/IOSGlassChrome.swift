//
//  IOSGlassChrome.swift
//  液态玻璃相关控件（与官方文档一致时优先系统样式）：
//  - [Landmarks: Building an app with Liquid Glass](https://developer.apple.com/documentation/swiftui/landmarks-building-an-app-with-liquid-glass)
//  - [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)
//  - [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)
//  圆形 / 玻璃按钮：
//  - iOS 26+ 导航栏：`ToolbarItem` 外已有 NavigationStack 的 Liquid Glass **一层**底，
//    再套 `.glass` 易叠成「外圈圆角矩形 + 内圈圆」。此处用 `.borderless`，玻璃外形交给系统。
//  - 其他场景 / 低版本：`IOSGlassCircleButtonStyle`（自绘圆 + glassEffect / 磨砂）。
//

import SwiftUI
import UIKit

// MARK: - 导航栏 SF Symbol 按钮（系统圆玻璃）

/// 导航栏图标按钮：iOS 26+ 仅用 borderless，避免与导航栏系统玻璃重复套层。
struct IOSNavigationGlassIconButton: View {
    let systemName: String
    var font: Font = .system(size: 17, weight: .semibold)
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                Button(action: action) {
                    Image(systemName: systemName)
                        .font(font)
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(Color(UIColor.label))
                }
                .buttonStyle(.borderless)
            } else {
                Button(action: action) {
                    Image(systemName: systemName)
                        .font(font)
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(Color(UIColor.label))
                }
                .buttonStyle(IOSGlassCircleButtonStyle())
            }
        }
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - 生活页主色胶囊按钮：黑底圆 + 白「+」

/// 用于黄底 `Capsule` 上的 leading 图标（与单色 `plus` 区分）。
struct LifeAccentChromePlusIcon: View {
    private let circleSize: CGFloat = 16

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black)
                .frame(width: circleSize, height: circleSize)
            Image(systemName: "plus")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - 滚动边缘「液态口袋」（仅作用于 ScrollView，不是胶囊控件）

/// Apple 的 **`scrollEdgeEffectStyle`** 只作用于**子树里的 `ScrollView`** 在滚动到顶/底时的边缘（见 [scrollEdgeEffectStyle](https://developer.apple.com/documentation/swiftui/view/scrolledgeeffectstyle(_:for:))）。
/// 根 **`IOSRootView`** 使用系统 **`TabView`** 时，底栏与切换动效由系统提供（见 [Landmarks: Building an app with Liquid Glass](https://developer.apple.com/documentation/swiftui/landmarks-building-an-app-with-liquid-glass)）；`scrollEdgeEffectStyle` 仍作用于各页内 **`ScrollView`**。
/// 顶/底均用 **`.automatic`**，与导航栏侧滚动边缘观感一致；根级 `bolaRootTabScrollEdgeStyles()` 与各单列上的本 modifier 可叠加以统一风格。
private struct BolaScrollEdgeLiquidGlassModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .scrollEdgeEffectStyle(.automatic, for: .bottom)
                .scrollEdgeEffectStyle(.automatic, for: .top)
        } else {
            content
        }
    }
}

/// 挂在 **根容器**（如 `IOSRootView` 的 `ZStack`）上，让各页内 **`ScrollView`** 统一继承滚动边缘样式。
private struct BolaRootTabScrollEdgeStylesModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .scrollEdgeEffectStyle(.automatic, for: .bottom)
                .scrollEdgeEffectStyle(.automatic, for: .top)
        } else {
            content
        }
    }
}

extension View {
    /// 单列 `ScrollView` 上可选叠加（若根级已加 `bolaRootTabScrollEdgeStyles` 可不再调用）。
    func bolaScrollEdgeLiquidGlassMainContent() -> some View {
        modifier(BolaScrollEdgeLiquidGlassModifier())
    }

    func bolaRootTabScrollEdgeStyles() -> some View {
        modifier(BolaRootTabScrollEdgeStylesModifier())
    }
}

// MARK: - 通用圆形（非导航栏或旧系统）

struct IOSGlassCircleButtonStyle: ButtonStyle {
    private let side: CGFloat = 44

    func makeBody(configuration: Configuration) -> some View {
        iosGlassLabel(configuration)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }

    @ViewBuilder
    private func iosGlassLabel(_ configuration: Configuration) -> some View {
        let core = ZStack {
            Color.clear
                .frame(width: side, height: side)
            configuration.label
        }
        .frame(width: side, height: side)

        if #available(iOS 26.0, *) {
            core
                .glassEffect(.regular.interactive(), in: Circle())
        } else {
            core
                .background {
                    Circle()
                        .fill(.ultraThinMaterial)
                }
                .clipShape(Circle())
                .shadow(color: Color.black.opacity(0.12), radius: 7, x: 0, y: 4)
        }
    }
}
