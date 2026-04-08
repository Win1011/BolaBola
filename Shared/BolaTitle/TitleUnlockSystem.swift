//
//  TitleUnlockSystem.swift
//  称号解锁系统：词库、解锁条件评估、持久化。
//  编译目标：iOS + watchOS（Shared）
//

import Foundation

// MARK: - 词类别

public enum TitleWordCategory: String, Codable, Sendable {
    case base        // 默认解锁（初始可用）
    case growth      // 等级里程碑解锁
    case behavior    // 任务/成就解锁
    case companion   // 陪伴值解锁
    case rare        // 稀有（特殊条件）
    case holiday     // 节日限定
    case personality // 性格类型解锁（Lv5+）
}

// MARK: - 解锁条件

public enum TitleUnlockCondition: Codable, Sendable {
    case always
    case level(Int)
    case milestone(String)          // BolaGrowthMilestone.rawValue
    case companionReached(Int)      // 陪伴值曾达到此值
    case personality(String)        // BolaPersonalityType.rawValue
    case levelAndCompanion(Int, Int)

    // 手动 Codable，因 associated values 无法自动合成
    enum CodingKeys: String, CodingKey { case type, value, value2 }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "always":               self = .always
        case "level":                self = .level(try c.decode(Int.self, forKey: .value))
        case "milestone":            self = .milestone(try c.decode(String.self, forKey: .value))
        case "companionReached":     self = .companionReached(try c.decode(Int.self, forKey: .value))
        case "personality":          self = .personality(try c.decode(String.self, forKey: .value))
        case "levelAndCompanion":
            self = .levelAndCompanion(
                try c.decode(Int.self, forKey: .value),
                try c.decode(Int.self, forKey: .value2)
            )
        default: self = .always
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .always:
            try c.encode("always", forKey: .type)
        case .level(let n):
            try c.encode("level", forKey: .type); try c.encode(n, forKey: .value)
        case .milestone(let m):
            try c.encode("milestone", forKey: .type); try c.encode(m, forKey: .value)
        case .companionReached(let n):
            try c.encode("companionReached", forKey: .type); try c.encode(n, forKey: .value)
        case .personality(let p):
            try c.encode("personality", forKey: .type); try c.encode(p, forKey: .value)
        case .levelAndCompanion(let l, let cv):
            try c.encode("levelAndCompanion", forKey: .type)
            try c.encode(l, forKey: .value); try c.encode(cv, forKey: .value2)
        }
    }
}

// MARK: - 词条模型

public struct TitleWord: Identifiable, Sendable {
    public let id: String          // 稳定 ID，格式：pool_序号，如 "a_0", "b_growth_1"
    public let text: String
    public let pool: Pool          // A 组（形容词）或 B 组（名词）
    public let category: TitleWordCategory
    public let unlockCondition: TitleUnlockCondition

    public enum Pool: String, Sendable { case a, b }

    public init(_ id: String, _ text: String, pool: Pool,
                category: TitleWordCategory, condition: TitleUnlockCondition) {
        self.id = id; self.text = text; self.pool = pool
        self.category = category; self.unlockCondition = condition
    }
}

// MARK: - 全量词库

public enum TitleWordBank {
    // MARK: A 组（形容词修饰语）
    public static let poolA: [TitleWord] = [
        // 基础（初始全解锁，对应原 BolaTitlePhraseBank.groupA）
        TitleWord("a_base_0", "路过的",      pool: .a, category: .base,     condition: .always),
        TitleWord("a_base_1", "认真的",      pool: .a, category: .base,     condition: .always),
        TitleWord("a_base_2", "熬夜的",      pool: .a, category: .base,     condition: .always),
        TitleWord("a_base_3", "爱喝水的",    pool: .a, category: .base,     condition: .always),
        TitleWord("a_base_4", "正在减肥的",  pool: .a, category: .base,     condition: .always),
        TitleWord("a_base_5", "随缘的",      pool: .a, category: .base,     condition: .always),
        TitleWord("a_base_6", "元气满满的",  pool: .a, category: .base,     condition: .always),
        TitleWord("a_base_7", "低调的",      pool: .a, category: .base,     condition: .always),
        // 成长解锁
        TitleWord("a_growth_0", "升级中的",  pool: .a, category: .growth,   condition: .level(2)),
        TitleWord("a_growth_1", "勤奋的",    pool: .a, category: .growth,   condition: .level(3)),
        TitleWord("a_growth_2", "越来越好的",pool: .a, category: .growth,   condition: .level(5)),
        TitleWord("a_growth_3", "传说级别的",pool: .a, category: .growth,   condition: .level(10)),
        TitleWord("a_growth_4", "满级的",    pool: .a, category: .growth,   condition: .level(20)),
        // 行为解锁
        TitleWord("a_behavior_0", "爱说话的",pool: .a, category: .behavior, condition: .milestone(BolaGrowthMilestone.firstIOSChat.rawValue)),
        TitleWord("a_behavior_1", "用声音的",pool: .a, category: .behavior, condition: .milestone(BolaGrowthMilestone.firstWatchVoice.rawValue)),
        TitleWord("a_behavior_2", "打卡达人", pool: .a, category: .behavior, condition: .level(4)),
        // 陪伴解锁
        TitleWord("a_comp_0", "超级亲密的",  pool: .a, category: .companion, condition: .companionReached(80)),
        TitleWord("a_comp_1", "满分陪伴的",  pool: .a, category: .companion, condition: .milestone(BolaGrowthMilestone.companion100.rawValue)),
        // 性格解锁（Lv5+）
        TitleWord("a_pers_0", "元气爆棚的",  pool: .a, category: .personality, condition: .personality(BolaPersonalityType.energetic.rawValue)),
        TitleWord("a_pers_1", "温温柔柔的",  pool: .a, category: .personality, condition: .personality(BolaPersonalityType.gentle.rawValue)),
        TitleWord("a_pers_2", "傲娇但可爱的",pool: .a, category: .personality, condition: .personality(BolaPersonalityType.tsundere.rawValue)),
        TitleWord("a_pers_3", "超级佛系的",  pool: .a, category: .personality, condition: .personality(BolaPersonalityType.chill.rawValue)),
        // 稀有
        TitleWord("a_rare_0", "神秘的",      pool: .a, category: .rare,     condition: .levelAndCompanion(10, 90)),
        TitleWord("a_rare_1", "无敌的",      pool: .a, category: .rare,     condition: .level(15)),
    ]

    // MARK: B 组（名词角色）
    public static let poolB: [TitleWord] = [
        // 基础（对应原 BolaTitlePhraseBank.groupB）
        TitleWord("b_base_0", "打工人",      pool: .b, category: .base,     condition: .always),
        TitleWord("b_base_1", "大学生",      pool: .b, category: .base,     condition: .always),
        TitleWord("b_base_2", "夜猫子",      pool: .b, category: .base,     condition: .always),
        TitleWord("b_base_3", "运动健将",    pool: .b, category: .base,     condition: .always),
        TitleWord("b_base_4", "摸鱼选手",    pool: .b, category: .base,     condition: .always),
        TitleWord("b_base_5", "养生党",      pool: .b, category: .base,     condition: .always),
        TitleWord("b_base_6", "铲屎官",      pool: .b, category: .base,     condition: .always),
        TitleWord("b_base_7", "干饭人",      pool: .b, category: .base,     condition: .always),
        // 成长解锁
        TitleWord("b_growth_0", "练习生",    pool: .b, category: .growth,   condition: .level(2)),
        TitleWord("b_growth_1", "探险家",    pool: .b, category: .growth,   condition: .level(3)),
        TitleWord("b_growth_2", "冒险者",    pool: .b, category: .growth,   condition: .level(5)),
        TitleWord("b_growth_3", "勇者",      pool: .b, category: .growth,   condition: .level(8)),
        TitleWord("b_growth_4", "传说",      pool: .b, category: .growth,   condition: .level(10)),
        TitleWord("b_growth_5", "神",        pool: .b, category: .growth,   condition: .level(20)),
        // 行为解锁
        TitleWord("b_behavior_0", "聊天王",  pool: .b, category: .behavior, condition: .milestone(BolaGrowthMilestone.firstIOSChat.rawValue)),
        TitleWord("b_behavior_1", "语音侠",  pool: .b, category: .behavior, condition: .milestone(BolaGrowthMilestone.firstWatchVoice.rawValue)),
        TitleWord("b_behavior_2", "任务狂",  pool: .b, category: .behavior, condition: .level(4)),
        // 陪伴解锁
        TitleWord("b_comp_0", "贴贴伙伴",    pool: .b, category: .companion, condition: .companionReached(60)),
        TitleWord("b_comp_1", "灵魂搭档",    pool: .b, category: .companion, condition: .milestone(BolaGrowthMilestone.companion100.rawValue)),
        // 性格解锁
        TitleWord("b_pers_0", "能量体",      pool: .b, category: .personality, condition: .personality(BolaPersonalityType.energetic.rawValue)),
        TitleWord("b_pers_1", "小绵羊",      pool: .b, category: .personality, condition: .personality(BolaPersonalityType.gentle.rawValue)),
        TitleWord("b_pers_2", "小傲娇",      pool: .b, category: .personality, condition: .personality(BolaPersonalityType.tsundere.rawValue)),
        TitleWord("b_pers_3", "淡淡的人",    pool: .b, category: .personality, condition: .personality(BolaPersonalityType.chill.rawValue)),
        // 稀有
        TitleWord("b_rare_0", "终极体",      pool: .b, category: .rare,     condition: .levelAndCompanion(10, 90)),
        TitleWord("b_rare_1", "满级存在",    pool: .b, category: .rare,     condition: .level(15)),
    ]

    public static func word(id: String) -> TitleWord? {
        (poolA + poolB).first { $0.id == id }
    }
}

// MARK: - 已解锁词 ID 持久化

public enum TitleUnlockStore {
    private static let defaultsKey = "bola_title_unlocked_ids_v1"
    private static var defaults: UserDefaults { BolaSharedDefaults.resolved() }

    public static func loadUnlockedIds() -> Set<String> {
        guard let data = defaults.data(forKey: defaultsKey),
              let arr = try? JSONDecoder().decode([String].self, from: data) else {
            // 首次：基础词全部解锁
            let baseIds = (TitleWordBank.poolA + TitleWordBank.poolB)
                .filter { $0.category == .base }
                .map(\.id)
            return Set(baseIds)
        }
        return Set(arr)
    }

    public static func save(_ ids: Set<String>) {
        if let data = try? JSONEncoder().encode(Array(ids).sorted()) {
            defaults.set(data, forKey: defaultsKey)
        }
    }

    public static func mergeFromRemote(_ remoteIds: Set<String>) {
        let local = loadUnlockedIds()
        save(local.union(remoteIds))
    }
}

// MARK: - 解锁条件评估器

public enum TitleUnlockManager {
    /// 评估所有词条的解锁条件，将新解锁的 ID 写入持久化，返回新解锁数量。
    @discardableResult
    public static func refreshUnlocks(
        state: BolaGrowthState? = nil,
        currentCompanionValue: Int = 0,
        maxEverCompanionValue: Int? = nil
    ) -> Int {
        let s = state ?? BolaGrowthStore.load()
        let (level, _) = BolaLevelFormula.levelAndRemainder(fromTotalXP: s.totalXP)
        let milestones = Set(s.completedMilestones)
        let personality = s.personalityType
        let maxCompanion = maxEverCompanionValue ?? currentCompanionValue

        var unlocked = TitleUnlockStore.loadUnlockedIds()
        var newCount = 0

        for word in TitleWordBank.poolA + TitleWordBank.poolB {
            guard !unlocked.contains(word.id) else { continue }
            if evaluate(word.unlockCondition, level: level, milestones: milestones,
                        maxCompanion: maxCompanion, personality: personality) {
                unlocked.insert(word.id)
                newCount += 1
            }
        }

        if newCount > 0 {
            TitleUnlockStore.save(unlocked)
            NotificationCenter.default.post(name: .bolaTitleUnlocksDidChange, object: nil)
        }
        return newCount
    }

    private static func evaluate(
        _ condition: TitleUnlockCondition,
        level: Int, milestones: Set<String>,
        maxCompanion: Int, personality: String?
    ) -> Bool {
        switch condition {
        case .always:                       return true
        case .level(let n):                 return level >= n
        case .milestone(let m):             return milestones.contains(m)
        case .companionReached(let n):      return maxCompanion >= n
        case .personality(let p):           return personality == p
        case .levelAndCompanion(let l, let cv):
            return level >= l && maxCompanion >= cv
        }
    }
}

public extension Notification.Name {
    static let bolaTitleUnlocksDidChange = Notification.Name("bolaTitleUnlocksDidChange")
}
