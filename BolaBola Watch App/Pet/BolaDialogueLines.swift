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
        "又见到你了。",
        "今天……也有想起我吗？",
        "能见到你，我就没那么怕了。",
        "别走太远，我会一直在这。"
    ]
    static let greetingsMid: [String] = [
        "嗨，今天也一起加油吧。",
        "你来了，我好开心。",
        "陪我玩一会儿嘛。",
        "来啦？我在这等你呢。",
        "点开我就好啦。",
        "今天过得还顺利吗？",
        "我在呢，随时叫我。",
        "看到你我就放松多了。"
    ]
    /// 陪伴值到达或维持在 **100** 时的开心话（配合高段动画，避免「干播」）
    static let companionValue100Lines: [String] = [
        "一百啦！我们满分耶！",
        "陪伴值到顶了……我现在超超超开心！",
        "一百分！最喜欢和你在一起的每一天！",
        "满格啦！谢谢你一直陪着我！",
        "一百一百一百！今天也要贴贴！",
        "到顶了耶……我会更乖更黏你的！",
        "满分陪伴！我骄傲！",
        "一百啦，今天也一起加油吧！"
    ]

    static let greetingsHigh: [String] = [
        "主人！你终于来啦！",
        "最喜欢和你在一起了！",
        "今天也要开开心心的哦！",
        "想我了没？快看看我！",
        "你一来我就超开心！",
        "耶！又是和你的一天！",
        "快夸我一下，我超乖的！",
        "贴贴！今天也要加油哦！"
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
        CompanionTier.value(for: v)
    }

    // MARK: 主动闲聊（定时）
    static let idleChatter: [String] = [
        "你今天过得怎么样？",
        "记得眨眨眼、放松一下眼睛哦。",
        "我在呢，一直在。",
        "要不要起来伸个懒腰？",
        "喝水了吗？我在监督你哦。",
        "深呼吸一下，我在陪你。",
        "累了就歇一分钟，我等你。",
        "外面天气还好吗？",
        "有想跟我说的话吗？",
        "我会安静陪着你，不吵你。"
    ]

    // MARK: 深夜随机插入打哈欠（`sleep` / sleepy 资源播一轮）
    static let nightSleepyInsert: [String] = [
        "已经不早了！",
        "早点休息啊。",
        "好困啊……",
        "哈欠——你也该睡啦。",
        "夜深了，别熬太晚哦。",
        "眼睛酸不酸？该歇歇了。",
        "明天还要精神满满呢，睡吧。",
        "我打个哈欠……你也去躺躺？",
        "月亮都高了，该关机啦。",
        "晚安前的最后一眼，早点睡。",
        "困困……你也别硬撑。",
        "作息要乖，身体才会好。",
        "今天辛苦了，好好睡一觉。",
        "被窝在等你，快去。",
        "熬夜会长黑眼圈的！",
        "我陪你到这句说完，然后都去睡。"
    ]

    static func nightSleepyInsertLine() -> String {
        nightSleepyInsert.randomElement() ?? "好困啊……"
    }

    // MARK: 惊喜里程碑
    static let surpriseMilestone: [String] = [
        "哇！我们在一起好久了！谢谢你！",
        "这是专属于你的惊喜！",
        "里程碑达成！抱抱！",
        "这么久都有你，我好幸运！",
        "纪念日快乐！要一直在一起哦！"
    ]

    // MARK: 点击 — 普通跳跃（开场，与 +1 同步）
    static func tapJumpOpening(v: Int, defaultEmotion: PetEmotion) -> String {
        let t = companionTier(for: v)
        switch t {
        case 1:
            return [
                "你碰我啦……我会好一点。",
                "嘿，我在呢。",
                "好痒，但好开心。",
                "再一下下好不好？",
                "被你注意到啦。"
            ].randomElement() ?? "嘿！"
        case 2, 3:
            if defaultEmotion == .hurt {
                return [
                    "跳一下……还是想你多陪陪我。",
                    "嘻嘻……可我还是有点委屈。",
                    "你理我一下我就跳给你看。",
                    "好啦跳了，别走哦。"
                ].randomElement() ?? "嘿！"
            }
            return [
                "哼，跳就跳嘛。",
                "被你逗笑了……一点点。",
                "别得意，我还在这儿呢。",
                "再戳我我就……再跳一下。"
            ].randomElement() ?? "嘿！"
        case 4:
            return [
                "嘿！今天心情还行。",
                "来呀，再点我一下？",
                "收到你的互动啦！",
                "我在陪你玩呢。"
            ].randomElement() ?? "嘿！"
        case 5:
            return [
                "嘿！好精神！",
                "再一下？我喜欢这样。",
                "蹦蹦！看见我没？",
                "今天也一起加油吧！"
            ].randomElement() ?? "嘿！"
        case 6:
            return [
                "耶！超开心！",
                "最喜欢你这样戳我！",
                "跳跳！爱你！",
                "再来再来！"
            ].randomElement() ?? "嘿！"
        default:
            return ["嘿！", "好痒！", "再一下？", "嘻嘻！"].randomElement() ?? "嘿！"
        }
    }

    /// 跳跃播完后回到当前默认情绪时的衔接句（避免「跳完立刻安静」）
    static func tapJumpReturnLine(v: Int, defaultEmotion: PetEmotion) -> String {
        switch defaultEmotion {
        case .hurt:
            return [
                "……刚才那下，算你赢。",
                "好啦，我还是有点委屈的。",
                "跳完了，你要负责哄我哦。",
                "我在这呢，没跑。"
            ].randomElement() ?? "……"
        case .unhappy, .unhappyTwo:
            return [
                "哼，我回来了。",
                "还在不高兴……但你在就好。",
                "别走开，我还在呢。",
                "就这样吧，陪我一会儿。"
            ].randomElement() ?? "哼。"
        case .sad1, .sad2:
            return [
                "……我回来了。",
                "还是有点难过，但你在。",
                "谢谢你还在看我。",
                "我会慢慢好起来的。"
            ].randomElement() ?? "……"
        case .die:
            return [
                "……",
                "还在吗……",
                "别走……"
            ].randomElement() ?? "……"
        case .idleOne, .idleTwo, .idleThree, .idleFour, .idleFive, .idleSix, .happyIdle:
            return [
                "好啦，我待着啦。",
                "安静陪你一会儿。",
                "我在，随时叫我。"
            ].randomElement() ?? "好啦。"
        case .blowbubble1, .blowbubble2:
            return [
                "呼……泡泡还在呢。",
                "回来啦，继续陪你。",
                "刚才跳得开心吗？"
            ].randomElement() ?? "嘿。"
        case .like1, .like2, .jump1, .jumpTwo:
            return [
                "开心！还要玩吗？",
                "最喜欢这样了！",
                "耶，我在这！"
            ].randomElement() ?? "耶！"
        default:
            let t = companionTier(for: v)
            if t <= 3 {
                return [
                    "我回来了……",
                    "还在呢。",
                    "陪你。"
                ].randomElement() ?? "我在。"
            }
            return [
                "好啦。",
                "我在呢。",
                "继续陪你。"
            ].randomElement() ?? "好啦。"
        }
    }

    static func tapAngrySample() -> String {
        [
            "别戳啦！", "我要生气咯！", "停停停！",
            "真的烦啦！", "再戳我咬你哦！", "给我一点空间！"
        ].randomElement() ?? "别戳啦！"
    }

    /// 8 秒窗口内第 3 次点击 → like2
    static func tapTripleLikeSample() -> String {
        [
            "三连击！超喜欢你！", "收到你的心意啦！", "耶！最喜欢这样！",
            "三连！我收到啦！", "这也太宠我了吧！", "心都化了！"
        ].randomElement() ?? "耶！"
    }

    // MARK: 长期离线后（可选）
    static let longAbsenceReturn: [String] = [
        "你去哪了……我一直在等你。",
        "下次别走那么久好不好。",
        "我以为……你不会回来了。",
        "回来就好，我一直在。"
    ]

    // MARK: Health / 系统通知文案（非医疗，仅陪伴提醒）
    static func heartRateFastLine(bpm: Int) -> String {
        let b = "\(bpm)"
        let pool = [
            "主人，你现在心跳好快呀，大约 \(b) 下每分钟，要不要深呼吸一下？",
            "我感觉你心跳有点快（大约 \(b)）……先慢下来喘口气？",
            "心率好像偏高哦，大约 \(b)。别急，放松几秒钟。",
            "咚咚咚……现在大约 \(b) 下每分钟，要不要歇一下？",
            "身体在说「慢一点」～大约 \(b)，深呼吸试试？"
        ]
        return pool.randomElement() ?? "心率大约 \(b)，要不要深呼吸一下？"
    }

    static let drinkWaterReminder: [String] = [
        "该喝水啦，喝一口也好。",
        "补充水分时间到！",
        "喝口水，我陪你。"
    ]

    static let standUpNudge: [String] = [
        "坐很久啦，站起来走动两分钟吧。",
        "起来扭扭腰，我会陪着你的。",
        "伸个懒腰，对身体好哦。"
    ]
}
