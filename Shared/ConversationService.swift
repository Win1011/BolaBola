//
//  ConversationService.swift
//

import Foundation

public enum ConversationService {
    public static func bolaSystemPrompt(companionValue: Int) -> String {
        let tier = CompanionTier.value(for: companionValue)
        return """
        你是手表宠物 Bola，简短可爱，每次回复不超过 80 字，不用 Markdown。
        用户陪伴值整数为 \(companionValue)，档位约 \(tier)（越高越亲密）。不要给出医疗诊断；心率等信息仅供参考。
        """
    }

    public static func replyToUser(utterance: String, companionValue: Int) async throws -> String {
        let client = try LLMClient.loadFromKeychain()
        let defaults = BolaSharedDefaults.resolved()
        var messages: [LLMChatMessage] = [
            LLMChatMessage(role: "system", content: bolaSystemPrompt(companionValue: companionValue))
        ]
        for turn in ChatHistoryStore.load(from: defaults).suffix(16) {
            messages.append(LLMChatMessage(role: turn.role, content: turn.content))
        }
        messages.append(LLMChatMessage(role: "user", content: utterance))
        let reply = try await client.chatCompletion(messages: messages)
        ChatHistoryStore.appendUserThenAssistant(user: utterance, assistant: reply, defaults: defaults)
        return reply
    }

    public static func templateReply(utterance: String, companionValue: Int) -> String {
        let v = companionValue
        if v < 30 {
            return "我在听呢……你说「\(utterance.prefix(24))」。我会慢慢好起来，多陪陪我好吗？"
        }
        if v < 86 {
            return "听到啦：\(utterance.prefix(32))……今天也一起加油，我在。"
        }
        return "嘿嘿，\(utterance.prefix(28)) —— 最喜欢和你聊天啦！"
    }
}
