//
//  LifeRecordCard.swift
//

import Foundation

public enum LifeRecordKind: String, Codable, Equatable, Sendable {
    case weather
    case event
    case habitTodo
}

public struct LifeRecordCard: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var kind: LifeRecordKind
    public var title: String
    public var subtitle: String?
    public var detailNote: String?

    public init(
        id: UUID = UUID(),
        kind: LifeRecordKind,
        title: String,
        subtitle: String? = nil,
        detailNote: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.detailNote = detailNote
    }
}

public enum LifeRecordStorageKeys {
    public static let recordsJSON = "bola_life_records_v1"
}
