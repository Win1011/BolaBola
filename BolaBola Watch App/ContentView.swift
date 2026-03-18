//
//  ContentView.swift
//  BolaBola Watch App
//
//  Created by Nan on 3/15/26.
//

import SwiftUI
import Combine
import UIKit
import AVFoundation
import AVKit

// MARK: - 基础模型

/// 宠物当前的大情绪 / 动作类型
enum PetEmotion {
    case idle
    case idleOne      // 新增：idleone 动作
    case scale        // 新增：scale 动作
    case angry2       // 新增：angry2 动作
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
    case sad1         // 新增：sad1 动作
    case sad2         // 新增：sad2 动作
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
    static let scale: CGFloat = 2.0

    static let happy: CGFloat = 2.0
    static let angry2: CGFloat = 2.0

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
    static let sad1: CGFloat = 2.5
    static let sad2: CGFloat = 2.5
    static let sleepy: CGFloat = 2.5
}

// MARK: - 动画帧限制（用于控制 watchOS 内存）
// watchOS 上循环播放时，图片/纹理缓存可能持续增长。
// 通过限制“实际参与播放的独特帧数量”，可以显著降低 OOM 风险。
enum AnimationLimits {
    static let maxUniqueFrames: Int = 16
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
    // 当前只有 shake 这一套动画，我们先把它当作 idle 来用：
    // 资源名形如：shake0, shake1, ...
    static let idle: PetAnimation = PetAnimation(
        emotion: .idle,
        displayScale: AnimationScale.idle,
        source: .frames(
            frameNames: PetAnimationLoader.loadFrameNames(prefix: "shake", maxFrames: 23),
            fps: 6,
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
            fps: 7,
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
            fps: 7,
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
            fps: 8,
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
            fps: 8,
            isLoop: true
        )
    )

    static let question1: PetAnimation = PetAnimation(
        emotion: .question1,
        displayScale: AnimationScale.question1,
        source: .frames(
            frameNames: PetAnimationLoader.loadFrameNames(prefix: "questionone", maxFrames: 30, maxUniqueFrames: AnimationLimits.maxUniqueFrames),
            fps: 8,
            isLoop: true
        )
    )

    static let question2: PetAnimation = PetAnimation(
        emotion: .question2,
        displayScale: AnimationScale.question2,
        source: .frames(
            frameNames: PetAnimationLoader.loadFrameNames(prefix: "questiontwo", maxFrames: 30, maxUniqueFrames: AnimationLimits.maxUniqueFrames),
            fps: 8,
            isLoop: true
        )
    )

    static let question3: PetAnimation = PetAnimation(
        emotion: .question3,
        displayScale: AnimationScale.question3,
        source: .frames(
            frameNames: PetAnimationLoader.loadFrameNames(prefix: "questionthree", maxFrames: 30, maxUniqueFrames: AnimationLimits.maxUniqueFrames),
            fps: 8,
            isLoop: true
        )
    )

    static let speak1: PetAnimation = PetAnimation(
        emotion: .speak1,
        displayScale: AnimationScale.speak1,
        source: .frames(
            frameNames: PetAnimationLoader.loadFrameNames(prefix: "speakone", maxFrames: 36, maxUniqueFrames: AnimationLimits.maxUniqueFrames),
            fps: 8,
            isLoop: true
        )
    )

    static let speak2: PetAnimation = PetAnimation(
        emotion: .speak2,
        displayScale: AnimationScale.speak2,
        source: .frames(
            frameNames: PetAnimationLoader.loadFrameNames(prefix: "speaktwo", maxFrames: 36, maxUniqueFrames: AnimationLimits.maxUniqueFrames),
            fps: 8,
            isLoop: true
        )
    )

    static let speak3: PetAnimation = PetAnimation(
        emotion: .speak3,
        displayScale: AnimationScale.speak3,
        source: .frames(
            frameNames: PetAnimationLoader.loadFrameNames(prefix: "speakthree", maxFrames: 30, maxUniqueFrames: AnimationLimits.maxUniqueFrames),
            fps: 8,
            isLoop: true
        )
    )

    static let blowbubble1: PetAnimation = PetAnimation(
        emotion: .blowbubble1,
        displayScale: AnimationScale.blowbubble1,
        source: .frames(
            frameNames: PetAnimationLoader.loadFrameNames(prefix: "blowbubbleone", maxFrames: 36, maxUniqueFrames: AnimationLimits.maxUniqueFrames),
            fps: 8,
            isLoop: true
        )
    )

    static let blowbubble2: PetAnimation = PetAnimation(
        emotion: .blowbubble2,
        displayScale: AnimationScale.blowbubble2,
        source: .frames(
            frameNames: PetAnimationLoader.loadFrameNames(prefix: "blowbubbletwo", maxFrames: 30, maxUniqueFrames: AnimationLimits.maxUniqueFrames),
            fps: 8,
            isLoop: true
        )
    )

    static let like1: PetAnimation = PetAnimation(
        emotion: .like1,
        displayScale: AnimationScale.like1,
        source: .frames(
            frameNames: PetAnimationLoader.loadFrameNames(prefix: "likeone", maxFrames: 36, maxUniqueFrames: AnimationLimits.maxUniqueFrames),
            fps: 8,
            isLoop: true
        )
    )

    static let like2: PetAnimation = PetAnimation(
        emotion: .like2,
        displayScale: AnimationScale.like2,
        source: .frames(
            frameNames: PetAnimationLoader.loadFrameNames(prefix: "liketwo", maxFrames: 36, maxUniqueFrames: AnimationLimits.maxUniqueFrames),
            fps: 8,
            isLoop: true
        )
    )

    static let sad1: PetAnimation = PetAnimation(
        emotion: .sad1,
        displayScale: AnimationScale.sad1,
        source: .frames(
            frameNames: PetAnimationLoader.loadFrameNames(prefix: "sadone", maxFrames: 30, maxUniqueFrames: AnimationLimits.maxUniqueFrames),
            fps: 8,
            isLoop: true
        )
    )

    static let sad2: PetAnimation = PetAnimation(
        emotion: .sad2,
        displayScale: AnimationScale.sad2,
        source: .frames(
            frameNames: PetAnimationLoader.loadFrameNames(prefix: "sadtwo", maxFrames: 30, maxUniqueFrames: AnimationLimits.maxUniqueFrames),
            fps: 8,
            isLoop: true
        )
    )

    static let sleepy: PetAnimation = PetAnimation(
        emotion: .sleepy,
        displayScale: AnimationScale.sleepy,
        source: .frames(
            frameNames: PetAnimationLoader.loadFrameNames(prefix: "sleepy", maxFrames: 30, maxUniqueFrames: AnimationLimits.maxUniqueFrames),
            fps: 8,
            isLoop: true
        )
    )
}

// MARK: - ViewModel（简单状态机雏形）

final class PetViewModel: ObservableObject {
    @Published var currentEmotion: PetEmotion = .idle
    @Published var currentFrameIndex: Int = 0

    /// 点击宠物时轮换的动作列表（你后续加动作只要往这里补）
    private let tapCycleEmotions: [PetEmotion] = [
        .idle, .idleOne, .scale,
        .angry2,
        .question1, .question2, .question3,
        .speak1, .speak2, .speak3
        ,
        .blowbubble1, .blowbubble2,
        .like1, .like2,
        .sad1, .sad2,
        .sleepy
    ]

    /// 当前情绪对应的动画配置
    var currentAnimation: PetAnimation {
        switch currentEmotion {
        case .idle:
            return PetAnimations.idle
        case .idleOne:
            return PetAnimations.idleOne
        case .scale:
            return PetAnimations.scale
        case .angry2:
            return PetAnimations.angry2
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
        case .sad1:
            return PetAnimations.sad1
        case .sad2:
            return PetAnimations.sad2
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
                    // 非循环动画播完回到 idle
                    currentEmotion = .idle
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
        guard let idx = tapCycleEmotions.firstIndex(of: currentEmotion) else {
            currentEmotion = tapCycleEmotions.first ?? .idle
            currentFrameIndex = 0
            return
        }
        let nextIndex = (idx + 1) % tapCycleEmotions.count
        currentEmotion = tapCycleEmotions[nextIndex]
        currentFrameIndex = 0
        print("🐾 Tap -> switch emotion:", String(describing: currentEmotion))
    }
}

// MARK: - 视图

struct ContentView: View {
    @StateObject private var viewModel = PetViewModel()

    var body: some View {
        VStack(spacing: 8) {
            // 宠物动画区域
            PetAnimationView(viewModel: viewModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                // watchOS 下 VideoPlayer 可能会抢占点击并显示播放控制层，
                // 用高优先级手势确保点击一定会切换动画。
                .highPriorityGesture(
                    TapGesture().onEnded { viewModel.cycleEmotionOnTap() }
                )

            // 简单的时间 + 陪伴值占位
            Text(Date(), style: .time)
                .font(.headline)

            HStack {
                Text("陪伴值")
                ProgressView(value: 0.3) // 后面接真实数据
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
        .onChange(of: videoFileName) { _ in
            configurePlayer()
        }
        .onChange(of: isLoop) { _ in
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

