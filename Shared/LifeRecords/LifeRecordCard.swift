//
//  LifeRecordCard.swift
//

import Foundation

public enum LifeRecordKind: String, Codable, Equatable, Sendable {
    case weather
    case event
    case habitTodo
    case food
    case travel
    case fitness
    case movie
    case shopping
}

public struct LifeRecordCard: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var kind: LifeRecordKind
    public var title: String
    public var subtitle: String?
    public var detailNote: String?
    /// 卡片左上角图标；`nil` 时由 UI 按 `kind` 使用默认 emoji（系统字体渲染）。
    public var iconEmoji: String?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        kind: LifeRecordKind,
        title: String,
        subtitle: String? = nil,
        detailNote: String? = nil,
        iconEmoji: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.detailNote = detailNote
        self.iconEmoji = iconEmoji
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, title, subtitle, detailNote, iconEmoji, createdAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try container.decode(LifeRecordKind.self, forKey: .kind)
        title = try container.decode(String.self, forKey: .title)
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
        detailNote = try container.decodeIfPresent(String.self, forKey: .detailNote)
        iconEmoji = try container.decodeIfPresent(String.self, forKey: .iconEmoji)
        // Older persisted life cards may not have a timestamp yet. Falling back to
        // "now" makes historical cards incorrectly appear in today's section, so we
        // keep them out of date-scoped views unless they carry an explicit day.
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .distantPast
    }
}

public enum LifeRecordStorageKeys {
    public static let recordsJSON = "bola_life_records_v1"
}
