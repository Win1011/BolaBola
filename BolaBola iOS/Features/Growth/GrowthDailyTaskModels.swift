//
//  GrowthDailyTaskModels.swift
//  成长页每日任务：卡片定义 + 可绑定进度（后续可接 HealthKit / 对话次数等）。
//

import Combine
import Foundation
import HealthKit
import SwiftUI

// MARK: - 随机任务卡翻面（每日 8:00 换周期，已翻开则持久为正面）

enum GrowthRandomCardFlipStore {
    private static let periodKey = "growth_random_flip_period_start"
    private static let revealedKey = "growth_random_revealed_task_ids_v1"

    private static var defaults: UserDefaults { BolaSharedDefaults.resolved() }

    /// 若跨日（8:00 周期），清空已翻开记录；返回当前周期内已朝上的任务 id。
    static func syncPeriodAndLoadRevealedIds() -> Set<String> {
        let current = GrowthDayBoundary.currentPeriodStart()
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

// MARK: - XP 发放记录（跨日自动清空，防止重启后重复发放）

enum GrowthTaskXPGrantStore {
    private static let periodKey   = "growth_task_xp_period_start_v1"
    private static let grantedKey  = "growth_task_xp_granted_ids_v1"
    private static var defaults: UserDefaults { BolaSharedDefaults.resolved() }

    /// 对齐当前 8:00 周期，返回本周期内已发放 XP 的任务 id 集合。
    static func syncAndLoadGrantedIds() -> Set<String> {
        let currentTs = GrowthDayBoundary.currentPeriodStart().timeIntervalSince1970
        if let stored = defaults.object(forKey: periodKey) as? TimeInterval {
            if abs(stored - currentTs) > 0.5 {
                defaults.set(currentTs, forKey: periodKey)
                defaults.removeObject(forKey: grantedKey)
                return []
            }
        } else {
            defaults.set(currentTs, forKey: periodKey)
        }
        return loadRaw()
    }

    static func saveGranted(taskId: String) {
        var s = loadRaw()
        s.insert(taskId)
        if let data = try? JSONEncoder().encode(Array(s).sorted()) {
            defaults.set(data, forKey: grantedKey)
        }
    }

    static func debugClear() {
        defaults.removeObject(forKey: grantedKey)
        defaults.removeObject(forKey: periodKey)
    }

    private static func loadRaw() -> Set<String> {
        guard let data = defaults.data(forKey: grantedKey),
              let arr  = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(arr)
    }
}

// MARK: - 单张卡配置（换图、换文案只改数据）

/// 卡面上半区底色策略（与 `GrowthPortraitTaskCard` 对应）。
enum GrowthDailyTaskCardSurfaceKind: Equatable {
    /// 与随机卡背面一致的主色渐变（如散步）
    case accentGradient
    /// 亮黄 + 纹理（如聊天）
    case yellowPattern
    /// 主色偏弱渐变，与亮黄区分（如随机任务正面）
    case accentMuted
}

struct GrowthDailyTaskCardDefinition: Identifiable, Equatable {
    let id: String
    var tag: String
    var illustrationAssetName: String?
    var placeholderSystemImage: String
    var detailLine1: String
    var detailLine2: String
    var isFlippable: Bool
    var surfaceKind: GrowthDailyTaskCardSurfaceKind
}

// MARK: - ViewModel（实时进度）

@MainActor
final class GrowthDailyTasksViewModel: ObservableObject {
    static let shared = GrowthDailyTasksViewModel()
    @Published private(set) var progressByTaskId: [String: Double]
    /// 底部三张随机卡：本周期内用户已翻开过的任务 id（翻面后持久为正面至下次 8:00 周期）。
    @Published private(set) var revealedRandomTaskIds: Set<String>
    /// 本周期内已触发 XP 的任务 id（跨日自动清空，防止重启后重复发放）。
    private var xpGrantedTaskIds: Set<String>

    let definitions: [GrowthDailyTaskCardDefinition]
    private let healthStore = HKHealthStore()
    private var growthObserver: NSObjectProtocol?
    private var chatObserver: NSObjectProtocol?

    init(
        definitions: [GrowthDailyTaskCardDefinition]? = nil,
        initialProgress: [String: Double]? = nil
    ) {
        let defs = definitions ?? GrowthDailyTaskModels.defaultTaskDefinitions
        self.definitions = defs
        var seed: [String: Double] = [:]
        for d in defs {
            seed[d.id] = initialProgress?[d.id] ?? 0
        }
        progressByTaskId = seed
        revealedRandomTaskIds = GrowthRandomCardFlipStore.syncPeriodAndLoadRevealedIds()
        xpGrantedTaskIds = GrowthTaskXPGrantStore.syncAndLoadGrantedIds()
        BolaXPEngine.ensureDailyReset()
        // 当对话 XP 发放后刷新聊天任务进度
        growthObserver = NotificationCenter.default.addObserver(
            forName: .bolaGrowthStateDidChange,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.refreshProgress() }
        }
        chatObserver = NotificationCenter.default.addObserver(
            forName: .bolaChatHistoryDidMerge,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.refreshProgress() }
        }
        Task { @MainActor [weak self] in
            await self?.refreshProgress()
        }
    }

    func refreshProgress() async {
        var next = progressByTaskId
        let defaults = BolaSharedDefaults.resolved()
        next["walk"] = await Self.queryWalkProgress(store: healthStore)
        next["chat"] = Self.chatProgressToday(defaults: defaults)
        next["random_a"] = 1.0
        next["random_b"] = 1.0
        next["random_c"] = 1.0
        for (taskId, value) in next {
            updateProgress(taskId: taskId, value: value)
        }
    }

    deinit {
        if let obs = growthObserver { NotificationCenter.default.removeObserver(obs) }
        if let obs = chatObserver { NotificationCenter.default.removeObserver(obs) }
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

    var completedCount: Int {
        definitions.filter { progress(for: $0.id) >= 1.0 }.count
    }

    func updateProgress(taskId: String, value: Double) {
        let clamped = min(1, max(0, value))
        let wasDone = (progressByTaskId[taskId] ?? 0) >= 1.0
        progressByTaskId[taskId] = clamped
        // 首次到达 100% 且本周期未发过 XP 时发放
        if clamped >= 1.0 && !wasDone && !xpGrantedTaskIds.contains(taskId) {
            BolaXPEngine.grantTaskXP()
            xpGrantedTaskIds.insert(taskId)
            TitleUnlockManager.refreshUnlocks()
        }
    }

    /// 调试：当作「刷新每日任务」——随机卡翻面重置、进度回到占位值。
    func debugRefreshDailyTasks() {
        GrowthRandomCardFlipStore.debugClearRandomRevealed()
        revealedRandomTaskIds = GrowthRandomCardFlipStore.syncPeriodAndLoadRevealedIds()
        GrowthTaskCompletionAnimStore.debugClearSeen()
        xpGrantedTaskIds = []
        Task { @MainActor [weak self] in
            await self?.refreshProgress()
        }
    }

    /// 调试：完成下一个未完成的任务（按 definitions 顺序）。
    func debugCompleteNextTask() {
        guard let task = definitions.first(where: { progress(for: $0.id) < 1.0 }) else { return }
        var next = progressByTaskId
        next[task.id] = 1.0
        progressByTaskId = next
    }

    /// 调试：一键将所有任务进度设为 1.0（已完成）。
    func debugCompleteAllTasks() {
        var next = progressByTaskId
        for d in definitions {
            next[d.id] = 1.0
        }
        progressByTaskId = next
    }

    private static func chatProgressToday(defaults: UserDefaults) -> Double {
        let turns = ChatHistoryStore.load(from: defaults)
        let todayStart = Calendar.current.startOfDay(for: Date())
        let todayUserTurns = turns.filter { $0.role == "user" && $0.createdAt >= todayStart }
        return todayUserTurns.isEmpty ? 0 : 1
    }

    nonisolated private static func queryWalkProgress(store: HKHealthStore) async -> Double {
        guard HKHealthStore.isHealthDataAvailable(),
              let type = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return 0 }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        let totalSteps: Double = await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
                continuation.resume(returning: stats?.sumQuantity()?.doubleValue(for: .count()) ?? 0)
            }
            store.execute(query)
        }
        return min(1.0, max(0.0, totalSteps / 5000.0))
    }

    private static func placeholderProgress(for id: String) -> Double {
        switch id {
        case "random_a", "random_b", "random_c": return 1
        default: return 0
        }
    }
}

// MARK: - 完成动画播放记录（首次看到完成动画后记入持久化，之后只展示静帧）

enum GrowthTaskCompletionAnimStore {
    private static let seenKey = "growth_task_completion_anim_seen_ids"
    private static var defaults: UserDefaults { BolaSharedDefaults.resolved() }

    static func hasSeen(taskId: String) -> Bool {
        loadSeenIds().contains(taskId)
    }

    static func markSeen(taskId: String) {
        var ids = loadSeenIds()
        guard !ids.contains(taskId) else { return }
        ids.insert(taskId)
        if let data = try? JSONEncoder().encode(Array(ids).sorted()) {
            defaults.set(data, forKey: seenKey)
        }
    }

    /// 调试：清空「已看过完成动画」记录，便于反复测首次播放。
    static func debugClearSeen() {
        defaults.removeObject(forKey: seenKey)
    }

    private static func loadSeenIds() -> Set<String> {
        guard let data = defaults.data(forKey: seenKey),
              let arr = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(arr)
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
            isFlippable: false,
            surfaceKind: .accentGradient
        ),
        GrowthDailyTaskCardDefinition(
            id: "chat",
            tag: "聊天",
            illustrationAssetName: "bola手拿玫瑰",
            placeholderSystemImage: "bubble.left.and.bubble.right.fill",
            detailLine1: "和我聊聊",
            detailLine2: "今天发生什么了",
            isFlippable: false,
            surfaceKind: .yellowPattern
        ),
        GrowthDailyTaskCardDefinition(
            id: "random_a",
            tag: "随机",
            illustrationAssetName: nil,
            placeholderSystemImage: "sparkles",
            detailLine1: "随机任务",
            detailLine2: "轻点翻面查看",
            isFlippable: true,
            surfaceKind: .accentMuted
        ),
        GrowthDailyTaskCardDefinition(
            id: "random_b",
            tag: "随机",
            illustrationAssetName: nil,
            placeholderSystemImage: "sparkles",
            detailLine1: "随机任务",
            detailLine2: "轻点翻面查看",
            isFlippable: true,
            surfaceKind: .accentMuted
        ),
        GrowthDailyTaskCardDefinition(
            id: "random_c",
            tag: "随机",
            illustrationAssetName: nil,
            placeholderSystemImage: "sparkles",
            detailLine1: "随机任务",
            detailLine2: "轻点翻面查看",
            isFlippable: true,
            surfaceKind: .accentMuted
        )
    ]
}
