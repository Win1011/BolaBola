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

    public init(
        id: UUID = UUID(),
        kind: LifeRecordKind,
        title: String,
        subtitle: String? = nil,
        detailNote: String? = nil,
        iconEmoji: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.detailNote = detailNote
        self.iconEmoji = iconEmoji
    }
}

public enum LifeRecordStorageKeys {
    public static let recordsJSON = "bola_life_records_v1"
}
