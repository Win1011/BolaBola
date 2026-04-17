//
//  PetCoreState.swift
//  Shared — 跨设备同步的宠物核心状态（不含动画细节）
//

import Foundation

/// 设备间同步的宠物核心状态。每台设备根据此状态 + companionValue 自行决定播放哪个动画。
public enum PetCoreState: String, Codable, Sendable {
    case idle
    case hungry
    case thirsty
    case sleepWait
    case sleeping
}

// MARK: - iPhone 侧：从核心状态 + 陪伴值推导动画前缀

public extension PetCoreState {

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

    /// 返回该核心状态在 iPhone 上应显示的固定台词（若为 nil 则不显示气泡）。
    var localDialogue: String? {
        switch self {
        case .idle:       return nil
        case .hungry:     return "有点饿，想吃东西啦"
        case .thirsty:    return "有点渴啦"
        case .sleepWait:  return "已经很晚了，好想睡觉"
        case .sleeping:   return nil
        }
    }

    // MARK: - Private

    /// 简化版：根据陪伴值选择 idle 变体前缀（对标手表 `selectDefaultEmotion` 的分档逻辑）。
    private static func idlePrefix(for companionValue: Double) -> String {
        let v = Int(companionValue.rounded())
        if v <= 2 {
            return "die"
        } else if v <= 9 {
            return v % 2 == 0 ? "sadtwo" : "sadone"
        } else if v <= 29 {
            switch (v - 10) % 3 {
            case 0:  return "hurt"
            case 1:  return "unhappy"
            default: return "unhappytwo"
            }
        } else if v <= 85 {
            return "idleone"
        } else {
            return "happyidle"
        }
    }
}
