//
//  ChatTurn.swift
//

import Foundation

public struct ChatTurn: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let role: String
    public let content: String
    public let createdAt: Date

    public init(id: UUID = UUID(), role: String, content: String, createdAt: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

public enum ChatHistoryKeys {
    public static let turnsJSON = "bola_chat_turns_v1"
}

public enum ChatHistoryStore {
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()
    public static let maxTurns = 24

    public static func load(from defaults: UserDefaults = BolaSharedDefaults.resolved()) -> [ChatTurn] {
        guard let data = defaults.data(forKey: ChatHistoryKeys.turnsJSON),
              let list = try? decoder.decode([ChatTurn].self, from: data) else {
            return []
        }
        return list
    }

    public static func save(_ turns: [ChatTurn], to defaults: UserDefaults = BolaSharedDefaults.resolved()) {
        let trimmed = Array(turns.suffix(maxTurns))
        guard let data = try? encoder.encode(trimmed) else { return }
        defaults.set(data, forKey: ChatHistoryKeys.turnsJSON)
    }

    public static func appendUserThenAssistant(
        user: String,
        assistant: String,
        defaults: UserDefaults = BolaSharedDefaults.resolved()
    ) {
        var t = load(from: defaults)
        t.append(ChatTurn(role: "user", content: user))
        t.append(ChatTurn(role: "assistant", content: assistant))
        save(t, to: defaults)
    }
}
