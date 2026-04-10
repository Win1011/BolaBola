//
//  BolaDiaryEntry.swift
//

import Foundation

public struct BolaDiaryEntry: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var summary: String
    public var emoji: String
    public var sourceText: String

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        summary: String,
        emoji: String = "📝",
        sourceText: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.summary = summary
        self.emoji = emoji
        self.sourceText = sourceText
    }
}

public enum BolaDiaryStorageKeys {
    public static let entriesJSON = "bola_diary_entries_v1"
}
