//
//  LifeRecordListStore.swift
//

import Foundation

public enum LifeRecordListStore {
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    public static func load(from defaults: UserDefaults = BolaSharedDefaults.resolved()) -> [LifeRecordCard] {
        guard let data = defaults.data(forKey: LifeRecordStorageKeys.recordsJSON),
              let list = try? decoder.decode([LifeRecordCard].self, from: data) else {
            return defaultDeck()
        }
        if list.isEmpty { return defaultDeck() }
        return ensureWeatherFirst(list)
    }

    public static func save(_ records: [LifeRecordCard], to defaults: UserDefaults = BolaSharedDefaults.resolved()) {
        let ordered = ensureWeatherFirst(records)
        guard let data = try? encoder.encode(ordered) else { return }
        defaults.set(data, forKey: LifeRecordStorageKeys.recordsJSON)
    }

    private static func defaultDeck() -> [LifeRecordCard] {
        [
            LifeRecordCard(
                kind: .weather,
                title: "天气",
                subtitle: nil,
                detailNote: nil
            )
        ]
    }

    private static func ensureWeatherFirst(_ list: [LifeRecordCard]) -> [LifeRecordCard] {
        let rest = list.filter { $0.kind != .weather }
        let weather = list.first(where: { $0.kind == .weather })
            ?? LifeRecordCard(kind: .weather, title: "天气")
        return [weather] + rest
    }
}
