//
//  LifeDashboardLayoutStore.swift
//  生活页仪表板卡片布局与尺寸持久化。
//

import Foundation

public enum LifeDashboardTileKind: String, Codable, CaseIterable, Identifiable {
    case reminders
    case sleep
    case activity

    public var id: String { rawValue }
}

public enum LifeDashboardTileVariant: String, Codable {
    case featured
    case compact
}

public struct LifeDashboardTileLayout: Codable, Equatable, Identifiable {
    public let kind: LifeDashboardTileKind
    public var variant: LifeDashboardTileVariant

    public var id: String { kind.rawValue }

    public init(kind: LifeDashboardTileKind, variant: LifeDashboardTileVariant) {
        self.kind = kind
        self.variant = variant
    }
}

public enum LifeDashboardLayoutStore {
    public static let storageKey = "bola_life_dashboard_layout_v1"

    public static func load(from defaults: UserDefaults = BolaSharedDefaults.resolved()) -> [LifeDashboardTileLayout] {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([LifeDashboardTileLayout].self, from: data) else {
            return defaultLayout()
        }
        return normalized(decoded)
    }

    public static func save(_ layout: [LifeDashboardTileLayout], to defaults: UserDefaults = BolaSharedDefaults.resolved()) {
        let normalizedLayout = normalized(layout)
        guard let data = try? JSONEncoder().encode(normalizedLayout) else { return }
        defaults.set(data, forKey: storageKey)
    }

    public static func defaultLayout() -> [LifeDashboardTileLayout] {
        [
            LifeDashboardTileLayout(kind: .reminders, variant: .featured),
            LifeDashboardTileLayout(kind: .sleep, variant: .featured),
            LifeDashboardTileLayout(kind: .activity, variant: .featured),
        ]
    }

    public static func normalized(_ layout: [LifeDashboardTileLayout]) -> [LifeDashboardTileLayout] {
        var seen = Set<LifeDashboardTileKind>()
        var result: [LifeDashboardTileLayout] = []

        for item in layout where !seen.contains(item.kind) {
            result.append(item)
            seen.insert(item.kind)
        }

        return result
    }
}
