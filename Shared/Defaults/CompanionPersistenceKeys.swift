//
//  CompanionPersistenceKeys.swift
//

import Foundation

/// UserDefaults keys for companion / surprise state (must stay stable across versions).
public enum CompanionPersistenceKeys {
    public static let companionValue = "bola_companionValue"
    public static let lastCompanionWallClock = "bola_lastCompanionWallClock"
    public static let lastCompanionInteractionWallClock = "bola_lastCompanionInteractionWallClock"
    public static let lastTickTimestamp = "bola_lastTickTimestamp"
    public static let totalActiveSeconds = "bola_totalActiveSeconds"
    public static let activeCarrySeconds = "bola_activeCarrySeconds"
    public static let lastSurpriseAtHours = "bola_lastSurpriseAtHours"
    /// WatchConnectivity 最后写入陪伴值时的 Unix 时间，用于与另一端合并「较新」一侧。
    public static let companionWCUpdatedAt = "bola_companion_wc_updated_at"

    public static let migratedToAppGroupMarker = "bola_migrated_to_app_group"

    /// 用户在 iPhone 上为宠物起的显示名（空则 UI 回退为「Bola」）。
    public static let companionDisplayName = "bola_companion_display_name_v1"
    /// 最近 7 天 HRV 聚合摘要 JSON；只保存日级统计，不保存 HealthKit 原始样本。
    public static let hrvWeeklySummaryJSON = "bola_hrv_weekly_summary_json_v1"
    /// 每日互动任务计数周期（与成长页 08:00 日界线一致）。
    public static let dailyInteractionPeriodStart = "bola_daily_interaction_period_start_v1"
    /// 今日触摸 Bola 次数。
    public static let dailyTouchBolaCount = "bola_daily_touch_bola_count_v1"
    /// 今日成功喂食次数。
    public static let dailyFeedBolaCount = "bola_daily_feed_bola_count_v1"
    /// 今日成功喂水次数。
    public static let dailyDrinkBolaCount = "bola_daily_drink_bola_count_v1"

    public static var allCompanionKeys: [String] {
        [
            companionValue,
            lastCompanionWallClock,
            lastCompanionInteractionWallClock,
            lastTickTimestamp,
            totalActiveSeconds,
            activeCarrySeconds,
            lastSurpriseAtHours,
            dailyInteractionPeriodStart,
            dailyTouchBolaCount,
            dailyFeedBolaCount,
            dailyDrinkBolaCount
        ]
    }

    /// 无 App Group 时经 WatchConnectivity 由手表推到 iPhone 的键集合（与 `allCompanionKeys` + WC 时间戳一致）。
    public static var wcGameStateSnapshotKeys: [String] {
        allCompanionKeys + [companionWCUpdatedAt]
    }
}
