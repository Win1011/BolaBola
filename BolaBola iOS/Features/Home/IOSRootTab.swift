//
//  IOSRootTab.swift
//  根级 `TabView` 选中值。第四项在 UI 上为「对话」，仍使用 `TabRole.search` 以获得系统圆形 Tab 样式（公开 API 暂无 `TabRole.chat`，见 [TabRole.search](https://developer.apple.com/documentation/swiftui/tabrole/search)）。
//

import Foundation

enum IOSRootTab: Int, CaseIterable, Hashable {
    case life = 0
    case status = 1
    case mine = 2
    /// 对话：与 `role: .search` 配对以使用圆形样式，语义上为对话而非搜索。
    case chat = 3

    var accessibilityTitle: String {
        switch self {
        case .life: return "生活"
        case .status: return "状态"
        case .mine: return "我的"
        case .chat: return "对话"
        }
    }
}
