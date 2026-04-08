//
//  CompanionDisplayNameStore.swift
//  宠物显示名（与成长页、生活页等共用）；持久化在 App Group / 标准 UserDefaults。
//

import Foundation

public enum CompanionDisplayNameStore {
    public static func resolved(using defaults: UserDefaults = BolaSharedDefaults.resolved()) -> String {
        let raw = defaults.string(forKey: CompanionPersistenceKeys.companionDisplayName)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? "Bola" : raw
    }
}
