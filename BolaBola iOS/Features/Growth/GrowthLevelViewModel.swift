
//
//  GrowthLevelViewModel.swift
//  从 BolaGrowthState 计算等级/XP/能力，监听通知实时刷新。
//

import Combine
import Foundation
import SwiftUI

struct LevelUpRewardItem: Identifiable, Equatable {
    let id: String
    let iconSystemName: String
    let title: String
    let detail: String
}

struct LevelUpPresentation: Identifiable, Equatable {
    let id: String
    let fromLevel: Int
    let toLevel: Int
    let rewards: [LevelUpRewardItem]

    static func build(from fromLevel: Int, to toLevel: Int) -> LevelUpPresentation {
        let normalizedFrom = max(1, fromLevel)
        let normalizedTo = max(normalizedFrom, toLevel)
        let titleRewardLevels = titleRewardRange(from: normalizedFrom + 1, to: normalizedTo)
        let unlockedWords = wordsUnlocked(in: titleRewardLevels)
        let unlockedFrames = framesUnlocked(in: titleRewardLevels)
        let featureRewards = featureRewardsUnlocked(from: normalizedFrom + 1, to: normalizedTo)

        var rewards = featureRewards

        if !unlockedWords.isEmpty {
            let sample = unlockedWords.prefix(3).map(\.text).joined(separator: "、")
            rewards.append(
                LevelUpRewardItem(
                    id: "title_words",
                    iconSystemName: "text.badge.plus",
                    title: "称号词条增加 \(unlockedWords.count) 个",
                    detail: sample.isEmpty ? "可以去称号页挑新的组合。" : "新词条包括 \(sample)。"
                )
            )
        }

        if !unlockedFrames.isEmpty {
            let names = unlockedFrames.map(\.displayName).joined(separator: "、")
            rewards.append(
                LevelUpRewardItem(
                    id: "title_frames",
                    iconSystemName: "sparkles.rectangle.stack",
                    title: "称号边框已扩充",
                    detail: "新增 \(names) 边框，可以直接换上新的等级外观。"
                )
            )
        }

        if rewards.isEmpty {
            rewards.append(
                LevelUpRewardItem(
                    id: "growth",
                    iconSystemName: "arrow.up.forward.circle.fill",
                    title: "成长值继续提升",
                    detail: nextMilestoneHint(after: normalizedTo)
                )
            )
        }

        return LevelUpPresentation(
            id: "level_up_\(normalizedFrom)_\(normalizedTo)",
            fromLevel: normalizedFrom,
            toLevel: normalizedTo,
            rewards: rewards
        )
    }

    private static func titleRewardRange(from startLevel: Int, to endLevel: Int) -> ClosedRange<Int>? {
        guard startLevel <= endLevel, endLevel >= 3 else { return nil }

        // 称号系统在 Lv.3 才真正可用；首次跨到 Lv.3 时，把此前可见但不可用的 Lv.2 词条一起并入奖励。
        if startLevel <= 3 {
            return max(2, startLevel) ... endLevel
        }
        return startLevel ... endLevel
    }

    private static func wordsUnlocked(in levels: ClosedRange<Int>?) -> [TitleWord] {
        guard let levels else { return [] }
        return (TitleWordBank.poolA + TitleWordBank.poolB).filter { word in
            switch word.unlockCondition {
            case .level(let level):
                return levels.contains(level)
            default:
                return false
            }
        }
    }

    private static func framesUnlocked(in levels: ClosedRange<Int>?) -> [TitleFrameDefinition] {
        guard let levels else { return [] }
        return TitleFrameBank.all.filter { frame in
            levels.contains(frame.level)
        }
    }

    private static func featureRewardsUnlocked(from startLevel: Int, to endLevel: Int) -> [LevelUpRewardItem] {
        guard startLevel <= endLevel else { return [] }
        let unlockedLevels = Array(startLevel ... endLevel)
        var items: [LevelUpRewardItem] = []

        if unlockedLevels.contains(3) {
            items.append(
                LevelUpRewardItem(
                    id: "titles",
                    iconSystemName: "medal.star.fill",
                    title: "称号系统解锁",
                    detail: "现在可以搭配称号词条和边框，还能把称号显示在表盘上。"
                )
            )
        }

        if unlockedLevels.contains(5) {
            items.append(
                LevelUpRewardItem(
                    id: "personality",
                    iconSystemName: "face.smiling.inverse",
                    title: "新性格已开启",
                    detail: "Lv.5 起解锁傲娇性格，可以去设置里切换 Bola 的个性。"
                )
            )
        }

        if unlockedLevels.contains(10) {
            items.append(
                LevelUpRewardItem(
                    id: "hidden_dialogue",
                    iconSystemName: "bubble.left.and.sparkles.fill",
                    title: "隐藏对话池解锁",
                    detail: "之后聊天会出现更多稀有回应，互动内容也会更丰富。"
                )
            )
        }

        return items
    }

    private static func nextMilestoneHint(after level: Int) -> String {
        switch level {
        case ..<3:
            return "继续升到 Lv.3，就能开启称号系统。"
        case ..<5:
            return "继续升到 Lv.5，就能解锁新人格。"
        case ..<10:
            return "继续升到 Lv.10，会开启隐藏对话池。"
        case ..<15:
            return "继续升级还能拿到更高阶的称号边框。"
        default:
            return "继续成长，后面还有更高级的边框和称号组合等着你。"
        }
    }
}

@MainActor
final class GrowthLevelViewModel: ObservableObject {
    static let shared = GrowthLevelViewModel()

    @Published private(set) var level: Int = 1
    @Published private(set) var xpInLevel: Int = 0
    @Published private(set) var xpForNextLevel: Int = 20
    @Published private(set) var totalXP: Int = 0
    @Published private(set) var capabilities: BolaLevelGate.Capabilities = .init(level: 1)
    @Published private(set) var activeLevelUp: LevelUpPresentation?

    private var observer: NSObjectProtocol?
    private let defaults = BolaSharedDefaults.resolved()
    private let lastSeenLevelKey = "growth_last_seen_level_v1"

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
        let previousSeenLevel = storedLastSeenLevel()

        level = lvl
        xpInLevel = rem
        xpForNextLevel = BolaLevelFormula.xpRequired(forLevel: min(lvl, BolaLevelFormula.maxLevel))
        totalXP = state.totalXP
        capabilities = BolaLevelGate.Capabilities(level: lvl)

        if previousSeenLevel == 0 {
            saveLastSeenLevel(lvl)
        } else if lvl > previousSeenLevel {
            activeLevelUp = LevelUpPresentation.build(from: previousSeenLevel, to: lvl)
            saveLastSeenLevel(lvl)
        } else if lvl < previousSeenLevel {
            // 支持调试重置等级后重新触发升级页。
            saveLastSeenLevel(lvl)
        }
    }

    func dismissLevelUp() {
        activeLevelUp = nil
    }

    private func storedLastSeenLevel() -> Int {
        defaults.integer(forKey: lastSeenLevelKey)
    }

    private func saveLastSeenLevel(_ level: Int) {
        defaults.set(level, forKey: lastSeenLevelKey)
    }
}
