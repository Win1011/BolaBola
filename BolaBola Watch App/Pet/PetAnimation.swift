//
//  PetAnimation.swift
//  BolaBola Watch App
//
//  宠物动画：模型、资源配置、帧加载与 SwiftUI 视图（由 ContentView / PetViewModel 使用）
//

import SwiftUI
import Combine
import AVFoundation
import AVKit

// MARK: - 基础模型

/// 宠物当前的大情绪 / 动作类型
enum PetEmotion {
    case idle
    case idleOne      // 新增：idleone 动作
    case idleTwo      // 新增：idletwo 动作
    case idleThree    // 新增：idlethree 动作
    /// Assets：`idlefour0`…（idle4 文件夹）
    case idleFour
    case idleFive
    case idleSix
    /// 不开心2（`unhappytwo0`…）
    case unhappyTwo
    /// 开心晃悠（`happyidle0`…）
    case happyIdle
    /// 思考1 / 思考2（仅语音流程：用户说完后、Bola 回复前），资源 `thinkone` / `thinktwo`
    case thinkOne
    case thinkTwo
    case scale        // 新增：scale 动作
    case die          // 新增：DIE 动作
    case angry2       // 新增：angry2 动作
    case unhappy      // 新增：不高兴 动作
    case letter       // 新增：信件 动作
    /// 信件播一轮（每日总结等）
    case letterOnce
    case hurt         // 新增：委屈 动作
    case question1    // 新增：question1 动作
    case question2    // 新增：question2 动作
    case question3    // 新增：question3 动作
    case speak1       // 新增：speak1 动作
    case speak2       // 新增：speak2 动作
    case speak3       // 新增：speak3 动作
    /// 语音回复：各 speak 序列播一轮
    case speak1Once
    case speak2Once
    case speak3Once
    case blowbubble1  // 新增：blowbubble1 动作
    case blowbubble2  // 新增：blowbubble2 动作
    case like1        // 新增：like1 动作
    case like2        // 新增：like2 动作
    case surprisedOne // 新增：惊喜1 动作
    case surprisedTwo // 新增：惊喜2 动作
    case sad1         // 新增：sad1 动作
    case sad2         // 新增：sad2 动作
    case jumpTwo      // 新增：跳跃2 动作
    /// 新增：happy1 序列帧（Assets：`happyone0`…`happyone35`）
    case happy1
    /// 新增：jump1 序列帧（Assets：`jumpone0`…`jumpone35`）
    case jump1
    case jumpTwoOnce  // 用于惊喜后“一次性”跳跃（2轮后自动回默认）
    /// `shake` 资源播一轮后回 idle（25–80 随机插入）
    case shakeOnce
    /// `happyone` 播一轮后回 idle（v>85 随机插入）
    case happy1Once
    /// `jumpone` 两轮长度（与 jumpTwoOnce 对应惊喜链）
    case jump1Once
    /// 与 `jump1` 同资源；点按播一轮
    case jump1Tap
    /// 与 `jumpTwo` 同一套 `jumptwo` 资源；仅播放模式不同（点一下播一轮即停，非第二套美术）
    case jumpTwoTap
    /// 点击：三连喜欢，播一轮后回 idle
    case like2Once
    /// 点击：暴怒，播一轮后回 idle
    case angry2Once
    /// happyIdle 播一轮
    case happyIdleOnce
    /// like1 播一轮
    case like1Once
    /// 吃东西等待：循环 idleapple（饿了）
    case eatingWait
    /// 吃东西：播一轮 eatapple
    case eatingOnce
    case sleepy       // 新增：sleepy 动作
    case happy
    case angry
    case sleep
    case special
    /// 夜间睡眠：等待入睡（循环 sleepy）
    case nightSleepWait
    /// 夜间睡眠：播一轮 fallasleep
    case fallAsleep
    /// 夜间睡眠：循环 sleeploop 直到早上被叫醒
    case sleepLoop
}

enum PetAnimationSource {
    case frames(frameNames: [String], fps: Double, isLoop: Bool)
    case video(videoFileName: String, isLoop: Bool) // bundle 里的 idleone.mp4 / scale.mp4（不带扩展名）
}

/// 宠物动画描述（支持 PNG 帧序列 或单个 mp4）
struct PetAnimation {
    let emotion: PetEmotion
    let displayScale: CGFloat
    let source: PetAnimationSource
}

// MARK: - 动画大小配置（每个动作单独 `scaleEffect`，按需改数字即可）
enum AnimationScale {
    static let idle: CGFloat = 1.5
    static let idleOne: CGFloat = 1.9
    static let idleTwo: CGFloat = 1.5
    static let idleThree: CGFloat = 1.5
    static let idleFour: CGFloat = 1.5
    static let idleFive: CGFloat = 1.5
    static let idleSix: CGFloat = 1.5
    static let unhappyTwo: CGFloat = 1.5
    static let happyIdle: CGFloat = 1.5
    static let thinkOne: CGFloat = 1.5
    static let thinkTwo: CGFloat = 1.5
    static let scale: CGFloat = 1.5

    static let die: CGFloat = 1.5
    static let happy: CGFloat = 1.5
    static let angry2: CGFloat = 1.5
    static let unhappy: CGFloat = 1.5
    static let letter: CGFloat = 1.5
    static let letterOnce: CGFloat = 1.5
    static let hurt: CGFloat = 1.5

    static let question1: CGFloat = 1.5
    static let question2: CGFloat = 1.5
    static let question3: CGFloat = 1.5

    static let speak1: CGFloat = 1.5
    static let speak2: CGFloat = 1.5
    static let speak3: CGFloat = 1.5
    static let speak1Once: CGFloat = 1.5
    static let speak2Once: CGFloat = 1.5
    static let speak3Once: CGFloat = 1.5

    static let blowbubble1: CGFloat = 1.5
    static let blowbubble2: CGFloat = 1.5
    static let like1: CGFloat = 1.5
    static let like2: CGFloat = 1.5
    static let surprisedOne: CGFloat = 1.5
    static let surprisedTwo: CGFloat = 1.5
    static let sad1: CGFloat = 1.5
    static let sad2: CGFloat = 1.5
    static let jumpTwo: CGFloat = 1.5
    static let happy1: CGFloat = 1.5
    static let jump1: CGFloat = 1.5
    static let shakeOnce: CGFloat = 1.5
    static let happyIdleOnce: CGFloat = 1.5
    static let like1Once: CGFloat = 1.5
    static let eatingWait: CGFloat = 1.5
    static let eatingOnce: CGFloat = 1.5
    static let sleepy: CGFloat = 1.5
    static let sleep: CGFloat = 1.5
    static let nightSleepWait: CGFloat = 1.5
    static let fallAsleep: CGFloat = 1.5
    static let sleepLoop: CGFloat = 1.5
}

// MARK: - 动画帧限制（用于控制 watchOS 内存）
// watchOS 上循环播放时，图片/纹理缓存可能持续增长。
// 通过限制“实际参与播放的独特帧数量”，可以显著降低 OOM 风险。
enum AnimationLimits {
    // 限制“参与解码/渲染的独特点帧数量”，避免 watchOS 因纹理/解码缓存累积而 OOM
    // 设得足够大即可关掉“抽帧/采样”，恢复到逐帧播放的效果。
    static let maxUniqueFrames: Int = 1000
}

/// 负责从 Bundle/Asset Catalog 中按前缀扫描所有帧的简单加载器（用于 PNG 帧序列兜底）
enum PetAnimationLoader {
    static func loadFrameNames(prefix namePrefix: String, maxFrames: Int = 300) -> [String] {
        var frameNames: [String] = []

        // 1) Asset Catalog 探测（适用于 Assets.xcassets：编译后不以 png 文件形式存在）
        frameNames = loadFromAssetCatalog(prefix: namePrefix, maxFrames: maxFrames)

        // 2) 回退：扫描 bundle 文件系统（适用于直接拷贝进 bundle 的 png）
        if frameNames.isEmpty {
            frameNames = scanBundleForPNGs(prefix: namePrefix)
        }

        if frameNames.isEmpty {
            print("⚠️ No frames found for prefix '\(namePrefix)'. Check asset names like \(namePrefix)0, \(namePrefix)1... or ensure pngs are copied into bundle.")
        } else {
            print("✅ Loaded frames for prefix '\(namePrefix)': \(frameNames.count) frames")
        }

        return frameNames
    }

    static func loadFrameNames(prefix namePrefix: String, maxFrames: Int, maxUniqueFrames: Int) -> [String] {
        let full = loadFrameNames(prefix: namePrefix, maxFrames: maxFrames)
        guard maxUniqueFrames > 0, full.count > maxUniqueFrames else { return full }

        // 计算步长：让参与播放的帧数不超过 maxUniqueFrames
        let stride = max(1, Int(ceil(Double(full.count) / Double(maxUniqueFrames))))
        return full.enumerated().compactMap { idx, name in
            idx % stride == 0 ? name : nil
        }
    }

    private static func loadFromAssetCatalog(prefix: String, maxFrames: Int) -> [String] {
        // 重要：不要在 watchOS 上调用 UIImage(named:) 进行任何存在性探测。
        // UIImage(named:) 会触发图片解码/缓存，容易造成启动阶段内存峰值过高导致被 kill。
        // 这里直接返回 prefix0...prefix(maxFrames-1) 的名字列表。
        // 即使个别帧不存在，`Image(frameName)` 也只是显示为空白，不会触发逐帧探测。
        guard maxFrames > 0 else { return [] }
        return (0..<maxFrames).map { "\(prefix)\($0)" }
    }

    private static func scanBundleForPNGs(prefix: String) -> [String] {
        guard let baseURL = Bundle.main.resourceURL else { return [] }
        var collected: [String] = []

        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: baseURL, includingPropertiesForKeys: nil) else {
            return []
        }

        for case let url as URL in enumerator {
            if url.pathExtension.lowercased() != "png" { continue }
            let name = url.deletingPathExtension().lastPathComponent
            if name.hasPrefix(prefix) {
                collected.append(name)
            }
        }

        // 按数字后缀做“自然排序”（shake2 在 shake10 前面）
        return collected.sorted { lhs, rhs in
            let li = Int(lhs.dropFirst(prefix.count)) ?? 0
            let ri = Int(rhs.dropFirst(prefix.count)) ?? 0
            if li == ri { return lhs < rhs }
            return li < ri
        }
    }
}

/// 所有可用动画的配置（只需要指定目录和基础参数）
enum PetAnimations {
    // 如果启用了帧采样（maxUniqueFrames），则实际“时间长度”会因为 stride 变短。
    // 为了让观感更接近原始播放速度，这里把 fps 按 stride 成比例缩小。
    private static func effectiveFPS(baseFPS: Double, maxFrames: Int) -> Double {
        let stride = max(1, (maxFrames + AnimationLimits.maxUniqueFrames - 1) / AnimationLimits.maxUniqueFrames)
        return baseFPS / Double(stride)
    }

    // 为了实现“播放两次后结束”，直接把同一套帧序列拼成两倍长度。
    private static func loopTwiceFrames(prefix: String, maxFrames: Int) -> [String] {
        let one = PetAnimationLoader.loadFrameNames(
            prefix: prefix,
            maxFrames: maxFrames,
            maxUniqueFrames: AnimationLimits.maxUniqueFrames
        )
        return one + one
    }

    // 当前只有 shake 这一套动画，我们先把它当作 idle 来用：
    // 资源名形如：shake0, shake1, ...
    static let idle: PetAnimation = PetAnimation(
        emotion: .idle,
        displayScale: AnimationScale.idle,
        source: .frames(
            frameNames: PetAnimationLoader.loadFrameNames(prefix: "shake", maxFrames: 23),
            fps: effectiveFPS(baseFPS: 6, maxFrames: 23),
            isLoop: true
        )
    )

    /// shake 播一轮（非循环）
    static let shakeOnce: PetAnimation = PetAnimation(
        emotion: .shakeOnce,
        displayScale: AnimationScale.shakeOnce,
        source: .frames(
            frameNames: PetAnimationLoader.loadFrameNames(prefix: "shake", maxFrames: 23),
            fps: effectiveFPS(baseFPS: 6, maxFrames: 23),
            isLoop: false
        )
    )

    // 新增 idleone 动作：资源名形如 idleone0, idleone1, ...
    static let idleOne: PetAnimation = PetAnimation(
        emotion: .idleOne,
        displayScale: AnimationScale.idleOne,
        // watchOS 上 VideoPlayer 会展示原生播放控制 UI，影响交互体验。
        // 直接使用 idleone 帧序列来渲染，避免播放器控件出现。
        source: .frames(
            frameNames: PetAnimationLoader.loadFrameNames(prefix: "idleone", maxFrames: 31, maxUniqueFrames: AnimationLimits.maxUniqueFrames),
            fps: effectiveFPS(baseFPS: 7, maxFrames: 31),
            isLoop: true
        )
    )

    // 新增 idleTwo：资源名形如 idletwo0, idletwo1, ...
    static let idleTwo: PetAnimation = PetAnimation(
        emotion: .idleTwo,
        displayScale: AnimationScale.idleTwo,
        source: .frames(
            frameNames: PetAnimationLoader.loadFrameNames(prefix: "idletwo", maxFrames: 31, maxUniqueFrames: AnimationLimits.maxUniqueFrames),
            fps: effectiveFPS(baseFPS: 7, maxFrames: 31),
            isLoop: true
        )
    )

    // 新增 idleThree：资源名形如 idlethree0, idlethree1, ...
    static let idleThree: PetAnimation = PetAnimation(
        emotion: .idleThree,
        displayScale: AnimationScale.idleThree,
        source: .frames(
            frameNames: PetAnimationLoader.loadFrameNames(prefix: "idlethree", maxFrames: 31, maxUniqueFrames: AnimationLimits.maxUniqueFrames),
            fps: effectiveFPS(baseFPS: 7, maxFrames: 31),
            isLoop: true
        )
    )

    static let idleFour: PetAnimation = PetAnimation(
        emotion: .idleFour,
        displayScale: AnimationScale.idleFour,
        source: .frames(
            frameNames: PetAnimationLoader.loadFrameNames(prefix: "idlefour", maxFrames: 30, maxUniqueFrames: AnimationLimits.maxUniqueFrames),
            fps: effectiveFPS(baseFPS: 7, maxFrames: 30),
            isLoop: true
        )
    )

    static let idleFive: PetAnimation = PetAnimation(
        emotion: .idleFive,
        displayScale: AnimationScale.idleFive,
        source: .frames(
            frameNames: PetAnimationLoader.loadFrameNames(prefix: "idlefive", maxFrames: 30, maxUniqueFrames: AnimationLimits.maxUniqueFrames),
            fps: effectiveFPS(baseFPS: 7, maxFrames: 30),
            isLoop: true
        )
    )

    static let idleSix: PetAnimation = PetAnimation(
        emotion: .idleSix,
        displayScale: AnimationScale.idleSix,
        source: .frames(
            frameNames: PetAnimationLoader.loadFrameNames(prefix: "idlesix", maxFrames: 36, maxUniqueFrames: AnimationLimits.maxUniqueFrames),
            fps: effectiveFPS(baseFPS: 7, maxFrames: 36),
            isLoop: true
        )
    )

    static let unhappyTwo: PetAnimation = PetAnimation(
        emotion: .unhappyTwo,
        displayScale: AnimationScale.unhappyTwo,
        source: .frames(
            frameNames: PetAnimationLoader.loadFrameNames(prefix: "unhappytwo", maxFrames: 30, maxUniqueFrames: AnimationLimits.maxUniqueFrames),
            fps: effectiveFPS(baseFPS: 8, maxFrames: 30),
            isLoop: true
        )
    )

    static let happyIdle: PetAnimation = PetAnimation(
        emotion: .happyIdle,
        displayScale: AnimationScale.happyIdle,
        source: .frames(
            frameNames: PetAnimationLoader.loadFrameNames(prefix: "happyidle", maxFrames: 36, maxUniqueFrames: AnimationLimits.maxUniqueFrames),
            fps: effectiveFPS(baseFPS: 7, maxFrames: 36),
            isLoop: true
        )
    )

    static let thinkOne: PetAnimation = PetAnimation(
        emotion: .thinkOne,
        displayScale: AnimationScale.thinkOne,
        source: .frames(
            frameNames: PetAnimationLoader.loadFrameNames(prefix: "thinkone", maxFrames: 30, maxUniqueFrames: AnimationLimits.maxUniqueFrames),
            fps: effectiveFPS(baseFPS: 7, maxFrames: 30),
            isLoop: true
        )
    )

    static let thinkTwo: PetAnimation = PetAnimation(
        emotion: .thinkTwo,
        displayScale: AnimationScale.thinkTwo,
        source: .frames(
            frameNames: PetAnimationLoader.loadFrameNames(prefix: "thinktwo", maxFrames: 30, maxUniqueFrames: AnimationLimits.maxUniqueFrames),
            fps: effectiveFPS(baseFPS: 7, maxFrames: 30),
            isLoop: true
        )
    )

    // 新增 scale 动作：资源名形如 scale0, scale1, ...
    static let scale: PetAnimation = PetAnimation(
        emotion: .scale,
        displayScale: AnimationScale.scale,
        // 同上：改用帧序列，避免 VideoPlayer 控件层。
        source: .frames(
            frameNames: PetAnimationLoader.loadFrameNames(prefix: "scale", maxFrames: 26, maxUniqueFrames: AnimationLimits.maxUniqueFrames),
            fps: effectiveFPS(baseFPS: 7, maxFrames: 26),
            isLoop: true
        )
    )

    // 新增 die：资源名形如 die0, die1, ...
    static let die: PetAnimation = PetAnimation(
        emotion: .die,
        displayScale: AnimationScale.die,
        source: .frames(
            frameNames: PetAnimationLoader.loadFrameNames(prefix: "die", maxFrames: 31, maxUniqueFrames: AnimationLimits.maxUniqueFrames),
            fps: effectiveFPS(baseFPS: 7, maxFrames: 31),
            isLoop: true
        )
    )

    // 预留 happy 配置，等你以后添加对应前缀的资源时再启用
    static let happy: PetAnimation = PetAnimation(
        emotion: .happy,
        displayScale: AnimationScale.happy,
        source: .frames(
            // 目前 Assets.xcassets 里不一定有 happy 资源；用很小的 maxFrames 避免无意义生成过多帧名。
            frameNames: PetAnimationLoader.loadFrameNames(prefix: "happy", maxFrames: 1, maxUniqueFrames: AnimationLimits.maxUniqueFrames),
            fps: effectiveFPS(baseFPS: 8, maxFrames: 1),
            isLoop: true
        )
    )

    // 按需继续加 angry / sleep / special...
    
    // 以下是 Assets 中新增的动作（帧序列）
    static let angry2: PetAnimation = PetAnimation(
        emotion: .angry2,
        displayScale: AnimationScale.angry2,
        source: .frames(
            frameNames: PetAnimationLoader.loadFrameNames(prefix: "angrytwo", maxFrames: 30, maxUniqueFrames: AnimationLimits.maxUniqueFrames),
            fps: effectiveFPS(baseFPS: 8, maxFrames: 30),
            isLoop: true
        )
    )

    // 新增 unhappy：资源名形如 unhappy0, unhappy1, ...
    static let unhappy: PetAnimation = PetAnimation(
        emotion: .unhappy,
        displayScale: AnimationScale.unhappy,
        source: .frames(
            frameNames: PetAnimationLoader.loadFrameNames(prefix: "unhappy", maxFrames: 31, maxUniqueFrames: AnimationLimits.maxUniqueFrames),
            fps: effectiveFPS(baseFPS: 8, maxFrames: 31),
            isLoop: true
        )
    )

    // 新增 letter：资源名形如 letter0, letter1, ...
    static let letter: PetAnimation = PetAnimation(
        emotion: .letter,
        displayScale: AnimationScale.letter,
        source: .frames(
            frameNames: PetAnimationLoader.loadFrameNames(prefix: "letter", maxFrames: 31, maxUniqueFrames: AnimationLimits.maxUniqueFrames),
            fps: effectiveFPS(baseFPS: 8, maxFrames: 31),
            isLoop: true
        )
    )

    static let letterOnce: PetAnimation = PetAnimation(
        emotion: .letterOnce,
        displayScale: AnimationScale.letterOnce,
        source: .frames(
            frameNames: PetAnimationLoader.loadFrameNames(prefix: "letter", maxFrames: 31, maxUniqueFrames: AnimationLimits.maxUniqueFrames),
            fps: effectiveFPS(baseFPS: 8, maxFrames: 31),
            isLoop: false
        )
    )

    // 新增 hurt：资源名形如 hurt0, hurt1, ...
    static let hurt: PetAnimation = PetAnimation(
        emotion: .hurt,
        displayScale: AnimationScale.hurt,
        source: .frames(
            frameNames: PetAnimationLoader.loadFrameNames(prefix: "hurt", maxFrames: 31, maxUniqueFrames: AnimationLimits.maxUniqueFrames),
            fps: effectiveFPS(baseFPS: 8, maxFrames: 31),
            isLoop: true
        )
    )

    static let question1: PetAnimation = PetAnimation(
        emotion: .question1,
        displayScale: AnimationScale.question1,
        source: .frames(
            frameNames: PetAnimationLoader.loadFrameNames(prefix: "questionone", maxFrames: 30, maxUniqueFrames: AnimationLimits.maxUniqueFrames),
            fps: effectiveFPS(baseFPS: 8, maxFrames: 30),
            isLoop: true
        )
    )

    static let question2: PetAnimation = PetAnimation(
        emotion: .question2,
        displayScale: AnimationScale.question2,
        source: .frames(
            frameNames: PetAnimationLoader.loadFrameNames(prefix: "questiontwo", maxFrames: 30, maxUniqueFrames: AnimationLimits.maxUniqueFrames),
            fps: effectiveFPS(baseFPS: 8, maxFrames: 30),
            isLoop: true
        )
    )

    static let question3: PetAnimation = PetAnimation(
        emotion: .question3,
        displayScale: AnimationScale.question3,
        source: .frames(
            frameNames: PetAnimationLoader.loadFrameNames(prefix: "questionthree", maxFrames: 30, maxUniqueFrames: AnimationLimits.maxUniqueFrames),
            fps: effectiveFPS(baseFPS: 8, maxFrames: 30),
            isLoop: true
        )
    )

    static let speak1: PetAnimation = PetAnimation(
        emotion: .speak1,
        displayScale: AnimationScale.speak1,
        source: .frames(
            frameNames: PetAnimationLoader.loadFrameNames(prefix: "speakone", maxFrames: 36, maxUniqueFrames: AnimationLimits.maxUniqueFrames),
            fps: effectiveFPS(baseFPS: 8, maxFrames: 36),
            isLoop: true
        )
    )

    static let speak2: PetAnimation = PetAnimation(
        emotion: .speak2,
        displayScale: AnimationScale.speak2,
        source: .frames(
            frameNames: PetAnimationLoader.loadFrameNames(prefix: "speaktwo", maxFrames: 36, maxUniqueFrames: AnimationLimits.maxUniqueFrames),
            fps: effectiveFPS(baseFPS: 8, maxFrames: 36),
            isLoop: true
        )
    )

    static let speak3: PetAnimation = PetAnimation(
        emotion: .speak3,
        displayScale: AnimationScale.speak3,
        source: .frames(
            frameNames: PetAnimationLoader.loadFrameNames(prefix: "speakthree", maxFrames: 30, maxUniqueFrames: AnimationLimits.maxUniqueFrames),
            fps: effectiveFPS(baseFPS: 8, maxFrames: 30),
            isLoop: true
        )
    )

    static let speak1Once: PetAnimation = PetAnimation(
        emotion: .speak1Once,
        displayScale: AnimationScale.speak1Once,
        source: .frames(
            frameNames: PetAnimationLoader.loadFrameNames(prefix: "speakone", maxFrames: 36, maxUniqueFrames: AnimationLimits.maxUniqueFrames),
            fps: effectiveFPS(baseFPS: 8, maxFrames: 36),
            isLoop: false
        )
    )

    static let speak2Once: PetAnimation = PetAnimation(
        emotion: .speak2Once,
        displayScale: AnimationScale.speak2Once,
        source: .frames(
            frameNames: PetAnimationLoader.loadFrameNames(prefix: "speaktwo", maxFrames: 36, maxUniqueFrames: AnimationLimits.maxUniqueFrames),
            fps: effectiveFPS(baseFPS: 8, maxFrames: 36),
            isLoop: false
        )
    )

    static let speak3Once: PetAnimation = PetAnimation(
        emotion: .speak3Once,
        displayScale: AnimationScale.speak3Once,
        source: .frames(
            frameNames: PetAnimationLoader.loadFrameNames(prefix: "speakthree", maxFrames: 30, maxUniqueFrames: AnimationLimits.maxUniqueFrames),
            fps: effectiveFPS(baseFPS: 8, maxFrames: 30),
            isLoop: false
        )
    )

    static let blowbubble1: PetAnimation = PetAnimation(
        emotion: .blowbubble1,
        displayScale: AnimationScale.blowbubble1,
        source: .frames(
            frameNames: PetAnimationLoader.loadFrameNames(prefix: "blowbubbleone", maxFrames: 36, maxUniqueFrames: AnimationLimits.maxUniqueFrames),
            fps: effectiveFPS(baseFPS: 8, maxFrames: 36),
            isLoop: true
        )
    )

    static let blowbubble2: PetAnimation = PetAnimation(
        emotion: .blowbubble2,
        displayScale: AnimationScale.blowbubble2,
        source: .frames(
            frameNames: PetAnimationLoader.loadFrameNames(prefix: "blowbubbletwo", maxFrames: 30, maxUniqueFrames: AnimationLimits.maxUniqueFrames),
            fps: effectiveFPS(baseFPS: 8, maxFrames: 30),
            isLoop: true
        )
    )

    static let like1: PetAnimation = PetAnimation(
        emotion: .like1,
        displayScale: AnimationScale.like1,
        source: .frames(
            frameNames: PetAnimationLoader.loadFrameNames(prefix: "likeone", maxFrames: 36, maxUniqueFrames: AnimationLimits.maxUniqueFrames),
            fps: effectiveFPS(baseFPS: 8, maxFrames: 36),
            isLoop: true
        )
    )

    static let like2: PetAnimation = PetAnimation(
        emotion: .like2,
        displayScale: AnimationScale.like2,
        source: .frames(
            frameNames: PetAnimationLoader.loadFrameNames(prefix: "liketwo", maxFrames: 36, maxUniqueFrames: AnimationLimits.maxUniqueFrames),
            fps: effectiveFPS(baseFPS: 8, maxFrames: 36),
            isLoop: true
        )
    )

    // 新增 surprisedOne：资源名形如 surprisedone0, surprisedone1, ...
    static let surprisedOne: PetAnimation = PetAnimation(
        emotion: .surprisedOne,
        displayScale: AnimationScale.surprisedOne,
        source: .frames(
            frameNames: loopTwiceFrames(prefix: "surprisedone", maxFrames: 31),
            fps: effectiveFPS(baseFPS: 10, maxFrames: 31),
            isLoop: false
        )
    )

    // 新增 surprisedTwo：资源名形如 surprisetwo0, surprisetwo1, ...
    static let surprisedTwo: PetAnimation = PetAnimation(
        emotion: .surprisedTwo,
        displayScale: AnimationScale.surprisedTwo,
        source: .frames(
            frameNames: loopTwiceFrames(prefix: "surprisetwo", maxFrames: 26),
            fps: effectiveFPS(baseFPS: 10, maxFrames: 26),
            isLoop: false
        )
    )

    static let sad1: PetAnimation = PetAnimation(
        emotion: .sad1,
        displayScale: AnimationScale.sad1,
        source: .frames(
            frameNames: PetAnimationLoader.loadFrameNames(prefix: "sadone", maxFrames: 30, maxUniqueFrames: AnimationLimits.maxUniqueFrames),
            fps: effectiveFPS(baseFPS: 8, maxFrames: 30),
            isLoop: true
        )
    )

    static let sad2: PetAnimation = PetAnimation(
        emotion: .sad2,
        displayScale: AnimationScale.sad2,
        source: .frames(
            frameNames: PetAnimationLoader.loadFrameNames(prefix: "sadtwo", maxFrames: 30, maxUniqueFrames: AnimationLimits.maxUniqueFrames),
            fps: effectiveFPS(baseFPS: 8, maxFrames: 30),
            isLoop: true
        )
    )

    // jumptwo 资源只有一套；以下为不同「播放模式」（循环 / 两轮一次性 / 点击播一轮）
    static let jumpTwo: PetAnimation = PetAnimation(
        emotion: .jumpTwo,
        displayScale: AnimationScale.jumpTwo,
        source: .frames(
            frameNames: PetAnimationLoader.loadFrameNames(prefix: "jumptwo", maxFrames: 31, maxUniqueFrames: AnimationLimits.maxUniqueFrames),
            fps: effectiveFPS(baseFPS: 10, maxFrames: 31),
            isLoop: true
        )
    )

    // 惊喜后追加跳：同一套 jumptwo 帧拼成两倍长度，播完两轮后回默认态
    static let jumpTwoOnce: PetAnimation = PetAnimation(
        emotion: .jumpTwoOnce,
        displayScale: AnimationScale.jumpTwo,
        source: .frames(
            frameNames: loopTwiceFrames(prefix: "jumptwo", maxFrames: 31),
            fps: effectiveFPS(baseFPS: 10, maxFrames: 31),
            isLoop: false
        )
    )

    /// 点击反馈：同一套 jumptwo，只跑一轮后回随机 idle（非循环）
    static let jumpTwoTap: PetAnimation = PetAnimation(
        emotion: .jumpTwoTap,
        displayScale: AnimationScale.jumpTwo,
        source: .frames(
            frameNames: PetAnimationLoader.loadFrameNames(prefix: "jumptwo", maxFrames: 31, maxUniqueFrames: AnimationLimits.maxUniqueFrames),
            fps: effectiveFPS(baseFPS: 10, maxFrames: 31),
            isLoop: false
        )
    )

    /// happy1：资源名形如 happyone0, happyone1, …（共 36 帧）
    static let happy1: PetAnimation = PetAnimation(
        emotion: .happy1,
        displayScale: AnimationScale.happy1,
        source: .frames(
            frameNames: PetAnimationLoader.loadFrameNames(prefix: "happyone", maxFrames: 36, maxUniqueFrames: AnimationLimits.maxUniqueFrames),
            fps: effectiveFPS(baseFPS: 8, maxFrames: 36),
            isLoop: true
        )
    )

    /// jump1：资源名形如 jumpone0, jumpone1, …（共 36 帧）
    static let jump1: PetAnimation = PetAnimation(
        emotion: .jump1,
        displayScale: AnimationScale.jump1,
        source: .frames(
            frameNames: PetAnimationLoader.loadFrameNames(prefix: "jumpone", maxFrames: 36, maxUniqueFrames: AnimationLimits.maxUniqueFrames),
            fps: effectiveFPS(baseFPS: 10, maxFrames: 36),
            isLoop: true
        )
    )

    /// 惊喜后：jumpone 两轮长度，播完回默认展示
    static let jump1Once: PetAnimation = PetAnimation(
        emotion: .jump1Once,
        displayScale: AnimationScale.jump1,
        source: .frames(
            frameNames: loopTwiceFrames(prefix: "jumpone", maxFrames: 36),
            fps: effectiveFPS(baseFPS: 10, maxFrames: 36),
            isLoop: false
        )
    )

    /// 点击：jumpone 播一轮
    static let jump1Tap: PetAnimation = PetAnimation(
        emotion: .jump1Tap,
        displayScale: AnimationScale.jump1,
        source: .frames(
            frameNames: PetAnimationLoader.loadFrameNames(prefix: "jumpone", maxFrames: 36, maxUniqueFrames: AnimationLimits.maxUniqueFrames),
            fps: effectiveFPS(baseFPS: 10, maxFrames: 36),
            isLoop: false
        )
    )

    /// happy1 播一轮（非循环）
    static let happy1Once: PetAnimation = PetAnimation(
        emotion: .happy1Once,
        displayScale: AnimationScale.happy1,
        source: .frames(
            frameNames: PetAnimationLoader.loadFrameNames(prefix: "happyone", maxFrames: 36, maxUniqueFrames: AnimationLimits.maxUniqueFrames),
            fps: effectiveFPS(baseFPS: 8, maxFrames: 36),
            isLoop: false
        )
    )

    /// 点击三连：播放一轮 like2 后回 idle
    static let like2Once: PetAnimation = PetAnimation(
        emotion: .like2Once,
        displayScale: AnimationScale.like2,
        source: .frames(
            frameNames: PetAnimationLoader.loadFrameNames(prefix: "liketwo", maxFrames: 36, maxUniqueFrames: AnimationLimits.maxUniqueFrames),
            fps: effectiveFPS(baseFPS: 8, maxFrames: 36),
            isLoop: false
        )
    )

    /// 点击暴怒：播放一轮生气后回 idle
    static let angry2Once: PetAnimation = PetAnimation(
        emotion: .angry2Once,
        displayScale: AnimationScale.angry2,
        source: .frames(
            frameNames: PetAnimationLoader.loadFrameNames(prefix: "angrytwo", maxFrames: 30, maxUniqueFrames: AnimationLimits.maxUniqueFrames),
            fps: effectiveFPS(baseFPS: 8, maxFrames: 30),
            isLoop: false
        )
    )

    /// happyIdle 播一轮
    static let happyIdleOnce: PetAnimation = PetAnimation(
        emotion: .happyIdleOnce,
        displayScale: AnimationScale.happyIdleOnce,
        source: .frames(
            frameNames: PetAnimationLoader.loadFrameNames(prefix: "happyidle", maxFrames: 36, maxUniqueFrames: AnimationLimits.maxUniqueFrames),
            fps: effectiveFPS(baseFPS: 7, maxFrames: 36),
            isLoop: false
        )
    )

    /// like1 播一轮
    static let like1Once: PetAnimation = PetAnimation(
        emotion: .like1Once,
        displayScale: AnimationScale.like1Once,
        source: .frames(
            frameNames: PetAnimationLoader.loadFrameNames(prefix: "likeone", maxFrames: 36, maxUniqueFrames: AnimationLimits.maxUniqueFrames),
            fps: effectiveFPS(baseFPS: 8, maxFrames: 36),
            isLoop: false
        )
    )

    /// 吃东西等待：循环 idleapple
    static let eatingWait: PetAnimation = PetAnimation(
        emotion: .eatingWait,
        displayScale: AnimationScale.eatingWait,
        source: .frames(
            frameNames: PetAnimationLoader.loadFrameNames(prefix: "idleapple", maxFrames: 30, maxUniqueFrames: AnimationLimits.maxUniqueFrames),
            fps: effectiveFPS(baseFPS: 8, maxFrames: 30),
            isLoop: true
        )
    )

    /// 吃东西：播一轮 eatapple
    static let eatingOnce: PetAnimation = PetAnimation(
        emotion: .eatingOnce,
        displayScale: AnimationScale.eatingOnce,
        source: .frames(
            frameNames: PetAnimationLoader.loadFrameNames(prefix: "eatapple", maxFrames: 30, maxUniqueFrames: AnimationLimits.maxUniqueFrames),
            fps: effectiveFPS(baseFPS: 8, maxFrames: 30),
            isLoop: false
        )
    )

    static let sleepy: PetAnimation = PetAnimation(
        emotion: .sleepy,
        displayScale: AnimationScale.sleepy,
        source: .frames(
            frameNames: PetAnimationLoader.loadFrameNames(prefix: "sleepy", maxFrames: 30, maxUniqueFrames: AnimationLimits.maxUniqueFrames),
            fps: effectiveFPS(baseFPS: 8, maxFrames: 30),
            isLoop: true
        )
    )

    /// 深夜随机插入：`sleepy` 资源播一轮（`PetEmotion.sleep`）
    static let sleepOnce: PetAnimation = PetAnimation(
        emotion: .sleep,
        displayScale: AnimationScale.sleep,
        source: .frames(
            frameNames: PetAnimationLoader.loadFrameNames(prefix: "sleepy", maxFrames: 30, maxUniqueFrames: AnimationLimits.maxUniqueFrames),
            fps: effectiveFPS(baseFPS: 8, maxFrames: 30),
            isLoop: false
        )
    )

    /// 夜间睡眠等待：循环 sleepy 资源，等待用户点击触发入睡
    static let nightSleepWait: PetAnimation = PetAnimation(
        emotion: .nightSleepWait,
        displayScale: AnimationScale.nightSleepWait,
        source: .frames(
            frameNames: PetAnimationLoader.loadFrameNames(prefix: "sleepy", maxFrames: 30, maxUniqueFrames: AnimationLimits.maxUniqueFrames),
            fps: effectiveFPS(baseFPS: 8, maxFrames: 30),
            isLoop: true
        )
    )

    /// 夜间睡眠：入睡过渡（fallasleep 播一轮）
    static let fallAsleep: PetAnimation = PetAnimation(
        emotion: .fallAsleep,
        displayScale: AnimationScale.fallAsleep,
        source: .frames(
            frameNames: PetAnimationLoader.loadFrameNames(prefix: "fallasleep", maxFrames: 30, maxUniqueFrames: AnimationLimits.maxUniqueFrames),
            fps: effectiveFPS(baseFPS: 8, maxFrames: 30),
            isLoop: false
        )
    )

    /// 夜间睡眠：sleeploop 循环到早晨被叫醒
    static let sleepLoop: PetAnimation = PetAnimation(
        emotion: .sleepLoop,
        displayScale: AnimationScale.sleepLoop,
        source: .frames(
            frameNames: PetAnimationLoader.loadFrameNames(prefix: "sleeploop", maxFrames: 30, maxUniqueFrames: AnimationLimits.maxUniqueFrames),
            fps: effectiveFPS(baseFPS: 8, maxFrames: 30),
            isLoop: true
        )
    )
}

/// 根据 ViewModel 当前动作，展示对应帧序列或 mp4
struct PetAnimationView: View {
    @ObservedObject var viewModel: PetViewModel

    var body: some View {
        let animation = viewModel.currentAnimation
        switch animation.source {
        case .frames(let frameNames, let fps, _):
            PetFramesView(
                viewModel: viewModel,
                frameNames: frameNames,
                fps: fps,
                displayScale: animation.displayScale
            )
        case .video(let videoFileName, let isLoop):
            PetVideoView(videoFileName: videoFileName, isLoop: isLoop)
                .scaleEffect(animation.displayScale)
                // 禁止视频控件接收触摸，避免出现播放按钮/暂停控制层，
                // 同时保证外层点击能切换动画。
                .allowsHitTesting(false)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct PetFramesView: View {
    @ObservedObject var viewModel: PetViewModel
    let frameNames: [String]
    let fps: Double
    let displayScale: CGFloat

    @State private var lastUpdate: Date = Date()
    // 用于驱动帧动画（高频），并确保在切换动作时取消旧计时器
    @State private var timerCancellable: AnyCancellable?

    var body: some View {
        let safeIndex = frameNames.indices.contains(viewModel.currentFrameIndex) ? viewModel.currentFrameIndex : 0
        let frameName = frameNames.isEmpty ? "" : frameNames[safeIndex]

        ZStack {
            if !frameName.isEmpty {
                Image(frameName)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(displayScale)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // 强制 SwiftUI 每帧重建该 Image，降低旧纹理/渲染缓存滞留概率
                    .id(frameName)
                    // 禁用隐式动画，避免中间帧/过渡导致额外纹理被保留
                    .transaction { txn in
                        txn.animation = nil
                    }
            } else {
                Color.clear
            }
        }
        .onAppear {
            print("🎬 PetFramesView appear:",
                  "emotion=", String(describing: viewModel.currentEmotion),
                  "frames=", frameNames.count,
                  "fps=", fps,
                  "displayScale=", displayScale)

            // 重置时间，避免刚切换时立刻推进多帧
            lastUpdate = Date()

            timerCancellable?.cancel()
            timerCancellable = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common)
                .autoconnect()
                .sink { now in
                    let elapsed = now.timeIntervalSince(lastUpdate)
                    let frameDuration = 1.0 / max(fps, 1)
                    if elapsed >= frameDuration {
                        viewModel.advanceFrame()
                        lastUpdate = now
                    }
                }
        }
        .onDisappear {
            timerCancellable?.cancel()
            timerCancellable = nil
        }
    }
}

private struct PetVideoView: View {
    let videoFileName: String // 不带扩展名，如 idleone / scale
    let isLoop: Bool

    @State private var player: AVPlayer?
    @State private var endObserver: NSObjectProtocol?

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
            } else {
                Color.clear
            }
        }
        .onAppear {
            configurePlayer()
        }
        .onDisappear {
            teardown()
        }
        .onChange(of: videoFileName) {
            configurePlayer()
        }
        .onChange(of: isLoop) {
            configurePlayer()
        }
    }

    private func configurePlayer() {
        teardown()

        guard let url = Bundle.main.url(forResource: videoFileName, withExtension: "mp4") else {
            player = nil
            return
        }

        let item = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.isMuted = true
        newPlayer.actionAtItemEnd = .pause

        if isLoop {
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak newPlayer] _ in
                guard let player = newPlayer else { return }
                player.seek(to: .zero) { _ in
                    player.play()
                }
            }
        }

        player = newPlayer
        newPlayer.play()
    }

    private func teardown() {
        if let obs = endObserver {
            NotificationCenter.default.removeObserver(obs)
            endObserver = nil
        }
        player?.pause()
        player = nil
    }
}
