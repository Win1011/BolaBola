//
//  BolaTitleSelection.swift
//  称号选择：从 indexA/indexB 迁移为 wordIdA/wordIdB；支持旧格式读取兼容。
//

import CoreGraphics
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
    public var frameId: String
    public var showsOnWatchFace: Bool

    public init(
        wordIdA: String = "a_base_0",
        wordIdB: String = "b_base_0",
        frameId: String = TitleFrameBank.fallbackFrameId,
        showsOnWatchFace: Bool = true
    ) {
        self.wordIdA = wordIdA
        self.wordIdB = wordIdB
        self.frameId = frameId
        self.showsOnWatchFace = showsOnWatchFace
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
        case frameId
        case showsOnWatchFace
        case indexA, indexB  // 旧键
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let idA = try? c.decodeIfPresent(String.self, forKey: .wordIdA),
           let idB = try? c.decodeIfPresent(String.self, forKey: .wordIdB) {
            wordIdA = idA
            wordIdB = idB
            frameId = (try? c.decodeIfPresent(String.self, forKey: .frameId))
                ?? TitleFrameBank.fallbackFrameId
            showsOnWatchFace = (try? c.decodeIfPresent(Bool.self, forKey: .showsOnWatchFace))
                ?? true
        } else {
            // 旧格式迁移
            let ia = (try? c.decode(Int.self, forKey: .indexA)) ?? 0
            let ib = (try? c.decode(Int.self, forKey: .indexB)) ?? 0
            wordIdA = BolaTitlePhraseBank.legacyAIdToWordId(ia)
            wordIdB = BolaTitlePhraseBank.legacyBIdToWordId(ib)
            frameId = TitleFrameBank.fallbackFrameId
            showsOnWatchFace = true
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(wordIdA, forKey: .wordIdA)
        try c.encode(wordIdB, forKey: .wordIdB)
        try c.encode(frameId, forKey: .frameId)
        try c.encode(showsOnWatchFace, forKey: .showsOnWatchFace)
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
        let level = BolaLevelFormula.levelAndRemainder(fromTotalXP: BolaGrowthStore.load().totalXP).level
        let unlockedFrames = TitleFrameBank.unlockedFrames(forLevel: level)
        let validFrameId = unlockedFrames.contains(where: { $0.id == sel.frameId })
            ? sel.frameId
            : TitleFrameBank.highestUnlockedFrame(forLevel: level).id
        return BolaTitleSelection(
            wordIdA: validA,
            wordIdB: validB,
            frameId: validFrameId,
            showsOnWatchFace: sel.showsOnWatchFace
        )
    }
}

public struct TitleBadgeMetrics: Sendable {
    public let fontSize: CGFloat
    public let horizontalPadding: CGFloat
    public let verticalPadding: CGFloat
    public let height: CGFloat
    public let minWidth: CGFloat
    public let minimumScaleFactor: CGFloat

    public init(
        fontSize: CGFloat,
        horizontalPadding: CGFloat,
        verticalPadding: CGFloat,
        height: CGFloat,
        minWidth: CGFloat,
        minimumScaleFactor: CGFloat
    ) {
        self.fontSize = fontSize
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.height = height
        self.minWidth = minWidth
        self.minimumScaleFactor = minimumScaleFactor
    }

    public func scaled(
        width widthScale: CGFloat,
        height heightScale: CGFloat,
        font fontScale: CGFloat,
        horizontalPadding horizontalPaddingScale: CGFloat,
        verticalPadding verticalPaddingScale: CGFloat
    ) -> TitleBadgeMetrics {
        TitleBadgeMetrics(
            fontSize: fontSize * fontScale,
            horizontalPadding: horizontalPadding * horizontalPaddingScale,
            verticalPadding: verticalPadding * verticalPaddingScale,
            height: height * heightScale,
            minWidth: minWidth * widthScale,
            minimumScaleFactor: minimumScaleFactor
        )
    }
}

public enum TitleBadgeLayout {
    public static func metrics(compact: Bool) -> TitleBadgeMetrics {
        if compact {
            return TitleBadgeMetrics(
                fontSize: 12,
                horizontalPadding: 14,
                verticalPadding: 8,
                height: 40,
                minWidth: 92,
                minimumScaleFactor: 0.58
            )
        }
        return TitleBadgeMetrics(
            fontSize: 14,
            horizontalPadding: 18,
            verticalPadding: 10,
            height: 56,
            minWidth: 180,
            minimumScaleFactor: 0.58
        )
    }
}

public enum TitleBadgeScene: Sendable {
    case phoneWatchPreview
    case realWatch
}

public struct TitleBadgeSceneConfiguration: Sendable {
    public let box: TitleBadgeMetrics
    public let fontSizeUnder6: CGFloat
    public let fontSizeUnder8: CGFloat
    public let trackingUnder6: CGFloat

    public func fontSize(for text: String) -> CGFloat {
        let count = text.count
        if count < 6 { return fontSizeUnder6 }
        if count < 8 { return fontSizeUnder8 }
        return box.fontSize
    }

    public func tracking(for text: String) -> CGFloat {
        text.count < 6 ? trackingUnder6 : 0
    }
}

public enum TitleBadgeSizing {
    /// 真实手表当前采用的显示尺寸。后续如果你要调真实手表大小，优先改这里，
    /// 手机表盘预览会按相对比例自动跟随。
    private static let realWatchReference = TitleBadgeMetrics(
        fontSize: 8.29,
        horizontalPadding: 9.22,
        verticalPadding: 1.84,
        height: 24.88,
        minWidth: 106.91,
        minimumScaleFactor: 0.48
    )

    private static let phonePreviewRelativeToWatch = (
        width: CGFloat(102.6 / 111.36),
        height: CGFloat(31.92 / 25.92),
        font: CGFloat(7.98 / 8.64),
        horizontalPadding: CGFloat(10.26 / 9.6),
        verticalPadding: CGFloat(5.7 / 1.92)
    )

    public static func configuration(for scene: TitleBadgeScene) -> TitleBadgeSceneConfiguration {
        switch scene {
        case .realWatch:
            return TitleBadgeSceneConfiguration(
                box: realWatchReference,
                fontSizeUnder6: 8.64,
                fontSizeUnder8: 8.45,
                trackingUnder6: 0.25
            )
        case .phoneWatchPreview:
            return TitleBadgeSceneConfiguration(
                box: realWatchReference.scaled(
                    width: phonePreviewRelativeToWatch.width,
                    height: phonePreviewRelativeToWatch.height,
                    font: phonePreviewRelativeToWatch.font,
                    horizontalPadding: phonePreviewRelativeToWatch.horizontalPadding,
                    verticalPadding: phonePreviewRelativeToWatch.verticalPadding
                ),
                fontSizeUnder6: 9,
                fontSizeUnder8: 8.5,
                trackingUnder6: 0.25
            )
        }
    }
}
