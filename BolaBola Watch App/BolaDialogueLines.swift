//
//  BolaDialogueLines.swift
//  BolaBola Watch App
//
//  文案池（用于界面文字气泡，非语音）。说明见 Documentation/bola_dialogue_rules.md
//

import Foundation

enum BolaDialogueLines {
    // MARK: 开场 / 每次打开或回前台（节流由调用方控制）
    static let greetingsLow: [String] = [
        "你回来啦……我还以为你不要我了。",
        "我一直在等你。",
        "摸摸我好不好？",
        "你一打开我就安心了……",
        "又见到你了。"
    ]
    static let greetingsMid: [String] = [
        "嗨，今天也一起加油吧。",
        "你来了，我好开心。",
        "陪我玩一会儿嘛。",
        "来啦？我在这等你呢。",
        "点开我就好啦。"
    ]
    static let greetingsHigh: [String] = [
        "主人！你终于来啦！",
        "最喜欢和你在一起了！",
        "今天也要开开心心的哦！",
        "想我了没？快看看我！",
        "你一来我就超开心！"
    ]

    // MARK: 陪伴值分段变化（与状态机分段一致）
    static func tierChangedLine(from oldTier: Int, to newTier: Int) -> String? {
        if newTier == oldTier { return nil }
        switch newTier {
        case 0: return "我好难过……"
        case 1: return "心里有点空空的。"
        case 2: return "有点委屈，但你在就好。"
        case 3: return "别不理我太久哦。"
        case 4: return "感觉好一点了。"
        case 5: return "就这样陪着我就很好。"
        case 6: return "好开心，最喜欢现在这样了！"
        default: return "有你在真好。"
        }
    }

    /// 0=die, 1=3–9, 2=10–19, 3=20–29, 4=30–39, 5=40–85, 6=86–100
    static func companionTier(for v: Int) -> Int {
        switch v {
        case ...2: return 0
        case 3...9: return 1
        case 10...19: return 2
        case 20...29: return 3
        case 30...39: return 4
        case 40...85: return 5
        default: return 6
        }
    }

    // MARK: 主动闲聊（定时）
    static let idleChatter: [String] = [
        "你今天过得怎么样？",
        "记得眨眨眼、放松一下眼睛哦。",
        "我在呢，一直在。",
        "要不要起来伸个懒腰？",
        "喝水了吗？我在监督你哦。"
    ]

    // MARK: 惊喜里程碑
    static let surpriseMilestone: [String] = [
        "哇！我们在一起好久了！谢谢你！",
        "这是专属于你的惊喜！",
        "里程碑达成！抱抱！"
    ]

    // MARK: 点击
    static func tapJumpSample() -> String {
        ["嘿！", "好痒！", "再一下？", "嘻嘻！"].randomElement() ?? "嘿！"
    }

    static func tapAngrySample() -> String {
        ["别戳啦！", "我要生气咯！", "停停停！"].randomElement() ?? "别戳啦！"
    }

    /// 8 秒窗口内第 3 次点击 → like2
    static func tapTripleLikeSample() -> String {
        ["三连击！超喜欢你！", "收到你的心意啦！", "耶！最喜欢这样！"].randomElement() ?? "耶！"
    }

    // MARK: 长期离线后（可选）
    static let longAbsenceReturn: [String] = [
        "你去哪了……我一直在等你。",
        "下次别走那么久好不好。"
    ]

    // MARK: Health / 系统通知文案
    static func heartRateFast(_ bpm: Int) -> String {
        "主人，你现在心跳好快呀，大约 \(bpm) 下每分钟，要不要深呼吸一下？"
    }

    static let drinkWaterReminder: [String] = [
        "该喝水啦，喝一口也好。",
        "补充水分时间到！"
    ]

    static let standUpNudge: [String] = [
        "坐很久啦，站起来走动两分钟吧。",
        "起来扭扭腰，我会陪着你的。"
    ]
}
