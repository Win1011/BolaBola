//
//  SpecialAnimationUnlockSystem.swift
//  Shared
//
//  特殊动画图鉴：定义、持久化与跨端合并。
//

import Foundation

public enum SpecialAnimationRewardID: String, Codable, CaseIterable, Sendable {
    case angry2
    case companion100Surprise
}

public struct SpecialAnimationRewardDefinition: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let unlockHint: String
    public let previewAssetName: String
    public let fallbackEmoji: String

    public init(
        id: SpecialAnimationRewardID,
        title: String,
        detail: String,
        unlockHint: String,
        framePrefix: String,
        frameCount: Int,
        fallbackEmoji: String
    ) {
        self.id = id.rawValue
        self.title = title
        self.detail = detail
        self.unlockHint = unlockHint
        self.previewAssetName = Self.previewAssetName(framePrefix: framePrefix, frameCount: frameCount)
        self.fallbackEmoji = fallbackEmoji
    }

    private static func previewAssetName(framePrefix: String, frameCount: Int) -> String {
        let clampedFrameCount = max(frameCount, 1)
        let previewIndex = max(clampedFrameCount - 5, 0)
        return "\(framePrefix)\(previewIndex)"
    }
}

public enum SpecialAnimationRewardBank {
    public static let all: [SpecialAnimationRewardDefinition] = [
        SpecialAnimationRewardDefinition(
            id: .angry2,
            title: "生气炸毛",
            detail: "连续招惹 Bola 后触发的暴怒动画。",
            unlockHint: "首次触发生气动画后解锁",
            framePrefix: "angrytwo",
            frameCount: 30,
            fallbackEmoji: "😤"
        ),
        SpecialAnimationRewardDefinition(
            id: .companion100Surprise,
            title: "满百惊喜",
            detail: "达到满分陪伴后的惊喜庆祝动画。",
            unlockHint: "首次触发满百惊喜后解锁",
            framePrefix: "surprisedone",
            frameCount: 90,
            fallbackEmoji: "🥳"
        )
    ]

    public static func definition(for id: String) -> SpecialAnimationRewardDefinition? {
        all.first { $0.id == id }
    }
}

public enum SpecialAnimationUnlockStore {
    private static let defaultsKey = "bola_special_animation_unlocked_ids_v1"
    private static var defaults: UserDefaults { BolaSharedDefaults.resolved() }

    public static func loadUnlockedOrderedIds() -> [String] {
        guard let data = defaults.data(forKey: defaultsKey),
              let ids = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return ids.filter { SpecialAnimationRewardBank.definition(for: $0) != nil }
    }

    public static func loadUnlockedIds() -> Set<String> {
        Set(loadUnlockedOrderedIds())
    }

    public static func saveOrdered(_ ids: [String]) {
        let deduped = ids.reduce(into: [String]()) { partial, id in
            guard SpecialAnimationRewardBank.definition(for: id) != nil else { return }
            guard !partial.contains(id) else { return }
            partial.append(id)
        }
        if let data = try? JSONEncoder().encode(deduped) {
            defaults.set(data, forKey: defaultsKey)
        }
        NotificationCenter.default.post(name: .bolaSpecialAnimationUnlocksDidChange, object: nil)
    }

    @discardableResult
    public static func unlock(_ id: SpecialAnimationRewardID) -> Bool {
        unlock(id.rawValue)
    }

    @discardableResult
    public static func unlock(_ id: String) -> Bool {
        guard SpecialAnimationRewardBank.definition(for: id) != nil else { return false }
        var unlocked = loadUnlockedOrderedIds()
        guard !unlocked.contains(id) else { return false }
        unlocked.append(id)
        saveOrdered(unlocked)
        return true
    }

    @discardableResult
    public static func mergeFromRemote(_ remoteIds: Set<String>) -> Bool {
        mergeFromRemote(Array(remoteIds))
    }

    @discardableResult
    public static func mergeFromRemote(_ remoteIds: [String]) -> Bool {
        let validRemoteIds = remoteIds.filter { SpecialAnimationRewardBank.definition(for: $0) != nil }
        guard !validRemoteIds.isEmpty else { return false }
        var local = loadUnlockedOrderedIds()
        let before = local
        for id in validRemoteIds where !local.contains(id) {
            local.append(id)
        }
        guard local != before else { return false }
        saveOrdered(local)
        return true
    }
}

public enum SpecialAnimationSeenStore {
    private static let defaultsKey = "bola_special_animation_seen_ids_v1"
    private static var defaults: UserDefaults { BolaSharedDefaults.resolved() }

    public static func loadSeenIds() -> Set<String> {
        guard let data = defaults.data(forKey: defaultsKey),
              let ids = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(ids.filter { SpecialAnimationRewardBank.definition(for: $0) != nil })
    }

    public static func save(_ ids: Set<String>) {
        if let data = try? JSONEncoder().encode(Array(ids).sorted()) {
            defaults.set(data, forKey: defaultsKey)
        }
        NotificationCenter.default.post(name: .bolaSpecialAnimationSeenStateDidChange, object: nil)
    }

    public static func markSeen(_ ids: Set<String>) {
        guard !ids.isEmpty else { return }
        var seen = loadSeenIds()
        let before = seen
        seen.formUnion(ids)
        guard seen != before else { return }
        save(seen)
    }

    public static func clear() {
        defaults.removeObject(forKey: defaultsKey)
        NotificationCenter.default.post(name: .bolaSpecialAnimationSeenStateDidChange, object: nil)
    }
}

public extension Notification.Name {
    static let bolaSpecialAnimationUnlocksDidChange = Notification.Name("bolaSpecialAnimationUnlocksDidChange")
    static let bolaSpecialAnimationSeenStateDidChange = Notification.Name("bolaSpecialAnimationSeenStateDidChange")
}
