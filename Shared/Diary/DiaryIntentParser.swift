//
//  DiaryIntentParser.swift
//

import Foundation
import os

private let bolaDiaryLog = Logger(subsystem: "com.gathxr.BolaBola", category: "Diary")

public struct BolaDiaryDraft: Codable, Equatable, Sendable {
    public var summary: String
    public var emoji: String?
}

public struct LifeRecordDraft: Codable, Equatable, Sendable {
    public var kind: LifeRecordKind
    public var title: String
    public var detail: String
    public var emoji: String?
}

public struct ConversationMemoryExtraction: Codable, Equatable, Sendable {
    public var shouldRecord: Bool
    public var diary: BolaDiaryDraft?
    public var lifeCard: LifeRecordDraft?
}

public enum DiaryIntentParser {
    public static func extract(
        client: LLMClient,
        userText: String,
        assistantReply: String,
        recentRecords: [LifeRecordCard]
    ) async -> ConversationMemoryExtraction? {
        let user = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard user.count >= 4 else { return nil }

        let prompt = extractionPrompt(
            userText: user,
            assistantReply: assistantReply,
            recentRecords: recentRecords
        )
        do {
            let raw = try await client.chatCompletion(messages: [
                LLMChatMessage(role: "system", content: extractionSystemPrompt),
                LLMChatMessage(role: "user", content: prompt)
            ])
            return parse(raw)
        } catch {
            bolaDiaryLog.error("memory extraction failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    public static func parse(_ raw: String) -> ConversationMemoryExtraction? {
        guard let object = firstJSONObject(in: raw),
              let data = object.data(using: .utf8),
              let parsed = try? JSONDecoder().decode(ConversationMemoryExtraction.self, from: data),
              parsed.shouldRecord else {
            return nil
        }
        return sanitized(parsed)
    }

    private static var extractionSystemPrompt: String {
        """
        你是 BolaBola 的生活记忆提取器。只输出一个 JSON 对象，不要 Markdown，不要解释。
        你要判断这轮对话是否包含值得记录的真实生活事件、体验、计划、饮食、运动、旅行、电影、购物或习惯。
        如果只是闲聊、问问题、设置闹钟、测试、打招呼、要求分析健康数据，shouldRecord=false。
        日记必须是 Bola 的陪伴视角：Bola 可以说“我觉得/我猜/我想陪着”，但用户的行为和计划必须称为“主人/你”，禁止把用户行为写成 Bola 自己的行为。
        正例：“主人说想去吃东北菜，我感觉一定会很好吃。”
        正例：“你今天去爬山了，虽然累，但我觉得你很开心。”
        反例：“我计划去吃东北菜。”（错：像用户本人写的）
        反例：“我今天去爬山了。”（错：把用户经历写成 Bola 经历）
        JSON schema:
        {"shouldRecord":true|false,"diary":{"summary":"Bola 陪伴视角的一句话，中文，40字以内，用户称为主人或你","emoji":"一个 emoji"},"lifeCard":{"kind":"event|habitTodo|food|travel|fitness|movie|shopping","title":"8字以内标题","detail":"中文，40字以内","emoji":"一个 emoji"}}
        """
    }

    private static func extractionPrompt(
        userText: String,
        assistantReply: String,
        recentRecords: [LifeRecordCard]
    ) -> String {
        let recent = recentRecords
            .filter { $0.kind != .weather }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(5)
            .map { "- \($0.title): \($0.detailNote ?? $0.subtitle ?? "")" }
            .joined(separator: "\n")
        return """
        最近生活卡片：
        \(recent.isEmpty ? "无" : recent)

        用户说：
        \(userText)

        Bola 回复：
        \(assistantReply)
        """
    }

    private static func sanitized(_ value: ConversationMemoryExtraction) -> ConversationMemoryExtraction? {
        guard let diary = value.diary else { return nil }
        let diarySummary = trimmed(diary.summary, limit: 80)
        guard diarySummary.count >= 4 else { return nil }

        var card = value.lifeCard
        if let draft = card {
            let title = trimmed(draft.title, limit: 24)
            let detail = trimmed(draft.detail, limit: 90)
            if title.isEmpty || detail.isEmpty {
                card = nil
            } else {
                card = LifeRecordDraft(
                    kind: draft.kind,
                    title: title,
                    detail: detail,
                    emoji: firstGrapheme(draft.emoji)
                )
            }
        }

        return ConversationMemoryExtraction(
            shouldRecord: true,
            diary: BolaDiaryDraft(summary: diarySummary, emoji: firstGrapheme(diary.emoji) ?? "📝"),
            lifeCard: card
        )
    }

    private static func firstJSONObject(in raw: String) -> String? {
        guard let start = raw.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var isEscaped = false
        var index = start
        while index < raw.endIndex {
            let ch = raw[index]
            if inString {
                if isEscaped {
                    isEscaped = false
                } else if ch == "\\" {
                    isEscaped = true
                } else if ch == "\"" {
                    inString = false
                }
            } else {
                if ch == "\"" {
                    inString = true
                } else if ch == "{" {
                    depth += 1
                } else if ch == "}" {
                    depth -= 1
                    if depth == 0 {
                        return String(raw[start ... index])
                    }
                }
            }
            index = raw.index(after: index)
        }
        return nil
    }

    private static func trimmed(_ value: String, limit: Int) -> String {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count > limit else { return text }
        return String(text.prefix(limit))
    }

    private static func firstGrapheme(_ raw: String?) -> String? {
        let text = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let first = text.first else { return nil }
        return String(first)
    }
}
