//
//  HomeWatchFaceLayout.swift
//  主界面手表预览的「表盘式」布局预设；与 AppStorage 字符串 rawValue 对应，便于后续扩展小组件落位。
//

import Foundation

enum HomeWatchFaceLayout: String, CaseIterable, Identifiable {
    /// 仅中央陪伴值（默认）
    case minimal
    /// 上/下分区，适合多模块
    case modular
    /// 四角预留小组件位
    case corners
    /// 中心大面积组件位
    case focus

    var id: String { rawValue }

    var title: String {
        switch self {
        case .minimal: return "简洁"
        case .modular: return "模块化"
        case .corners: return "四角"
        case .focus: return "聚焦"
        }
    }

    var subtitle: String {
        switch self {
        case .minimal: return "仅显示陪伴值"
        case .modular: return "上下分区"
        case .corners: return "四角预留位"
        case .focus: return "中心突出区域"
        }
    }

    static let appStorageKey = "bola_ios_home_watch_face_layout"
}
