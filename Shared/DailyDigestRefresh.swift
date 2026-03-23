//
//  DailyDigestRefresh.swift
//

import Foundation

public enum DailyDigestRefresh {
    private static func todayYMD(calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: Date())
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    /// 若今日尚未生成总结则写入 `lastDigestBody` 并刷新定时通知。
    @MainActor
    public static func regenerateIfNeeded(companionValue: Int) async {
        let config = DailyDigestStore.load()
        guard config.isEnabled else {
            #if canImport(UserNotifications)
            await DailyDigestUNScheduler.sync(config: config)
            #endif
            return
        }

        let defaults = BolaSharedDefaults.resolved()
        let ymd = todayYMD()
        if defaults.string(forKey: DailyDigestStorageKeys.lastDigestDateYMD) == ymd,
           let existing = defaults.string(forKey: DailyDigestStorageKeys.lastDigestBody),
           !existing.isEmpty {
            #if canImport(UserNotifications)
            await DailyDigestUNScheduler.sync(config: config)
            #endif
            return
        }

        let body: String
        do {
            let client = try LLMClient.loadFromKeychain()
            let prompt = """
            用中文写一段 Bola 宠物给主人的每日小结，60 字以内，温暖、非医疗、不提诊断。\
            用户今日陪伴值约 \(companionValue)。
            """
            let messages = [
                LLMChatMessage(role: "system", content: "你是 Bola，简短口语化。"),
                LLMChatMessage(role: "user", content: prompt)
            ]
            body = try await client.chatCompletion(messages: messages)
        } catch {
            body = "今天陪伴值大约 \(companionValue)。谢谢你陪我，明天也记得来看看我呀。"
        }

        defaults.set(body, forKey: DailyDigestStorageKeys.lastDigestBody)
        defaults.set(ymd, forKey: DailyDigestStorageKeys.lastDigestDateYMD)
        DailyDigestStore.save(config, to: defaults)
        #if canImport(UserNotifications)
        await DailyDigestUNScheduler.sync(config: config)
        #endif
    }
}
