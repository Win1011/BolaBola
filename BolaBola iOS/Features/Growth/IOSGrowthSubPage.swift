//
//  IOSGrowthSubPage.swift
//  成长 Tab 内分段：成长主内容 / 时光（与生活 Tab 的 生活/时光 结构对应）。
//

import Foundation

enum IOSGrowthSubPage: Int, CaseIterable, Identifiable, Hashable {
    case growth = 0
    case timeMoments = 1

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .growth: return "成长"
        case .timeMoments: return "时光"
        }
    }
}
