//
//  DailyDigestConfig.swift
//

import Foundation

public struct DailyDigestConfig: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    /// Local hour 0...23
    public var hour: Int
    /// Minute 0...59
    public var minute: Int
    /// When true, user allows non-identifying health summaries in digest prompts (never raw diagnosis).
    public var includeHealthSummaryInPrompt: Bool

    public static let `default` = DailyDigestConfig(
        isEnabled: false,
        hour: 21,
        minute: 0,
        includeHealthSummaryInPrompt: false
    )

    public init(isEnabled: Bool, hour: Int, minute: Int, includeHealthSummaryInPrompt: Bool) {
        self.isEnabled = isEnabled
        self.hour = hour
        self.minute = minute
        self.includeHealthSummaryInPrompt = includeHealthSummaryInPrompt
    }
}

public enum DailyDigestStorageKeys {
    public static let configJSON = "bola_digest_config_v1"
    public static let lastDigestBody = "bola_last_digest_body"
    public static let lastDigestDateYMD = "bola_last_digest_date_ymd"
}

public enum DailyDigestStore {
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    public static func load(from defaults: UserDefaults = BolaSharedDefaults.resolved()) -> DailyDigestConfig {
        guard let data = defaults.data(forKey: DailyDigestStorageKeys.configJSON),
              let c = try? decoder.decode(DailyDigestConfig.self, from: data) else {
            return .default
        }
        return c
    }

    public static func save(_ config: DailyDigestConfig, to defaults: UserDefaults = BolaSharedDefaults.resolved()) {
        guard let data = try? encoder.encode(config) else { return }
        defaults.set(data, forKey: DailyDigestStorageKeys.configJSON)
    }
}
