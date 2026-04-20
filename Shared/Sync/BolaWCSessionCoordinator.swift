//
//  BolaWCSessionCoordinator.swift
//

#if os(iOS) || os(watchOS)
import Foundation
import os
import Combine
import WatchConnectivity

private let bolaWCChatLog = Logger(subsystem: "com.gathxr.BolaBola.sync", category: "WatchConnectivity")

/// 通过 `updateApplicationContext`（失败时 `transferUserInfo`）同步陪伴值；激活后消费 `receivedApplicationContext`。
public final class BolaWCSessionCoordinator: NSObject, ObservableObject, WCSessionDelegate {
    public static let shared = BolaWCSessionCoordinator()

    /// 主线程：远端较新时写入本机 `BolaSharedDefaults.resolved()` 后调用。
    public var onReceiveCompanionValue: ((Double) -> Void)?

    /// 跨设备同步的宠物核心状态（idle / hungry / thirsty / sleepWait / sleeping）。
    @Published public var currentPetCoreState: PetCoreState = .idle

    /// 仅用于 iPhone 调试面板：当前正在播放的情绪动画标签（由手表推送）。
    @Published public var currentPetEmotionLabel: String = "idle"

    // MARK: - 调试面板镜像的 WCSession 状态
    @Published public private(set) var debugActivationState: Int = 0      // WCSessionActivationState.rawValue
    @Published public private(set) var debugIsReachable: Bool = false
    @Published public private(set) var debugIsPaired: Bool = false        // iOS 专有，watch 固定 false
    @Published public private(set) var debugIsCounterpartInstalled: Bool = false
    @Published public private(set) var debugPendingContext: Bool = false
    @Published public private(set) var debugPendingChatDeltaCount: Int = 0

    /// 节流：`petEmotionLabel` 上次推送（调试模式才推）。
    #if os(watchOS)
    private var lastPushedPetEmotionLabel: String = ""
    private var petEmotionLabelDebounceTask: Task<Void, Never>?
    #endif

    #if os(watchOS)
    /// iPhone → 手表指令 id 去重（保留最近 16 个 id）。
    private var recentPetCommandIds: [String] = []
    private let maxPetCommandIdHistory = 16
    #endif

    private var pendingPayload: [String: Any]?
    /// `pushChatDelta` 在 session 未激活或对端未就绪时入队，就绪后按 FIFO `transferUserInfo`（与 `pendingPayload` 对称）。
    private var pendingChatDeltaPayloads: [[String: Any]] = []
    private let maxPendingChatDeltaPayloads = 32

    #if os(watchOS)
    private static let llmKeychainPullThrottleSeconds: TimeInterval = 45
    private static let llmKeychainPullDefaultsKey = "bola_last_llm_keychain_pull_request_ts"

    /// 手表未写入 LLM API Key 时，向 iPhone 发 `transferUserInfo` 触发对方 `pushStoredLLMConfigurationToWatchIfConfigured`。
    private func requestLLMKeychainFromPhoneIfMissing(session: WCSession) {
        guard session.activationState == .activated, session.isCompanionAppInstalled else { return }
        let raw = KeychainHelper.get(service: LLMKeychain.service, account: LLMKeychain.accountAPIKey) ?? ""
        let hasKey = !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard !hasKey else { return }
        let now = Date().timeIntervalSince1970
        let last = UserDefaults.standard.double(forKey: Self.llmKeychainPullDefaultsKey)
        guard now - last >= Self.llmKeychainPullThrottleSeconds else { return }
        UserDefaults.standard.set(now, forKey: Self.llmKeychainPullDefaultsKey)
        session.transferUserInfo([WCSyncPayload.requestSync: WCSyncPayload.requestSyncValueLLMKeychain])
        bolaWCChatLog.info("requestLLMKeychainFromPhone queued (watch has no API key, transferUserInfo)")
        BolaDebugLog.shared.log(.llm, "手表无 API Key，向 iPhone 请求同步")
    }

    /// 无 App Group 时：把手表上的陪伴游戏状态批量同步到 iPhone defaults（防抖，避免每 tick 刷屏）。
    private var companionGameStateSnapshotDebounceTask: Task<Void, Never>?
    /// 手表 → iPhone 语音中继：等待与 `requestId` 匹配的转写结果
    private var speechRelayPending: (id: String, completion: (String?) -> Void)?
    private var speechRelayTimeoutWorkItem: DispatchWorkItem?
    #endif

    private override init() {
        super.init()
    }

    #if os(watchOS)
    /// 手表 `PetViewModel` 在情绪动画变化时调用。仅当调试面板开启时，防抖推送到 iPhone。
    public func updatePetEmotionLabel(_ label: String) {
        let run: () -> Void = { [weak self] in
            guard let self else { return }
            guard self.currentPetEmotionLabel != label else { return }
            self.currentPetEmotionLabel = label
            BolaDebugLog.shared.log(.petState, "emotion → \(label)")
            guard BolaDebugLog.shared.isEnabled else { return }
            guard self.lastPushedPetEmotionLabel != label else { return }
            self.petEmotionLabelDebounceTask?.cancel()
            self.petEmotionLabelDebounceTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 300_000_000) // 300ms 合并
                guard let self else { return }
                guard !Task.isCancelled else { return }
                self.sendPetEmotionLabelNow(self.currentPetEmotionLabel)
            }
        }
        if Thread.isMainThread { run() } else { DispatchQueue.main.async(execute: run) }
    }

    private func sendPetEmotionLabelNow(_ label: String) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isCompanionAppInstalled else { return }
        lastPushedPetEmotionLabel = label
        let payload: [String: Any] = [
            WCSyncPayload.petEmotionLabel: label,
            WCSyncPayload.petCoreState: currentPetCoreState.rawValue
        ]
        session.transferUserInfo(payload)
        BolaDebugLog.shared.log(.send, "emotion label transferUserInfo → \(label)")
    }

    public func prepareSpeechRelay(requestId: String, completion: @escaping (String?) -> Void) {
        speechRelayPending = (requestId, completion)
        speechRelayTimeoutWorkItem?.cancel()
        BolaDebugLog.shared.log(.speech, "语音中继开始 id=\(requestId.prefix(8))")
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if let pending = self.speechRelayPending, pending.id == requestId {
                self.speechRelayPending = nil
                BolaDebugLog.shared.log(.error, "语音中继超时 45s id=\(requestId.prefix(8))")
                pending.completion(nil)
            }
        }
        speechRelayTimeoutWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 45, execute: work)
    }

    public func cancelPendingSpeechRelay() {
        speechRelayTimeoutWorkItem?.cancel()
        speechRelayPending = nil
    }

    private func ingestSpeechRelayReplyIfPresent(_ dict: [String: Any]) -> Bool {
        guard (dict[WCSyncPayload.speechRelayKind] as? String) == "speechRelayReply" else { return false }
        guard let id = dict[WCSyncPayload.speechRelayRequestId] as? String,
              let pending = speechRelayPending, pending.id == id else { return false }
        speechRelayPending = nil
        speechRelayTimeoutWorkItem?.cancel()
        if let err = dict[WCSyncPayload.speechRelayError] as? String, !err.isEmpty {
            BolaDebugLog.shared.log(.speech, "语音中继回包错误 err=\(err)")
            pending.completion(nil)
            return true
        }
        let text = dict[WCSyncPayload.speechRelayTranscript] as? String ?? ""
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        BolaDebugLog.shared.log(.speech, "语音中继转写 len=\(trimmed.count)")
        pending.completion(trimmed.isEmpty ? nil : trimmed)
        return true
    }
    #endif

    #if os(iOS)
    private func sendSpeechRelayReplyToWatch(_ payload: [String: Any], session: WCSession) {
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        // 仅用 transferUserInfo 排队，避免 sendMessage 在「短暂不可达」时触发 WCErrorCodeNotReachable 刷屏
        session.transferUserInfo(payload)
    }
    #endif

    public func activate() {
        guard WCSession.isSupported() else {
            BolaDebugLog.shared.log(.wc, "activate skip: WCSession not supported")
            return
        }
        let session = WCSession.default
        session.delegate = self
        switch session.activationState {
        case .activated:
            // 已激活时只补读 context，避免多处调用 `activate()` 打出 “already in progress or activated”
            BolaDebugLog.shared.log(.wc, "activate noop (already activated)")
            DispatchQueue.main.async { [weak self] in
                self?.refreshDebugSessionState(session)
                self?.ingest(session.receivedApplicationContext)
            }
        case .inactive:
            // 正在激活过程中，勿重复调用
            BolaDebugLog.shared.log(.wc, "activate noop (inactive/in progress)")
            break
        case .notActivated:
            BolaDebugLog.shared.log(.wc, "activate() called")
            session.activate()
        @unknown default:
            session.activate()
        }
    }

    /// 把当前 `WCSession` 的配对/可达/安装状态镜像到 `@Published` 上，供调试面板订阅。
    private func refreshDebugSessionState(_ session: WCSession) {
        let activation = session.activationState.rawValue
        let reachable = session.isReachable
        #if os(iOS)
        let paired = session.isPaired
        let installed = session.isWatchAppInstalled
        #elseif os(watchOS)
        let paired = false
        let installed = session.isCompanionAppInstalled
        #else
        let paired = false
        let installed = false
        #endif
        let update: () -> Void = { [weak self] in
            guard let self else { return }
            self.debugActivationState = activation
            self.debugIsReachable = reachable
            self.debugIsPaired = paired
            self.debugIsCounterpartInstalled = installed
            self.debugPendingContext = (self.pendingPayload != nil)
            self.debugPendingChatDeltaCount = self.pendingChatDeltaPayloads.count
        }
        if Thread.isMainThread { update() } else { DispatchQueue.main.async(execute: update) }
    }

    /// 对端 Watch/iPhone App 是否已安装（未安装时发 WC 会刷屏系统日志）
    private func isCounterpartAppReady(_ session: WCSession) -> Bool {
        #if os(iOS)
        return session.isPaired && session.isWatchAppInstalled
        #elseif os(watchOS)
        return session.isCompanionAppInstalled
        #else
        return true
        #endif
    }

    /// 回到前台时可再读一次对端最后一次 `applicationContext`（与 `didReceive` 互补）。
    public func reapplyLatestReceivedContext() {
        let run: () -> Void = { [weak self] in
            guard let self else { return }
            let session = WCSession.default
            guard session.activationState == .activated else { return }
            self.ingest(session.receivedApplicationContext)
        }
        if Thread.isMainThread {
            run()
        } else {
            DispatchQueue.main.async(execute: run)
        }
    }

    /// 将当前陪伴值写入本机 defaults 并尽力推到另一端（session 未激活时会排队，激活后发出）。
    public func pushCompanionValue(_ value: Double, forcedForWatch: Bool = false) {
        let ts = Date().timeIntervalSince1970
        var payload: [String: Any] = [
            WCSyncPayload.companionValue: value,
            WCSyncPayload.companionValueUpdatedAt: ts,
            WCSyncPayload.petCoreState: currentPetCoreState.rawValue
        ]
        #if os(iOS)
        if forcedForWatch {
            payload[WCSyncPayload.companionSyncForcedFromPhone] = true
        }
        Self.appendWatchHomeScreenPayload(&payload)
        #endif
        #if os(watchOS)
        // 仅在调试面板开启时，随 context 一起带上当前情绪动画标签（供 iPhone 调试 UI 显示）。
        if BolaDebugLog.shared.isEnabled, !currentPetEmotionLabel.isEmpty {
            payload[WCSyncPayload.petEmotionLabel] = currentPetEmotionLabel
        }
        #endif
        let defaults = BolaSharedDefaults.resolved()
        defaults.set(value, forKey: CompanionPersistenceKeys.companionValue)
        defaults.set(ts, forKey: CompanionPersistenceKeys.companionWCUpdatedAt)

        let run: () -> Void = { [weak self] in
            guard let self else { return }
            let session = WCSession.default
            if session.activationState == .activated, self.isCounterpartAppReady(session) {
                self.sendPayload(payload, session: session)
                self.pendingPayload = nil
            } else if session.activationState == .activated {
                #if os(iOS)
                if !session.isWatchAppInstalled {
                    bolaWCChatLog.warning("pushCompanionValue 未发往手表：isWatchAppInstalled=false")
                    BolaDebugLog.shared.log(.pending, "pushCompanion 搁置：watchApp 未安装 value=\(value)")
                } else if !session.isPaired {
                    bolaWCChatLog.warning("pushCompanionValue 未发往手表：当前未配对 Apple Watch")
                    BolaDebugLog.shared.log(.pending, "pushCompanion 搁置：未配对手表 value=\(value)")
                }
                #elseif os(watchOS)
                if !session.isCompanionAppInstalled {
                    bolaWCChatLog.warning("pushCompanionValue 未发往 iPhone：isCompanionAppInstalled=false")
                    BolaDebugLog.shared.log(.pending, "pushCompanion 搁置：iPhone 未安装 value=\(value)")
                }
                #endif
                self.pendingPayload = payload
            } else {
                BolaDebugLog.shared.log(.pending, "pushCompanion 搁置：session 未激活 value=\(value)")
                self.pendingPayload = payload
            }
            self.refreshDebugSessionState(session)
        }
        if Thread.isMainThread {
            run()
        } else {
            DispatchQueue.main.async(execute: run)
        }
    }

    /// 推送宠物核心状态变化（附带当前陪伴值，以便对端同步更新）。
    /// 先在主线程设置 currentPetCoreState，再调用 pushCompanionValue，
    /// 确保发出的 payload 携带的是新状态而非旧值。
    public func pushPetCoreState(_ state: PetCoreState) {
        let defaults = BolaSharedDefaults.resolved()
        let value: Double
        if defaults.object(forKey: CompanionPersistenceKeys.companionValue) != nil {
            value = defaults.double(forKey: CompanionPersistenceKeys.companionValue)
        } else {
            value = 50
        }
        let run: () -> Void = { [weak self] in
            guard let self else { return }
            if self.currentPetCoreState != state {
                BolaDebugLog.shared.log(.petState, "coreState → \(state.rawValue)")
            }
            self.currentPetCoreState = state
            self.pushCompanionValue(value)
        }
        if Thread.isMainThread {
            run()
        } else {
            DispatchQueue.main.async(execute: run)
        }
    }

    #if os(iOS)
    /// iPhone 点击宠物时本机直接 +1 陪伴值（乐观更新），并同步到手表。
    public func incrementCompanionValueLocally(by delta: Double = 1) {
        let defaults = BolaSharedDefaults.resolved()
        var v: Double
        if defaults.object(forKey: CompanionPersistenceKeys.companionValue) != nil {
            v = defaults.double(forKey: CompanionPersistenceKeys.companionValue)
        } else {
            v = 50
        }
        v = min(max(v + delta, 0), 100)
        pushCompanionValue(v)
    }

    /// 把 iPhone 上的宠物交互指令发给手表（仅 eat/drink/sleep；tap 已改为本机处理）。
    public func sendPetCommand(_ kind: String) {
        guard WCSession.isSupported() else { return }
        let payload: [String: Any] = [
            WCSyncPayload.petCommandKind: kind,
            WCSyncPayload.petCommandId: UUID().uuidString
        ]
        let run: () -> Void = {
            let session = WCSession.default
            guard session.activationState == .activated,
                  session.isPaired,
                  session.isWatchAppInstalled else {
                bolaWCChatLog.warning("sendPetCommand skip: session not ready kind=\(kind, privacy: .public)")
                return
            }
            if session.isReachable {
                session.sendMessage(payload, replyHandler: nil) { err in
                    bolaWCChatLog.warning("sendPetCommand sendMessage failed kind=\(kind, privacy: .public) err=\(String(describing: err), privacy: .public); falling back to transferUserInfo")
                    BolaDebugLog.shared.log(.error, "sendMessage 失败(kind=\(kind))，回退 transferUserInfo")
                    session.transferUserInfo(payload)
                }
            } else {
                session.transferUserInfo(payload)
            }
            bolaWCChatLog.info("sendPetCommand dispatched kind=\(kind, privacy: .public)")
            BolaDebugLog.shared.log(.command, "发出指令 kind=\(kind) viaMessage=\(session.isReachable)")
        }
        if Thread.isMainThread { run() } else { DispatchQueue.main.async(execute: run) }
    }
    #endif

    #if os(watchOS)
    /// 若 `dict` 携带 `petCommandKind` 且指令 id 未处理过，则发通知给 `PetViewModel` 分发。
    @discardableResult
    private func ingestPetCommandIfPresent(_ dict: [String: Any]) -> Bool {
        guard let kind = dict[WCSyncPayload.petCommandKind] as? String, !kind.isEmpty else {
            return false
        }
        let id = (dict[WCSyncPayload.petCommandId] as? String) ?? ""
        if !id.isEmpty {
            if recentPetCommandIds.contains(id) {
                bolaWCChatLog.info("ingestPetCommand skip dup id=\(id, privacy: .public) kind=\(kind, privacy: .public)")
                return true
            }
            recentPetCommandIds.append(id)
            if recentPetCommandIds.count > maxPetCommandIdHistory {
                recentPetCommandIds.removeFirst(recentPetCommandIds.count - maxPetCommandIdHistory)
            }
        }
        bolaWCChatLog.info("ingestPetCommand kind=\(kind, privacy: .public) id=\(id, privacy: .public)")
        BolaDebugLog.shared.log(.command, "收到指令 kind=\(kind)")
        NotificationCenter.default.post(
            name: .bolaPetCommandReceived,
            object: nil,
            userInfo: [PetCommandNotificationKey.kind: kind]
        )
        return true
    }
    #endif

    private func sendPayload(_ payload: [String: Any], session: WCSession) {
        guard isCounterpartAppReady(session) else {
            BolaDebugLog.shared.log(.pending, "sendPayload skip: counterpart not ready")
            return
        }
        var contextOK = true
        do {
            try session.updateApplicationContext(payload)
        } catch {
            contextOK = false
            bolaWCChatLog.warning("updateApplicationContext failed, companion will rely on transferUserInfo: \(String(describing: error), privacy: .public)")
            BolaDebugLog.shared.log(.error, "updateApplicationContext 失败: \(error.localizedDescription)")
        }
        // 与 application context 并行排队：部分环境下表端 `receivedApplicationContext` 长期为空，仍可通过 `didReceiveUserInfo` 合并陪伴值。
        session.transferUserInfo(payload)
        let keys = payload.keys.sorted().joined(separator: ",")
        bolaWCChatLog.info("sendPayload companion queued transferUserInfo keys=\(keys, privacy: .public)")
        let v = Self.doubleValue(payload[WCSyncPayload.companionValue]).map { String(format: "%.1f", $0) } ?? "-"
        BolaDebugLog.shared.log(.send, "context\(contextOK ? "+ui" : " failed → ui") value=\(v) keys=[\(keys)]")
    }

#if os(iOS)
    public enum WatchInstallabilityStatus: Sendable {
        case ready
        case notPaired
        case appNotInstalled
    }

    public func watchInstallabilityStatus() -> WatchInstallabilityStatus {
        guard WCSession.isSupported() else { return .ready }
        let session = WCSession.default
        guard session.isPaired else { return .notPaired }
        return session.isWatchAppInstalled ? .ready : .appNotInstalled
    }

    /// 将 LLM 配置发到已配对的 Apple Watch（`transferUserInfo`，可达时送达）。
    public func pushLLMConfigurationToWatch(apiKey: String, baseURL: String, model: String, useBearerAuth: Bool) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        let payload: [String: Any] = [
            WCSyncPayload.llmApiKey: apiKey,
            WCSyncPayload.llmBaseURL: baseURL,
            WCSyncPayload.llmModelId: model,
            WCSyncPayload.llmAuthBearer: useBearerAuth ? "1" : "0"
        ]
        session.transferUserInfo(payload)
    }

    /// 提醒列表在 iPhone 侧变更后，直接把列表发给手表并触发表端重排本地通知。
    public func pushReminderRefreshToWatchIfPossible() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        let reminders = ReminderListStore.load()
        guard let data = try? JSONEncoder().encode(reminders) else { return }
        let payload = [WCSyncPayload.remindersListB64: data.base64EncodedString()]
        session.transferUserInfo(payload)
    }

    /// 餐食配置在 iPhone 侧变更后，推送到手表让 MealEngine 重建今日记录。
    public func pushMealSlotsToWatchIfPossible() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        let slots = MealSlotStore.load()
        guard let data = try? JSONEncoder().encode(slots) else { return }
        let payload = [WCSyncPayload.mealSlotsB64: data.base64EncodedString()]
        session.transferUserInfo(payload)
        BolaDebugLog.shared.log(.meal, "pushMealSlots → Watch count=\(slots.count)")
    }

    /// 系统是否认为「已配对的 Apple Watch 上已安装本 App」。为 false 时 `updateApplicationContext` 不会送达表端。
    public func shouldShowWatchAppMissingHint() -> Bool {
        watchInstallabilityStatus() == .appNotInstalled
    }

    private func postWatchInstallabilityChanged() {
        NotificationCenter.default.post(name: .bolaWatchInstallabilityDidChange, object: nil)
    }

    /// 若本机 Keychain 已有 LLM 配置，则在「手表 App 已安装且 WC 已激活」时推给手表。
    /// 用于：`activationDidComplete` 时 `isWatchAppInstalled` 仍为 false、稍后变为 true；或先点保存再装表端。
    public func pushStoredLLMConfigurationToWatchIfConfigured() {
        guard WCSession.isSupported() else { return }
        let run = { [weak self] in
            guard let self else { return }
            let session = WCSession.default
            guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
            guard let rawKey = KeychainHelper.get(service: LLMKeychain.service, account: LLMKeychain.accountAPIKey) else {
                bolaWCChatLog.info("pushStoredLLMConfigurationToWatchIfConfigured skip: iPhone Keychain has no API key (在设置里保存并同步)")
                return
            }
            let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return }
            let base = KeychainHelper.get(service: LLMKeychain.service, account: LLMKeychain.accountBaseURL)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let model = KeychainHelper.get(service: LLMKeychain.service, account: LLMKeychain.accountModelId)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let useBearer = KeychainHelper.get(service: LLMKeychain.service, account: LLMKeychain.accountAuthBearer) != "0"
            self.pushLLMConfigurationToWatch(apiKey: key, baseURL: base, model: model, useBearerAuth: useBearer)
            bolaWCChatLog.info("pushStoredLLMConfigurationToWatchIfConfigured sent (llm transferUserInfo)")
            BolaDebugLog.shared.log(.llm, "已向手表推送 LLM 配置")
        }
        if Thread.isMainThread {
            run()
        } else {
            DispatchQueue.main.async(execute: run)
        }
    }

    /// 读取本机 defaults 中的陪伴值并再走 `pushCompanionValue`。
    /// 解决：用户从未在 iPhone 上点过 +/- 时，从未调用过 `pushCompanionValue`，手表端 `receivedApplicationContext` 一直为空。
    public func pushLocalCompanionTowardWatchFromDefaults() {
        let defaults = BolaSharedDefaults.resolved()
        let v: Double
        if defaults.object(forKey: CompanionPersistenceKeys.companionValue) != nil {
            v = defaults.double(forKey: CompanionPersistenceKeys.companionValue)
        } else {
            v = 50
        }
        pushCompanionValue(v, forcedForWatch: true)
        bolaWCChatLog.info("pushLocalCompanionTowardWatchFromDefaults pushed value=\(v)")
    }

    private static func appendWatchHomeScreenPayload(_ payload: inout [String: Any]) {
        let slots = WatchFaceSlotsStore.load()
        if let data = try? JSONEncoder().encode(slots) {
            payload[WCSyncPayload.watchFaceSlotsB64] = data.base64EncodedString()
        }
        let title = BolaTitleSelectionStore.load()
        if let data = try? JSONEncoder().encode(title) {
            payload[WCSyncPayload.titleSelectionB64] = data.base64EncodedString()
        }
        payload[WCSyncPayload.personalitySelectionRaw] = BolaPersonalitySelectionStore.validated().rawValue
        // Growth state
        let growthState = BolaGrowthStore.load()
        if let data = try? JSONEncoder().encode(growthState) {
            payload[WCSyncPayload.growthStateB64] = data.base64EncodedString()
        }
        // Title unlocked IDs
        let unlockedIds = Array(TitleUnlockStore.loadUnlockedIds()).sorted()
        if let data = try? JSONEncoder().encode(unlockedIds) {
            payload[WCSyncPayload.titleUnlockedIdsB64] = data.base64EncodedString()
        }
        // Max-ever companion value for title unlock conditions
        let defaults = BolaSharedDefaults.resolved()
        let maxCV = defaults.double(forKey: "bola_max_ever_companion_v1")
        payload[WCSyncPayload.maxEverCompanionValue] = maxCV
    }
    #endif

    private func enqueueChatDeltaPayload(_ payload: [String: Any]) {
        if pendingChatDeltaPayloads.count >= maxPendingChatDeltaPayloads {
            pendingChatDeltaPayloads.removeFirst()
            bolaWCChatLog.warning("pushChatDelta queue full: dropped oldest pending")
            BolaDebugLog.shared.log(.error, "chatDelta 队列已满，丢弃最旧一条")
        }
        pendingChatDeltaPayloads.append(payload)
        bolaWCChatLog.info("pushChatDelta enqueued pendingCount=\(self.pendingChatDeltaPayloads.count, privacy: .public)")
        debugPendingChatDeltaCount = pendingChatDeltaPayloads.count
        BolaDebugLog.shared.log(.pending, "chatDelta 入队 pending=\(pendingChatDeltaPayloads.count)")
    }

    /// 对端就绪且 session 已激活时，按顺序发出队列中的聊天记录包。
    private func flushPendingChatDeltasIfReady(session: WCSession) {
        guard session.activationState == .activated, isCounterpartAppReady(session) else { return }
        let initial = pendingChatDeltaPayloads.count
        while !pendingChatDeltaPayloads.isEmpty {
            let payload = pendingChatDeltaPayloads.removeFirst()
            session.transferUserInfo(payload)
            bolaWCChatLog.info("flushPendingChatDeltas transferUserInfo remaining=\(self.pendingChatDeltaPayloads.count, privacy: .public)")
        }
        if initial > 0 {
            BolaDebugLog.shared.log(.send, "chatDelta flush \(initial) 条")
        }
        debugPendingChatDeltaCount = pendingChatDeltaPayloads.count
    }

    /// 推送本轮新增的两条对话到对端（手表 / iPhone 各有一份本地存储，需 WC 合并）。
    public func pushChatDelta(_ turns: [ChatTurn]) {
        guard turns.count == 1 || turns.count == 2 else {
            bolaWCChatLog.warning("pushChatDelta skip: turns.count=\(turns.count, privacy: .public) (need 1 or 2)")
            return
        }
        let enc = JSONEncoder()
        guard let data = try? enc.encode(turns) else {
            bolaWCChatLog.error("pushChatDelta encode failed")
            return
        }
        let b64 = data.base64EncodedString()
        let payload: [String: Any] = [
            WCSyncPayload.chatDeltaKind: "v1",
            WCSyncPayload.chatDeltaDataB64: b64
        ]
        let ids = turns.map(\.id.uuidString).joined(separator: ",")
        bolaWCChatLog.info("pushChatDelta encode OK ids=[\(ids, privacy: .public)] jsonBytes=\(data.count, privacy: .public) b64Len=\(b64.count, privacy: .public)")
        DispatchQueue.main.async {
            guard WCSession.isSupported() else {
                bolaWCChatLog.warning("pushChatDelta skip: WCSession not supported")
                return
            }
            let session = WCSession.default
            let state = session.activationState.rawValue
            let ready = self.isCounterpartAppReady(session)
            #if os(iOS)
            let detail = "activation=\(state) paired=\(session.isPaired) watchAppInstalled=\(session.isWatchAppInstalled) counterpartReady=\(ready)"
            #elseif os(watchOS)
            let detail = "activation=\(state) companionInstalled=\(session.isCompanionAppInstalled) counterpartReady=\(ready)"
            #else
            let detail = "activation=\(state) counterpartReady=\(ready)"
            #endif
            self.flushPendingChatDeltasIfReady(session: session)
            guard session.activationState == .activated else {
                self.enqueueChatDeltaPayload(payload)
                bolaWCChatLog.warning("pushChatDelta enqueued (session not activated): \(detail)")
                return
            }
            guard ready else {
                self.enqueueChatDeltaPayload(payload)
                bolaWCChatLog.warning("pushChatDelta enqueued (counterpart not ready): \(detail)")
                return
            }
            session.transferUserInfo(payload)
            bolaWCChatLog.info("pushChatDelta transferUserInfo submitted \(detail)")
            BolaDebugLog.shared.log(.send, "chatDelta 已发出 turns=\(turns.count)")
        }
    }

    private func ingestChatDeltaIfPresent(_ dict: [String: Any]) -> Bool {
        guard (dict[WCSyncPayload.chatDeltaKind] as? String) == "v1" else { return false }
        guard let b64 = dict[WCSyncPayload.chatDeltaDataB64] as? String,
              let raw = Data(base64Encoded: b64) else {
            bolaWCChatLog.warning("ingestChatDelta malformed b64")
            BolaDebugLog.shared.log(.error, "chatDelta 收到但 b64 解析失败")
            return false
        }
        let dec = JSONDecoder()
        guard let turns = try? dec.decode([ChatTurn].self, from: raw), !turns.isEmpty else {
            bolaWCChatLog.warning("ingestChatDelta decode failed rawBytes=\(raw.count, privacy: .public)")
            BolaDebugLog.shared.log(.error, "chatDelta 收到但 JSON 解码失败 bytes=\(raw.count)")
            return false
        }
        bolaWCChatLog.info("ingestChatDelta merging turns=\(turns.count, privacy: .public)")
        ChatHistoryStore.mergeRemoteTurns(turns)
        NotificationCenter.default.post(name: .bolaChatHistoryDidMerge, object: nil)
        bolaWCChatLog.info("ingestChatDelta done → posted bolaChatHistoryDidMerge")
        BolaDebugLog.shared.log(.recv, "chatDelta 合并 turns=\(turns.count)")
        return true
    }

    #if os(watchOS)
    /// 无 App Group 时：把手表 `UserDefaults` 中的陪伴游戏状态防抖同步到 iPhone（`transferUserInfo`）。
    public func schedulePushCompanionGameStateSnapshotToPhoneDebounced() {
        companionGameStateSnapshotDebounceTask?.cancel()
        companionGameStateSnapshotDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let self else { return }
            guard !Task.isCancelled else { return }
            self.pushCompanionGameStateSnapshotToPhoneNow()
        }
    }

    private func pushCompanionGameStateSnapshotToPhoneNow() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        // watchOS 无 `isPaired`（仅 iOS）；能发 transferUserInfo 时 companion 已配对即可。
        guard session.activationState == .activated, session.isCompanionAppInstalled else { return }
        let defaults = BolaSharedDefaults.resolved()
        var plist: [String: Any] = [:]
        for key in CompanionPersistenceKeys.wcGameStateSnapshotKeys {
            guard let o = defaults.object(forKey: key) else { continue }
            switch o {
            case let n as NSNumber:
                plist[key] = n
            case let b as Bool:
                plist[key] = b
            case let s as String:
                plist[key] = s
            case let d as Double:
                plist[key] = d
            case let i as Int:
                plist[key] = i
            default:
                break
            }
        }
        guard !plist.isEmpty else { return }
        guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0) else {
            bolaWCChatLog.warning("pushCompanionSnapshot plist encode failed")
            return
        }
        let b64 = data.base64EncodedString()
        let payload: [String: Any] = [
            WCSyncPayload.companionSnapshotKind: WCSyncPayload.companionSnapshotKindV1,
            WCSyncPayload.companionSnapshotB64: b64
        ]
        session.transferUserInfo(payload)
        bolaWCChatLog.info("pushCompanionSnapshotToPhone transferUserInfo plistBytes=\(data.count) entryCount=\(plist.count, privacy: .public)")
    }
    #endif

    #if os(iOS)
    /// 合并手表推送的游戏状态：计数/墙钟等始终采用手表；`companionValue` 若本机 WC 时间戳更新则不回退（避免覆盖手机上刚点的 +/-）。
    private func ingestCompanionGameStateSnapshotFromWatchIfPresent(_ dict: [String: Any]) -> Bool {
        guard (dict[WCSyncPayload.companionSnapshotKind] as? String) == WCSyncPayload.companionSnapshotKindV1 else { return false }
        guard let b64 = dict[WCSyncPayload.companionSnapshotB64] as? String,
              let raw = Data(base64Encoded: b64) else {
            bolaWCChatLog.warning("ingestCompanionSnapshot malformed b64")
            return false
        }
        var fmt = PropertyListSerialization.PropertyListFormat.binary
        guard let plist = try? PropertyListSerialization.propertyList(from: raw, options: [], format: &fmt),
              let remote = plist as? [String: Any] else {
            bolaWCChatLog.warning("ingestCompanionSnapshot decode failed")
            return false
        }

        let defaults = BolaSharedDefaults.resolved()
        let localWC = defaults.double(forKey: CompanionPersistenceKeys.companionWCUpdatedAt)
        let remoteWC = Self.doubleValue(remote[CompanionPersistenceKeys.companionWCUpdatedAt]) ?? 0

        var didApply = false
        for key in CompanionPersistenceKeys.allCompanionKeys {
            guard key != CompanionPersistenceKeys.companionValue else { continue }
            guard let v = remote[key] else { continue }
            defaults.set(v, forKey: key)
            didApply = true
        }

        if let cvRaw = remote[CompanionPersistenceKeys.companionValue], let cv = Self.doubleValue(cvRaw) {
            if remoteWC >= localWC - 0.000_1 {
                defaults.set(cv, forKey: CompanionPersistenceKeys.companionValue)
                if remoteWC > 0 {
                    defaults.set(remoteWC, forKey: CompanionPersistenceKeys.companionWCUpdatedAt)
                }
                didApply = true
            }
        } else if remoteWC >= localWC - 0.000_1, remoteWC > 0 {
            defaults.set(remoteWC, forKey: CompanionPersistenceKeys.companionWCUpdatedAt)
            didApply = true
        }

        bolaWCChatLog.info("ingestCompanionSnapshot from watch remoteWC=\(remoteWC, privacy: .public) localWC=\(localWC, privacy: .public) didApply=\(didApply, privacy: .public)")
        if didApply {
            NotificationCenter.default.post(name: .bolaCompanionStateDidMergeFromWatch, object: nil)
            if defaults.object(forKey: CompanionPersistenceKeys.companionValue) != nil {
                onReceiveCompanionValue?(defaults.double(forKey: CompanionPersistenceKeys.companionValue))
            }
        }
        return true
    }
    #endif

    #if os(iOS)
    /// 仅用于调试：若 payload 只携带 `petEmotionLabel`（+ 可选 `petCoreState`），写入镜像状态后返回 true。
    @discardableResult
    private func ingestPetEmotionLabelIfPresent(_ dict: [String: Any]) -> Bool {
        guard dict[WCSyncPayload.companionValue] == nil else { return false }
        guard let label = dict[WCSyncPayload.petEmotionLabel] as? String, !label.isEmpty else { return false }
        if currentPetEmotionLabel != label {
            BolaDebugLog.shared.log(.recv, "emotion 标签 → \(label)")
            currentPetEmotionLabel = label
        }
        if let raw = dict[WCSyncPayload.petCoreState] as? String,
           let state = PetCoreState(rawValue: raw), currentPetCoreState != state {
            BolaDebugLog.shared.log(.petState, "coreState → \(state.rawValue)")
            currentPetCoreState = state
        }
        return true
    }
    #endif

    /// 若 `userInfo` 为 LLM 同步包则写入本机 Keychain 并返回 `true`。
    private func ingestLLMConfigurationIfPresent(_ dict: [String: Any]) -> Bool {
        guard dict.keys.contains(WCSyncPayload.llmApiKey) else { return false }
        let apiKey = (dict[WCSyncPayload.llmApiKey] as? String) ?? ""
        let base = (dict[WCSyncPayload.llmBaseURL] as? String) ?? ""
        let model = (dict[WCSyncPayload.llmModelId] as? String) ?? ""

        if apiKey.isEmpty {
            KeychainHelper.remove(service: LLMKeychain.service, account: LLMKeychain.accountAPIKey)
        } else {
            KeychainHelper.set(apiKey, service: LLMKeychain.service, account: LLMKeychain.accountAPIKey)
        }
        if base.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            KeychainHelper.remove(service: LLMKeychain.service, account: LLMKeychain.accountBaseURL)
        } else {
            KeychainHelper.set(base.trimmingCharacters(in: .whitespacesAndNewlines), service: LLMKeychain.service, account: LLMKeychain.accountBaseURL)
        }
        if model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            KeychainHelper.remove(service: LLMKeychain.service, account: LLMKeychain.accountModelId)
        } else {
            KeychainHelper.set(model.trimmingCharacters(in: .whitespacesAndNewlines), service: LLMKeychain.service, account: LLMKeychain.accountModelId)
        }
        if let bearer = dict[WCSyncPayload.llmAuthBearer] as? String {
            KeychainHelper.set(bearer, service: LLMKeychain.service, account: LLMKeychain.accountAuthBearer)
        }
        let hasKey = !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        bolaWCChatLog.info("ingestLLMConfiguration applied hasApiKey=\(hasKey, privacy: .public) baseLen=\(base.count, privacy: .public) modelLen=\(model.count, privacy: .public)")
        BolaDebugLog.shared.log(.llm, "LLM 配置落地 hasKey=\(hasKey) baseLen=\(base.count) modelLen=\(model.count)")
        return true
    }

    #if os(watchOS)
    /// 从 iPhone 的 `applicationContext` / `userInfo` 合并表盘槽、称号、成长状态。
    private static func ingestWatchHomeScreenPayloadIfPresent(_ dict: [String: Any]) {
        var changed = false
        if let b64 = dict[WCSyncPayload.watchFaceSlotsB64] as? String,
           let data = Data(base64Encoded: b64),
           let cfg = try? JSONDecoder().decode(WatchFaceSlotsConfiguration.self, from: data) {
            WatchFaceSlotsStore.save(cfg)
            changed = true
        }
        if let b64 = dict[WCSyncPayload.titleSelectionB64] as? String,
           let data = Data(base64Encoded: b64),
           let sel = try? JSONDecoder().decode(BolaTitleSelection.self, from: data) {
            BolaTitleSelectionStore.save(sel)
            changed = true
        }
        if let raw = dict[WCSyncPayload.personalitySelectionRaw] as? String,
           let selection = BolaPersonalitySelection(rawValue: raw) {
            BolaPersonalitySelectionStore.save(selection)
            changed = true
        }
        // 成长状态合并（totalXP 取大值）
        if let b64 = dict[WCSyncPayload.growthStateB64] as? String,
           let data = Data(base64Encoded: b64),
           let remoteState = try? JSONDecoder().decode(BolaGrowthState.self, from: data) {
            BolaGrowthStore.mergeFromRemote(remoteState)
            changed = true
        }
        // 称号解锁 ID 合并（取并集）
        if let b64 = dict[WCSyncPayload.titleUnlockedIdsB64] as? String,
           let data = Data(base64Encoded: b64),
           let ids = try? JSONDecoder().decode([String].self, from: data) {
            TitleUnlockStore.mergeFromRemote(Set(ids))
            changed = true
        }
        if changed {
            NotificationCenter.default.post(name: .bolaWatchHomeScreenPayloadDidUpdate, object: nil)
        }
    }
    #endif

    /// 陪伴值写入受时间戳保护（last-write-wins），petCoreState / petEmotionLabel
    /// 与陪伴值时间戳无关，始终先于时间戳守卫应用，确保核心状态即时同步。
    private func ingest(_ dict: [String: Any]) {
        #if os(watchOS)
        if Self.ingestRemindersIfPresent(dict) {
            return
        }
        if Self.ingestMealSlotsIfPresent(dict) {
            return
        }
        Self.ingestWatchHomeScreenPayloadIfPresent(dict)
        #endif

        // petCoreState 与 petEmotionLabel 不受陪伴值时间戳守卫限制；
        // 它们由对端直接驱动，应始终应用以保证即时同步。
        if let raw = dict[WCSyncPayload.petCoreState] as? String,
           let state = PetCoreState(rawValue: raw) {
            if currentPetCoreState != state {
                BolaDebugLog.shared.log(.petState, "coreState → \(state.rawValue)")
            }
            currentPetCoreState = state
        }
        #if os(iOS)
        if let label = dict[WCSyncPayload.petEmotionLabel] as? String, !label.isEmpty {
            if currentPetEmotionLabel != label {
                BolaDebugLog.shared.log(.petState, "watch emotion → \(label)")
            }
            currentPetEmotionLabel = label
        }
        #endif

        guard let (v, tsRaw) = Self.parsePayload(dict) else { return }
        let forcedFromPhone = Self.boolFlag(dict[WCSyncPayload.companionSyncForcedFromPhone])
        let defaults = BolaSharedDefaults.resolved()
        let localTs = defaults.double(forKey: CompanionPersistenceKeys.companionWCUpdatedAt)

        let remoteTs: TimeInterval
        if tsRaw > 0 {
            remoteTs = tsRaw
        } else if localTs == 0 || forcedFromPhone {
            remoteTs = Date().timeIntervalSince1970
        } else {
            return
        }

        if !forcedFromPhone {
            guard remoteTs > localTs else { return }
        }

        defaults.set(v, forKey: CompanionPersistenceKeys.companionValue)
        // 强制同步时用「当下」时间戳，避免手表刚写入的旧 remoteTs 在后续往返中输给仍带旧戳的延迟包。
        let storedTs = forcedFromPhone ? Date().timeIntervalSince1970 : remoteTs
        defaults.set(storedTs, forKey: CompanionPersistenceKeys.companionWCUpdatedAt)
        onReceiveCompanionValue?(v)
        BolaDebugLog.shared.log(.recv, "companion value=\(String(format: "%.1f", v)) forced=\(forcedFromPhone)")
    }

    private static func parsePayload(_ dict: [String: Any]) -> (Double, TimeInterval)? {
        guard let v = doubleValue(dict[WCSyncPayload.companionValue]) else { return nil }
        let ts = doubleValue(dict[WCSyncPayload.companionValueUpdatedAt]) ?? 0
        return (v, ts)
    }

    private static func doubleValue(_ any: Any?) -> Double? {
        switch any {
        case let d as Double: return d
        case let f as Float: return Double(f)
        case let n as NSNumber: return n.doubleValue
        case let i as Int: return Double(i)
        default: return nil
        }
    }

    private static func boolFlag(_ any: Any?) -> Bool {
        switch any {
        case let b as Bool: return b
        case let n as NSNumber: return n.boolValue
        case let s as NSString: return s.boolValue
        default: return false
        }
    }

    #if os(watchOS)
    @discardableResult
    private static func ingestRemindersIfPresent(_ dict: [String: Any]) -> Bool {
        guard let b64 = dict[WCSyncPayload.remindersListB64] as? String,
              let data = Data(base64Encoded: b64),
              let reminders = try? JSONDecoder().decode([BolaReminder].self, from: data) else { return false }
        ReminderListStore.save(reminders)
        Task { await BolaReminderUNScheduler.sync(reminders: reminders) }
        return true
    }

    @discardableResult
    private static func ingestMealSlotsIfPresent(_ dict: [String: Any]) -> Bool {
        guard let b64 = dict[WCSyncPayload.mealSlotsB64] as? String,
              let data = Data(base64Encoded: b64),
              let slots = try? JSONDecoder().decode([MealSlot].self, from: data) else { return false }
        MealSlotStore.save(slots)
        BolaDebugLog.shared.log(.meal, "ingestMealSlots from iPhone count=\(slots.count)")
        NotificationCenter.default.post(name: .bolaMealSlotsDidUpdate, object: nil)
        return true
    }
    #endif

    // MARK: - WCSessionDelegate

    public func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let error {
                bolaWCChatLog.error("WCSession activation error=\(String(describing: error), privacy: .public) state=\(activationState.rawValue, privacy: .public)")
                BolaDebugLog.shared.log(.error, "activation error state=\(activationState.rawValue) err=\(error.localizedDescription)")
            } else {
                #if os(iOS)
                bolaWCChatLog.info("WCSession activation state=\(activationState.rawValue, privacy: .public) paired=\(session.isPaired, privacy: .public) watchAppInstalled=\(session.isWatchAppInstalled, privacy: .public) reachable=\(session.isReachable, privacy: .public)")
                BolaDebugLog.shared.log(.wc, "activated state=\(activationState.rawValue) paired=\(session.isPaired) watchInstalled=\(session.isWatchAppInstalled) reach=\(session.isReachable)")
                #elseif os(watchOS)
                bolaWCChatLog.info("WCSession activation state=\(activationState.rawValue, privacy: .public) companionInstalled=\(session.isCompanionAppInstalled, privacy: .public) reachable=\(session.isReachable, privacy: .public)")
                BolaDebugLog.shared.log(.wc, "activated state=\(activationState.rawValue) iPhoneInstalled=\(session.isCompanionAppInstalled) reach=\(session.isReachable)")
                #else
                bolaWCChatLog.info("WCSession activation state=\(activationState.rawValue, privacy: .public)")
                #endif
            }
            self.refreshDebugSessionState(session)
            guard activationState == .activated else { return }
            let ctx = session.receivedApplicationContext
            bolaWCChatLog.info("receivedApplicationContext keys=\(ctx.keys.sorted().joined(separator: ","), privacy: .public) count=\(ctx.count, privacy: .public)")
            self.ingest(session.receivedApplicationContext)
            if let pending = self.pendingPayload {
                let defaults = BolaSharedDefaults.resolved()
                let localTs = defaults.double(forKey: CompanionPersistenceKeys.companionWCUpdatedAt)
                if let (_, pendingTs) = Self.parsePayload(pending), pendingTs >= localTs - 0.000_1 {
                    if self.isCounterpartAppReady(session) {
                        self.sendPayload(pending, session: session)
                        self.pendingPayload = nil
                    }
                } else {
                    self.pendingPayload = nil
                }
            }
            #if os(iOS)
            self.pushStoredLLMConfigurationToWatchIfConfigured()
            self.pushLocalCompanionTowardWatchFromDefaults()
            self.pushReminderRefreshToWatchIfPossible()
            self.pushMealSlotsToWatchIfPossible()
            self.postWatchInstallabilityChanged()
            #endif
            self.flushPendingChatDeltasIfReady(session: session)
            #if os(watchOS)
            self.requestLLMKeychainFromPhoneIfMissing(session: session)
            #endif
        }
    }

    #if os(iOS)
    /// 配对/安装状态变化时系统回调；此前 `isWatchAppInstalled` 可能刚从 false 变 true。
    public func sessionWatchStateDidChange(_ session: WCSession) {
        bolaWCChatLog.info("sessionWatchStateDidChange watchAppInstalled=\(session.isWatchAppInstalled) paired=\(session.isPaired) reachable=\(session.isReachable)")
        BolaDebugLog.shared.log(.wc, "watchState paired=\(session.isPaired) installed=\(session.isWatchAppInstalled) reach=\(session.isReachable)")
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refreshDebugSessionState(session)
            self.flushPendingChatDeltasIfReady(session: session)
            self.pushStoredLLMConfigurationToWatchIfConfigured()
            self.pushLocalCompanionTowardWatchFromDefaults()
            self.pushReminderRefreshToWatchIfPossible()
            self.pushMealSlotsToWatchIfPossible()
            self.postWatchInstallabilityChanged()
        }
    }

    public func sessionReachabilityDidChange(_ session: WCSession) {
        bolaWCChatLog.info("sessionReachabilityDidChange reachable=\(session.isReachable) watchAppInstalled=\(session.isWatchAppInstalled)")
        BolaDebugLog.shared.log(.wc, "reachability → \(session.isReachable)")
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refreshDebugSessionState(session)
            self.flushPendingChatDeltasIfReady(session: session)
            guard session.isReachable, session.isWatchAppInstalled else { return }
            self.pushStoredLLMConfigurationToWatchIfConfigured()
            self.pushLocalCompanionTowardWatchFromDefaults()
            self.pushReminderRefreshToWatchIfPossible()
            self.pushMealSlotsToWatchIfPossible()
        }
    }

    public func sessionDidBecomeInactive(_ session: WCSession) {}
    public func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.delegate = self
        WCSession.default.activate()
    }
    #elseif os(watchOS)
    /// iPhone 伴侣 App 安装/可达性变化时，把本机当前陪伴值再推给手机（与 iPhone 侧 `pushLocalCompanionTowardWatchFromDefaults` 对称）。
    public func sessionCompanionStateDidChange(_ session: WCSession) {
        bolaWCChatLog.info("sessionCompanionStateDidChange companionInstalled=\(session.isCompanionAppInstalled) reachable=\(session.isReachable)")
        BolaDebugLog.shared.log(.wc, "companionState installed=\(session.isCompanionAppInstalled) reach=\(session.isReachable)")
        refreshDebugSessionState(session)
        guard session.isCompanionAppInstalled else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.flushPendingChatDeltasIfReady(session: session)
            let defaults = BolaSharedDefaults.resolved()
            let v: Double
            if defaults.object(forKey: CompanionPersistenceKeys.companionValue) != nil {
                v = defaults.double(forKey: CompanionPersistenceKeys.companionValue)
            } else {
                v = 50
            }
            self.pushCompanionValue(v)
            self.schedulePushCompanionGameStateSnapshotToPhoneDebounced()
            self.requestLLMKeychainFromPhoneIfMissing(session: session)
            bolaWCChatLog.info("sessionCompanionStateDidChange pushed companion toward iPhone value=\(v)")
        }
    }
    #endif

    public func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let keys = applicationContext.keys.sorted().joined(separator: ",")
        BolaDebugLog.shared.log(.recv, "context keys=[\(keys)]")
        DispatchQueue.main.async { [weak self] in
            self?.ingest(applicationContext)
        }
    }

    public func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let keys = userInfo.keys.sorted().joined(separator: ",")
            bolaWCChatLog.info("didReceiveUserInfo keys=\(keys, privacy: .public) count=\(userInfo.count, privacy: .public)")
            BolaDebugLog.shared.log(.recv, "userInfo keys=[\(keys)]")
            // petCoreState 不依赖陪伴值时间戳，在任何专用 ingestor 判断前先应用。
            if let raw = userInfo[WCSyncPayload.petCoreState] as? String,
               let state = PetCoreState(rawValue: raw), self.currentPetCoreState != state {
                BolaDebugLog.shared.log(.petState, "coreState → \(state.rawValue) (userInfo early)")
                self.currentPetCoreState = state
            }
            #if os(iOS)
            if (userInfo[WCSyncPayload.requestSync] as? String) == WCSyncPayload.requestSyncValueLLMKeychain {
                bolaWCChatLog.info("didReceiveUserInfo: watch asked for LLM Keychain → pushStored")
                self.pushStoredLLMConfigurationToWatchIfConfigured()
                return
            }
            #endif
            #if os(watchOS)
            if self.ingestSpeechRelayReplyIfPresent(userInfo) {
                bolaWCChatLog.info("didReceiveUserInfo handled as speechRelayReply")
                return
            }
            if self.ingestPetCommandIfPresent(userInfo) {
                return
            }
            #endif
            if self.ingestChatDeltaIfPresent(userInfo) {
                return
            }
            #if os(iOS)
            if self.ingestCompanionGameStateSnapshotFromWatchIfPresent(userInfo) {
                return
            }
            if self.ingestPetEmotionLabelIfPresent(userInfo) {
                return
            }
            #endif
            if self.ingestLLMConfigurationIfPresent(userInfo) {
                return
            }
            self.ingest(userInfo)
        }
    }

    public func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let keys = message.keys.sorted().joined(separator: ",")
            bolaWCChatLog.info("didReceiveMessage keys=\(keys, privacy: .public)")
            BolaDebugLog.shared.log(.recv, "message keys=[\(keys)]")
            // petCoreState 不依赖陪伴值时间戳，优先应用。
            if let raw = message[WCSyncPayload.petCoreState] as? String,
               let state = PetCoreState(rawValue: raw), self.currentPetCoreState != state {
                BolaDebugLog.shared.log(.petState, "coreState → \(state.rawValue) (message early)")
                self.currentPetCoreState = state
            }
            #if os(watchOS)
            if self.ingestSpeechRelayReplyIfPresent(message) {
                return
            }
            if self.ingestPetCommandIfPresent(message) {
                return
            }
            #endif
            if self.ingestChatDeltaIfPresent(message) {
                return
            }
            self.ingest(message)
        }
    }

    public func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
        let info = userInfoTransfer.userInfo
        guard info[WCSyncPayload.chatDeltaKind] != nil else { return }
        if let error {
            bolaWCChatLog.error("chatDelta userInfoTransfer finished ERROR=\(String(describing: error), privacy: .public)")
        } else {
            bolaWCChatLog.info("chatDelta userInfoTransfer finished OK")
        }
    }

    #if os(iOS)
    public func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let kind = file.metadata?[WCSyncPayload.speechRelayKind] as? String
        guard kind == "speechRelay" else { return }
        let requestId = (file.metadata?[WCSyncPayload.speechRelayRequestId] as? String) ?? ""
        let src = file.fileURL
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("bola_relay_in_\(UUID().uuidString).m4a")
        do {
            try FileManager.default.copyItem(at: src, to: dest)
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.sendSpeechRelayReplyToWatch(
                    [
                        WCSyncPayload.speechRelayRequestId: requestId,
                        WCSyncPayload.speechRelayKind: "speechRelayReply",
                        WCSyncPayload.speechRelayError: error.localizedDescription
                    ],
                    session: session
                )
            }
            return
        }
        IOSpeechRelayTranscriber.shared.transcribe(url: dest) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                var payload: [String: Any] = [
                    WCSyncPayload.speechRelayRequestId: requestId,
                    WCSyncPayload.speechRelayKind: "speechRelayReply"
                ]
                switch result {
                case .success(let t):
                    payload[WCSyncPayload.speechRelayTranscript] = t
                case .failure(let e):
                    payload[WCSyncPayload.speechRelayError] = e.localizedDescription
                }
                self.sendSpeechRelayReplyToWatch(payload, session: session)
            }
        }
    }
    #endif
}
#endif
