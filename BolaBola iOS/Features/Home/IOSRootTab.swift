//
//  IOSRootTab.swift
//  根级 `TabView` 选中值。第四项在 UI 上为「对话」，仍使用 `TabRole.search` 以获得系统圆形 Tab 样式（公开 API 暂无 `TabRole.chat`，见 [TabRole.search](https://developer.apple.com/documentation/swiftui/tabrole/search)）。
//

import Foundation

enum IOSRootTab: Int, CaseIterable, Hashable {
    /// 主界面：模拟表盘、陪伴值与表盘配置（底栏第一项）。
    case mine = 0
    /// 成长：游戏化与任务（底栏第二项；视图仍为 `IOSStatusView` 占位，待替换为成长页）。
    case status = 1
    /// 生活：数据、提醒、记录与时光（底栏第三项）。
    case life = 2
    /// 对话：与 `role: .search` 配对以使用圆形样式，语义上为对话而非搜索。
    case chat = 3

    var accessibilityTitle: String {
        switch self {
        case .mine: return "主界面"
        case .status: return "成长"
        case .life: return "生活"
        case .chat: return "对话"
        }
    }
}
