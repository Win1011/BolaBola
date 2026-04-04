//
//  BolaTitleSelection.swift
//  斯普拉遁式称号：A + B 两段词库与当前选择（双端共享）。
//

import Foundation

public enum BolaTitlePhraseBank: Sendable {
    public static let groupA: [String] = [
        "路过的", "认真的", "熬夜的", "爱喝水的", "正在减肥的", "随缘的", "元气满满的", "低调的"
    ]

    public static let groupB: [String] = [
        "打工人", "大学生", "夜猫子", "运动健将", "摸鱼选手", "养生党", "铲屎官", "干饭人"
    ]
}

public struct BolaTitleSelection: Codable, Equatable, Sendable {
    public var indexA: Int
    public var indexB: Int

    public init(indexA: Int = 0, indexB: Int = 0) {
        self.indexA = max(0, indexA)
        self.indexB = max(0, indexB)
    }

    public func resolvedLine() -> String {
        let ga = BolaTitlePhraseBank.groupA
        let gb = BolaTitlePhraseBank.groupB
        let a = indexA >= 0 && indexA < ga.count ? ga[indexA] : (ga.first ?? "")
        let b = indexB >= 0 && indexB < gb.count ? gb[indexB] : (gb.first ?? "")
        let t = "\(a)\(b)"
        return t.isEmpty ? "—" : t
    }
}

public enum BolaTitleSelectionStore {
    private static let defaultsKey = "bola_title_selection_v1"

    public static func load() -> BolaTitleSelection {
        let d = BolaSharedDefaults.resolved()
        guard let data = d.data(forKey: defaultsKey),
              let s = try? JSONDecoder().decode(BolaTitleSelection.self, from: data) else {
            return BolaTitleSelection()
        }
        return s
    }

    public static func save(_ selection: BolaTitleSelection) {
        let d = BolaSharedDefaults.resolved()
        if let data = try? JSONEncoder().encode(selection) {
            d.set(data, forKey: defaultsKey)
        }
    }

    public static func clamped(_ selection: BolaTitleSelection) -> BolaTitleSelection {
        let maxA = max(BolaTitlePhraseBank.groupA.count - 1, 0)
        let maxB = max(BolaTitlePhraseBank.groupB.count - 1, 0)
        return BolaTitleSelection(
            indexA: min(selection.indexA, maxA),
            indexB: min(selection.indexB, maxB)
        )
    }
}
