//
//  ContentView.swift
//  BolaBola Watch App
//
//  Created by Nan on 3/15/26.
//

import SwiftUI
import Combine
import WatchKit
import WidgetKit

// MARK: - ViewModel（简单状态机雏形）

final class PetViewModel: ObservableObject {
    @Published var currentEmotion: PetEmotion = .idle
    @Published var currentFrameIndex: Int = 0
    @Published var companionValue: Double = 50
    // 内部陪伴值允许小数（用于 5 分钟级别的 +/-0.1/-0.1 平滑），对外与状态机使用“四舍五入后的整数值”。
    private var companionValueInternal: Double = 50

    /// 惊喜里程碑间隔（小时）。与 Debug/Release 一致，避免启动时被「快速惊喜」抢占默认动画。
    private let surpriseMilestoneHours: Double = 100

    private var bolaDefaults: UserDefaults { BolaSharedDefaults.resolved() }

    /// 加分：每满该秒数 +1（无每日上限）。**当前 600s = 10 分钟 +1（便于测试）；正式可调回 3600（每小时 +1）。**
    private let secondsPerCompanionBonus: TimeInterval = 600
    /// 距上次墙钟打点超过此时长（秒），视为「长期未回到 App」，自动按 Gap 扣分且不把这整段当挂机加分（无需用户点按钮）。
    private let longAbsenceWithoutForegroundSeconds: TimeInterval = 24 * 3600

    /// 扣分：有效 Gap 超过 2 小时的部分，每 300 秒 -0.1（无单次上限，随离线变长而增加；最终仍受 0～100 裁剪）
    private let deductionGraceSeconds: TimeInterval = 2 * 3600
    private let deductionChunkSeconds: TimeInterval = 300
    private let deductionPerChunk: Double = 0.1

    private var totalActiveSeconds: TimeInterval = 0
    private var activeCarrySeconds: TimeInterval = 0
    private var surprisePending: Bool = false
    // 记录“上一次惊喜触发在多少小时里程碑”，用于实现 100h -> 200h -> 300h… 的幂等触发。
    private var lastSurpriseMilestoneHours: Double = 0
    // 惊喜播放完（surprisedOne/Two 2轮）后，需要排队再播放一次 jumpTwoOnce。
    private var surpriseJumpTwoQueued: Bool = false

    /// 深夜 23:30–次日 03:00 随机插入「睡觉」一轮（`sleepy` 资源）
    private let sleepNightProbability: Double = 0.2
    /// 陪伴值 25–80 随机插入 shake 一轮
    private let shakeMidTierProbability: Double = 0.2
    /// 陪伴值 >85 随机插入 happy1 一轮
    private let happy1HighTierProbability: Double = 0.2
    /// 陪伴值 ≥86 时，`happyIdle` 进入默认态的概率（与 like/跳/泡泡 并存）
    private let happyIdleVeryHighTierProbability: Double = 1.0 / 6.0
    /// 维持在 100 时，偶尔补一句开心话（与「首次冲到 100」分开节流）
    private let companion100AmbientCooldownSeconds: TimeInterval = 8 * 60
    /// 点击触发的跳跃/喜欢/生气播完后，回到 idle 变体等（非陪伴值默认池）
    private var tapChainReturnsToRandomIdle: Bool = false
    /// 仅「普通跳跃 + 陪伴 +1」播完后需要衔接台词与延后跨档句；生气 / 三连喜欢为 false
    private var shouldPlayTapJumpFollowUp: Bool = false
    /// 正在播放点击插入动画时忽略新点击（避免连跳）
    private var isTapInteractionAnimating: Bool = false
    /// 8 秒窗口内连击次数（用于生气与三连喜欢）
    private var tapBurstCount: Int = 0
    private var lastTapBurstAt: TimeInterval = 0
    private let tapBurstWindowSeconds: TimeInterval = 8
    private var angryTapCooldownUntil: TimeInterval = 0

    /// 按住说话流程中：屏蔽宠物点击交互
    @Published private(set) var voiceConversationActive: Bool = false
    private var voiceReplyPlaying: Bool = false

    /// 吃东西状态机：waiting → eating → finished
    private(set) var isInEatingState: Bool = false

    /// 当前气泡文案（空则隐藏）；新文案会替换上一条并重新计时
    @Published var dialogueLine: String = ""
    private var dialogueDismissWorkItem: DispatchWorkItem?
    private var dialogueGeneration: UInt = 0

    /// 每次普通点击跳跃 +1 陪伴时刷新，供界面播放「+1」泡泡动效
    @Published var tapBonusToken: UUID?

    /// 点击跳跃 +1 导致跨档时，跨档台词延后到跳跃结束后再播，避免顶掉跳跃开场白
    private var pendingTierSpeechAfterTap: String?
    private var pendingTierDeferredWorkItem: DispatchWorkItem?

    private var lastCompanionTierForSpeech: Int = -1
    /// 用于检测「第一次从 &lt;100 升到 100」以播庆祝台词（需在 `init` 里与磁盘值对齐）
    private var previousCompanionRoundedForHundredSpeech: Int = -1
    private var lastCompanion100AmbientWallClock: TimeInterval = 0
    private var lastGreetingWallClock: TimeInterval = 0
    /// 每次进入界面/回到前台都想打招呼；仅防 `onAppear` 与 `scenePhase.active` 同一次打开重复播两次（秒）
    private let greetingThrottleSeconds: TimeInterval = 12
    private var proactiveChatCancellable: AnyCancellable?
    /// 前台周期查心率；仅用户已授权读 HealthKit 时启用
    private var heartRateMonitorCancellable: AnyCancellable?
    private var healthKitReadAuthorized = false
    private var lastHeartRateAlertWallClock: TimeInterval = 0
    /// 两次「心跳偏快」气泡之间的最短间隔，避免刷屏
    private let heartRateAlertCooldownSeconds: TimeInterval = 8 * 60
    /// 前台轮询间隔（秒）；略省电量
    private let heartRateForegroundPollSeconds: TimeInterval = 90
    /// 仅前台时播放主动闲聊（与计划「仅前台」一致）
    private var isForegroundActive = true

    /// 抽屉面板展示用（最近一次心率 BPM 数字或 "—"）
    @Published var latestHeartRateText: String = "—"

    private var currentDefaultEmotion: PetEmotion = .idle
    private var milestoneTimerCancellable: AnyCancellable?
    /// 上次已结算的墙钟时刻（与 `lastCompanionWallClockKey` 同步）
    private var lastCompanionWallClockTime: TimeInterval = 0

    /// 点击宠物时轮换的动作列表（你后续加动作只要往这里补）
    private let tapCycleEmotions: [PetEmotion] = [
        .idle, .idleOne, .idleTwo, .idleThree,
        .idleFour, .idleFive, .idleSix,
        .unhappyTwo, .happyIdle,
        .scale,
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
        .happy1, .jump1,
        .sleepy,
        .eatingWait
    ]

    init() {
        BolaSharedDefaults.migrateStandardToGroupIfNeeded()
        #if os(watchOS)
        BolaWCSessionCoordinator.shared.onReceiveCompanionValue = { [weak self] v in
            guard let self else { return }
            Task { @MainActor in
                self.applyRemoteCompanionValue(v)
            }
        }
        // WCSession 已在 `BolaBolaApp.init()` 中激活；此处不再重复 activate，仅绑定回调。
        #endif

        // 初始化：按「会话墙钟」累计陪伴与惊喜；超长离线由 `longAbsenceWithoutForegroundSeconds` 自动检测并扣分。
        hydrateTotalTimeAndSurpriseState()

        previousCompanionRoundedForHundredSpeech = Int(companionValue.rounded())
        selectDefaultEmotion()
        applyDefaultEmotionDisplay()
        let v0 = Int(companionValue.rounded())
        lastCompanionTierForSpeech = BolaDialogueLines.companionTier(for: v0)

        // 启动后台检查：如果在运行过程中跨过 100 小时里程碑，则触发惊喜。
        startMilestoneTimer()
        startProactiveChatTimer()
        maybeTriggerSurpriseIfNeeded()
    }

    private func applyRemoteCompanionValue(_ v: Double) {
        companionValueInternal = clampCompanionValue(v)
        companionValue = companionValueInternal.rounded()
        persistCompanionSnapshot(bolaDefaults, pushToPhone: false)
        selectDefaultEmotion()
        applyDefaultEmotionDisplay()
        currentFrameIndex = 0
        trackCompanionTierSpeechIfNeeded()
    }

    /// Bola「开口」时轻触手腕（与文字气泡同步）
    private func playDialogueHaptic() {
        WKInterfaceDevice.current().play(.click)
    }

    /// 在界面以文字气泡展示一句台词（非语音）
    func showDialogue(_ text: String, duration: TimeInterval = 5) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        dialogueDismissWorkItem?.cancel()
        dialogueGeneration += 1
        let gen = dialogueGeneration
        dialogueLine = trimmed
        playDialogueHaptic()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.dialogueGeneration == gen {
                self.dialogueLine = ""
            }
        }
        dialogueDismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    /// 视图出现或需要一次性初始化提醒时调用（由 ContentView `onAppear` 触发）
    /// +1 泡泡动效播完后由视图调用，清除 token
    func clearTapBonusBubble() {
        tapBonusToken = nil
    }

    func onViewAppear() {
        // 冷启动时 `onChange(scenePhase)` 有时不会对初始 `.active` 触发，这里保证「一打开就说一句」
        speakForegroundGreetingIfNeeded()
        consumeDigestNotificationIfNeeded()
        refreshLatestHeartRateForDisplay()
        ReminderScheduler.shared.scheduleDefaultsIfAuthorized()
        HealthKitManager.shared.requestAuthorization { [weak self] ok in
            guard let self else { return }
            self.healthKitReadAuthorized = ok
            guard ok else { return }
            HealthKitManager.shared.elevatedHeartRateDialogueLineIfNeeded { [weak self] line in
                guard let self, let line else { return }
                self.lastHeartRateAlertWallClock = Date().timeIntervalSince1970
                self.showDialogue(line, duration: 7)
            }
            self.startHeartRateForegroundMonitoring()
        }
    }

    private func startHeartRateForegroundMonitoring() {
        heartRateMonitorCancellable?.cancel()
        guard healthKitReadAuthorized else { return }
        heartRateMonitorCancellable = Timer
            .publish(every: heartRateForegroundPollSeconds, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.checkElevatedHeartRateReminderIfNeeded()
            }
    }

    private func stopHeartRateForegroundMonitoring() {
        heartRateMonitorCancellable?.cancel()
        heartRateMonitorCancellable = nil
    }

    /// App 打开在前台时周期性调用：心率偏高且样本较新则气泡提醒（带冷却）
    private func checkElevatedHeartRateReminderIfNeeded() {
        guard isForegroundActive, healthKitReadAuthorized else { return }
        let now = Date().timeIntervalSince1970
        guard now - lastHeartRateAlertWallClock >= heartRateAlertCooldownSeconds else { return }

        HealthKitManager.shared.elevatedHeartRateDialogueLineIfNeeded { [weak self] line in
            guard let self, let line else { return }
            self.lastHeartRateAlertWallClock = Date().timeIntervalSince1970
            self.showDialogue(line, duration: 7)
        }
    }

    /// 打开 App / 回到前台时问候（短节流，避免同一次启动重复两遍）
    func speakForegroundGreetingIfNeeded() {
        let now = Date().timeIntervalSince1970
        guard now - lastGreetingWallClock >= greetingThrottleSeconds else { return }
        lastGreetingWallClock = now
        let v = Int(companionValue.rounded())
        let tier = BolaDialogueLines.companionTier(for: v)
        let pool: [String]
        switch tier {
        case 0...2: pool = BolaDialogueLines.greetingsLow
        case 3...4: pool = BolaDialogueLines.greetingsMid
        default: pool = BolaDialogueLines.greetingsHigh
        }
        showDialogue(pool.randomElement() ?? "嗨。")
    }

    private func startProactiveChatTimer() {
        proactiveChatCancellable?.cancel()
        // 约 25 分钟一条（20–40 分钟量级；可后续改为随机间隔）
        proactiveChatCancellable = Timer
            .publish(every: 25 * 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, self.isForegroundActive else { return }
                let line = BolaDialogueLines.idleChatter.randomElement() ?? ""
                self.showDialogue(line, duration: 5)
            }
    }

    private func trackCompanionTierSpeechIfNeeded() {
        let v = Int(companionValue.rounded())
        if previousCompanionRoundedForHundredSpeech < 100 && v == 100 {
            showDialogue(
                BolaDialogueLines.companionValue100Lines.randomElement() ?? "一百啦！",
                duration: 8
            )
            lastCompanion100AmbientWallClock = Date().timeIntervalSince1970
        }
        previousCompanionRoundedForHundredSpeech = v

        let tier = BolaDialogueLines.companionTier(for: v)
        if lastCompanionTierForSpeech >= 0, lastCompanionTierForSpeech != tier,
           let line = BolaDialogueLines.tierChangedLine(from: lastCompanionTierForSpeech, to: tier) {
            showDialogue(line)
        }
        lastCompanionTierForSpeech = tier
    }

    /// 长期维持 100 时，在展示默认高段动画时偶尔补一句（避免与刚播的庆祝叠太近）
    private func maybeShowCompanion100AmbientLine() {
        let now = Date().timeIntervalSince1970
        guard now - lastCompanion100AmbientWallClock >= companion100AmbientCooldownSeconds else { return }
        lastCompanion100AmbientWallClock = now
        showDialogue(
            BolaDialogueLines.companionValue100Lines.randomElement() ?? "好开心！",
            duration: 6
        )
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
        case .idleFour:
            return PetAnimations.idleFour
        case .idleFive:
            return PetAnimations.idleFive
        case .idleSix:
            return PetAnimations.idleSix
        case .unhappyTwo:
            return PetAnimations.unhappyTwo
        case .happyIdle:
            return PetAnimations.happyIdle
        case .thinkOne:
            return PetAnimations.thinkOne
        case .thinkTwo:
            return PetAnimations.thinkTwo
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
        case .letterOnce:
            return PetAnimations.letterOnce
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
        case .speak1Once:
            return PetAnimations.speak1Once
        case .speak2Once:
            return PetAnimations.speak2Once
        case .speak3Once:
            return PetAnimations.speak3Once
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
        case .happy1:
            return PetAnimations.happy1
        case .jump1:
            return PetAnimations.jump1
        case .jumpTwoOnce:
            return PetAnimations.jumpTwoOnce
        case .jumpTwoTap:
            return PetAnimations.jumpTwoTap
        case .shakeOnce:
            return PetAnimations.shakeOnce
        case .happy1Once:
            return PetAnimations.happy1Once
        case .jump1Once:
            return PetAnimations.jump1Once
        case .jump1Tap:
            return PetAnimations.jump1Tap
        case .like2Once:
            return PetAnimations.like2Once
        case .angry2Once:
            return PetAnimations.angry2Once
        case .sleepy:
            return PetAnimations.sleepy
        case .happyIdleOnce:
            return PetAnimations.happyIdleOnce
        case .like1Once:
            return PetAnimations.like1Once
        case .eatingWait:
            return PetAnimations.eatingWait
        case .eatingOnce:
            return PetAnimations.eatingOnce
        case .happy:
            return PetAnimations.happy
        case .angry:
            return PetAnimations.happy // 占位，后面改成对应动画
        case .sleep:
            return PetAnimations.sleepOnce
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
                    // 非循环动画播完
                    if surpriseJumpTwoQueued {
                        // 惊喜分两段：surprisedOne/Two 播完（2轮）后，额外再播一次 jump1Once / jumpTwoOnce（随机）。
                        surpriseJumpTwoQueued = false
                        currentEmotion = Bool.random() ? .jump1Once : .jumpTwoOnce
                        currentFrameIndex = 0
                        return
                    }
                    if currentEmotion == .eatingOnce {
                        finishEatingAnimation()
                        return
                    }
                    if isInEatingState && (currentEmotion == .happyIdleOnce || currentEmotion == .like1Once || currentEmotion == .like2Once) {
                        finishEatingHappyAnimation()
                        return
                    }
                    if tapChainReturnsToRandomIdle {
                        tapChainReturnsToRandomIdle = false
                        isTapInteractionAnimating = false
                        selectDefaultEmotion()
                        let next = resolvedEmotionAfterInteractionOrInsert()
                        currentEmotion = next
                        currentDefaultEmotion = next
                        currentFrameIndex = 0
                        if shouldPlayTapJumpFollowUp {
                            shouldPlayTapJumpFollowUp = false
                            completeTapChainReturn(defaultEmotion: next)
                        } else {
                            lastCompanionTierForSpeech = BolaDialogueLines.companionTier(for: Int(companionValue.rounded()))
                        }
                        if surprisePending {
                            maybeTriggerSurpriseIfNeeded(forcePending: true)
                        }
                        return
                    }
                    switch currentEmotion {
                    case .shakeOnce, .happy1Once, .sleep, .letterOnce:
                        finishInsertOnceReturningToRandomIdle()
                        return
                    default:
                        finishNonLoopReturningToDefaultDisplay()
                        return
                    }
                }
            } else {
                currentFrameIndex = next
            }
        case .video:
            // 视频动画不需要逐帧推进
            return
        }
    }

    /// 待机 idle 变体（30–85 段随机用）。`happyIdle` 仅在陪伴 ≥86 时由 `selectDefaultEmotion()` 单独随机。
    private func randomIdleEmotion() -> PetEmotion {
        [
            .idleOne, .idleTwo, .idleThree,
            .idleFour, .idleFive, .idleSix
        ].randomElement() ?? .idleOne
    }

    /// 点击跳跃播完：衔接台词 + 延后播放跨档台词（若有）
    private func completeTapChainReturn(defaultEmotion: PetEmotion) {
        let v = Int(companionValue.rounded())
        let returnLine = BolaDialogueLines.tapJumpReturnLine(v: v, defaultEmotion: defaultEmotion)
        showDialogue(returnLine, duration: 4)

        pendingTierDeferredWorkItem?.cancel()
        if let pending = pendingTierSpeechAfterTap {
            pendingTierSpeechAfterTap = nil
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.showDialogue(pending, duration: 5)
                self.lastCompanionTierForSpeech = BolaDialogueLines.companionTier(for: Int(self.companionValue.rounded()))
            }
            pendingTierDeferredWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.65, execute: work)
        } else {
            lastCompanionTierForSpeech = BolaDialogueLines.companionTier(for: v)
        }
    }

    /// 普通点击跳跃：+1 陪伴值；跨档台词入队，不立刻 `showDialogue`
    private func applyCompanionBonusFromTapJump() {
        pendingTierDeferredWorkItem?.cancel()
        let vBefore = Int(companionValue.rounded())
        let tierBefore = BolaDialogueLines.companionTier(for: vBefore)
        companionValueInternal += 1
        companionValueInternal = clampCompanionValue(companionValueInternal)
        companionValue = companionValueInternal.rounded()
        let vAfter = Int(companionValue.rounded())
        let tierAfter = BolaDialogueLines.companionTier(for: vAfter)
        persistCompanionSnapshot(bolaDefaults)

        tapBonusToken = UUID()

        if tierBefore != tierAfter, let line = BolaDialogueLines.tierChangedLine(from: tierBefore, to: tierAfter) {
            pendingTierSpeechAfterTap = line
        } else {
            pendingTierSpeechAfterTap = nil
        }
    }

    /// 在**已调用** `selectDefaultEmotion()` 之后使用：陪伴值 **<30** 时回到分段默认态（die/sad/unhappy/hurt），避免出现 idle 变体；
    /// ≥30 时维持原逻辑：随机 idle 变体（与点击/插入结束后的表现一致）。
    private func resolvedEmotionAfterInteractionOrInsert() -> PetEmotion {
        let v = Int(companionValue.rounded())
        if v < 30 {
            return currentDefaultEmotion
        }
        return randomIdleEmotion()
    }

    /// 本地时间 23:30–次日 03:00（含 03:00 整）
    private func isInNightSleepWindow(_ date: Date) -> Bool {
        let c = Calendar.current
        let h = c.component(.hour, from: date)
        let m = c.component(.minute, from: date)
        if h == 23 && m >= 30 { return true }
        if h >= 0 && h < 3 { return true }
        if h == 3 && m == 0 { return true }
        return false
    }

    /// 在 `selectDefaultEmotion()` 已更新 `currentDefaultEmotion` 后调用：按概率插入 sleep / shake / happy1 一轮，否则展示默认循环态。
    private func applyDefaultEmotionDisplay(at date: Date = Date()) {
        let v = Int(companionValue.rounded())
        guard v > 2 else {
            currentEmotion = currentDefaultEmotion
            return
        }
        if isInNightSleepWindow(date), Double.random(in: 0...1) < sleepNightProbability {
            currentEmotion = .sleep
            showDialogue(BolaDialogueLines.nightSleepyInsertLine(), duration: 4.5)
            return
        }
        if (25...80).contains(v), Double.random(in: 0...1) < shakeMidTierProbability {
            currentEmotion = .shakeOnce
            return
        }
        if v > 85, Double.random(in: 0...1) < happy1HighTierProbability {
            currentEmotion = .happy1Once
            return
        }
        currentEmotion = currentDefaultEmotion
        if v == 100, currentEmotion == currentDefaultEmotion {
            maybeShowCompanion100AmbientLine()
        }
    }

    /// shake / happy1 / sleep 一轮播完：≥30 回到随机 idle；<30 回到当前分段默认态（避免低陪伴误回 idle）。
    private func finishInsertOnceReturningToRandomIdle() {
        selectDefaultEmotion()
        let next = resolvedEmotionAfterInteractionOrInsert()
        currentEmotion = next
        currentDefaultEmotion = next
        currentFrameIndex = 0
        if surprisePending {
            maybeTriggerSurpriseIfNeeded(forcePending: true)
        }
    }

    /// jump1Once / jumpTwoOnce 等播完：回到「默认展示」（含随机插入判定）。
    private func finishNonLoopReturningToDefaultDisplay() {
        if voiceReplyPlaying {
            voiceReplyPlaying = false
            voiceConversationActive = false
            isTapInteractionAnimating = false
        }
        selectDefaultEmotion()
        applyDefaultEmotionDisplay()
        currentFrameIndex = 0
        if surprisePending {
            maybeTriggerSurpriseIfNeeded(forcePending: true)
        }
    }

    // MARK: - Voice（按住说话）与每日信件

    /// 语音：点麦克风后 → 随机 question 系列（用户在说）
    func beginVoiceListeningSession() {
        guard !voiceConversationActive else { return }
        voiceConversationActive = true
        isTapInteractionAnimating = true
        surprisePending = false
        currentEmotion = [.question1, .question2, .question3].randomElement() ?? .question1
        currentFrameIndex = 0
    }

    /// 语音：用户说完、等待/生成回复时 → 随机 think 系列（thinking）
    func setVoiceThinkingEmotion() {
        currentEmotion = [.thinkOne, .thinkTwo].randomElement() ?? .thinkOne
        currentFrameIndex = 0
    }

    /// 语音：Bola 开口回复时 → 随机 speakOnce 系列
    func playVoiceAssistantReply(_ text: String) {
        voiceReplyPlaying = true
        showDialogue(text, duration: 10)
        currentEmotion = [.speak1Once, .speak2Once, .speak3Once].randomElement() ?? .speak1Once
        currentFrameIndex = 0
    }

    func cancelVoiceSession() {
        voiceConversationActive = false
        voiceReplyPlaying = false
        isTapInteractionAnimating = false
        selectDefaultEmotion()
        applyDefaultEmotionDisplay()
        currentFrameIndex = 0
    }

    /// 每日总结：展示正文并播 `letterOnce`
    func playDailyDigestLetter(body: String) {
        showDialogue(body, duration: 12)
        currentEmotion = .letterOnce
        currentFrameIndex = 0
    }

    // MARK: - 吃东西

    /// 进入吃东西等待状态：循环 idleapple + 饿了台词
    func enterEatingState() {
        isInEatingState = true
        isTapInteractionAnimating = true
        currentEmotion = .eatingWait
        currentFrameIndex = 0
        showDialogue("有点饿，想吃东西啦", duration: 120)
    }

    /// 吃东西等待中被点击：播一轮 eatapple
    private func handleEatingTap() {
        currentEmotion = .eatingOnce
        currentFrameIndex = 0
        dialogueDismissWorkItem?.cancel()
        dialogueLine = ""
    }

    /// eatapple 播完：随机播 happyIdleOnce / like1Once / like2Once + 台词
    private func finishEatingAnimation() {
        let happyEmotion: PetEmotion = [.happyIdleOnce, .like1Once, .like2Once].randomElement() ?? .happyIdleOnce
        currentEmotion = happyEmotion
        currentFrameIndex = 0
        showDialogue("好吃好吃，你也吃点东西吧!", duration: 5)
    }

    /// 吃完开心动画播完：回到默认状态
    private func finishEatingHappyAnimation() {
        isInEatingState = false
        isTapInteractionAnimating = false
        selectDefaultEmotion()
        applyDefaultEmotionDisplay()
        currentFrameIndex = 0
    }

    func refreshLatestHeartRateForDisplay() {
        HealthKitManager.shared.fetchLatestHeartRateForDisplay { [weak self] bpm in
            Task { @MainActor in
                guard let self else { return }
                self.latestHeartRateText = bpm.map { "\(Int($0.rounded()))" } ?? "—"
            }
        }
    }

    func consumeDigestNotificationIfNeeded() {
        let d = bolaDefaults
        guard d.bool(forKey: BolaNotificationBridgeKeys.digestTapOpen) else { return }
        d.set(false, forKey: BolaNotificationBridgeKeys.digestTapOpen)
        let body = d.string(forKey: DailyDigestStorageKeys.lastDigestBody) ?? ""
        guard !body.isEmpty else { return }
        playDailyDigestLetter(body: body)
    }

    func cycleEmotionOnTap() {
        // 吃东西等待中：点击触发吃东西动画
        if isInEatingState && currentEmotion == .eatingWait {
            handleEatingTap()
            return
        }

        let nowTs = Date().timeIntervalSince1970
        let v = Int(companionValue.rounded())

        // die 段：无反应（强化死亡无交互感）
        if v <= 2 {
            return
        }

        if voiceConversationActive {
            return
        }

        if nowTs < angryTapCooldownUntil {
            return
        }

        // 插入动画未播完时不响应新点击（避免连续跳）
        if isTapInteractionAnimating {
            return
        }

        if nowTs - lastTapBurstAt > tapBurstWindowSeconds {
            tapBurstCount = 0
        }
        lastTapBurstAt = nowTs
        tapBurstCount += 1

        // 先判定第 9 次起生气（否则会一直被「第 3 次喜欢」清零，永远到不了 9）
        if tapBurstCount > 8 {
            tapBurstCount = 0
            angryTapCooldownUntil = nowTs + 10
            shouldPlayTapJumpFollowUp = false
            pendingTierDeferredWorkItem?.cancel()
            pendingTierSpeechAfterTap = nil
            tapChainReturnsToRandomIdle = true
            isTapInteractionAnimating = true
            currentEmotion = .angry2Once
            currentFrameIndex = 0
            showDialogue(BolaDialogueLines.tapAngrySample())
            print("🐾 Tap -> angry2Once")
            return
        }

        // 窗口内第 3 次 → 播一轮喜欢（不重置计数，以便继续点到第 9 次生怒）
        if tapBurstCount == 3 {
            shouldPlayTapJumpFollowUp = false
            pendingTierDeferredWorkItem?.cancel()
            pendingTierSpeechAfterTap = nil
            tapChainReturnsToRandomIdle = true
            isTapInteractionAnimating = true
            currentEmotion = .like2Once
            currentFrameIndex = 0
            showDialogue(BolaDialogueLines.tapTripleLikeSample())
            print("🐾 Tap -> like2Once")
            return
        }

        // 普通点击：jump1 / jump2 随机播一轮；+1 陪伴值与 +1 泡泡；台词按档与默认态
        shouldPlayTapJumpFollowUp = true
        let vBeforeTap = Int(companionValue.rounded())
        applyCompanionBonusFromTapJump()
        selectDefaultEmotion()
        let vNow = Int(companionValue.rounded())
        tapChainReturnsToRandomIdle = true
        isTapInteractionAnimating = true
        currentEmotion = Bool.random() ? .jump1Tap : .jumpTwoTap
        currentFrameIndex = 0
        if vBeforeTap == 99 && vNow == 100 {
            previousCompanionRoundedForHundredSpeech = 100
            lastCompanion100AmbientWallClock = Date().timeIntervalSince1970
            showDialogue(
                BolaDialogueLines.companionValue100Lines.randomElement() ?? "一百啦！",
                duration: 8
            )
        } else {
            showDialogue(BolaDialogueLines.tapJumpOpening(v: vNow, defaultEmotion: currentDefaultEmotion))
        }
        print("🐾 Tap -> jump tap", String(describing: currentEmotion))
    }

    // MARK: - Companion value time coupling

    private func clampCompanionValue(_ v: Double) -> Double {
        min(max(v, 0), 100)
    }

    /// 调试：手动调节陪伴值（每次 ±2），用于检查动画与状态机。
    func adjustCompanionValueManual(by delta: Double) {
        pendingTierDeferredWorkItem?.cancel()
        pendingTierSpeechAfterTap = nil
        companionValueInternal += delta
        companionValueInternal = clampCompanionValue(companionValueInternal)
        companionValue = companionValueInternal.rounded()
        trackCompanionTierSpeechIfNeeded()
        selectDefaultEmotion()
        applyDefaultEmotionDisplay()
        currentFrameIndex = 0
        persistCompanionSnapshot(bolaDefaults)
    }

    // Timer / 墙钟：每累计 1 小时 +1，不足部分进位（无每日上限）。
    private func applyActiveAddition(_ seconds: TimeInterval) {
        activeCarrySeconds += seconds
        while activeCarrySeconds >= secondsPerCompanionBonus {
            activeCarrySeconds -= secondsPerCompanionBonus
            companionValueInternal += 1
        }

        companionValueInternal = (companionValueInternal * 10).rounded() / 10
        companionValueInternal = clampCompanionValue(companionValueInternal)
        companionValue = companionValueInternal.rounded()
        trackCompanionTierSpeechIfNeeded()
    }

    /// 长期离线分支：按「离开 Gap」扣分（剔除 00:00~07:00 后，2 小时内不扣，超出部分每 5 分钟 -0.1）
    private func applyHydrationGapDeduction(effectiveGapSeconds: TimeInterval) {
        guard effectiveGapSeconds > deductionGraceSeconds else { return }
        let excess = effectiveGapSeconds - deductionGraceSeconds
        let rawDeduction = floor(excess / deductionChunkSeconds) * deductionPerChunk
        let deduction = rawDeduction
        guard deduction > 0 else { return }
        companionValueInternal -= deduction
        companionValueInternal = (companionValueInternal * 10).rounded() / 10
        companionValueInternal = clampCompanionValue(companionValueInternal)
        companionValue = companionValueInternal.rounded()
        trackCompanionTierSpeechIfNeeded()
    }

    /// 用于扣分：Gap 内剔除每日 00:00~07:00 后的秒数（与 `Documentation/companion_value_rules.md` 一致）
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

    private func persistCompanionSnapshot(_ defaults: UserDefaults, pushToPhone: Bool = true) {
        defaults.set(companionValueInternal, forKey: CompanionPersistenceKeys.companionValue)
        defaults.set(totalActiveSeconds, forKey: CompanionPersistenceKeys.totalActiveSeconds)
        defaults.set(activeCarrySeconds, forKey: CompanionPersistenceKeys.activeCarrySeconds)
        defaults.set(lastCompanionWallClockTime, forKey: CompanionPersistenceKeys.lastCompanionWallClock)
        #if os(watchOS)
        WidgetCenter.shared.reloadAllTimelines()
        if pushToPhone {
            BolaWCSessionCoordinator.shared.pushCompanionValue(companionValueInternal)
            BolaWCSessionCoordinator.shared.schedulePushCompanionGameStateSnapshotToPhoneDebounced()
        }
        #endif
    }

    /// 从磁盘恢复 `lastCompanionWallClockTime`；若无新键则从旧版 `lastTickTimestamp` 迁移。
    private func migrateLastCompanionWallClockFromDefaults(_ defaults: UserDefaults, nowTs: TimeInterval) {
        defaults.removeObject(forKey: "bola_lastBackgroundTimestamp")
        defaults.removeObject(forKey: "bola_sessionExplicitlyEndedAt")
        defaults.removeObject(forKey: "bola_bonusGainToday")
        defaults.removeObject(forKey: "bola_bonusCalendarDay")
        if defaults.object(forKey: CompanionPersistenceKeys.lastCompanionWallClock) != nil {
            lastCompanionWallClockTime = defaults.double(forKey: CompanionPersistenceKeys.lastCompanionWallClock)
            return
        }
        if defaults.object(forKey: CompanionPersistenceKeys.lastTickTimestamp) != nil {
            lastCompanionWallClockTime = defaults.double(forKey: CompanionPersistenceKeys.lastTickTimestamp)
            defaults.set(lastCompanionWallClockTime, forKey: CompanionPersistenceKeys.lastCompanionWallClock)
            return
        }
        lastCompanionWallClockTime = nowTs
    }

    /// 自上次墙钟打点以来的间隔：若超过 `longAbsenceWithoutForegroundSeconds` 则自动按 Gap 扣分且不把这整段当挂机加分；否则计入陪伴与惊喜。
    private func creditOrPenalizeWallClockGapIfNeeded(now: Date, nowTs: TimeInterval, defaults: UserDefaults) {
        let delta = max(0, nowTs - lastCompanionWallClockTime)
        guard delta > 0 else { return }

        if delta > longAbsenceWithoutForegroundSeconds {
            let from = Date(timeIntervalSince1970: lastCompanionWallClockTime)
            let effectiveGap = deductibleSecondsOutsideNightWindow(from: from, to: now)
            applyHydrationGapDeduction(effectiveGapSeconds: effectiveGap)
            lastCompanionWallClockTime = nowTs
            persistCompanionSnapshot(defaults)
            selectDefaultEmotion()
            if currentEmotion == currentDefaultEmotion {
                applyDefaultEmotionDisplay()
                currentFrameIndex = 0
            }
            showDialogue(BolaDialogueLines.longAbsenceReturn.randomElement() ?? "")
            trackCompanionTierSpeechIfNeeded()
            return
        }

        let oldDefaultEmotion = currentDefaultEmotion
        applyActiveAddition(delta)
        totalActiveSeconds += delta
        selectDefaultEmotion()
        if currentEmotion == oldDefaultEmotion {
            applyDefaultEmotionDisplay()
            currentFrameIndex = 0
        }

        lastCompanionWallClockTime = nowTs
        persistCompanionSnapshot(defaults)
        trackCompanionTierSpeechIfNeeded()
    }

    private func applyWallClockCompanionDeltaFromLastCredit() {
        let defaults = bolaDefaults
        let now = Date()
        let nowTs = now.timeIntervalSince1970
        creditOrPenalizeWallClockGapIfNeeded(now: now, nowTs: nowTs, defaults: defaults)
    }

    /// watchOS：进后台不推进墙钟，挂机/睡眠在回到前台或 hydrate 时按整段间隔补算。
    func handleScenePhaseChange(_ phase: ScenePhase) {
        let defaults = bolaDefaults
        switch phase {
        case .background:
            isForegroundActive = false
            stopHeartRateForegroundMonitoring()
            defaults.set(lastCompanionWallClockTime, forKey: CompanionPersistenceKeys.lastCompanionWallClock)
            persistCompanionSnapshot(defaults)
        case .active:
            isForegroundActive = true
            #if os(watchOS)
            BolaWCSessionCoordinator.shared.reapplyLatestReceivedContext()
            #endif
            applyWallClockCompanionDeltaFromLastCredit()
            speakForegroundGreetingIfNeeded()
            maybeTriggerSurpriseIfNeeded()
            Task {
                await DailyDigestRefresh.regenerateIfNeeded(companionValue: Int(companionValue.rounded()))
            }
            refreshLatestHeartRateForDisplay()
            consumeDigestNotificationIfNeeded()
            if healthKitReadAuthorized {
                startHeartRateForegroundMonitoring()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                    self?.checkElevatedHeartRateReminderIfNeeded()
                }
            }
        case .inactive:
            isForegroundActive = false
        @unknown default:
            break
        }
    }

    // MARK: - Surprise / Default state machine (minimal, testable)

    private func hydrateTotalTimeAndSurpriseState() {
        let defaults = bolaDefaults
        let now = Date()
        let nowTs = now.timeIntervalSince1970

        // 1) hydration: companionValue / totalActiveSeconds / carry
        if defaults.object(forKey: CompanionPersistenceKeys.companionValue) != nil {
            companionValueInternal = defaults.double(forKey: CompanionPersistenceKeys.companionValue)
        } else {
            companionValueInternal = 50 // 默认值：避免一开始就太悲伤
        }

        totalActiveSeconds = defaults.double(forKey: CompanionPersistenceKeys.totalActiveSeconds)
        activeCarrySeconds = defaults.double(forKey: CompanionPersistenceKeys.activeCarrySeconds)

        companionValueInternal = clampCompanionValue(companionValueInternal)
        companionValue = companionValueInternal.rounded()

        // 2) 冷启动：墙钟迁移 + 加分或「长期离线」自动扣分（见 `creditOrPenalizeWallClockGapIfNeeded`）
        migrateLastCompanionWallClockFromDefaults(defaults, nowTs: nowTs)

        creditOrPenalizeWallClockGapIfNeeded(now: now, nowTs: nowTs, defaults: defaults)

        companionValueInternal = clampCompanionValue(companionValueInternal)
        companionValue = companionValueInternal.rounded()

        // 3) persist（冷启动不向手机推，避免无意义往返）
        persistCompanionSnapshot(defaults, pushToPhone: false)

        // 4) surprise idempotency：lastSurpriseMilestoneHours >= 当前应该触发的下一档时则不触发
        lastSurpriseMilestoneHours = defaults.double(forKey: CompanionPersistenceKeys.lastSurpriseAtHours)
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
        applyWallClockCompanionDeltaFromLastCredit()
        maybeTriggerSurpriseIfNeeded()
    }

    /// 86～100 段默认态：`v%5==0` 为 `like1`，但 **90、95** 不再给 `like1`（改为其它高段动作随机）
    private func defaultEmotionForHighTier86To100(v: Int) -> PetEmotion {
        if v == 90 || v == 95 {
            return [.like2, .blowbubble1, .blowbubble2, Bool.random() ? .jump1 : .jumpTwo].randomElement() ?? .like2
        }
        switch v % 5 {
        case 0: return .like1
        case 1: return .like2
        case 2: return Bool.random() ? .jump1 : .jumpTwo
        case 3: return .blowbubble1
        default: return .blowbubble2
        }
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
        bolaDefaults.set(nextMilestoneHours, forKey: CompanionPersistenceKeys.lastSurpriseAtHours)

        showDialogue(BolaDialogueLines.surpriseMilestone.randomElement() ?? "惊喜！", duration: 5)

        // 里程碑触发后：随机只选一个惊喜动画。
        currentEmotion = Bool.random() ? .surprisedOne : .surprisedTwo
        currentFrameIndex = 0
        print("🎉 Surprise triggered at hours:", totalHours, "(milestone:", nextMilestoneHours, ") =>", String(describing: currentEmotion))
    }

    private func selectDefaultEmotion() {
        // 默认状态由 companionValue 决定（确定性映射，见 `Documentation/state_machine_list.md`）。
        let v = Int(companionValue.rounded())
        if v <= 2 {
            currentDefaultEmotion = .die
        } else if v <= 9 {
            currentDefaultEmotion = (v % 2 == 0) ? .sad2 : .sad1
        } else if v <= 29 {
            // 不高兴档：`hurt` / `unhappy` / `unhappyTwo`（不开心2）按分数轮换
            switch (v - 10) % 3 {
            case 0: currentDefaultEmotion = .hurt
            case 1: currentDefaultEmotion = .unhappy
            default: currentDefaultEmotion = .unhappyTwo
            }
        } else if v <= 39 {
            currentDefaultEmotion = randomIdleEmotion()
        } else if v <= 85 {
            switch v % 5 {
            case 0, 1, 2:
                currentDefaultEmotion = randomIdleEmotion()
            case 3: currentDefaultEmotion = .blowbubble1
            default: currentDefaultEmotion = .blowbubble2
            }
        } else {
            // 86~100：`happyIdle` 仅在此段随机；其余按 v%5，但 **90、95 不再用 like1**（原 v%5==0）
            if Double.random(in: 0...1) < happyIdleVeryHighTierProbability {
                currentDefaultEmotion = .happyIdle
            } else {
                currentDefaultEmotion = defaultEmotionForHighTier86To100(v: v)
            }
        }
    }
}

// MARK: - +1 陪伴泡泡（与台词气泡分层）

private struct TapBonusBubbleView: View {
    let onFinished: () -> Void
    @State private var popScale: CGFloat = 0.35
    @State private var opacity: Double = 0

    var body: some View {
        Text("+1")
            .font(.system(size: 13, weight: .heavy))
            .foregroundStyle(.primary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(.white.opacity(0.45), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
            .scaleEffect(popScale)
            .opacity(opacity)
            .onAppear {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.68)) {
                    popScale = 1.05
                    opacity = 1
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
                    withAnimation(.easeOut(duration: 0.22)) {
                        popScale = 1.45
                        opacity = 0
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
                        onFinished()
                    }
                }
            }
    }
}

// MARK: - 视图

struct ContentView: View {
    @StateObject private var viewModel = PetViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showPanelSheet = false
    @State private var showRemindersSheet = false
    @State private var showSettingsSheet = false

    var body: some View {
        // 气泡必须叠在宠物上（overlay），不要放进与底栏同一层、会随台词改变高度的容器里，
        // 否则 scaledToFit 会重算尺寸，跳跃动画会像「突然放大/缩小」。
        // 底栏贴底；面板与「提醒」相同，用全屏 Sheet + NavigationStack + 完成。
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                PetAnimationView(viewModel: viewModel)
                    .id(viewModel.currentEmotion)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .highPriorityGesture(
                        TapGesture().onEnded { viewModel.cycleEmotionOnTap() }
                    )

                WatchFaceComplicationsOverlay(viewModel: viewModel)
                    .allowsHitTesting(false)

                if !viewModel.dialogueLine.isEmpty {
                    Text(viewModel.dialogueLine)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.88)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color(red: 229 / 255, green: 1, blue: 0), lineWidth: 0.75)
                        )
                        .padding(.horizontal, 6)
                        .offset(y: -12)
                        .zIndex(1)
                        .allowsHitTesting(false)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if viewModel.tapBonusToken != nil {
                    TapBonusBubbleView {
                        viewModel.clearTapBonusBubble()
                    }
                    .id(viewModel.tapBonusToken)
                    .offset(y: 28)
                    .zIndex(2)
                    .allowsHitTesting(false)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            WatchBottomChromeToolbar(
                viewModel: viewModel,
                onOpenPanel: { showPanelSheet = true }
            )
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(edges: .bottom)
        .sheet(isPresented: $showPanelSheet) {
            WatchPanelSheetView(
                viewModel: viewModel,
                showRemindersSheet: $showRemindersSheet,
                showSettingsSheet: $showSettingsSheet
            )
        }
        .sheet(isPresented: $showRemindersSheet) {
            WatchRemindersListView()
        }
        .sheet(isPresented: $showSettingsSheet) {
            WatchSettingsView(viewModel: viewModel)
        }
        .onAppear {
            viewModel.onViewAppear()
        }
        .onChange(of: scenePhase) { _, newPhase in
            viewModel.handleScenePhaseChange(newPhase)
        }
    }
}


