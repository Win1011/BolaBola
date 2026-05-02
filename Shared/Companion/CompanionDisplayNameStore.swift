//
//  CompanionDisplayNameStore.swift
//  宠物显示名（与成长页、生活页等共用）；持久化在 App Group / 标准 UserDefaults。
//

import Foundation

public extension Notification.Name {
    static let bolaCompanionDisplayNameDidChange = Notification.Name("bolaCompanionDisplayNameDidChange")
}

public enum CompanionDisplayNameStore {
    public static let fallbackName = "Bola"
    public static let maxVisibleCharacters = 8

    public static func resolved(using defaults: UserDefaults = BolaSharedDefaults.resolved()) -> String {
        let raw = defaults.string(forKey: CompanionPersistenceKeys.companionDisplayName) ?? ""
        let name = sanitized(raw)
        return name.isEmpty ? fallbackName : name
    }

    public static func sanitized(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return String(trimmed.prefix(maxVisibleCharacters))
    }

    @discardableResult
    public static func save(_ raw: String, using defaults: UserDefaults = BolaSharedDefaults.resolved()) -> String {
        let name = sanitized(raw)
        if name.isEmpty {
            defaults.removeObject(forKey: CompanionPersistenceKeys.companionDisplayName)
        } else {
            defaults.set(name, forKey: CompanionPersistenceKeys.companionDisplayName)
        }
        NotificationCenter.default.post(name: .bolaCompanionDisplayNameDidChange, object: nil)
        return name.isEmpty ? fallbackName : name
    }

    public static func clear(using defaults: UserDefaults = BolaSharedDefaults.resolved()) {
        defaults.removeObject(forKey: CompanionPersistenceKeys.companionDisplayName)
        NotificationCenter.default.post(name: .bolaCompanionDisplayNameDidChange, object: nil)
    }
}
