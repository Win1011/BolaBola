//
//  BolaSharedDefaults.swift
//

import Foundation

public enum BolaSharedDefaults {
    /// App Group suite; nil if capability missing (falls back to standard).
    public static var groupSuite: UserDefaults? {
        UserDefaults(suiteName: AppGroupConfig.suiteName)
    }

    /// Prefer App Group; fall back to `standard` so the app still runs before entitlements are fixed.
    public static func resolved() -> UserDefaults {
        groupSuite ?? .standard
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
