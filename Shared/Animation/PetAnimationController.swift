//
//  PetAnimationController.swift
//  Shared — 基础交互（点击跳跃 / 吃 / 喝 / 夜间睡眠）跨平台统一的触发状态机。
//
//  设计原则：
//  - 只覆盖用户可见的「基础交互」流程，不涉及手表端的默认态轮换、惊喜、语音、日记、档位台词等。
//  - 网线只搬运 `PetCoreState` + 陪伴值；控制器独立在每台设备本机上运行，两端靠 `PetCoreState` 的过渡事件
//    对齐（例如：手表 `pushPetCoreState(.hungry)` → iPhone 收到后调用 `enterHungry()`）。
//  - 一次性动画（eat/drink/fallAsleep/tap-jump）的过渡由控制器内部的 `DispatchWorkItem` 定时器驱动，
//    不再依赖渲染层的帧结束回调 —— 两端渲染各自独立，定时器保证流程节拍一致。
//  - 副作用（台词 / `pushPetCoreState` / 本地 bookkeeping）由平台层通过 `onTransition` 回调处理。
//

import Foundation
import Combine

// MARK: - 过渡事件

/// 控制器进入新状态（或回到 idle）时发出的事件，用于平台层挂台词 / 同步 / 触觉等副作用。
public enum PetInteractionTransitionReason: Sendable {
    case tapJumpStarted
    case tapJumpCompleted
    case hungryStarted
    case eatingStarted
    case eatingFinisherStarted
    case eatingCompleted
    case thirstyStarted
    case drinkingStarted
    case drinkingFinisherStarted
    case drinkingCompleted
    case sleepWaitStarted
    case fallingAsleepStarted
    case sleepingStarted
    case cleared
}

// MARK: - 基础交互中「当前要展示的帧序列」

/// 基础交互流程中正在展示的动画；非交互态时 `PetAnimationController.activeInteraction == nil`，
/// 此时各平台照常展示自己的默认 idle。
public enum PetInteractionEmotion: Sendable, Equatable {
    // 点击反馈（普通 idle 态点击）
    case tapJumpOne
    case tapJumpTwo

    // 吃东西流程
    case eatingWait        // idleapple 循环
    case eatingOnce        // eatappletransparent 一次
    case eatingHappyIdle   // happyidle 收尾
    case eatingLikeOne     // likeone 收尾
    case eatingLikeTwo     // liketwo 收尾

    // 喝水流程
    case idleDrinkOne      // idledrink1 循环
    case idleDrinkTwo      // idledrink2 循环
    case drinkOnce         // drink 一次
    case blowbubbleOne     // blowbubble1 循环（保持 5s 提示）
    case blowbubbleTwo     // blowbubble2 循环（保持 5s 提示）

    // 夜间睡眠流程
    case nightSleepWait    // sleepy 循环
    case fallAsleep        // fallasleep 一次
    case sleepLoop         // sleeploop 循环

    public var animationPrefix: String {
        switch self {
        case .tapJumpOne:        return "jumpone"
        case .tapJumpTwo:        return "jumptwo"
        case .eatingWait:        return "idleapple"
        case .eatingOnce:        return "eatappletransparent"
        case .eatingHappyIdle:   return "happyidle"
        case .eatingLikeOne:     return "likeone"
        case .eatingLikeTwo:     return "liketwo"
        case .idleDrinkOne:      return "idledrink1"
        case .idleDrinkTwo:      return "idledrink2"
        case .drinkOnce:         return "drink"
        case .blowbubbleOne:     return "blowbubbleone"
        case .blowbubbleTwo:     return "blowbubbletwo"
        case .nightSleepWait:    return "sleepy"
        case .fallAsleep:        return "fallasleep"
        case .sleepLoop:         return "sleeploop"
        }
    }

    /// 资源包内该前缀存在的帧数；iPhone `PetFramePlayer` 用来避开空帧。
    public var frameCount: Int {
        switch self {
        case .eatingOnce: return 121
        default:          return 90
        }
    }

    public var fps: Double {
        switch self {
        case .tapJumpOne, .tapJumpTwo: return 30
        case .eatingHappyIdle:         return 21
        default:                       return 24
        }
    }

    public var isLoop: Bool {
        switch self {
        case .eatingWait,
             .idleDrinkOne, .idleDrinkTwo,
             .blowbubbleOne, .blowbubbleTwo,
             .nightSleepWait,
             .sleepLoop:
            return true
        default:
            return false
        }
    }

    /// 一次性动画的自然时长；平台层可用作定时器或等价的视觉反馈 hint。
    public var oneShotDuration: TimeInterval {
        guard !isLoop else { return 0 }
        return Double(frameCount) / max(fps, 1)
    }
}

// MARK: - 控制器

/// 基础交互的跨平台触发状态机。手表 / iPhone 各持一份独立实例；手表是陪伴值与 `PetCoreState` 的
/// 真相源，iPhone 在收到对端状态变化时把控制器对齐过去即可。
@MainActor
public final class PetAnimationController: ObservableObject {
    /// 当前活动的基础交互动画；`nil` 表示让平台层显示它自己的默认 idle。
    @Published public private(set) var activeInteraction: PetInteractionEmotion?

    /// 平台层挂台词 / 同步 / 触觉的副作用钩子。注意：切线程已在 `@MainActor` 上执行。
    public var onTransition: ((PetInteractionTransitionReason, PetInteractionEmotion?) -> Void)?

    /// 随机收尾选择可注入，便于测试；默认使用 `.random()`。
    public var randomEatingFinisher: () -> PetInteractionEmotion = {
        [.eatingHappyIdle, .eatingLikeOne, .eatingLikeTwo].randomElement() ?? .eatingHappyIdle
    }
    public var randomDrinkBlowbubble: () -> PetInteractionEmotion = {
        Bool.random() ? .blowbubbleOne : .blowbubbleTwo
    }
    public var randomIdleDrinkVariant: () -> PetInteractionEmotion = {
        Bool.random() ? .idleDrinkOne : .idleDrinkTwo
    }
    public var randomTapJumpVariant: () -> PetInteractionEmotion = {
        Bool.random() ? .tapJumpOne : .tapJumpTwo
    }

    /// blowbubble 在 drink 收尾后多长时间自动回到 idle（与手表 `finishDrinkWaterAnimation` 的 5s 对齐）。
    private let blowbubbleHoldSeconds: TimeInterval = 5

    private var pendingWorkItem: DispatchWorkItem?

    public init() {}

    // MARK: - 公开事件

    /// 普通 idle 态点击：立即播一轮随机 jump；若当前正处于任何基础交互，视为忽略（一致于手表
    /// `isTapInteractionAnimating` 的闭锁）。
    @discardableResult
    public func handleIdleTap() -> Bool {
        guard activeInteraction == nil else { return false }
        let variant = randomTapJumpVariant()
        schedule(variant, reason: .tapJumpStarted)
        scheduleOneShotAdvance(after: variant.oneShotDuration) { [weak self] in
            self?.finishTapJump()
        }
        return true
    }

    /// 对端进入「饿了」等待状态；进入 `eatingWait` 循环（平台层可播台词「有点饿…」）。
    public func enterHungry() {
        schedule(.eatingWait, reason: .hungryStarted)
    }

    /// 「喂食」指令；仅在 `eatingWait` 时生效。立即进入 `eatingOnce`，一轮后随机进入收尾动作，再回 idle。
    @discardableResult
    public func applyEatCommand() -> Bool {
        guard activeInteraction == .eatingWait else { return false }
        schedule(.eatingOnce, reason: .eatingStarted)
        scheduleOneShotAdvance(after: PetInteractionEmotion.eatingOnce.oneShotDuration) { [weak self] in
            self?.advanceEatingToFinisher()
        }
        return true
    }

    public func enterThirsty() {
        let variant = randomIdleDrinkVariant()
        schedule(variant, reason: .thirstyStarted)
    }

    @discardableResult
    public func applyDrinkCommand() -> Bool {
        guard activeInteraction == .idleDrinkOne || activeInteraction == .idleDrinkTwo else { return false }
        schedule(.drinkOnce, reason: .drinkingStarted)
        scheduleOneShotAdvance(after: PetInteractionEmotion.drinkOnce.oneShotDuration) { [weak self] in
            self?.advanceDrinkingToBlowbubble()
        }
        return true
    }

    public func enterSleepWait() {
        schedule(.nightSleepWait, reason: .sleepWaitStarted)
    }

    @discardableResult
    public func applySleepCommand() -> Bool {
        guard activeInteraction == .nightSleepWait else { return false }
        schedule(.fallAsleep, reason: .fallingAsleepStarted)
        scheduleOneShotAdvance(after: PetInteractionEmotion.fallAsleep.oneShotDuration) { [weak self] in
            self?.advanceToSleepLoop()
        }
        return true
    }

    /// 直接切到 `sleepLoop`（例如对端已经在睡了，iPhone 收到 `.sleeping` 后对齐）。
    public func enterSleeping() {
        schedule(.sleepLoop, reason: .sleepingStarted)
    }

    /// 任何流程的收尾：回到 idle（清空 `activeInteraction`）。
    public func returnToIdle() {
        guard activeInteraction != nil else { return }
        cancelPending()
        setActive(nil, reason: .cleared)
    }

    /// 强制清空并取消所有定时器；用于状态迁移冲突时兜底（如无痕切到另一个等待态）。
    public func forceClear() {
        cancelPending()
        if activeInteraction != nil {
            setActive(nil, reason: .cleared)
        }
    }

    // MARK: - 内部过渡

    private func finishTapJump() {
        guard activeInteraction == .tapJumpOne || activeInteraction == .tapJumpTwo else { return }
        setActive(nil, reason: .tapJumpCompleted)
    }

    private func advanceEatingToFinisher() {
        guard activeInteraction == .eatingOnce else { return }
        let finisher = randomEatingFinisher()
        setActive(finisher, reason: .eatingFinisherStarted)
        scheduleOneShotAdvance(after: finisher.oneShotDuration) { [weak self] in
            self?.finishEatingFlow()
        }
    }

    private func finishEatingFlow() {
        switch activeInteraction {
        case .eatingHappyIdle, .eatingLikeOne, .eatingLikeTwo:
            setActive(nil, reason: .eatingCompleted)
        default:
            break
        }
    }

    private func advanceDrinkingToBlowbubble() {
        guard activeInteraction == .drinkOnce else { return }
        let bubble = randomDrinkBlowbubble()
        setActive(bubble, reason: .drinkingFinisherStarted)
        scheduleOneShotAdvance(after: blowbubbleHoldSeconds) { [weak self] in
            self?.finishDrinkingFlow()
        }
    }

    private func finishDrinkingFlow() {
        switch activeInteraction {
        case .blowbubbleOne, .blowbubbleTwo:
            setActive(nil, reason: .drinkingCompleted)
        default:
            break
        }
    }

    private func advanceToSleepLoop() {
        guard activeInteraction == .fallAsleep else { return }
        setActive(.sleepLoop, reason: .sleepingStarted)
    }

    // MARK: - 基础操作

    private func schedule(_ emotion: PetInteractionEmotion, reason: PetInteractionTransitionReason) {
        cancelPending()
        setActive(emotion, reason: reason)
    }

    private func setActive(_ emotion: PetInteractionEmotion?, reason: PetInteractionTransitionReason) {
        if activeInteraction != emotion {
            activeInteraction = emotion
        }
        onTransition?(reason, emotion)
    }

    private func scheduleOneShotAdvance(after seconds: TimeInterval, _ work: @escaping () -> Void) {
        cancelPending()
        let item = DispatchWorkItem { [weak self] in
            guard self != nil else { return }
            work()
        }
        pendingWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + max(seconds, 0.01), execute: item)
    }

    private func cancelPending() {
        pendingWorkItem?.cancel()
        pendingWorkItem = nil
    }
}
