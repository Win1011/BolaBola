//
//  ContentView.swift
//  BolaBola Watch App
//
//  Created by Nan on 3/15/26.
//

import SwiftUI
import Combine
import WatchKit

// MARK: - ViewModel（简单状态机雏形）

final class PetViewModel: ObservableObject {
    @Published var currentEmotion: PetEmotion = .idle
    @Published var currentFrameIndex: Int = 0
    @Published var companionValue: Double = 50
    // 内部陪伴值允许小数（用于 5 分钟级别的 +/-0.1/-0.1 平滑），对外与状态机使用“四舍五入后的整数值”。
    private var companionValueInternal: Double = 50

    /// 惊喜里程碑间隔（小时）。与 Debug/Release 一致，避免启动时被「快速惊喜」抢占默认动画。
    private let surpriseMilestoneHours: Double = 100

    private let companionValueKey = "bola_companionValue"
    /// 上次把「墙钟时间」计入陪伴加分 / 惊喜累计的时刻（Unix 秒）。进后台、睡眠期间不推进，回到前台或冷启动时一次性补算整段间隔。
    private let lastCompanionWallClockKey = "bola_lastCompanionWallClock"
    /// 兼容旧版：曾用 lastTickTimestamp 表示打点，迁移时读取。
    private let lastTickTimestampKey = "bola_lastTickTimestamp"

    // Surprise：累积“活跃时间”的总秒数（会话墙钟：含挂机/睡眠；超长离线见 `longAbsenceWithoutForegroundSeconds`）
    private let totalActiveSecondsKey = "bola_totalActiveSeconds"
    private let activeCarrySecondsKey = "bola_activeCarrySeconds"
    private let lastSurpriseAtHoursKey = "bola_lastSurpriseAtHours"

    /// 加分：每满 3600 秒 +1（无每日上限）
    private let secondsPerCompanionBonus: TimeInterval = 3600
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
    /// 陪伴值 10–29：不高兴档内 `hurt` 与 `unhappy` 的稳定映射（`(v-10) % stride == 0` → `hurt`，约 35%）
    private let unhappyTierHurtStride: Int = 3
    /// 点击触发的跳跃/喜欢/生气播完后，回到 idleOne/Two/Three 随机其一（非陪伴值默认池）
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
    private var lastGreetingWallClock: TimeInterval = 0
    /// 每次进入界面/回到前台都想打招呼；仅防 `onAppear` 与 `scenePhase.active` 同一次打开重复播两次（秒）
    private let greetingThrottleSeconds: TimeInterval = 12
    private var proactiveChatCancellable: AnyCancellable?
    /// 仅前台时播放主动闲聊（与计划「仅前台」一致）
    private var isForegroundActive = true

    private var currentDefaultEmotion: PetEmotion = .idle
    private var milestoneTimerCancellable: AnyCancellable?
    /// 上次已结算的墙钟时刻（与 `lastCompanionWallClockKey` 同步）
    private var lastCompanionWallClockTime: TimeInterval = 0

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
        .happy1, .jump1,
        .sleepy
    ]

    init() {
        // 初始化：按「会话墙钟」累计陪伴与惊喜；超长离线由 `longAbsenceWithoutForegroundSeconds` 自动检测并扣分。
        hydrateTotalTimeAndSurpriseState()

        selectDefaultEmotion()
        applyDefaultEmotionDisplay()
        lastCompanionTierForSpeech = BolaDialogueLines.companionTier(for: Int(companionValue.rounded()))

        // 启动后台检查：如果在运行过程中跨过 100 小时里程碑，则触发惊喜。
        startMilestoneTimer()
        startProactiveChatTimer()
        maybeTriggerSurpriseIfNeeded()
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
        ReminderScheduler.shared.scheduleDefaultsIfAuthorized()
        HealthKitManager.shared.requestAuthorization { [weak self] ok in
            guard let self, ok else { return }
            HealthKitManager.shared.elevatedHeartRateDialogueLineIfNeeded { line in
                if let line { self.showDialogue(line, duration: 6) }
            }
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
        let tier = BolaDialogueLines.companionTier(for: v)
        if lastCompanionTierForSpeech >= 0, lastCompanionTierForSpeech != tier,
           let line = BolaDialogueLines.tierChangedLine(from: lastCompanionTierForSpeech, to: tier) {
            showDialogue(line)
        }
        lastCompanionTierForSpeech = tier
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
                    case .shakeOnce, .happy1Once, .sleep:
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

    /// idleone / idletwo / idlethree 随机其一（用于「待机」与点击结束回 idle）
    private func randomIdleEmotion() -> PetEmotion {
        [.idleOne, .idleTwo, .idleThree].randomElement() ?? .idleOne
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
        persistCompanionSnapshot(UserDefaults.standard)

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
        selectDefaultEmotion()
        applyDefaultEmotionDisplay()
        currentFrameIndex = 0
        if surprisePending {
            maybeTriggerSurpriseIfNeeded(forcePending: true)
        }
    }

    func cycleEmotionOnTap() {
        let nowTs = Date().timeIntervalSince1970
        let v = Int(companionValue.rounded())

        // die 段：无反应（强化死亡无交互感）
        if v <= 2 {
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
        applyCompanionBonusFromTapJump()
        selectDefaultEmotion()
        let vNow = Int(companionValue.rounded())
        tapChainReturnsToRandomIdle = true
        isTapInteractionAnimating = true
        currentEmotion = Bool.random() ? .jump1Tap : .jumpTwoTap
        currentFrameIndex = 0
        showDialogue(BolaDialogueLines.tapJumpOpening(v: vNow, defaultEmotion: currentDefaultEmotion))
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
        persistCompanionSnapshot(UserDefaults.standard)
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

    private func persistCompanionSnapshot(_ defaults: UserDefaults) {
        defaults.set(companionValueInternal, forKey: companionValueKey)
        defaults.set(totalActiveSeconds, forKey: totalActiveSecondsKey)
        defaults.set(activeCarrySeconds, forKey: activeCarrySecondsKey)
        defaults.set(lastCompanionWallClockTime, forKey: lastCompanionWallClockKey)
    }

    /// 从磁盘恢复 `lastCompanionWallClockTime`；若无新键则从旧版 `lastTickTimestamp` 迁移。
    private func migrateLastCompanionWallClockFromDefaults(_ defaults: UserDefaults, nowTs: TimeInterval) {
        defaults.removeObject(forKey: "bola_lastBackgroundTimestamp")
        defaults.removeObject(forKey: "bola_sessionExplicitlyEndedAt")
        defaults.removeObject(forKey: "bola_bonusGainToday")
        defaults.removeObject(forKey: "bola_bonusCalendarDay")
        if defaults.object(forKey: lastCompanionWallClockKey) != nil {
            lastCompanionWallClockTime = defaults.double(forKey: lastCompanionWallClockKey)
            return
        }
        if defaults.object(forKey: lastTickTimestampKey) != nil {
            lastCompanionWallClockTime = defaults.double(forKey: lastTickTimestampKey)
            defaults.set(lastCompanionWallClockTime, forKey: lastCompanionWallClockKey)
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
        let defaults = UserDefaults.standard
        let now = Date()
        let nowTs = now.timeIntervalSince1970
        creditOrPenalizeWallClockGapIfNeeded(now: now, nowTs: nowTs, defaults: defaults)
    }

    /// watchOS：进后台不推进墙钟，挂机/睡眠在回到前台或 hydrate 时按整段间隔补算。
    func handleScenePhaseChange(_ phase: ScenePhase) {
        let defaults = UserDefaults.standard
        switch phase {
        case .background:
            isForegroundActive = false
            defaults.set(lastCompanionWallClockTime, forKey: lastCompanionWallClockKey)
            persistCompanionSnapshot(defaults)
        case .active:
            isForegroundActive = true
            applyWallClockCompanionDeltaFromLastCredit()
            speakForegroundGreetingIfNeeded()
            maybeTriggerSurpriseIfNeeded()
        case .inactive:
            isForegroundActive = false
        @unknown default:
            break
        }
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

        companionValueInternal = clampCompanionValue(companionValueInternal)
        companionValue = companionValueInternal.rounded()

        // 2) 冷启动：墙钟迁移 + 加分或「长期离线」自动扣分（见 `creditOrPenalizeWallClockGapIfNeeded`）
        migrateLastCompanionWallClockFromDefaults(defaults, nowTs: nowTs)

        creditOrPenalizeWallClockGapIfNeeded(now: now, nowTs: nowTs, defaults: defaults)

        companionValueInternal = clampCompanionValue(companionValueInternal)
        companionValue = companionValueInternal.rounded()

        // 3) persist
        persistCompanionSnapshot(defaults)

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
        applyWallClockCompanionDeltaFromLastCredit()
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
            // 不高兴档：`unhappy` 为主，按分数稳定混入 `hurt`（避免每次墙钟结算随机抖动）
            currentDefaultEmotion = ((v - 10) % unhappyTierHurtStride == 0) ? .hurt : .unhappy
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
            // 86~100
            switch v % 5 {
            case 0: currentDefaultEmotion = .like1
            case 1: currentDefaultEmotion = .like2
            case 2: currentDefaultEmotion = Bool.random() ? .jump1 : .jumpTwo
            case 3: currentDefaultEmotion = .blowbubble1
            default: currentDefaultEmotion = .blowbubble2
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
            .font(.system(size: 13, weight: .heavy, design: .rounded))
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

    var body: some View {
        // 气泡必须叠在宠物上（overlay），不要放进 VStack 占高度，否则一有台词主区域变矮，
        // scaledToFit 会重算尺寸，跳跃动画会像「突然放大/缩小」。
        ZStack(alignment: .top) {
            PetAnimationView(viewModel: viewModel)
                .id(viewModel.currentEmotion)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .highPriorityGesture(
                    TapGesture().onEnded { viewModel.cycleEmotionOnTap() }
                )

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
                    .padding(.horizontal, 6)
                    // 整体上移，更靠表冠/安全区上沿，少挡宠物脸
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(alignment: .center, spacing: 3) {
                Button {
                    viewModel.adjustCompanionValueManual(by: -2)
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 6, weight: .semibold))
                        .frame(minWidth: 22, minHeight: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .scaleEffect(0.72)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 3) {
                        Text("陪伴值")
                        Text("\(Int(viewModel.companionValue.rounded()))")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .font(.system(size: 9)) // 比 caption2 更小

                    ProgressView(value: viewModel.companionValue / 100.0)
                        .frame(height: 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    viewModel.adjustCompanionValueManual(by: 2)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 6, weight: .semibold))
                        .frame(minWidth: 22, minHeight: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .scaleEffect(0.72)
            }
            .padding(.horizontal, 4)
            .padding(.top, 2)
            .padding(.bottom, 6)
        }
        .padding(.horizontal, 8)
        .padding(.top, 0)
        .onAppear {
            viewModel.onViewAppear()
        }
        .onChange(of: scenePhase) { _, newPhase in
            viewModel.handleScenePhaseChange(newPhase)
        }
    }
}


