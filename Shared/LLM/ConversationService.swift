//
//  ConversationService.swift
//

import Foundation
import os

private let bolaConversationSyncLog = Logger(subsystem: "com.GathXRTeam.BolaBola.sync", category: "Conversation")
private let bolaWatchVoiceLog = Logger(subsystem: "com.GathXRTeam.BolaBola", category: "WatchVoice")

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
        - N 分钟/小时后提醒一次：<<ALARM:{"mode":"once","minutes":N,"title":"提醒标题","body":"提醒内容"}>>
        - 今天/明天/后天某时提醒一次：<<ALARM:{"mode":"once","hour":H,"minute":M,"dayOffset":D,"title":"提醒标题","body":"提醒内容"}>>，`dayOffset` 为 0/1/2
        - 每天固定时间：<<ALARM:{"mode":"daily","hour":H,"minute":M,"title":"提醒标题","body":"提醒内容"}>>
        - 工作日固定时间：<<ALARM:{"mode":"workweek","hour":H,"minute":M,"title":"提醒标题","body":"提醒内容"}>>
        - 每周几固定时间：<<ALARM:{"mode":"weekly","hour":H,"minute":M,"weekdays":[2,4,6],"title":"提醒标题","body":"提醒内容"}>>
        - 每隔 N 小时/分钟重复：<<ALARM:{"mode":"interval","hours":N,"title":"提醒标题","body":"提醒内容"}>> 或 <<ALARM:{"mode":"interval","minutes":N,"title":"提醒标题","body":"提醒内容"}>>
        `title` 要简短，优先直接写要做的事，比如“洗头提醒”“拿快递提醒”。
        `body` 要像一句真正会发出的提醒，比如“主人该洗头啦～”。
        如果用户说“每天/每晚/工作日/每周一三五/每隔两小时”，要选对应的重复模式，不要误写成一次性提醒。
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
            let reminderContent = inferredReminderContent(
                from: utterance,
                parsedTitle: parsed.intent.title,
                parsedBody: parsed.intent.body
            )
            let alarm = BolaReminder(
                title: reminderContent.title,
                notificationBody: reminderContent.body,
                schedule: parsed.intent.schedule,
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
            bolaConversationSyncLog.info("replyToUser: alarm scheduled summary=\(alarm.scheduleSummary(), privacy: .public)")
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

    private static func inferredReminderContent(
        from utterance: String,
        parsedTitle: String?,
        parsedBody: String?
    ) -> (title: String, body: String) {
        let action = extractReminderAction(from: utterance)

        let title = {
            if let parsedTitle, !parsedTitle.isEmpty { return String(parsedTitle.prefix(18)) }
            if !action.isEmpty { return String("\(action)提醒".prefix(18)) }
            return "Bola提醒"
        }()

        let body = {
            if let parsedBody, !parsedBody.isEmpty { return String(parsedBody.prefix(40)) }
            if !action.isEmpty { return String("主人该\(action)啦～".prefix(40)) }
            return "主人，时间到啦～"
        }()

        return (title, body)
    }

    private static func extractReminderAction(from utterance: String) -> String {
        let text = utterance
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: "")

        let cues = ["提醒我", "告诉我", "记得", "帮我记得", "到时候提醒我", "叫我"]
        for cue in cues {
            if let range = text.range(of: cue, options: .backwards) {
                let tail = String(text[range.upperBound...])
                let cleaned = cleanReminderActionFragment(tail)
                if !cleaned.isEmpty { return cleaned }
            }
        }

        return cleanReminderActionFragment(text)
    }

    private static func cleanReminderActionFragment(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let leadingPatterns = [
            #"^(在|到|于)?"#,
            #"^([零一二两三四五六七八九十百半\d]+)(秒钟|秒|分钟|分|小时|点|天)(后|的时候|时)?"#,
            #"^(今天|明天|后天)(早上|上午|中午|下午|晚上)?([零一二两三四五六七八九十百\d]+点([零一二两三四五六七八九十百\d]+分)?)?"#
        ]
        for pattern in leadingPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(text.startIndex..<text.endIndex, in: text)
                text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        let trailingJunk = CharacterSet(charactersIn: "，。,！!？?～~ ")
        text = text.trimmingCharacters(in: trailingJunk)

        let fillers = ["一下", "这件事", "这个", "这件"]
        for filler in fillers where text.hasSuffix(filler) {
            text.removeLast(filler.count)
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return String(text.prefix(12))
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
                    title: diary.title,
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
