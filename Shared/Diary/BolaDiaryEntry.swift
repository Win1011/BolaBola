//
//  BolaDiaryEntry.swift
//

import Foundation

public struct BolaDiaryEntry: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var title: String
    public var summary: String
    public var emoji: String
    public var sourceText: String

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        title: String,
        summary: String,
        emoji: String = "📝",
        sourceText: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.title = title
        self.summary = summary
        self.emoji = emoji
        self.sourceText = sourceText
    }

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case title
        case summary
        case emoji
        case sourceText
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        summary = try container.decode(String.self, forKey: .summary)
        emoji = try container.decode(String.self, forKey: .emoji)
        sourceText = try container.decode(String.self, forKey: .sourceText)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? Self.fallbackTitle(from: summary)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(title, forKey: .title)
        try container.encode(summary, forKey: .summary)
        try container.encode(emoji, forKey: .emoji)
        try container.encode(sourceText, forKey: .sourceText)
    }

    private static func fallbackTitle(from summary: String) -> String {
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "时光片段" }
        return String(trimmed.prefix(8))
    }
}

public enum BolaDiaryStorageKeys {
    public static let entriesJSON = "bola_diary_entries_v1"
}
