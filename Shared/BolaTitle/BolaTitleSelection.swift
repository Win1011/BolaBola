//
//  BolaTitleSelection.swift
//  称号选择：从 indexA/indexB 迁移为 wordIdA/wordIdB；支持旧格式读取兼容。
//

import Foundation

public extension Notification.Name {
    /// 称号选择已持久化（与主界面成长页联动刷新）。
    static let bolaTitleSelectionDidChange = Notification.Name("bolaTitleSelectionDidChange")
}

// MARK: - 保留旧词库（向后兼容：旧 index → 新 ID 映射）

public enum BolaTitlePhraseBank: Sendable {
    public static let groupA: [String] = [
        "路过的", "认真的", "熬夜的", "爱喝水的", "正在减肥的", "随缘的", "元气满满的", "低调的"
    ]
    public static let groupB: [String] = [
        "打工人", "大学生", "夜猫子", "运动健将", "摸鱼选手", "养生党", "铲屎官", "干饭人"
    ]

    /// 旧 indexA → 新 word ID（对应 TitleWordBank 基础词）
    static func legacyAIdToWordId(_ index: Int) -> String {
        "a_base_\(max(0, min(index, groupA.count - 1)))"
    }
    static func legacyBIdToWordId(_ index: Int) -> String {
        "b_base_\(max(0, min(index, groupB.count - 1)))"
    }
}

// MARK: - 称号选择模型（新版：用 word ID）

public struct BolaTitleSelection: Codable, Equatable, Sendable {
    public var wordIdA: String
    public var wordIdB: String

    public init(wordIdA: String = "a_base_0", wordIdB: String = "b_base_0") {
        self.wordIdA = wordIdA
        self.wordIdB = wordIdB
    }

    public func resolvedLine() -> String {
        let a = TitleWordBank.word(id: wordIdA)?.text
            ?? BolaTitlePhraseBank.groupA.first ?? ""
        let b = TitleWordBank.word(id: wordIdB)?.text
            ?? BolaTitlePhraseBank.groupB.first ?? ""
        let t = "\(a)\(b)"
        return t.isEmpty ? "—" : t
    }

    // MARK: 旧格式兼容 Codable

    enum CodingKeys: String, CodingKey {
        case wordIdA, wordIdB
        case indexA, indexB  // 旧键
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let idA = try? c.decodeIfPresent(String.self, forKey: .wordIdA),
           let idB = try? c.decodeIfPresent(String.self, forKey: .wordIdB) {
            wordIdA = idA
            wordIdB = idB
        } else {
            // 旧格式迁移
            let ia = (try? c.decode(Int.self, forKey: .indexA)) ?? 0
            let ib = (try? c.decode(Int.self, forKey: .indexB)) ?? 0
            wordIdA = BolaTitlePhraseBank.legacyAIdToWordId(ia)
            wordIdB = BolaTitlePhraseBank.legacyBIdToWordId(ib)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(wordIdA, forKey: .wordIdA)
        try c.encode(wordIdB, forKey: .wordIdB)
    }
}

// MARK: - 持久化

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
            NotificationCenter.default.post(name: .bolaTitleSelectionDidChange, object: nil)
        }
    }

    /// 确保已选词 ID 在解锁列表中，否则重置为默认值。
    public static func validated() -> BolaTitleSelection {
        let sel = load()
        let unlocked = TitleUnlockStore.loadUnlockedIds()
        let validA = unlocked.contains(sel.wordIdA) ? sel.wordIdA : "a_base_0"
        let validB = unlocked.contains(sel.wordIdB) ? sel.wordIdB : "b_base_0"
        return BolaTitleSelection(wordIdA: validA, wordIdB: validB)
    }
}
