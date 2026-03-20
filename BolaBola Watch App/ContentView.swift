//
//  ContentView.swift
//  BolaBola Watch App
//
//  Created by Nan on 3/15/26.
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
    case scale        // 新增：scale 动作
    case die          // 新增：DIE 动作
    case angry2       // 新增：angry2 动作
    case unhappy      // 新增：不高兴 动作
    case letter       // 新增：信件 动作
    case hurt         // 新增：委屈 动作
    case question1    // 新增：question1 动作
    case question2    // 新增：question2 动作
    case question3    // 新增：question3 动作
    case speak1       // 新增：speak1 动作
    case speak2       // 新增：speak2 动作
    case speak3       // 新增：speak3 动作
    case blowbubble1  // 新增：blowbubble1 动作
    case blowbubble2  // 新增：blowbubble2 动作
    case like1        // 新增：like1 动作
    case like2        // 新增：like2 动作
    case surprisedOne // 新增：惊喜1 动作
    case surprisedTwo // 新增：惊喜2 动作
    case sad1         // 新增：sad1 动作
    case sad2         // 新增：sad2 动作
    case jumpTwo      // 新增：跳跃2 动作
    case jumpTwoOnce  // 用于惊喜后“一次性”跳跃（2轮后自动回默认）
    case sleepy       // 新增：sleepy 动作
    case happy
    case angry
    case sleep
    case special
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

// MARK: - 动画大小配置
// 你可以在这里“单独”调每个动作的大小（对应 PetEmotion / Assets 前缀）。
enum AnimationScale {
    static let idle: CGFloat = 2.0
    static let idleOne: CGFloat = 3.0
    static let idleTwo: CGFloat = 3.0
    static let idleThree: CGFloat = 3.0
    static let scale: CGFloat = 2.0

    static let die: CGFloat = 3.0
    static let happy: CGFloat = 2.0
    static let angry2: CGFloat = 2.0
    static let unhappy: CGFloat = 2.5
    static let letter: CGFloat = 2.5
    static let hurt: CGFloat = 2.5

    static let question1: CGFloat = 2.5
    static let question2: CGFloat = 2.5
    static let question3: CGFloat = 2.5

    static let speak1: CGFloat = 2.5
    static let speak2: CGFloat = 2.5
    static let speak3: CGFloat = 2.5

    static let blowbubble1: CGFloat = 2.5
    static let blowbubble2: CGFloat = 2.5
    static let like1: CGFloat = 2.5
    static let like2: CGFloat = 2.5
    static let surprisedOne: CGFloat = 2.5
    static let surprisedTwo: CGFloat = 2.5
    static let sad1: CGFloat = 2.5
    static let sad2: CGFloat = 2.5
    static let jumpTwo: CGFloat = 2.5
    static let sleepy: CGFloat = 2.5
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

    // 新增 jumpTwo：资源名形如 jumptwo0, jumptwo1, ...
    static let jumpTwo: PetAnimation = PetAnimation(
        emotion: .jumpTwo,
        displayScale: AnimationScale.jumpTwo,
        source: .frames(
            frameNames: PetAnimationLoader.loadFrameNames(prefix: "jumptwo", maxFrames: 31, maxUniqueFrames: AnimationLimits.maxUniqueFrames),
            fps: effectiveFPS(baseFPS: 10, maxFrames: 31),
            isLoop: true
        )
    )

    // 用于惊喜后“额外跳一下”的一次性版本：播放 2 轮后自动回默认状态。
    static let jumpTwoOnce: PetAnimation = PetAnimation(
        emotion: .jumpTwoOnce,
        displayScale: AnimationScale.jumpTwo,
        source: .frames(
            frameNames: loopTwiceFrames(prefix: "jumptwo", maxFrames: 31),
            fps: effectiveFPS(baseFPS: 10, maxFrames: 31),
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
}

// MARK: - ViewModel（简单状态机雏形）

final class PetViewModel: ObservableObject {
    @Published var currentEmotion: PetEmotion = .idle
    @Published var currentFrameIndex: Int = 0
    @Published var companionValue: Double = 50
    // 内部陪伴值允许小数（用于 5 分钟级别的 +/-0.1/-0.1 平滑），对外与状态机使用“四舍五入后的整数值”。
    private var companionValueInternal: Double = 50

    private let surpriseMilestoneHours: Double = {
        // 为了方便你在真机上快速验证逻辑：Debug 下把 100 小时缩短到很小的数。
        // Release 仍然是 100 小时。
        #if DEBUG
        return 0.02 // 0.02h ~= 72 秒
        #else
        return 100
        #endif
    }()

    private let companionValueKey = "bola_companionValue"
    private let lastTickTimestampKey = "bola_lastTickTimestamp"

    // Surprise：累积“活跃时间”的总秒数（只在 App active 时计入）
    private let totalActiveSecondsKey = "bola_totalActiveSeconds"
    private let activeCarrySecondsKey = "bola_activeCarrySeconds"
    // companionValue 的衰减：累积“非活跃扣减时长”的总秒数（00:00~07:00 不扣减）
    private let inactiveCarrySecondsKey = "bola_inactiveCarrySeconds"

    private let lastSurpriseAtHoursKey = "bola_lastSurpriseAtHours"

    private var totalActiveSeconds: TimeInterval = 0
    private var activeCarrySeconds: TimeInterval = 0
    private var inactiveCarrySeconds: TimeInterval = 0
    private var surprisePending: Bool = false
    // 记录“上一次惊喜触发在多少小时里程碑”，用于实现 100h -> 200h -> 300h… 的幂等触发。
    private var lastSurpriseMilestoneHours: Double = 0
    // 惊喜播放完（surprisedOne/Two 2轮）后，需要排队再播放一次 jumpTwoOnce。
    private var surpriseJumpTwoQueued: Bool = false
    private var lastTapTimestamp: TimeInterval = 0

    private var currentDefaultEmotion: PetEmotion = .idle
    private var milestoneTimerCancellable: AnyCancellable?
    private var lastTickTimestamp: TimeInterval = 0

    /// 点击宠物时轮换的动作列表（你后续加动作只要往这里补）
    private let tapCycleEmotions: [PetEmotion] = [
        .idle, .idleOne, .idleTwo, .idleThree, .scale,
        .die,
        .angry2,
        .unhappy, .letter, .hurt,
        .question1, .question2, .question3,
        .speak1, .speak2, .speak3
        ,
        .blowbubble1, .blowbubble2,
        .like1, .like2,
        .surprisedOne, .surprisedTwo,
        .sad1, .sad2,
        .jumpTwo,
        .sleepy
    ]

    init() {
        // 初始化：按“App active 时间 + 依据时段不扣减规则”计算 companionValue，
        // 同时按 active 累计时间计算惊喜里程碑。
        hydrateTotalTimeAndSurpriseState()

        // DEBUG：为了你能立刻验证惊喜逻辑（而不是等几十秒/几小时），
        // 直接把 totalActiveSeconds 拉到里程碑阈值，并清掉“已触发过惊喜”的记录。
        #if DEBUG
        lastSurpriseMilestoneHours = 0
        surprisePending = false
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: lastSurpriseAtHoursKey)
        totalActiveSeconds = max(totalActiveSeconds, surpriseMilestoneHours * 3600.0)
        defaults.set(totalActiveSeconds, forKey: totalActiveSecondsKey)

        // DEBUG：先固定一个陪伴值，方便你验证“播完回默认”的效果。
        companionValueInternal = 80
        companionValue = companionValueInternal.rounded()
        defaults.set(companionValueInternal, forKey: companionValueKey)
        activeCarrySeconds = 0
        inactiveCarrySeconds = 0
        defaults.set(activeCarrySeconds, forKey: activeCarrySecondsKey)
        defaults.set(inactiveCarrySeconds, forKey: inactiveCarrySecondsKey)
        #endif

        selectDefaultEmotion()
        currentEmotion = currentDefaultEmotion

        // 启动后台检查：如果在运行过程中跨过 100 小时里程碑，则触发惊喜。
        startMilestoneTimer()
        #if DEBUG
        // 给你几秒切换到“非默认动画”，验证“排队到播放结束后再触发惊喜”。
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.maybeTriggerSurpriseIfNeeded()
        }
        #else
        maybeTriggerSurpriseIfNeeded()
        #endif
    }

    /// 当前情绪对应的动画配置
    var currentAnimation: PetAnimation {
        switch currentEmotion {
        case .idle:
            return PetAnimations.idle
        case .idleOne:
            return PetAnimations.idleOne
        case .idleTwo:
            return PetAnimations.idleTwo
        case .idleThree:
            return PetAnimations.idleThree
        case .scale:
            return PetAnimations.scale
        case .die:
            return PetAnimations.die
        case .angry2:
            return PetAnimations.angry2
        case .unhappy:
            return PetAnimations.unhappy
        case .letter:
            return PetAnimations.letter
        case .hurt:
            return PetAnimations.hurt
        case .question1:
            return PetAnimations.question1
        case .question2:
            return PetAnimations.question2
        case .question3:
            return PetAnimations.question3
        case .speak1:
            return PetAnimations.speak1
        case .speak2:
            return PetAnimations.speak2
        case .speak3:
            return PetAnimations.speak3
        case .blowbubble1:
            return PetAnimations.blowbubble1
        case .blowbubble2:
            return PetAnimations.blowbubble2
        case .like1:
            return PetAnimations.like1
        case .like2:
            return PetAnimations.like2
        case .surprisedOne:
            return PetAnimations.surprisedOne
        case .surprisedTwo:
            return PetAnimations.surprisedTwo
        case .sad1:
            return PetAnimations.sad1
        case .sad2:
            return PetAnimations.sad2
        case .jumpTwo:
            return PetAnimations.jumpTwo
        case .jumpTwoOnce:
            return PetAnimations.jumpTwoOnce
        case .sleepy:
            return PetAnimations.sleepy
        case .happy:
            return PetAnimations.happy
        case .angry:
            return PetAnimations.happy // 占位，后面改成对应动画
        case .sleep:
            return PetAnimations.idle  // 占位
        case .special:
            return PetAnimations.happy // 占位
        }
    }

    /// 推进一帧（由外部定时器控制节奏）
    func advanceFrame() {
        switch currentAnimation.source {
        case .frames(let frameNames, _, let isLoop):
            let frameCount = max(frameNames.count, 1)
            let next = currentFrameIndex + 1
            if next >= frameCount {
                if isLoop {
                    currentFrameIndex = 0
                } else {
                    // 非循环动画播完：回到“默认状态”
                    // 惊喜/插入类动画在播放完成后，统一回到 companionValue 决定的默认状态。
                    if surpriseJumpTwoQueued {
                        // 惊喜分两段：surprisedOne/Two 播完（2轮）后，额外再播一次 jumpTwoOnce。
                        surpriseJumpTwoQueued = false
                        currentEmotion = .jumpTwoOnce
                        currentFrameIndex = 0
                        // 提前返回：不要在 jumpTwoOnce 播放期间启动下一次惊喜排队。
                        return
                    } else {
                        selectDefaultEmotion()
                        currentEmotion = currentDefaultEmotion
                    }
                    // 如果里程碑触发时因为播放了别的动画而排队，则这里开始播放惊喜。
                    if surprisePending {
                        maybeTriggerSurpriseIfNeeded(forcePending: true)
                    }
                    currentFrameIndex = 0
                }
            } else {
                currentFrameIndex = next
            }
        case .video:
            // 视频动画不需要逐帧推进
            return
        }
    }

    func cycleEmotionOnTap() {
        let nowTs = Date().timeIntervalSince1970
        // 点击冷却：3 秒内不允许重复触发（避免狂点打乱状态）
        if nowTs - lastTapTimestamp < 3 {
            return
        }
        lastTapTimestamp = nowTs

        let v = Int(companionValue.rounded()) // companionValue 已经是四舍五入后的整数

        // die 段：无反应（强化死亡无交互感）
        if v <= 2 {
            return
        }

        // 先刷新“主状态”，用它来确定当前分段的基础情绪。
        selectDefaultEmotion()
        let main = currentDefaultEmotion

        let next: PetEmotion
        switch v {
        case 3...9:
            // hurt ↔ sad1/sad2
            next = Bool.random() ? .hurt : main
        case 10...19:
            // hurt ↔ unhappy
            next = Bool.random() ? .hurt : .unhappy
        case 20...39:
            // question1 ↔ sad1
            next = Bool.random() ? .question1 : .sad1
        case 40...59:
            // scale ↔ idleOne/idleTwo
            next = Bool.random() ? .scale : main
        case 60...69:
            // speak1 ↔ question1/question2
            next = Bool.random() ? .speak1 : main
        case 70...79:
            // speak* ↔ question*
            next = Bool.random() ? main : (v % 2 == 0 ? .question1 : .question2)
        case 80...89:
            // like1 ↔ jumpTwo ↔ idleThree
            next = [PetEmotion.like1, .jumpTwo, .idleThree].randomElement() ?? .like1
        default:
            // 90...100：like2 ↔ blowbubble2 ↔ jumpTwo
            next = [PetEmotion.like2, .blowbubble2, .jumpTwo].randomElement() ?? .like2
        }

        currentEmotion = next
        currentFrameIndex = 0
        print("🐾 Tap -> switch emotion:", String(describing: currentEmotion))
    }

    // MARK: - Companion value time coupling

    private func clampCompanionValue(_ v: Double) -> Double {
        min(max(v, 0), 100)
    }

    // App active 时：每累计 5 分钟 +1（00:00~07:00 也计入加成）
    private func applyActiveAddition(_ seconds: TimeInterval) {
        activeCarrySeconds += seconds
        while activeCarrySeconds >= 300 {
            companionValueInternal += 1
            activeCarrySeconds -= 300
        }

        // 清理浮点误差（-0.1 会产生 0.30000000004 之类的问题）
        companionValueInternal = (companionValueInternal * 10).rounded() / 10
        companionValueInternal = clampCompanionValue(companionValueInternal)
        companionValue = companionValueInternal.rounded()
    }

    // App inactive 时：每累计 5 分钟 -0.1（00:00~07:00 不扣减）
    private func applyInactiveDeduction(_ secondsToDeduct: TimeInterval) {
        inactiveCarrySeconds += secondsToDeduct
        while inactiveCarrySeconds >= 300 {
            companionValueInternal -= 0.1
            inactiveCarrySeconds -= 300
        }
        companionValueInternal = (companionValueInternal * 10).rounded() / 10
        companionValueInternal = clampCompanionValue(companionValueInternal)
        companionValue = companionValueInternal.rounded()
    }

    // 扣减窗口：每天 00:00~07:00 这段不扣减，其余时间都可用于扣减
    private func deductibleSecondsOutsideNightWindow(from: Date, to: Date) -> TimeInterval {
        if to <= from { return 0 }
        let calendar = Calendar.current
        var noDeduct: TimeInterval = 0

        var cursor = from
        while cursor < to {
            let dayStart = calendar.startOfDay(for: cursor)
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) else { break }

            let chunkEnd = min(to, nextDay)
            let windowStart = dayStart
            let windowEnd = dayStart.addingTimeInterval(7 * 3600)

            let overlapStart = max(cursor, windowStart)
            let overlapEnd = min(chunkEnd, windowEnd)

            if overlapEnd > overlapStart {
                noDeduct += overlapEnd.timeIntervalSince(overlapStart)
            }
            cursor = chunkEnd
        }

        return max(0, to.timeIntervalSince(from) - noDeduct)
    }

    // MARK: - Surprise / Default state machine (minimal, testable)

    private func hydrateTotalTimeAndSurpriseState() {
        let defaults = UserDefaults.standard
        let now = Date()
        let nowTs = now.timeIntervalSince1970

        // 1) hydration: companionValue / totalActiveSeconds / carry
        if defaults.object(forKey: companionValueKey) != nil {
            companionValueInternal = defaults.double(forKey: companionValueKey)
        } else {
            companionValueInternal = 50 // 默认值：避免一开始就太悲伤
        }

        totalActiveSeconds = defaults.double(forKey: totalActiveSecondsKey)
        activeCarrySeconds = defaults.double(forKey: activeCarrySecondsKey)
        inactiveCarrySeconds = defaults.double(forKey: inactiveCarrySecondsKey)

        companionValueInternal = clampCompanionValue(companionValueInternal)
        companionValue = companionValueInternal.rounded()

        // 2) inactive deduction: 上次 tick 到现在的非活跃时间
        if defaults.object(forKey: lastTickTimestampKey) != nil {
            lastTickTimestamp = defaults.double(forKey: lastTickTimestampKey)
            let lastDate = Date(timeIntervalSince1970: lastTickTimestamp)
            let inactiveDeductSeconds = deductibleSecondsOutsideNightWindow(from: lastDate, to: now)
            applyInactiveDeduction(inactiveDeductSeconds)
        } else {
            lastTickTimestamp = nowTs
        }

        // 3) persist: lastTickTimestamp + 当前状态
        lastTickTimestamp = nowTs
        defaults.set(companionValueInternal, forKey: companionValueKey)
        defaults.set(totalActiveSeconds, forKey: totalActiveSecondsKey)
        defaults.set(activeCarrySeconds, forKey: activeCarrySecondsKey)
        defaults.set(inactiveCarrySeconds, forKey: inactiveCarrySecondsKey)
        defaults.set(lastTickTimestamp, forKey: lastTickTimestampKey)

        // 4) surprise idempotency：lastSurpriseMilestoneHours >= 当前应该触发的下一档时则不触发
        lastSurpriseMilestoneHours = defaults.double(forKey: lastSurpriseAtHoursKey)
    }

    private func startMilestoneTimer() {
        milestoneTimerCancellable?.cancel()
        milestoneTimerCancellable = Timer
            .publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.accumulateTimeAndMaybeTrigger()
            }
    }

    private func accumulateTimeAndMaybeTrigger() {
        let defaults = UserDefaults.standard
        let now = Date()
        let nowTs = now.timeIntervalSince1970

        // active delta: App 处于运行状态时的时间增量
        let effectiveDelta = max(0, nowTs - lastTickTimestamp)
        if effectiveDelta > 0 {
            let oldDefaultEmotion = currentDefaultEmotion

            // 1) companionValue: 每累计 5 分钟 active +1
            applyActiveAddition(effectiveDelta)

            // 2) 根据新的 companionValue 重新计算默认状态；
            //    如果当前就在“默认状态”，则切换到新的默认状态。
            selectDefaultEmotion()
            if currentEmotion == oldDefaultEmotion {
                currentEmotion = currentDefaultEmotion
                currentFrameIndex = 0
            }

            // 2) surprise: active 累计用于 100 小时里程碑
            totalActiveSeconds += effectiveDelta

            // persist
            defaults.set(companionValueInternal, forKey: companionValueKey)
            defaults.set(totalActiveSeconds, forKey: totalActiveSecondsKey)
            defaults.set(activeCarrySeconds, forKey: activeCarrySecondsKey)
            defaults.set(inactiveCarrySeconds, forKey: inactiveCarrySecondsKey)
            lastTickTimestamp = nowTs
            defaults.set(lastTickTimestamp, forKey: lastTickTimestampKey)
        }

        maybeTriggerSurpriseIfNeeded()
    }

    private func maybeTriggerSurpriseIfNeeded(forcePending: Bool = false) {
        let totalHours = totalActiveSeconds / 3600.0

        // 100h -> 200h -> 300h ...：每次在上一次触发点基础上再往后推一步。
        let nextMilestoneHours: Double = (lastSurpriseMilestoneHours <= 0)
        ? surpriseMilestoneHours
        : (lastSurpriseMilestoneHours + surpriseMilestoneHours)

        guard totalHours >= nextMilestoneHours else { return }
        // 已经触发过下一档就不再触发
        guard lastSurpriseMilestoneHours < nextMilestoneHours else { return }

        // 规则：只有当当前动画属于默认状态时才立即触发；
        // 如果当前在播放别的动画，则先排队（等待“非循环动画”播放结束后再触发）。
        let canStartNow = (currentEmotion == currentDefaultEmotion)
        if !canStartNow && !forcePending {
            surprisePending = true
            return
        }

        surprisePending = false
        surpriseJumpTwoQueued = true

        lastSurpriseMilestoneHours = nextMilestoneHours
        UserDefaults.standard.set(nextMilestoneHours, forKey: lastSurpriseAtHoursKey)

        // 里程碑触发后：随机只选一个惊喜动画。
        currentEmotion = Bool.random() ? .surprisedOne : .surprisedTwo
        currentFrameIndex = 0
        print("🎉 Surprise triggered at hours:", totalHours, "(milestone:", nextMilestoneHours, ") =>", String(describing: currentEmotion))
    }

    private func selectDefaultEmotion() {
        // 默认状态由 companionValue 决定（为了避免抖动，这里用确定性映射）。
        let v = Int(companionValue.rounded())
        if v <= 2 {
            currentDefaultEmotion = .die
        } else if v <= 9 {
            // 3~9：sad1/sad2（随机循环的等价：按 v 做确定性分层）
            currentDefaultEmotion = (v % 2 == 0) ? .sad2 : .sad1
        } else if v <= 19 {
            currentDefaultEmotion = .unhappy
        } else if v <= 39 {
            currentDefaultEmotion = .sad1
        } else if v <= 59 {
            // 40~59：idleOne/idleTwo
            currentDefaultEmotion = (v % 2 == 0) ? .idleOne : .idleTwo
        } else if v <= 69 {
            // 60~69：question1/question2
            currentDefaultEmotion = (v % 2 == 0) ? .question1 : .question2
        } else if v <= 79 {
            // 70~79：speak1/speak2
            currentDefaultEmotion = (v % 2 == 0) ? .speak1 : .speak2
        } else if v <= 89 {
            // 80~89：like1/idleThree/jumpTwo
            switch v % 3 {
            case 0: currentDefaultEmotion = .like1
            case 1: currentDefaultEmotion = .idleThree
            default: currentDefaultEmotion = .jumpTwo
            }
        } else {
            // 90~100：like2/blowbubble2/jumpTwo
            switch v % 3 {
            case 0: currentDefaultEmotion = .like2
            case 1: currentDefaultEmotion = .blowbubble2
            default: currentDefaultEmotion = .jumpTwo
            }
        }
    }
}

// MARK: - 视图

struct ContentView: View {
    @StateObject private var viewModel = PetViewModel()

    var body: some View {
        VStack(spacing: 8) {
            PetAnimationView(viewModel: viewModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .highPriorityGesture(
                    TapGesture().onEnded { viewModel.cycleEmotionOnTap() }
                )

            Text(Date(), style: .time)
                .font(.headline)

            HStack {
                Text("陪伴值")
                ProgressView(value: viewModel.companionValue / 100.0)
            }
            .font(.footnote)
        }
        .padding()
    }
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

