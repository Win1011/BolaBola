//
//  IOSLifeSubPage.swift
//

import Foundation

enum IOSLifeSubPage: Int, CaseIterable, Identifiable, Hashable {
    case dailyLife = 0
    case timeMoments = 1

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .dailyLife: return "生活"
        case .timeMoments: return "时光"
        }
    }
}
