//
//  ChatTurn.swift
//

import Foundation
import os

private let bolaChatStoreLog = Logger(subsystem: "com.gathxr.BolaBola.sync", category: "ChatStore")

public extension Notification.Name {
    /// 通过 WatchConnectivity 合并远端聊天记录后发出，供 iOS / watchOS 列表刷新。
    static let bolaChatHistoryDidMerge = Notification.Name("bolaChatHistoryDidMerge")
    /// iPhone：`isWatchAppInstalled` 等变化时发出，供主界面刷新「能否同步到手表」提示。
    static let bolaWatchInstallabilityDidChange = Notification.Name("bolaWatchInstallabilityDidChange")
    /// iPhone：收到手表经 WC 推送的陪伴游戏状态快照并写入本机 defaults 后发出，用于刷新 UI。
    static let bolaCompanionStateDidMergeFromWatch = Notification.Name("bolaCompanionStateDidMergeFromWatch")
    static let bolaOpenSettingsRequested = Notification.Name("bolaOpenSettingsRequested")
    static let bolaLLMConfigurationDidChange = Notification.Name("bolaLLMConfigurationDidChange")
    /// 手表端：收到 iPhone 经 WC 发来的宠物交互指令（`tap`/`eat`/`drink`/`sleep`）。
    static let bolaPetCommandReceived = Notification.Name("bolaPetCommandReceived")
}

public enum PetCommandNotificationKey {
    public static let kind = "kind"
}

public enum PetCommandKind {
    public static let tap = "tap"
    public static let eat = "eat"
    public static let drink = "drink"
    public static let sleep = "sleep"
}

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

    /// 仅追加一条 assistant 角色的 turn（用于镜像手表侧自主台词，如每日信件）。
    @discardableResult
    public static func appendAssistantOnly(
        _ text: String,
        defaults: UserDefaults = BolaSharedDefaults.resolved()
    ) -> ChatTurn {
        let turn = ChatTurn(role: "assistant", content: text)
        var t = load(from: defaults)
        t.append(turn)
        save(t, to: defaults)
        bolaChatStoreLog.info("appendAssistantOnly id=\(turn.id.uuidString, privacy: .public) localTurns=\(t.count, privacy: .public)")
        return turn
    }

    @discardableResult
    public static func appendUserThenAssistant(
        user: String,
        assistant: String,
        defaults: UserDefaults = BolaSharedDefaults.resolved()
    ) -> [ChatTurn] {
        var t = load(from: defaults)
        let u = ChatTurn(role: "user", content: user)
        let a = ChatTurn(role: "assistant", content: assistant)
        t.append(u)
        t.append(a)
        save(t, to: defaults)
        bolaChatStoreLog.info("appendUserThenAssistant userId=\(u.id.uuidString, privacy: .public) asstId=\(a.id.uuidString, privacy: .public) localTurns=\(t.count, privacy: .public) appGroup=\(BolaSharedDefaults.groupSuite != nil, privacy: .public)")
        return [u, a]
    }

    /// 合并对端经 WC 推送的增量（按 `id` 去重，按时间排序，截断 `maxTurns`）。
    public static func mergeRemoteTurns(_ remote: [ChatTurn], defaults: UserDefaults = BolaSharedDefaults.resolved()) {
        guard !remote.isEmpty else { return }
        var local = load(from: defaults)
        let before = local.count
        var seen = Set(local.map(\.id))
        var inserted = 0
        for turn in remote where !seen.contains(turn.id) {
            local.append(turn)
            seen.insert(turn.id)
            inserted += 1
        }
        local.sort { $0.createdAt < $1.createdAt }
        save(local, to: defaults)
        let after = load(from: defaults).count
        let remoteIds = remote.map(\.id.uuidString).joined(separator: ",")
        bolaChatStoreLog.info("mergeRemoteTurns remote=\(remote.count, privacy: .public) inserted=\(inserted, privacy: .public) before=\(before, privacy: .public) after=\(after, privacy: .public) ids=[\(remoteIds, privacy: .public)] appGroup=\(BolaSharedDefaults.groupSuite != nil, privacy: .public)")
    }

    public static func clear(defaults: UserDefaults = BolaSharedDefaults.resolved()) {
        defaults.removeObject(forKey: ChatHistoryKeys.turnsJSON)
    }
}
