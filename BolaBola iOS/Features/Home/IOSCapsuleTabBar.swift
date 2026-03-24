//
//  IOSCapsuleTabBar.swift
//

import SwiftUI

enum IOSMainTab: Int, CaseIterable {
    case analysis = 0
    case home = 1
    case chat = 2

    static var tabBarOrder: [IOSMainTab] { [.analysis, .home, .chat] }

    var accessibilityTitle: String {
        switch self {
        case .analysis: return "分析"
        case .home: return "主界面"
        case .chat: return "对话"
        }
    }

    var systemImage: String {
        switch self {
        case .analysis: return "chart.bar.xaxis"
        case .home: return "house.fill"
        case .chat: return "bubble.left.and.bubble.right.fill"
        }
    }
}

private enum TabBarMetrics {
    /// 单列最小高度（≥44pt 建议值，整体视觉更扁）
    static let rowMinHeight: CGFloat = 52
    /// 选中圆形直径
    static let selectedDiameterHome: CGFloat = 48
    static let selectedDiameterSide: CGFloat = 44
}

struct IOSCapsuleTabBar: View {
    @Binding var selection: IOSMainTab

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                // Liquid Glass（iOS 26+）：默认 .regular + Capsule，与系统 Tab/工具栏一致
                tabButtons
                    .padding(.horizontal, 6)
                    .padding(.vertical, 6)
                    .glassEffect()
            } else {
                tabButtons
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background {
                        Capsule()
                            .fill(Color(uiColor: .secondarySystemBackground))
                    }
                    .overlay {
                        Capsule()
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    }
                    .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 3)
            }
        }
    }

    private var tabButtons: some View {
        HStack(spacing: 0) {
            ForEach(IOSMainTab.tabBarOrder, id: \.rawValue) { tab in
                let on = selection == tab
                let isHome = tab == .home
                let disc: CGFloat = isHome ? TabBarMetrics.selectedDiameterHome : TabBarMetrics.selectedDiameterSide

                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        selection = tab
                    }
                } label: {
                    ZStack {
                        if on {
                            Circle()
                                .fill(BolaTheme.accent)
                                .frame(width: disc, height: disc)
                                .shadow(color: BolaTheme.accent.opacity(0.28), radius: 4, x: 0, y: 1)
                        }

                        Image(systemName: tab.systemImage)
                            .font(iconFont(tab: tab, selected: on))
                            .foregroundStyle(on ? BolaTheme.onAccentForeground : .secondary)
                            .symbolRenderingMode(.hierarchical)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: TabBarMetrics.rowMinHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.accessibilityTitle)
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
        }
    }

    private func iconFont(tab: IOSMainTab, selected: Bool) -> Font {
        if selected {
            return tab == .home
                ? .system(size: 22, weight: .semibold)
                : .system(size: 21, weight: .semibold)
        }
        return .system(size: 20, weight: .semibold)
    }
}
