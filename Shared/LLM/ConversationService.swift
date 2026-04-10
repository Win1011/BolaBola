//
//  ConversationService.swift
//

import Foundation
import os

private let bolaConversationSyncLog = Logger(subsystem: "com.gathxr.BolaBola.sync", category: "Conversation")
private let bolaWatchVoiceLog = Logger(subsystem: "com.gathxr.BolaBola", category: "WatchVoice")

public enum ConversationService {
    public static func bolaSystemPrompt(companionValue: Int, growthLevel: Int? = nil) -> String {
        let tier = CompanionTier.value(for: companionValue)
        let growthState = BolaGrowthStore.load()
        let level = growthLevel ?? BolaLevelFormula.levelAndRemainder(
            fromTotalXP: growthState.totalXP).level
        let caps = BolaLevelGate.Capabilities(level: level)
        let personalitySelection = BolaPersonalitySelectionStore.validated(growthState: growthState)

        var levelInstruction = ""
        switch caps.speechMode {
        case .none:
            // Lv0：不应到达这里（调用方应拦截），但保险起见给最简回复
            levelInstruction = "你还很小，只会发出简短的声音，每次回复不超过 10 字，不用完整句子。"
        case .clumsy:
            if level <= 1 {
                levelInstruction = "你刚学会说话（Lv\(level)），句子要很短，会重复字，表达稚嫩可爱，每次回复不超过 24 字。"
            } else {
                levelInstruction = "你还在学说话（Lv\(level)），偶尔会结巴或把词说错，句子比之前稍长一点，每次回复不超过 40 字。"
            }
        case .normal:
            if caps.hasPersonality && personalitySelection == .tsundere {
                levelInstruction = """
                你当前启用了「傲娇」人格：嘴上别扭一点、偶尔先嘴硬再关心，但本质是在乎用户的。
                不要刻薄，不要攻击用户，不要阴阳怪气过头，也不要变成恋爱陪聊机器人；你仍然是可爱的宠物 Bola。
                每次回复不超过 80 字，语气要有傲娇感，但落点要温柔。
                """
            } else {
                levelInstruction = "简短可爱，每次回复不超过 80 字。"
            }
        }

        return """
        你是手表宠物 Bola，不用 Markdown。\(levelInstruction)
        用户陪伴值整数为 \(companionValue)，档位约 \(tier)（越高越亲密）。不要给出医疗诊断；心率等信息仅供参考。
        \(recentLifeContextInstruction())

        如果用户要求设闹钟、定时器或计时提醒，在回复末尾加上标签（用户看不到标签）：
        - 倒计时 N 分钟：<<ALARM:{"minutes":N}>>
        - 指定时间：<<ALARM:{"hour":H,"minute":M}>>（24 小时制）
        只加一个标签，不要解释标签格式。用可爱语气确认闹钟已设好。
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
        let rawReply = try await client.chatCompletion(messages: messages)

        // Check for alarm intent tag in the LLM response
        let reply: String
        if let parsed = AlarmIntentParser.parse(fromLLMReply: rawReply) {
            reply = parsed.cleanedReply
            let alarm = BolaReminder(
                title: "Bola 闹钟",
                notificationBody: "时间到啦～",
                schedule: .once(parsed.intent.fireDate),
                kind: .custom
            )
            var reminders = ReminderListStore.load(from: defaults)
            reminders.append(alarm)
            ReminderListStore.save(reminders, to: defaults)
            #if canImport(UserNotifications)
            await BolaReminderUNScheduler.sync(reminders: reminders)
            #endif
            #if os(iOS)
            BolaWCSessionCoordinator.shared.pushReminderRefreshToWatchIfPossible()
            #endif
            bolaConversationSyncLog.info("replyToUser: alarm scheduled at \(parsed.intent.fireDate, privacy: .public)")
        } else {
            reply = rawReply
        }

        let delta = ChatHistoryStore.appendUserThenAssistant(user: utterance, assistant: reply, defaults: defaults)
        let ids = delta.map(\.id.uuidString).joined(separator: ",")
        bolaConversationSyncLog.info("replyToUser OK → pushChatDelta ids=[\(ids, privacy: .public)] utteranceLen=\(utterance.count, privacy: .public)")
        BolaWCSessionCoordinator.shared.pushChatDelta(delta)

        persistConversationMemoriesInBackground(
            client: client,
            utterance: utterance,
            reply: reply,
            defaults: defaults
        )

        // XP：iOS 对话（每日限 2 次）+ 首次对话里程碑
        BolaXPEngine.grantIOSChatXP()
        BolaXPEngine.completeMilestone(.firstIOSChat)
        TitleUnlockManager.refreshUnlocks()

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

    private static func recentLifeContextInstruction() -> String {
        let recent = LifeRecordListStore.load()
            .filter { $0.kind != .weather }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(5)
            .map { card in
                let detail = card.detailNote ?? card.subtitle ?? ""
                return "- \(card.title)：\(detail)"
            }
            .joined(separator: "\n")

        guard !recent.isEmpty else { return "" }
        return """

        最近生活记忆（可自然参考，不要逐条复述）：
        \(recent)
        """
    }

    private static func persistConversationMemoriesInBackground(
        client: LLMClient,
        utterance: String,
        reply: String,
        defaults: UserDefaults
    ) {
        let recentRecords = LifeRecordListStore.load(from: defaults)
        Task(priority: .utility) {
            guard let extraction = await DiaryIntentParser.extract(
                client: client,
                userText: utterance,
                assistantReply: reply,
                recentRecords: recentRecords
            ) else {
                return
            }
            persist(extraction: extraction, sourceText: utterance, defaults: defaults)
        }
    }

    private static func persist(
        extraction: ConversationMemoryExtraction,
        sourceText: String,
        defaults: UserDefaults
    ) {
        if let diary = extraction.diary {
            BolaDiaryStore.append(
                BolaDiaryEntry(
                    summary: diary.summary,
                    emoji: diary.emoji ?? "📝",
                    sourceText: sourceText
                ),
                to: defaults
            )
        }

        guard let cardDraft = extraction.lifeCard else { return }
        let card = LifeRecordCard(
            kind: cardDraft.kind,
            title: cardDraft.title,
            subtitle: cardDraft.detail,
            detailNote: cardDraft.detail,
            iconEmoji: cardDraft.emoji
        )
        var records = LifeRecordListStore.load(from: defaults)
        if !records.contains(where: { existing in
            existing.kind == card.kind
                && existing.title == card.title
                && (existing.detailNote ?? existing.subtitle ?? "") == (card.detailNote ?? card.subtitle ?? "")
        }) {
            records.append(card)
            LifeRecordListStore.save(records, to: defaults)
        }
    }
}
