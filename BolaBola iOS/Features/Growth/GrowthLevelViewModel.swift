
//
//  GrowthLevelViewModel.swift
//  从 BolaGrowthState 计算等级/XP/能力，监听通知实时刷新。
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class GrowthLevelViewModel: ObservableObject {
    static let shared = GrowthLevelViewModel()

    @Published private(set) var level: Int = 1
    @Published private(set) var xpInLevel: Int = 0
    @Published private(set) var xpForNextLevel: Int = 20
    @Published private(set) var totalXP: Int = 0
    @Published private(set) var capabilities: BolaLevelGate.Capabilities = .init(level: 1)

    private var observer: NSObjectProtocol?

    init() {
        refresh()
        observer = NotificationCenter.default.addObserver(
            forName: .bolaGrowthStateDidChange,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    deinit {
        if let obs = observer { NotificationCenter.default.removeObserver(obs) }
    }

    func refresh() {
        let state = BolaGrowthStore.load()
        let (lvl, rem) = BolaLevelFormula.levelAndRemainder(fromTotalXP: state.totalXP)
        level = lvl
        xpInLevel = rem
        xpForNextLevel = BolaLevelFormula.xpRequired(forLevel: min(lvl, BolaLevelFormula.maxLevel))
        totalXP = state.totalXP
        capabilities = BolaLevelGate.Capabilities(level: lvl)
    }
}
