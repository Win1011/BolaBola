//
//  PetCoreState.swift
//  Shared — 跨设备同步的宠物核心状态（不含动画细节）
//

import Foundation

/// 设备间同步的宠物核心状态。每台设备根据此状态 + companionValue 自行决定播放哪个动画。
/// 交互过渡动画（eating / drinking / fallingAsleep）由本机 `PetAnimationController` 驱动，
/// 不作为核心状态同步；对端仅在结果状态变化时更新。
public enum PetCoreState: String, Codable, Sendable {
    case idle
    case hungry
    case thirsty
    case sleepWait
    case sleeping
}

// MARK: - iPhone 侧：从核心状态 + 陪伴值推导动画前缀

public extension PetCoreState {

    /// 夜间睡眠核心态只在本地 23:30–次日 08:30 有效；超过窗口的跨设备旧包应回落到 idle。
    var isNightSleepState: Bool {
        switch self {
        case .sleepWait, .sleeping:
            return true
        default:
            return false
        }
    }

    /// 与手表端清晨自动醒来规则对齐：本地时间 [23:30, 08:30) 才允许保持 sleepWait / sleeping。
    static func isNightSleepActiveTime(_ date: Date = Date(), calendar: Calendar = .current) -> Bool {
        let h = calendar.component(.hour, from: date)
        let m = calendar.component(.minute, from: date)
        if h == 23 && m >= 30 { return true }
        if h < 8 { return true }
        if h == 8 && m < 30 { return true }
        return false
    }

    /// 将超出睡眠窗口的旧 sleepWait / sleeping 状态视为过期，避免 Watch 离线时 iPhone 长时间停在睡眠态。
    func normalizedForLocalClock(_ date: Date = Date(), calendar: Calendar = .current) -> PetCoreState {
        guard isNightSleepState, !Self.isNightSleepActiveTime(date, calendar: calendar) else {
            return self
        }
        return .idle
    }

    /// 返回 iPhone 端 `PetFramePlayer` 应播放的动画帧前缀。
    func animationPrefix(companionValue: Double) -> String {
        switch self {
        case .idle:
            return Self.idlePrefix(for: companionValue)
        case .hungry:
            return "idleapple"
        case .thirsty:
            return Bool.random() ? "idledrink1" : "idledrink2"
        case .sleepWait:
            return "sleepy"
        case .sleeping:
            return "sleeploop"
        }
    }

    /// 返回该核心状态对应的统一动画参数（fps + maxFrames）。
    func animationParams(companionValue: Double) -> PetAnimationParams {
        PetAnimationConfig.params(forPrefix: animationPrefix(companionValue: companionValue))
    }

    /// 返回该核心状态在 iPhone 上应显示的固定台词（若为 nil 则不显示气泡）。
    var localDialogue: String? {
        switch self {
        case .idle:          return nil
        case .hungry:        return "有点饿，想吃东西啦"
        case .thirsty:       return "有点渴啦"
        case .sleepWait:     return "已经很晚了，好想睡觉"
        case .sleeping:      return nil
        }
    }

    /// iPhone 触摸手表时是否应当提交对应指令（而非普通 +1 陪伴值）。
    /// 返回值与 `PetCommandKind` 的常量保持一致（`eat`/`drink`/`sleep`）。
    var petCommandForMockupTap: String? {
        switch self {
        case .hungry:    return "eat"
        case .thirsty:   return "drink"
        case .sleepWait: return "sleep"
        default:         return nil
        }
    }

    // MARK: - Private

    /// 简化版：根据陪伴值选择 idle 变体前缀（对标手表 `selectDefaultEmotion` 的分档逻辑）。
    private static func idlePrefix(for companionValue: Double) -> String {
        let v = Int(companionValue.rounded())
        if v <= 2 {
            return "die"
        } else if v <= 9 {
            switch (v - 3) % 3 {
            case 0:  return "hurt"
            case 1:  return "unhappy"
            default: return "unhappytwo"
            }
        } else if v <= 29 {
            return v % 2 == 0 ? "sadtwo" : "sadone"
        } else if v <= 85 {
            return "idleone"
        } else {
            return "happyidle"
        }
    }
}
