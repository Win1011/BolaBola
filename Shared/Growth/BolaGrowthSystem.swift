//
//  BolaGrowthSystem.swift
//  等级系统核心：公式、状态模型、持久化、XP 引擎、等级门控、日界线工具。
//  编译目标：iOS + watchOS（Shared）
//

import Foundation

// MARK: - 日界线工具（08:00 为每日起点）

public enum GrowthDayBoundary {
    /// 当前「成长日」起点：本地当日 08:00；若此刻未到 08:00，则为昨日 08:00。
    public static func currentPeriodStart(from date: Date = Date()) -> Date {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: date)
        guard let eightToday = cal.date(bySettingHour: 8, minute: 0, second: 0, of: dayStart) else {
            return date
        }
        return date < eightToday
            ? (cal.date(byAdding: .day, value: -1, to: eightToday) ?? eightToday)
            : eightToday
    }
}

// MARK: - 等级公式（纯函数，无副作用）

public enum BolaLevelFormula {
    public static let maxLevel = 20

    /// 升到下一级所需 XP：Lv.1→2 = 20，之后每级 +10。
    public static func xpRequired(forLevel level: Int) -> Int {
        20 + (max(1, level) - 1) * 10
    }

    /// 到达第 `level` 级所需累计 XP（level 1 = 0）。
    /// 公式：5 × (n-1) × (n+2)
    public static func cumulativeXP(forLevel level: Int) -> Int {
        let n = max(1, min(level, maxLevel + 1))
        guard n > 1 else { return 0 }
        return 5 * (n - 1) * (n + 2)
    }

    /// 从总 XP 计算当前等级（1–20）及等级内剩余 XP。
    public static func levelAndRemainder(fromTotalXP xp: Int) -> (level: Int, remainder: Int) {
        var lvl = 1
        for l in stride(from: maxLevel, through: 1, by: -1) {
            if xp >= cumulativeXP(forLevel: l) { lvl = l; break }
        }
        let remainder = xp - cumulativeXP(forLevel: lvl)
        return (lvl, remainder)
    }
}

// MARK: - 里程碑

public enum BolaGrowthMilestone: String, Codable, CaseIterable, Sendable {
    case firstIOSChat       // 首次 iOS 对话 (+20 XP)
    case firstWatchVoice    // 首次 Watch 语音 (+20 XP)
    case tierUpgrade1       // 陪伴值档位升到 Tier 1 (+30 XP)
    case tierUpgrade2
    case tierUpgrade3
    case tierUpgrade4
    case tierUpgrade5
    case tierUpgrade6
    case companion100       // 陪伴值到达 100 (+100 XP)

    public var xpReward: Int {
        switch self {
        case .firstIOSChat, .firstWatchVoice: return 20
        case .tierUpgrade1, .tierUpgrade2, .tierUpgrade3,
             .tierUpgrade4, .tierUpgrade5, .tierUpgrade6: return 30
        case .companion100: return 100
        }
    }
}

// MARK: - 核心状态模型

public struct BolaGrowthState: Codable, Sendable {
    public var totalXP: Int = 0
    /// 打开 App 的成长时间权重累计；每满一个阈值可结算为 1 XP。
    public var openAppGrowthCarrySeconds: TimeInterval = 0

    // 每日计数器（与 dailyPeriodStart 绑定，超过 08:00 周期自动重置）
    public var dailyPeriodStart: TimeInterval = 0
    public var dailyTaskXPCount: Int = 0      // 每日任务 XP 发放次数（上限 5）
    public var dailyIOSChatCount: Int = 0     // 每日 iOS 对话 XP 次数（上限 2）
    public var dailyWatchVoiceCount: Int = 0  // 每日 Watch 语音 XP 次数（上限 2）
    public var dailySleepCount: Int = 0       // 每日睡眠 XP 次数（上限 1）

    public var completedMilestones: [String] = []   // BolaGrowthMilestone.rawValue
    public var personalityType: String? = nil        // Lv5+ 随机分配，持久化

    public init() {
        dailyPeriodStart = GrowthDayBoundary.currentPeriodStart().timeIntervalSince1970
    }
}

// MARK: - 持久化 Store

public enum BolaGrowthStore {
    private static let defaultsKey = "bola_growth_state_v1"
    private static var defaults: UserDefaults { BolaSharedDefaults.resolved() }

    public static func load() -> BolaGrowthState {
        guard let data = defaults.data(forKey: defaultsKey),
              let state = try? JSONDecoder().decode(BolaGrowthState.self, from: data) else {
            return BolaGrowthState()
        }
        return state
    }

    public static func save(_ state: BolaGrowthState) {
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: defaultsKey)
        }
        NotificationCenter.default.post(name: .bolaGrowthStateDidChange, object: nil)
    }

    /// 合并策略：totalXP 取较大值，里程碑取并集，每日计数取本地（本设备更准确）。
    public static func mergeFromRemote(_ remote: BolaGrowthState) {
        var local = load()
        if remote.totalXP > local.totalXP {
            local.totalXP = remote.totalXP
        }
        let localSet = Set(local.completedMilestones)
        let remoteSet = Set(remote.completedMilestones)
        local.completedMilestones = Array(localSet.union(remoteSet)).sorted()
        if local.personalityType == nil, let rp = remote.personalityType {
            local.personalityType = rp
        }
        save(local)
    }
}

public extension Notification.Name {
    static let bolaGrowthStateDidChange = Notification.Name("bolaGrowthStateDidChange")
}

// MARK: - XP 引擎（所有 XP 变动的唯一入口）

public enum BolaXPEngine {
    // MARK: 每日重置

    /// 检查日界线，若已跨 08:00 则重置每日计数器。
    @discardableResult
    public static func ensureDailyReset() -> BolaGrowthState {
        var state = BolaGrowthStore.load()
        _resetIfNeeded(&state)
        return state
    }

    private static func _resetIfNeeded(_ state: inout BolaGrowthState) {
        let currentTs = GrowthDayBoundary.currentPeriodStart().timeIntervalSince1970
        if abs(state.dailyPeriodStart - currentTs) > 0.5 {
            state.dailyPeriodStart = currentTs
            state.dailyTaskXPCount = 0
            state.dailyIOSChatCount = 0
            state.dailyWatchVoiceCount = 0
            state.dailySleepCount = 0
        }
    }

    // MARK: XP 发放

    public static let openAppXPSecondsPerPoint: TimeInterval = 20 * 60
    public static let highCompanionOpenAppXPMultiplier: Double = 1.2

    /// 任务完成：+10 XP，每日上限 5 次。
    @discardableResult
    public static func grantTaskXP() -> Bool {
        var state = BolaGrowthStore.load()
        _resetIfNeeded(&state)
        guard state.dailyTaskXPCount < 5 else { return false }
        state.totalXP += 10
        state.dailyTaskXPCount += 1
        BolaGrowthStore.save(state)
        return true
    }

    /// 应用处于打开状态时累计成长；陪伴值 >= 80 时按 1.2x 结算。
    @discardableResult
    public static func grantOpenAppXP(elapsedSeconds: TimeInterval, companionValue: Int) -> Int {
        guard elapsedSeconds > 0 else { return 0 }
        var state = BolaGrowthStore.load()
        _resetIfNeeded(&state)

        let multiplier = companionValue >= 80 ? highCompanionOpenAppXPMultiplier : 1.0
        state.openAppGrowthCarrySeconds += elapsedSeconds * multiplier

        let grantedXP = Int(state.openAppGrowthCarrySeconds / openAppXPSecondsPerPoint)
        if grantedXP > 0 {
            state.totalXP += grantedXP
            state.openAppGrowthCarrySeconds -= Double(grantedXP) * openAppXPSecondsPerPoint
        }

        BolaGrowthStore.save(state)
        return grantedXP
    }

    /// iOS 对话完成：+5 XP，每日上限 2 次。
    @discardableResult
    public static func grantIOSChatXP() -> Bool {
        var state = BolaGrowthStore.load()
        _resetIfNeeded(&state)
        guard state.dailyIOSChatCount < 2 else { return false }
        state.totalXP += 5
        state.dailyIOSChatCount += 1
        BolaGrowthStore.save(state)
        return true
    }

    /// Watch 语音回复完成：+5 XP，每日上限 2 次。
    @discardableResult
    public static func grantWatchVoiceXP() -> Bool {
        var state = BolaGrowthStore.load()
        _resetIfNeeded(&state)
        guard state.dailyWatchVoiceCount < 2 else { return false }
        state.totalXP += 5
        state.dailyWatchVoiceCount += 1
        BolaGrowthStore.save(state)
        return true
    }

    /// 睡眠检测到：+5 XP，每日上限 1 次。
    @discardableResult
    public static func grantSleepXP() -> Bool {
        var state = BolaGrowthStore.load()
        _resetIfNeeded(&state)
        guard state.dailySleepCount < 1 else { return false }
        state.totalXP += 5
        state.dailySleepCount += 1
        BolaGrowthStore.save(state)
        return true
    }

    /// 里程碑奖励（一次性）。
    @discardableResult
    public static func completeMilestone(_ milestone: BolaGrowthMilestone) -> Bool {
        var state = BolaGrowthStore.load()
        guard !state.completedMilestones.contains(milestone.rawValue) else { return false }
        state.totalXP += milestone.xpReward
        state.completedMilestones.append(milestone.rawValue)
        // Lv5+ 首次分配性格
        if state.personalityType == nil {
            let (level, _) = BolaLevelFormula.levelAndRemainder(fromTotalXP: state.totalXP)
            if level >= 5 {
                state.personalityType = BolaPersonalityType.allCases.randomElement()?.rawValue
            }
        }
        BolaGrowthStore.save(state)
        return true
    }
}

// MARK: - 等级门控

public enum BolaLevelGate {
    public struct Capabilities: Sendable {
        public let level: Int
        /// Lv1+ 才能对话
        public var canDialogue: Bool { level >= 1 }
        /// 语音模式：Lv0=none, Lv1-2=clumsy（学话）, Lv3+=normal
        public var speechMode: SpeechMode {
            if level == 0 { return .none }
            if level <= 2 { return .clumsy }
            return .normal
        }
        /// Lv3+ 解锁称号选择
        public var canUseTitles: Bool { level >= 3 }
        /// Lv3+ 解锁表盘槽位自定义
        public var canUseWatchFaceSlots: Bool { level >= 3 }
        /// Lv5+ 有随机性格
        public var hasPersonality: Bool { level >= 5 }
        /// Lv10+ 解锁隐藏对话池
        public var hasHiddenDialoguePool: Bool { level >= 10 }

        public enum SpeechMode: Sendable { case none, clumsy, normal }
    }

    public static func capabilities(for totalXP: Int) -> Capabilities {
        let (level, _) = BolaLevelFormula.levelAndRemainder(fromTotalXP: totalXP)
        return Capabilities(level: level)
    }

    public static func capabilities() -> Capabilities {
        let state = BolaGrowthStore.load()
        return capabilities(for: state.totalXP)
    }
}

// MARK: - 性格类型（Lv5+ 随机分配）

public enum BolaPersonalityType: String, CaseIterable, Sendable {
    case energetic   = "元气"
    case gentle      = "温柔"
    case tsundere    = "傲娇"
    case chill       = "佛系"
}
