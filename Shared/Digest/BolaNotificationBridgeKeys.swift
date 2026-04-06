//
//  BolaNotificationBridgeKeys.swift
//

import Foundation

public enum BolaNotificationBridgeKeys {
    /// User tapped the daily digest notification; main UI should play `letterOnce`.
    public static let digestTapOpen = "bola_digest_tap_open"
    /// A water reminder fired or was tapped; watch UI should enter the drink prompt flow.
    public static let waterReminderTrigger = "bola_water_reminder_trigger"
}

public extension Notification.Name {
    static let bolaWaterReminderTriggered = Notification.Name("bolaWaterReminderTriggered")
}
