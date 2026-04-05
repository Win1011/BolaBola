//
//  GrowthDailyTaskModels.swift
//  成长页每日任务：卡片定义 + 可绑定进度（后续可接 HealthKit / 对话次数等）。
//

import Combine
import Foundation
import SwiftUI

// MARK: - 随机任务卡翻面（每日 8:00 换周期，已翻开则持久为正面）

enum GrowthRandomCardFlipStore {
    private static let periodKey = "growth_random_flip_period_start"
    private static let revealedKey = "growth_random_revealed_task_ids_v1"

    private static var defaults: UserDefaults { BolaSharedDefaults.resolved() }

    /// 当前「成长日」起点：本地当日 8:00；若此刻未到 8:00，则为昨日 8:00。
    static func currentPeriodStart(from date: Date = Date()) -> Date {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: date)
        guard let eightToday = cal.date(bySettingHour: 8, minute: 0, second: 0, of: dayStart) else {
            return date
        }
        if date < eightToday {
            return cal.date(byAdding: .day, value: -1, to: eightToday) ?? eightToday
        }
        return eightToday
    }

    /// 若跨日（8:00 周期），清空已翻开记录；返回当前周期内已朝上的任务 id。
    static func syncPeriodAndLoadRevealedIds() -> Set<String> {
        let current = currentPeriodStart()
        let currentTs = current.timeIntervalSince1970
        if let stored = defaults.object(forKey: periodKey) as? TimeInterval {
            if abs(stored - currentTs) > 0.5 {
                defaults.set(currentTs, forKey: periodKey)
                defaults.removeObject(forKey: revealedKey)
                return []
            }
        } else {
            defaults.set(currentTs, forKey: periodKey)
        }
        return loadRevealedIdsRaw()
    }

    private static func loadRevealedIdsRaw() -> Set<String> {
        guard let data = defaults.data(forKey: revealedKey),
              let arr = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(arr)
    }

    static func saveRevealed(taskId: String) {
        var s = loadRevealedIdsRaw()
        s.insert(taskId)
        if let data = try? JSONEncoder().encode(Array(s).sorted()) {
            defaults.set(data, forKey: revealedKey)
        }
    }

    /// 调试：清空本周期随机卡翻面记录（三张卡重新背面朝上）。
    static func debugClearRandomRevealed() {
        defaults.removeObject(forKey: revealedKey)
    }
}

// MARK: - 单张卡配置（换图、换文案只改数据）

struct GrowthDailyTaskCardDefinition: Identifiable, Equatable {
    let id: String
    var tag: String
    var illustrationAssetName: String?
    var placeholderSystemImage: String
    var detailLine1: String
    var detailLine2: String
    var isFlippable: Bool
}

// MARK: - ViewModel（实时进度）

@MainActor
final class GrowthDailyTasksViewModel: ObservableObject {
    @Published private(set) var progressByTaskId: [String: Double]
    /// 底部三张随机卡：本周期内用户已翻开过的任务 id（翻面后持久为正面至下次 8:00 周期）。
    @Published private(set) var revealedRandomTaskIds: Set<String>

    let definitions: [GrowthDailyTaskCardDefinition]

    init(
        definitions: [GrowthDailyTaskCardDefinition]? = nil,
        initialProgress: [String: Double]? = nil
    ) {
        let defs = definitions ?? GrowthDailyTaskModels.defaultTaskDefinitions
        self.definitions = defs
        var seed: [String: Double] = [:]
        for d in defs {
            seed[d.id] = initialProgress?[d.id] ?? Self.placeholderProgress(for: d.id)
        }
        progressByTaskId = seed
        revealedRandomTaskIds = GrowthRandomCardFlipStore.syncPeriodAndLoadRevealedIds()
    }

    /// 进入前台或跨日时调用：新周期会清空翻面状态。
    func refreshRandomFlipStateIfNeeded() {
        let next = GrowthRandomCardFlipStore.syncPeriodAndLoadRevealedIds()
        if next != revealedRandomTaskIds {
            revealedRandomTaskIds = next
        }
    }

    func isRandomTaskRevealed(id: String) -> Bool {
        revealedRandomTaskIds.contains(id)
    }

    func markRandomTaskRevealed(id: String) {
        guard definitions.contains(where: { $0.id == id && $0.isFlippable }) else { return }
        GrowthRandomCardFlipStore.saveRevealed(taskId: id)
        revealedRandomTaskIds.insert(id)
    }

    func progress(for id: String) -> Double {
        min(1, max(0, progressByTaskId[id] ?? 0))
    }

    func updateProgress(taskId: String, value: Double) {
        progressByTaskId[taskId] = min(1, max(0, value))
    }

    /// 调试：当作「刷新每日任务」——随机卡翻面重置、进度回到占位值。
    func debugRefreshDailyTasks() {
        GrowthRandomCardFlipStore.debugClearRandomRevealed()
        revealedRandomTaskIds = GrowthRandomCardFlipStore.syncPeriodAndLoadRevealedIds()
        var next = progressByTaskId
        for d in definitions {
            next[d.id] = Self.placeholderProgress(for: d.id)
        }
        progressByTaskId = next
    }

    private static func placeholderProgress(for id: String) -> Double {
        switch id {
        case "walk": return 0.42
        case "chat": return 0.18
        case "random_a", "random_b", "random_c": return 0
        default: return 0
        }
    }
}

enum GrowthDailyTaskModels {
    static let cardAspectRatio: CGFloat = 3.0 / 4.0

    /// 默认每日任务卡列表（换卡面/文案改这里或注入自定义数组）
    static let defaultTaskDefinitions: [GrowthDailyTaskCardDefinition] = [
        GrowthDailyTaskCardDefinition(
            id: "walk",
            tag: "散步",
            illustrationAssetName: nil,
            placeholderSystemImage: "figure.walk",
            detailLine1: "和我一起散步",
            detailLine2: "10min / 5000 步",
            isFlippable: false
        ),
        GrowthDailyTaskCardDefinition(
            id: "chat",
            tag: "聊天",
            illustrationAssetName: "bola手拿玫瑰",
            placeholderSystemImage: "bubble.left.and.bubble.right.fill",
            detailLine1: "和我聊聊",
            detailLine2: "今天发生什么了",
            isFlippable: false
        ),
        GrowthDailyTaskCardDefinition(
            id: "random_a",
            tag: "随机",
            illustrationAssetName: nil,
            placeholderSystemImage: "sparkles",
            detailLine1: "随机任务",
            detailLine2: "轻点翻面查看",
            isFlippable: true
        ),
        GrowthDailyTaskCardDefinition(
            id: "random_b",
            tag: "随机",
            illustrationAssetName: nil,
            placeholderSystemImage: "sparkles",
            detailLine1: "随机任务",
            detailLine2: "轻点翻面查看",
            isFlippable: true
        ),
        GrowthDailyTaskCardDefinition(
            id: "random_c",
            tag: "随机",
            illustrationAssetName: nil,
            placeholderSystemImage: "sparkles",
            detailLine1: "随机任务",
            detailLine2: "轻点翻面查看",
            isFlippable: true
        )
    ]
}
