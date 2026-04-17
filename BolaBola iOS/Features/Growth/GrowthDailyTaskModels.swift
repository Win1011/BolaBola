//
//  GrowthDailyTaskModels.swift
//  成长页每日任务：卡片定义 + 可绑定进度（后续可接 HealthKit / 对话次数等）。
//

import Combine
import Foundation
import HealthKit
import SwiftUI

// MARK: - 每日任务选择（每日 8:00 切换一组，当天内保持稳定）

enum GrowthDailyTaskSelectionStore {
    private static let periodKey = "growth_daily_selection_period_start_v1"
    private static let selectedKey = "growth_daily_selected_task_ids_v1"
    private static let dailyTaskCount = 5

    private static var defaults: UserDefaults { BolaSharedDefaults.resolved() }

    static func syncAndLoadSelectedIds(taskPool: [GrowthDailyTaskCardDefinition]) -> [String] {
        let currentTs = GrowthDayBoundary.currentPeriodStart().timeIntervalSince1970
        let poolIds = Set(taskPool.map(\.id))

        if let stored = defaults.object(forKey: periodKey) as? TimeInterval,
           abs(stored - currentTs) <= 0.5,
           let ids = loadRaw(),
           ids.count == min(dailyTaskCount, taskPool.count),
           ids.allSatisfy(poolIds.contains) {
            return ids
        }

        let next = Array(taskPool.shuffled().prefix(dailyTaskCount)).map(\.id)
        defaults.set(currentTs, forKey: periodKey)
        save(next)
        return next
    }

    static func debugClear() {
        defaults.removeObject(forKey: periodKey)
        defaults.removeObject(forKey: selectedKey)
    }

    private static func loadRaw() -> [String]? {
        guard let data = defaults.data(forKey: selectedKey),
              let ids = try? JSONDecoder().decode([String].self, from: data) else {
            return nil
        }
        return ids
    }

    private static func save(_ ids: [String]) {
        if let data = try? JSONEncoder().encode(ids) {
            defaults.set(data, forKey: selectedKey)
        }
    }
}

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
    var surfaceKind: GrowthDailyTaskCardSurfaceKind
}

// MARK: - ViewModel（实时进度）

@MainActor
final class GrowthDailyTasksViewModel: ObservableObject {
    static let shared = GrowthDailyTasksViewModel()
    @Published private(set) var progressByTaskId: [String: Double]
    /// 当前周期抽到的 5 个每日任务（上 2 张直接展示，下 3 张翻卡）。
    @Published private(set) var dailyDefinitions: [GrowthDailyTaskCardDefinition]
    /// 底部三张任务在本周期内已翻开过的任务 id（翻面后持久为正面至下次 8:00 周期）。
    @Published private(set) var revealedRandomTaskIds: Set<String>
    /// 本周期内已触发 XP 的任务 id（跨日自动清空，防止重启后重复发放）。
    private var xpGrantedTaskIds: Set<String>

    let taskPool: [GrowthDailyTaskCardDefinition]
    private let healthStore = HKHealthStore()
    private var growthObserver: NSObjectProtocol?
    private var chatObserver: NSObjectProtocol?

    init(
        definitions: [GrowthDailyTaskCardDefinition]? = nil,
        initialProgress: [String: Double]? = nil
    ) {
        let defs = definitions ?? GrowthDailyTaskModels.defaultTaskDefinitions
        self.taskPool = defs
        var seed: [String: Double] = [:]
        for d in defs {
            seed[d.id] = initialProgress?[d.id] ?? 0
        }
        progressByTaskId = seed
        let selectedIds = GrowthDailyTaskSelectionStore.syncAndLoadSelectedIds(taskPool: defs)
        dailyDefinitions = defs.filter { selectedIds.contains($0.id) }
            .sorted { lhs, rhs in
                guard let li = selectedIds.firstIndex(of: lhs.id),
                      let ri = selectedIds.firstIndex(of: rhs.id) else { return false }
                return li < ri
            }
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
        next["walk_5000"] = await Self.queryWalkProgress(store: healthStore)
        next["chat_daily"] = Self.chatProgressToday(defaults: defaults)
        next["exercise_15m"] = await Self.queryExerciseMinutesProgress(store: healthStore, goalMinutes: 15)
        next["praise_bola"] = Self.placeholderProgress(for: "praise_bola")
        next["drink_water_once"] = Self.placeholderProgress(for: "drink_water_once")
        next["touch_bola_5"] = Self.placeholderProgress(for: "touch_bola_5")
        next["feed_bola_once"] = Self.placeholderProgress(for: "feed_bola_once")
        next["share_mood"] = Self.placeholderProgress(for: "share_mood")
        next["complete_reminder_once"] = Self.placeholderProgress(for: "complete_reminder_once")
        next["chat_meal"] = Self.placeholderProgress(for: "chat_meal")
        next["life_record_two_cards"] = Self.placeholderProgress(for: "life_record_two_cards")
        // 批量写入：单次 Dictionary 赋值只触发一次 objectWillChange，
        // 避免逐条 updateProgress() 造成多次 re-render。
        applyProgressBatch(next)
    }

    /// 一次性更新全部进度并处理 XP 发放，仅触发一次 objectWillChange。
    private func applyProgressBatch(_ next: [String: Double]) {
        var updated = progressByTaskId
        for (taskId, rawValue) in next {
            let clamped = min(1, max(0, rawValue))
            let wasDone = (updated[taskId] ?? 0) >= 1.0
            updated[taskId] = clamped
            if clamped >= 1.0 && !wasDone && !xpGrantedTaskIds.contains(taskId) {
                BolaXPEngine.grantTaskXP()
                xpGrantedTaskIds.insert(taskId)
                TitleUnlockManager.refreshUnlocks()
            }
        }
        progressByTaskId = updated  // 单次赋值 → 单次 objectWillChange
    }

    deinit {
        if let obs = growthObserver { NotificationCenter.default.removeObserver(obs) }
        if let obs = chatObserver { NotificationCenter.default.removeObserver(obs) }
    }

    /// 进入前台或跨日时调用：新周期会清空翻面状态。
    func refreshRandomFlipStateIfNeeded() {
        refreshDailyDefinitionsIfNeeded()
        let next = GrowthRandomCardFlipStore.syncPeriodAndLoadRevealedIds()
        if next != revealedRandomTaskIds {
            revealedRandomTaskIds = next
        }
    }

    func isRandomTaskRevealed(id: String) -> Bool {
        revealedRandomTaskIds.contains(id)
    }

    func markRandomTaskRevealed(id: String) {
        guard dailyDefinitions.suffix(3).contains(where: { $0.id == id }) else { return }
        GrowthRandomCardFlipStore.saveRevealed(taskId: id)
        revealedRandomTaskIds.insert(id)
    }

    func progress(for id: String) -> Double {
        min(1, max(0, progressByTaskId[id] ?? 0))
    }

    var completedCount: Int {
        dailyDefinitions.filter { progress(for: $0.id) >= 1.0 }.count
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
        GrowthDailyTaskSelectionStore.debugClear()
        refreshDailyDefinitionsIfNeeded()
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
        guard let task = dailyDefinitions.first(where: { progress(for: $0.id) < 1.0 }) else { return }
        var next = progressByTaskId
        next[task.id] = 1.0
        progressByTaskId = next
    }

    /// 调试：一键将所有任务进度设为 1.0（已完成）。
    func debugCompleteAllTasks() {
        var next = progressByTaskId
        for d in dailyDefinitions {
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

    nonisolated private static func queryExerciseMinutesProgress(store: HKHealthStore, goalMinutes: Double) async -> Double {
        guard HKHealthStore.isHealthDataAvailable(),
              let type = HKQuantityType.quantityType(forIdentifier: .appleExerciseTime) else { return 0 }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        let totalMinutes: Double = await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
                let minutes = stats?.sumQuantity()?.doubleValue(for: .minute()) ?? 0
                continuation.resume(returning: minutes)
            }
            store.execute(query)
        }
        guard goalMinutes > 0 else { return 0 }
        return min(1.0, max(0.0, totalMinutes / goalMinutes))
    }

    private static func placeholderProgress(for id: String) -> Double {
        switch id {
        case "praise_bola",
             "drink_water_once",
             "touch_bola_5",
             "feed_bola_once",
             "share_mood",
             "complete_reminder_once",
             "chat_meal",
             "life_record_two_cards":
            return 0
        default: return 0
        }
    }

    private func refreshDailyDefinitionsIfNeeded() {
        let selectedIds = GrowthDailyTaskSelectionStore.syncAndLoadSelectedIds(taskPool: taskPool)
        let next = taskPool.filter { selectedIds.contains($0.id) }
            .sorted { lhs, rhs in
                guard let li = selectedIds.firstIndex(of: lhs.id),
                      let ri = selectedIds.firstIndex(of: rhs.id) else { return false }
                return li < ri
            }
        if next != dailyDefinitions {
            dailyDefinitions = next
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

    /// 总任务库：每日会从这里抽取 5 张卡展示（上 2 张直接展示，下 3 张翻卡）。
    static let defaultTaskDefinitions: [GrowthDailyTaskCardDefinition] = [
        GrowthDailyTaskCardDefinition(
            id: "walk_5000",
            tag: "散步",
            illustrationAssetName: nil,
            placeholderSystemImage: "figure.walk",
            detailLine1: "和我一起散步",
            detailLine2: "今日走够 5000 步",
            surfaceKind: .accentGradient
        ),
        GrowthDailyTaskCardDefinition(
            id: "chat_daily",
            tag: "聊天",
            illustrationAssetName: "bola手拿玫瑰",
            placeholderSystemImage: "bubble.left.and.bubble.right.fill",
            detailLine1: "和我聊聊",
            detailLine2: "今日发生什么了",
            surfaceKind: .yellowPattern
        ),
        GrowthDailyTaskCardDefinition(
            id: "exercise_15m",
            tag: "运动",
            illustrationAssetName: nil,
            placeholderSystemImage: "figure.run",
            detailLine1: "一起运动哦",
            detailLine2: "今日运动 15min",
            surfaceKind: .accentGradient
        ),
        GrowthDailyTaskCardDefinition(
            id: "praise_bola",
            tag: "互动",
            illustrationAssetName: nil,
            placeholderSystemImage: "heart.text.square.fill",
            detailLine1: "给我一句夸夸",
            detailLine2: "说给我听听吧",
            surfaceKind: .accentGradient
        ),
        GrowthDailyTaskCardDefinition(
            id: "drink_water_once",
            tag: "喝水",
            illustrationAssetName: nil,
            placeholderSystemImage: "drop.fill",
            detailLine1: "喝一大口水",
            detailLine2: "完成一次喝水",
            surfaceKind: .accentGradient
        ),
        GrowthDailyTaskCardDefinition(
            id: "touch_bola_5",
            tag: "互动",
            illustrationAssetName: nil,
            placeholderSystemImage: "hand.tap.fill",
            detailLine1: "多摸摸我",
            detailLine2: "今日摸我 5 次",
            surfaceKind: .accentMuted
        ),
        GrowthDailyTaskCardDefinition(
            id: "feed_bola_once",
            tag: "喂食",
            illustrationAssetName: nil,
            placeholderSystemImage: "carrot.fill",
            detailLine1: "喂我好吃的",
            detailLine2: "完成喂食一次",
            surfaceKind: .accentMuted
        ),
        GrowthDailyTaskCardDefinition(
            id: "share_mood",
            tag: "心情",
            illustrationAssetName: nil,
            placeholderSystemImage: "face.smiling.fill",
            detailLine1: "说说心情吧",
            detailLine2: "告诉我你的心情",
            surfaceKind: .accentMuted
        ),
        GrowthDailyTaskCardDefinition(
            id: "complete_reminder_once",
            tag: "提醒",
            illustrationAssetName: nil,
            placeholderSystemImage: "bell.badge.fill",
            detailLine1: "让我来提醒你",
            detailLine2: "完成一个提醒",
            surfaceKind: .accentMuted
        ),
        GrowthDailyTaskCardDefinition(
            id: "chat_meal",
            tag: "聊天",
            illustrationAssetName: nil,
            placeholderSystemImage: "fork.knife.circle.fill",
            detailLine1: "和我聊聊",
            detailLine2: "告诉我吃了什么",
            surfaceKind: .yellowPattern
        ),
        GrowthDailyTaskCardDefinition(
            id: "life_record_two_cards",
            tag: "生活",
            illustrationAssetName: nil,
            placeholderSystemImage: "sparkles.rectangle.stack.fill",
            detailLine1: "记录生活哦",
            detailLine2: "添加两张生活记录卡",
            surfaceKind: .accentMuted
        )
    ]
}
