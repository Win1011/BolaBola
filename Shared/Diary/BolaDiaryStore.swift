//
//  BolaDiaryStore.swift
//

import Foundation

public extension Notification.Name {
    static let bolaDiaryEntriesDidChange = Notification.Name("bolaDiaryEntriesDidChange")
}

public enum BolaDiaryStore {
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()
    private static let maxEntries = 240

    public static func load(from defaults: UserDefaults = BolaSharedDefaults.resolved()) -> [BolaDiaryEntry] {
        guard let data = defaults.data(forKey: BolaDiaryStorageKeys.entriesJSON),
              let entries = try? decoder.decode([BolaDiaryEntry].self, from: data) else {
            return []
        }
        return entries.sorted { $0.createdAt > $1.createdAt }
    }

    public static func save(_ entries: [BolaDiaryEntry], to defaults: UserDefaults = BolaSharedDefaults.resolved()) {
        let ordered = entries
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(maxEntries)
        guard let data = try? encoder.encode(Array(ordered)) else { return }
        defaults.set(data, forKey: BolaDiaryStorageKeys.entriesJSON)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .bolaDiaryEntriesDidChange, object: nil)
        }
    }

    public static func append(_ entry: BolaDiaryEntry, to defaults: UserDefaults = BolaSharedDefaults.resolved()) {
        var entries = load(from: defaults)
        if containsLikelyDuplicate(entry, in: entries) {
            return
        }
        entries.append(entry)
        save(entries, to: defaults)
    }

    private static func containsLikelyDuplicate(_ entry: BolaDiaryEntry, in entries: [BolaDiaryEntry]) -> Bool {
        let normalized = normalize(entry.summary)
        guard !normalized.isEmpty else { return false }
        let recentWindow: TimeInterval = 10 * 60
        return entries.contains { existing in
            abs(existing.createdAt.timeIntervalSince(entry.createdAt)) < recentWindow
                && normalize(existing.summary) == normalized
        }
    }

    private static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\n", with: "")
    }
}
