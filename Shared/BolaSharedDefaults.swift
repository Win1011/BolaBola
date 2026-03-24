//
//  BolaSharedDefaults.swift
//

import Foundation
import os

private let bolaPrefsLog = Logger(subsystem: "com.gathxr.BolaBola.sync", category: "AppGroup")

public enum BolaSharedDefaults {
    private static let suiteLogLock = NSLock()
    private static var didLogSuiteResolution = false

    /// App Group suite; nil if capability missing (falls back to standard).
    public static var groupSuite: UserDefaults? {
        UserDefaults(suiteName: AppGroupConfig.suiteName)
    }

    /// Prefer App Group; fall back to `standard` so the app still runs before entitlements are fixed.
    public static func resolved() -> UserDefaults {
        let group = groupSuite
        suiteLogLock.lock()
        let first = !didLogSuiteResolution
        if first { didLogSuiteResolution = true }
        suiteLogLock.unlock()
        if first {
            if group != nil {
                bolaPrefsLog.info("UserDefaults → App Group suite=\(AppGroupConfig.suiteName, privacy: .public)")
            } else {
                bolaPrefsLog.warning("UserDefaults → standard (App Group nil). 检查 Entitlements / 真机 / 与后台 App Group 一致。")
            }
        }
        return group ?? .standard
    }

    /// One-time copy from `UserDefaults.standard` into the App Group so existing users keep progress.
    public static func migrateStandardToGroupIfNeeded() {
        guard let group = groupSuite else { return }
        if group.bool(forKey: CompanionPersistenceKeys.migratedToAppGroupMarker) { return }

        let standard = UserDefaults.standard
        for key in CompanionPersistenceKeys.allCompanionKeys {
            guard standard.object(forKey: key) != nil else { continue }
            group.set(standard.object(forKey: key), forKey: key)
        }
        group.set(true, forKey: CompanionPersistenceKeys.migratedToAppGroupMarker)
        group.synchronize()
    }
}
