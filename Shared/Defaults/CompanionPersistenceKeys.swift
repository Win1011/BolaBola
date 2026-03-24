//
//  CompanionPersistenceKeys.swift
//

import Foundation

/// UserDefaults keys for companion / surprise state (must stay stable across versions).
public enum CompanionPersistenceKeys {
    public static let companionValue = "bola_companionValue"
    public static let lastCompanionWallClock = "bola_lastCompanionWallClock"
    public static let lastTickTimestamp = "bola_lastTickTimestamp"
    public static let totalActiveSeconds = "bola_totalActiveSeconds"
    public static let activeCarrySeconds = "bola_activeCarrySeconds"
    public static let lastSurpriseAtHours = "bola_lastSurpriseAtHours"
    /// WatchConnectivity 最后写入陪伴值时的 Unix 时间，用于与另一端合并「较新」一侧。
    public static let companionWCUpdatedAt = "bola_companion_wc_updated_at"

    public static let migratedToAppGroupMarker = "bola_migrated_to_app_group"

    public static var allCompanionKeys: [String] {
        [
            companionValue,
            lastCompanionWallClock,
            lastTickTimestamp,
            totalActiveSeconds,
            activeCarrySeconds,
            lastSurpriseAtHours
        ]
    }

    /// 无 App Group 时经 WatchConnectivity 由手表推到 iPhone 的键集合（与 `allCompanionKeys` + WC 时间戳一致）。
    public static var wcGameStateSnapshotKeys: [String] {
        allCompanionKeys + [companionWCUpdatedAt]
    }
}
