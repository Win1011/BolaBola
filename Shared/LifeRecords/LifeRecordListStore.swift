//
//  LifeRecordListStore.swift
//

import Foundation

public extension Notification.Name {
    /// 生活记录卡组被恢复为默认（仅天气）后发出；`IOSLifeContainerView` 等可据此刷新内存中的列表。
    static let bolaLifeRecordsDidReset = Notification.Name("bolaLifeRecordsDidReset")
    static let bolaLifeRecordsDidChange = Notification.Name("bolaLifeRecordsDidChange")
}

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
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .bolaLifeRecordsDidChange, object: nil)
        }
    }

    /// 将卡组恢复为默认（仅保留「天气」卡），并主线程发出 `bolaLifeRecordsDidReset`。
    public static func resetToDefaultDeck(to defaults: UserDefaults = BolaSharedDefaults.resolved()) {
        save(defaultDeck(), to: defaults)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .bolaLifeRecordsDidReset, object: nil)
        }
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
