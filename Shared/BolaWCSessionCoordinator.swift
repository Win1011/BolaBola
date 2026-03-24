//
//  BolaWCSessionCoordinator.swift
//

#if os(iOS) || os(watchOS)
import Foundation
import os
import WatchConnectivity

private let bolaWCChatLog = Logger(subsystem: "com.gathxr.BolaBola.sync", category: "WatchConnectivity")

/// 通过 `updateApplicationContext`（失败时 `transferUserInfo`）同步陪伴值；激活后消费 `receivedApplicationContext`。
public final class BolaWCSessionCoordinator: NSObject, WCSessionDelegate {
    public static let shared = BolaWCSessionCoordinator()

    /// 主线程：远端较新时写入 App Group 后调用。
    public var onReceiveCompanionValue: ((Double) -> Void)?

    private var pendingPayload: [String: Any]?

    #if os(watchOS)
    /// 手表 → iPhone 语音中继：等待与 `requestId` 匹配的转写结果
    private var speechRelayPending: (id: String, completion: (String?) -> Void)?
    private var speechRelayTimeoutWorkItem: DispatchWorkItem?
    #endif

    private override init() {
        super.init()
    }

    #if os(watchOS)
    public func prepareSpeechRelay(requestId: String, completion: @escaping (String?) -> Void) {
        speechRelayPending = (requestId, completion)
        speechRelayTimeoutWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if let pending = self.speechRelayPending, pending.id == requestId {
                self.speechRelayPending = nil
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
            pending.completion(nil)
            return true
        }
        let text = dict[WCSyncPayload.speechRelayTranscript] as? String ?? ""
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
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
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        switch session.activationState {
        case .activated:
            // 已激活时只补读 context，避免多处调用 `activate()` 打出 “already in progress or activated”
            DispatchQueue.main.async { [weak self] in
                self?.ingest(session.receivedApplicationContext)
            }
        case .inactive:
            // 正在激活过程中，勿重复调用
            break
        case .notActivated:
            session.activate()
        @unknown default:
            session.activate()
        }
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

    /// 将当前陪伴值写入 App Group 并尽力推到另一端（session 未激活时会排队，激活后发出）。
    /// - Parameter forcedForWatch: 仅 iPhone 上「同步手表」为 true，避免手表因晚到的 context 被本地较新的 `companionWCUpdatedAt` 拒绝。
    public func pushCompanionValue(_ value: Double, forcedForWatch: Bool = false) {
        let ts = Date().timeIntervalSince1970
        var payload: [String: Any] = [
            WCSyncPayload.companionValue: value,
            WCSyncPayload.companionValueUpdatedAt: ts
        ]
        #if os(iOS)
        if forcedForWatch {
            payload[WCSyncPayload.companionSyncForcedFromPhone] = true
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
                // 对端 App 未装好时先排队，安装配对后会再激活并发送
                #if os(iOS)
                if !session.isWatchAppInstalled {
                    bolaWCChatLog.warning("pushCompanionValue 未发往手表：isWatchAppInstalled=false（系统认定表端未安装 BolaBola）。请在 iPhone「Watch」App 安装表端，或用主 App Scheme 部署到手表后打开一次。")
                } else if !session.isPaired {
                    bolaWCChatLog.warning("pushCompanionValue 未发往手表：当前未配对 Apple Watch")
                }
                #elseif os(watchOS)
                if !session.isCompanionAppInstalled {
                    bolaWCChatLog.warning("pushCompanionValue 未发往 iPhone：isCompanionAppInstalled=false")
                }
                #endif
                self.pendingPayload = payload
            } else {
                self.pendingPayload = payload
            }
        }
        if Thread.isMainThread {
            run()
        } else {
            DispatchQueue.main.async(execute: run)
        }
    }

    private func sendPayload(_ payload: [String: Any], session: WCSession) {
        guard isCounterpartAppReady(session) else { return }
        do {
            try session.updateApplicationContext(payload)
        } catch {
            bolaWCChatLog.warning("updateApplicationContext failed, companion will rely on transferUserInfo: \(String(describing: error), privacy: .public)")
        }
        // 与 application context 并行排队：部分环境下表端 `receivedApplicationContext` 长期为空，仍可通过 `didReceiveUserInfo` 合并陪伴值。
        session.transferUserInfo(payload)
        let keys = payload.keys.sorted().joined(separator: ",")
        bolaWCChatLog.info("sendPayload companion queued transferUserInfo keys=\(keys, privacy: .public)")
    }

    #if os(iOS)
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

    /// 系统是否认为「已配对的 Apple Watch 上已安装本 App」。为 false 时 `updateApplicationContext` 不会送达表端。
    public func shouldShowWatchAppMissingHint() -> Bool {
        guard WCSession.isSupported() else { return false }
        let s = WCSession.default
        guard s.activationState == .activated, s.isPaired else { return false }
        return !s.isWatchAppInstalled
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
            guard let rawKey = KeychainHelper.get(service: LLMKeychain.service, account: LLMKeychain.accountAPIKey) else { return }
            let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return }
            let base = KeychainHelper.get(service: LLMKeychain.service, account: LLMKeychain.accountBaseURL)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let model = KeychainHelper.get(service: LLMKeychain.service, account: LLMKeychain.accountModelId)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let useBearer = KeychainHelper.get(service: LLMKeychain.service, account: LLMKeychain.accountAuthBearer) != "0"
            self.pushLLMConfigurationToWatch(apiKey: key, baseURL: base, model: model, useBearerAuth: useBearer)
            bolaWCChatLog.info("pushStoredLLMConfigurationToWatchIfConfigured sent (llm transferUserInfo)")
        }
        if Thread.isMainThread {
            run()
        } else {
            DispatchQueue.main.async(execute: run)
        }
    }

    /// 读取本机 App Group 中的陪伴值并再走 `pushCompanionValue`。
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
    #endif

    /// 推送本轮新增的两条对话到对端（手表 / iPhone 各有一份本地存储，需 WC 合并）。
    public func pushChatDelta(_ turns: [ChatTurn]) {
        guard turns.count == 2 else {
            bolaWCChatLog.warning("pushChatDelta skip: turns.count=\(turns.count, privacy: .public) (need 2)")
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
            guard session.activationState == .activated, ready else {
                bolaWCChatLog.warning("pushChatDelta skip: \(detail)")
                return
            }
            session.transferUserInfo(payload)
            bolaWCChatLog.info("pushChatDelta transferUserInfo submitted \(detail)")
        }
    }

    private func ingestChatDeltaIfPresent(_ dict: [String: Any]) -> Bool {
        guard (dict[WCSyncPayload.chatDeltaKind] as? String) == "v1" else { return false }
        guard let b64 = dict[WCSyncPayload.chatDeltaDataB64] as? String,
              let raw = Data(base64Encoded: b64) else {
            bolaWCChatLog.warning("ingestChatDelta malformed b64")
            return false
        }
        let dec = JSONDecoder()
        guard let turns = try? dec.decode([ChatTurn].self, from: raw), !turns.isEmpty else {
            bolaWCChatLog.warning("ingestChatDelta decode failed rawBytes=\(raw.count, privacy: .public)")
            return false
        }
        bolaWCChatLog.info("ingestChatDelta merging turns=\(turns.count, privacy: .public)")
        ChatHistoryStore.mergeRemoteTurns(turns)
        NotificationCenter.default.post(name: .bolaChatHistoryDidMerge, object: nil)
        bolaWCChatLog.info("ingestChatDelta done → posted bolaChatHistoryDidMerge")
        return true
    }

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
        return true
    }

    /// 仅当远端时间戳更新时才写入并回调，避免旧包覆盖新本地编辑。
    private func ingest(_ dict: [String: Any]) {
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
            } else {
                #if os(iOS)
                bolaWCChatLog.info("WCSession activation state=\(activationState.rawValue, privacy: .public) paired=\(session.isPaired, privacy: .public) watchAppInstalled=\(session.isWatchAppInstalled, privacy: .public) reachable=\(session.isReachable, privacy: .public)")
                #elseif os(watchOS)
                bolaWCChatLog.info("WCSession activation state=\(activationState.rawValue, privacy: .public) companionInstalled=\(session.isCompanionAppInstalled, privacy: .public) reachable=\(session.isReachable, privacy: .public)")
                #else
                bolaWCChatLog.info("WCSession activation state=\(activationState.rawValue, privacy: .public)")
                #endif
            }
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
            self.postWatchInstallabilityChanged()
            #endif
        }
    }

    #if os(iOS)
    /// 配对/安装状态变化时系统回调；此前 `isWatchAppInstalled` 可能刚从 false 变 true。
    public func sessionWatchStateDidChange(_ session: WCSession) {
        bolaWCChatLog.info("sessionWatchStateDidChange watchAppInstalled=\(session.isWatchAppInstalled) paired=\(session.isPaired) reachable=\(session.isReachable)")
        pushStoredLLMConfigurationToWatchIfConfigured()
        pushLocalCompanionTowardWatchFromDefaults()
        postWatchInstallabilityChanged()
    }

    public func sessionReachabilityDidChange(_ session: WCSession) {
        bolaWCChatLog.info("sessionReachabilityDidChange reachable=\(session.isReachable) watchAppInstalled=\(session.isWatchAppInstalled)")
        guard session.isReachable, session.isWatchAppInstalled else { return }
        pushStoredLLMConfigurationToWatchIfConfigured()
        pushLocalCompanionTowardWatchFromDefaults()
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
        guard session.isCompanionAppInstalled else { return }
        let defaults = BolaSharedDefaults.resolved()
        let v: Double
        if defaults.object(forKey: CompanionPersistenceKeys.companionValue) != nil {
            v = defaults.double(forKey: CompanionPersistenceKeys.companionValue)
        } else {
            v = 50
        }
        pushCompanionValue(v)
        bolaWCChatLog.info("sessionCompanionStateDidChange pushed companion toward iPhone value=\(v)")
    }
    #endif

    public func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            self?.ingest(applicationContext)
        }
    }

    public func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let keys = userInfo.keys.sorted().joined(separator: ",")
            bolaWCChatLog.info("didReceiveUserInfo keys=\(keys, privacy: .public) count=\(userInfo.count, privacy: .public)")
            #if os(watchOS)
            if self.ingestSpeechRelayReplyIfPresent(userInfo) {
                bolaWCChatLog.info("didReceiveUserInfo handled as speechRelayReply")
                return
            }
            #endif
            if self.ingestChatDeltaIfPresent(userInfo) {
                return
            }
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
            #if os(watchOS)
            if self.ingestSpeechRelayReplyIfPresent(message) {
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
