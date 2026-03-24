//
//  ConversationService.swift
//

import Foundation
import os

private let bolaConversationSyncLog = Logger(subsystem: "com.gathxr.BolaBola.sync", category: "Conversation")
private let bolaWatchVoiceLog = Logger(subsystem: "com.gathxr.BolaBola", category: "WatchVoice")

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
        let delta = ChatHistoryStore.appendUserThenAssistant(user: utterance, assistant: reply, defaults: defaults)
        let ids = delta.map(\.id.uuidString).joined(separator: ",")
        bolaConversationSyncLog.info("replyToUser OK → pushChatDelta ids=[\(ids, privacy: .public)] utteranceLen=\(utterance.count, privacy: .public)")
        BolaWCSessionCoordinator.shared.pushChatDelta(delta)
        return reply
    }

    /// 手表录音 → 智谱 ASR 转文字 → 再走 `replyToUser`（需 Base URL 为 `open.bigmodel.cn`）
    public static func replyToUserFromRecordedAudio(fileURL: URL, companionValue: Int) async throws -> String {
        bolaWatchVoiceLog.info("replyFromAudio begin file=\(fileURL.lastPathComponent, privacy: .public) companion=\(companionValue, privacy: .public)")
        let client: LLMClient
        do {
            client = try LLMClient.loadFromKeychain()
        } catch {
            bolaWatchVoiceLog.error("replyFromAudio loadFromKeychain failed \(String(describing: error), privacy: .public)")
            throw error
        }
        let utterance: String
        do {
            utterance = try await client.transcribeAudio(fileURL: fileURL)
        } catch {
            bolaWatchVoiceLog.error("replyFromAudio transcribe failed \(String(describing: error), privacy: .public)")
            throw error
        }
        guard !utterance.isEmpty else {
            bolaWatchVoiceLog.error("replyFromAudio transcribe returned empty string")
            throw LLMClientError.badResponse
        }
        bolaWatchVoiceLog.info("replyFromAudio ASR text chars=\(utterance.count, privacy: .public)")
        do {
            let reply = try await replyToUser(utterance: utterance, companionValue: companionValue)
            bolaWatchVoiceLog.info("replyFromAudio chat OK replyChars=\(reply.count, privacy: .public)")
            return reply
        } catch {
            bolaWatchVoiceLog.error("replyFromAudio chat failed \(String(describing: error), privacy: .public)")
            throw error
        }
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
