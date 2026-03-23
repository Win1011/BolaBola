//
//  BolaWCSessionCoordinator.swift
//

#if os(iOS) || os(watchOS)
import Foundation
import WatchConnectivity

/// 通过 `updateApplicationContext`（失败时 `transferUserInfo`）同步陪伴值；激活后消费 `receivedApplicationContext`。
public final class BolaWCSessionCoordinator: NSObject, WCSessionDelegate {
    public static let shared = BolaWCSessionCoordinator()

    /// 主线程：远端较新时写入 App Group 后调用。
    public var onReceiveCompanionValue: ((Double) -> Void)?

    private var pendingPayload: [String: Any]?

    private override init() {
        super.init()
    }

    public func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
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
    public func pushCompanionValue(_ value: Double) {
        let ts = Date().timeIntervalSince1970
        let payload: [String: Any] = [
            WCSyncPayload.companionValue: value,
            WCSyncPayload.companionValueUpdatedAt: ts
        ]
        let defaults = BolaSharedDefaults.resolved()
        defaults.set(value, forKey: CompanionPersistenceKeys.companionValue)
        defaults.set(ts, forKey: CompanionPersistenceKeys.companionWCUpdatedAt)

        let run: () -> Void = { [weak self] in
            guard let self else { return }
            let session = WCSession.default
            if session.activationState == .activated {
                self.sendPayload(payload, session: session)
                self.pendingPayload = nil
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
        do {
            try session.updateApplicationContext(payload)
        } catch {
            session.transferUserInfo(payload)
        }
    }

    /// 仅当远端时间戳更新时才写入并回调，避免旧包覆盖新本地编辑。
    private func ingest(_ dict: [String: Any]) {
        guard let (v, tsRaw) = Self.parsePayload(dict) else { return }
        let defaults = BolaSharedDefaults.resolved()
        let localTs = defaults.double(forKey: CompanionPersistenceKeys.companionWCUpdatedAt)

        let remoteTs: TimeInterval
        if tsRaw > 0 {
            remoteTs = tsRaw
        } else if localTs == 0 {
            remoteTs = Date().timeIntervalSince1970
        } else {
            return
        }

        guard remoteTs > localTs else { return }

        defaults.set(v, forKey: CompanionPersistenceKeys.companionValue)
        defaults.set(remoteTs, forKey: CompanionPersistenceKeys.companionWCUpdatedAt)
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

    // MARK: - WCSessionDelegate

    public func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard activationState == .activated else { return }
            self.ingest(session.receivedApplicationContext)
            if let pending = self.pendingPayload {
                let defaults = BolaSharedDefaults.resolved()
                let localTs = defaults.double(forKey: CompanionPersistenceKeys.companionWCUpdatedAt)
                if let (_, pendingTs) = Self.parsePayload(pending), pendingTs >= localTs - 0.000_1 {
                    self.sendPayload(pending, session: session)
                }
                self.pendingPayload = nil
            }
        }
    }

    #if os(iOS)
    public func sessionDidBecomeInactive(_ session: WCSession) {}
    public func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }
    #endif

    public func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            self?.ingest(applicationContext)
        }
    }

    public func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        DispatchQueue.main.async { [weak self] in
            self?.ingest(userInfo)
        }
    }
}
#endif
