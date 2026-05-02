//
//  PetAnimationConfig.swift
//  Shared — 统一动画参数配置表，手表与 iPhone 共用
//
//  修改任何动画的播放速度时，只需修改此处，两端自动同步。
//  baseFPS  = 基础帧率（watchOS 会经过 effectiveFPS() 按帧采样比例调整）
//  maxFrames = Asset Catalog 中该前缀的最大帧数
//

import Foundation

// MARK: - 动画参数

/// 单条动画的播放参数，由 `PetAnimationConfig.params(forPrefix:)` 返回
public struct PetAnimationParams: Sendable, Equatable {
    /// 基础帧率（每秒帧数）；watchOS 侧会再经过 effectiveFPS() 调整
    public let baseFPS: Double
    /// Asset Catalog 中该前缀存在的最大帧数
    public let maxFrames: Int
    /// 渲染缩放比例（.scaleEffect）；补偿源帧素材大小差异，使所有动画视觉大小一致
    public let displayScale: CGFloat

    public init(baseFPS: Double, maxFrames: Int, displayScale: CGFloat = 1.5) {
        self.baseFPS = baseFPS
        self.maxFrames = maxFrames
        self.displayScale = displayScale
    }
}

// MARK: - 配置表

/// 统一动画参数配置表 — 手表与 iPhone 共用，确保两端播放速度一致。
///
/// 用法：
/// ```swift
/// let p = PetAnimationConfig.params(forPrefix: "idleone")
/// // p.baseFPS == 30, p.maxFrames == 90
/// ```
///
/// 未收录的前缀使用默认值 (24 fps, 90 frames)。
public enum PetAnimationConfig {

    /// 根据动画帧前缀返回统一参数；未收录的前缀使用默认值 (24 fps, 90 frames, 1.5 scale)
    public static func params(forPrefix prefix: String) -> PetAnimationParams {
        switch prefix {

        // ── idleone：源帧 bola 偏小，需更大 displayScale 补偿 ──
        case "idleone":
            return PetAnimationParams(baseFPS: 30, maxFrames: 90, displayScale: 1.9)

        // ── 30 fps / 1.5 scale：idle 系列 + 思考 + 缩放 + 死亡 + 大部分动作 ──
        case "idletwo", "idlethree", "idlefour", "idlefive", "idlesix",
             "happyidle", "thinktwo", "scale", "die",
             "unhappytwo", "unhappy", "letter", "hurt",
             "questionone", "questiontwo",
             "speakone", "speaktwo", "speakthree",
             "blowbubbleone", "blowbubbletwo",
             "sadone", "sadtwo",
             "happyone",
             "idleapple",
             "sleepy", "fallasleep", "sleeploop",
             "jumpone", "jumptwo", "surprisedone":
            return PetAnimationParams(baseFPS: 30, maxFrames: 90)

        // ── 40 fps：喝水动画 ──
        case "idledrink1", "idledrink2", "drink":
            return PetAnimationParams(baseFPS: 40, maxFrames: 90)

        // ── 50 fps：点赞动画 ──
        case "like1", "like2":
            return PetAnimationParams(baseFPS: 50, maxFrames: 90)

        // ── 70 fps，121 帧：吃东西动画 ──
        case "eatappletransparent":
            return PetAnimationParams(baseFPS: 70, maxFrames: 121)
        // ── 预留 / 占位 ──
        case "happy":
            return PetAnimationParams(baseFPS: 8, maxFrames: 1)

        // ── 兜底：未收录前缀使用默认值 ──
        default:
            return PetAnimationParams(baseFPS: 24, maxFrames: 90)
        }
    }
}
