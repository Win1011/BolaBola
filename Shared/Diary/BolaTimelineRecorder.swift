//
//  BolaTimelineRecorder.swift
//

import Foundation

public enum BolaTimelineRecorder {
    private static let onboardingUserNicknameKey = "bola_onboarding_user_nickname_v1"
    private static let appleSignInFullNameKey = "bola_apple_sign_in_full_name_v1"

    public static func syncLifeCards(_ cards: [LifeRecordCard] = LifeRecordListStore.load(), to defaults: UserDefaults = BolaSharedDefaults.resolved()) {
        cards.forEach { card in
            guard !isLifeCardSynced(card, defaults: defaults) else { return }
            recordLifeCard(card, to: defaults)
        }
    }

    public static func recordLifeCard(_ card: LifeRecordCard, to defaults: UserDefaults = BolaSharedDefaults.resolved()) {
        guard card.kind != .weather else { return }
        defer { markLifeCardSynced(card, defaults: defaults) }
        let title = card.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = (card.detailNote ?? card.subtitle ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let userName = resolvedUserDisplayName()
        let summary: String
        if detail.isEmpty {
            summary = "\(userName)记录了\(title.isEmpty ? "一件生活小事" : title)。"
        } else {
            summary = "\(userName)记录了\(title.isEmpty ? "一件生活小事" : title)：\(detail)"
        }

        BolaDiaryStore.append(
            BolaDiaryEntry(
                createdAt: card.createdAt,
                title: title.isEmpty ? "生活记录" : String(title.prefix(8)),
                summary: String(summary.prefix(44)),
                emoji: card.iconEmoji ?? defaultEmoji(for: card.kind),
                sourceText: summary
            ),
            to: defaults
        )
    }

    public static func markLifeCardSynced(_ card: LifeRecordCard, defaults: UserDefaults = BolaSharedDefaults.resolved()) {
        var ids = Set(defaults.stringArray(forKey: LifeRecordStorageKeys.diarySyncedRecordIds) ?? [])
        ids.insert(card.id.uuidString)
        defaults.set(Array(ids), forKey: LifeRecordStorageKeys.diarySyncedRecordIds)
    }

    public static func recordPetActivity(_ activity: PetActivity, at date: Date = Date(), to defaults: UserDefaults = BolaSharedDefaults.resolved()) {
        let userName = resolvedUserDisplayName()
        let companionName = CompanionDisplayNameStore.resolved()
        let summary: String
        switch activity {
        case .feed:
            summary = "\(userName)给\(companionName)喂了食。"
        case .water:
            summary = "\(userName)给\(companionName)喂了水。"
        case .sleep:
            summary = "\(userName)哄\(companionName)乖乖睡觉。"
        }

        BolaDiaryStore.append(
            BolaDiaryEntry(
                createdAt: date,
                title: activity.title,
                summary: summary,
                emoji: activity.emoji,
                sourceText: summary
            ),
            to: defaults
        )
    }

    public static func resolvedUserDisplayName() -> String {
        let defaults = UserDefaults.standard
        let raw = defaults.string(forKey: onboardingUserNicknameKey)
            ?? defaults.string(forKey: appleSignInFullNameKey)
            ?? ""
        let name = CompanionDisplayNameStore.sanitized(raw)
        return name.isEmpty ? "你" : name
    }

    private static func defaultEmoji(for kind: LifeRecordKind) -> String {
        switch kind {
        case .event: return "⭐️"
        case .habitTodo: return "✅"
        case .weather: return "🌤️"
        case .food: return "🍜"
        case .travel: return "✈️"
        case .fitness: return "🏃"
        case .movie: return "🎬"
        case .shopping: return "🛍️"
        }
    }

    private static func isLifeCardSynced(_ card: LifeRecordCard, defaults: UserDefaults) -> Bool {
        let ids = defaults.stringArray(forKey: LifeRecordStorageKeys.diarySyncedRecordIds) ?? []
        return ids.contains(card.id.uuidString)
    }
}

public enum PetActivity: String, Codable, Equatable, Sendable {
    case feed
    case water
    case sleep

    public var title: String {
        switch self {
        case .feed: return "喂食"
        case .water: return "喂水"
        case .sleep: return "睡觉"
        }
    }

    public var emoji: String {
        switch self {
        case .feed: return "🍎"
        case .water: return "💧"
        case .sleep: return "🌙"
        }
    }
}
