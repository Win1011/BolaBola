//
//  HelpCenterContent.swift
//

import Foundation

// MARK: - Models

struct HelpSection: Identifiable {
    let id = UUID()
    let title: String
    let items: [HelpItem]
}

struct HelpItem: Identifiable {
    let id = UUID()
    let title: String
    let children: [HelpItem]?
    let content: HelpArticle?

    init(title: String, content: HelpArticle) {
        self.title = title
        self.children = nil
        self.content = content
    }

    init(title: String, children: [HelpItem]) {
        self.title = title
        self.children = children
        self.content = nil
    }
}

struct HelpArticle {
    let blocks: [HelpBlock]
}

enum HelpBlock {
    case h1(String)
    case h2(String)
    case body(String)
    case boldLeadBody(String, String)
    case divider
}

// MARK: - Content

enum HelpCenterContent {
    static let allSections: [HelpSection] = [
        recognizeBola,
        coreFeatures,
        faq,
        legal,
    ]

    // MARK: 认识 BolaBola

    private static let recognizeBola = HelpSection(
        title: "认识 BolaBola",
        items: [
            HelpItem(title: "BolaBola 是什么？", content: HelpArticle(blocks: [
                .h1("BolaBola 是什么？"),
                .body("BolaBola 是一款以 Apple Watch 为主屏幕的数字宠物陪伴应用。你的手腕上住着一只叫 Bola 的小精灵——它会根据你的健康状态、日常互动和生活节奏，呈现出不同的情绪与反应。"),
                .body("iPhone 端作为配套的「大本营」，提供健康数据分析、生活记录、成长日志，以及与 Bola 的 AI 深度对话。"),
                .h2("BolaBola 的核心理念"),
                .body("BolaBola 不是一款督促你「打卡」的 App。Bola 不会因为你没有完成目标就惩罚你，它只是真实地感知你的状态，陪着你度过每一天——无论是活力满满还是需要休息的时候。"),
            ])),
            HelpItem(title: "认识 Bola", content: HelpArticle(blocks: [
                .h1("认识 Bola"),
                .body("Bola 是你的数字宠物伙伴，常驻在你的 Apple Watch 表盘上。它有自己的情绪状态，会随你的健康数据和互动方式而变化。"),
                .h2("Bola 的情绪状态"),
                .boldLeadBody("愉快（Happy）：", "当你完成了运动、保持了良好睡眠，或者给了 Bola 很多关爱时，Bola 会显得很开心。"),
                .boldLeadBody("慵懒（Sleepy）：", "如果你最近活动量较少，或者 Bola 很久没有被互动，它会开始打盹。"),
                .boldLeadBody("生气（Angry）：", "连续快速地戳 Bola 会让它发火。Bola 也有自己的小脾气！"),
                .boldLeadBody("平静（Idle）：", "默认状态，Bola 安静地陪着你。"),
                .body("Bola 的情绪变化完全基于本地逻辑，无需联网即可正常运作。"),
            ])),
        ]
    )

    // MARK: 核心功能

    private static let coreFeatures = HelpSection(
        title: "核心功能",
        items: [
            HelpItem(title: "陪伴值是什么？", content: HelpArticle(blocks: [
                .h1("陪伴值是什么？"),
                .body("陪伴值（Companion Value）是衡量你与 Bola 当下「亲密度」的数值，范围是 0 到 100。它不是一个永久积累的分数，而是反映你最近状态的动态指标。"),
                .h2("陪伴值如何变化？"),
                .boldLeadBody("增加：", "与 Bola 互动（轻触、语音、对话），完成健康目标，保持良好睡眠。"),
                .boldLeadBody("减少：", "长时间不与 Bola 互动，持续惹 Bola 生气，随时间自然衰减。"),
                .body("陪伴值的高低会影响 Bola 的情绪倾向，以及在 AI 对话中 Bola 对你的态度。"),
                .h2("陪伴值与等级的区别"),
                .body("陪伴值是「当下的亲密感」，是动态波动的。等级（XP）是「成长的积累」，只会增加不会减少。两者各有意义，共同描述你与 Bola 的关系。"),
            ])),
            HelpItem(title: "等级系统", content: HelpArticle(blocks: [
                .h1("等级系统"),
                .body("通过与 Bola 互动和完成每日任务，你会积累经验值（XP）并不断升级。等级代表你们之间关系的深度。"),
                .h2("如何获得 XP？"),
                .boldLeadBody("每日任务：", "完成当天的活动、睡眠、互动目标，每项可获得 XP 奖励。"),
                .boldLeadBody("特殊里程碑：", "首次对话、陪伴值达到满分、坚持使用一个月……这些特殊成就会给予额外 XP。"),
                .h2("升级有什么奖励？"),
                .body("升级会解锁新的 Bola 称号词条、成就图鉴，以及未来将上线的更多内容。到达 Lv.5 后，你还可以解锁 Bola 的「傲娇」人格模式。"),
            ])),
            HelpItem(title: "手表互动方式", content: HelpArticle(blocks: [
                .h1("手表互动方式"),
                .body("Apple Watch 是与 Bola 互动的主要场所。以下是所有可用的互动方式："),
                .h2("触摸互动"),
                .boldLeadBody("轻触 Bola：", "给 Bola 一个小小的关爱，陪伴值 +1。但不要太频繁——连续快速戳 Bola 会让它生气！"),
                .boldLeadBody("长按或组合触碰：", "某些情绪状态下，Bola 会有特殊反应。"),
                .h2("语音互动"),
                .body("对着手表说话，Bola 会通过语音识别理解你说的话，并经由 AI 回复。语音消息会转发到 iPhone 处理，再同步回手表显示。"),
                .h2("注意事项"),
                .body("为了避免惹 Bola 生气，建议每次互动之间留有一定间隔。Bola 生气后需要一段时间才会平复。"),
            ])),
            HelpItem(title: "健康数据分析", content: HelpArticle(blocks: [
                .h1("健康数据分析"),
                .body("BolaBola 会读取你授权的 Apple Health 数据，在 iPhone 端的「成长」标签中呈现可视化分析。"),
                .h2("分析哪些数据？"),
                .boldLeadBody("步数：", "当日步行量与周趋势。"),
                .boldLeadBody("活跃能量（Move）：", "消耗的卡路里。"),
                .boldLeadBody("锻炼时间：", "有氧运动的分钟数。"),
                .boldLeadBody("站立时间：", "站立小时数。"),
                .boldLeadBody("睡眠：", "最近一次睡眠的时长。"),
                .body("这些数据仅在本地处理和展示，不会上传到任何服务器。"),
                .h2("数据权限问题"),
                .body("如果健康数据显示异常或为零，请前往「常见问题 › 健康数据无法读取」查看解决方案。"),
            ])),
            HelpItem(title: "AI 对话功能", content: HelpArticle(blocks: [
                .h1("AI 对话功能"),
                .body("BolaBola 支持接入兼容 OpenAI 协议的 AI 服务，让 Bola 真正能「说话」并理解你的问题。"),
                .h2("如何开启？"),
                .body("在「设置 › 连接 › 对话 API」中填入你的 API 密钥和接口地址即可。BolaBola 支持 OpenAI、智谱（Zhipu）以及任何兼容 OpenAI 格式的服务商。"),
                .h2("对话是否私密？"),
                .body("API 密钥仅保存在本机钥匙串中，不会经过 BolaBola 的服务器。你的对话直接从设备发送到你配置的 AI 服务商，BolaBola 不存储任何对话内容。"),
                .h2("手表上的语音对话"),
                .body("在手表上触发语音后，录音会通过 WatchConnectivity 转发到 iPhone 端进行语音识别（ASR），识别结果再调用 AI 生成回复，最终同步显示在手表上。整个过程约需 5–15 秒，请保持 iPhone 在附近且已解锁。"),
            ])),
            HelpItem(title: "生活记录", content: HelpArticle(blocks: [
                .h1("生活记录"),
                .body("「生活」标签是你记录日常点滴的空间。它包含可自定义的数据卡片、文字与心情记录，以及健康节律可视化图表。"),
                .h2("生活卡片"),
                .body("你可以在卡片面板中添加、移除和排序各类卡片，包括天气、心率节律、健康摘要等。长按卡片可进行编辑操作。"),
                .h2("日记与心情"),
                .body("点击「＋」按钮可以添加当下的感受：选择一个表情符号代表心情，配上简短的文字记录。这些记录只存在本地，完全私密。"),
            ])),
        ]
    )

    // MARK: 常见问题

    private static let faq = HelpSection(
        title: "常见问题",
        items: [
            HelpItem(title: "Bola 为什么突然生气了？", content: HelpArticle(blocks: [
                .h1("Bola 为什么突然生气了？"),
                .body("Bola 在连续快速触碰的情况下会进入愤怒状态。在短时间内连续戳 Bola 超过一定次数，它会认为你在「欺负」它。"),
                .body("Bola 生气后会有一段时间的「冷静期」，在这段时间内它不会理你。等它平复后，可以温柔地互动来重新建立好感。"),
                .body("Bola 生气不会影响陪伴值的长期趋势，但短期内持续激怒 Bola 会有少量扣分。"),
            ])),
            HelpItem(title: "陪伴值为什么在降低？", content: HelpArticle(blocks: [
                .h1("陪伴值为什么在降低？"),
                .body("陪伴值是动态波动的，有以下几种情况会导致它下降："),
                .boldLeadBody("自然衰减：", "如果长时间没有与 Bola 互动，陪伴值会随时间缓慢减少。"),
                .boldLeadBody("惹 Bola 生气：", "持续激怒 Bola 会导致少量陪伴值扣减。"),
                .body("这是正常现象。陪伴值反映的是「现在」的亲密感，需要持续的互动来维持。就像真实的友情一样，需要用心经营。"),
            ])),
            HelpItem(title: "手表与手机数据不同步？", content: HelpArticle(blocks: [
                .h1("手表与手机数据不同步？"),
                .body("BolaBola 使用 Apple 的 WatchConnectivity 框架进行手机与手表之间的数据同步。以下情况可能导致同步延迟："),
                .boldLeadBody("手机未解锁：", "WatchConnectivity 要求 iPhone 处于未锁定或后台活跃状态。"),
                .boldLeadBody("蓝牙或 Wi-Fi 问题：", "手机与手表之间的通信依赖蓝牙，请确保两者距离较近。"),
                .boldLeadBody("App 未在后台运行：", "在手机端打开 BolaBola 一次，可以帮助激活后台同步。"),
                .body("陪伴值的同步约每 5 分钟进行一次；AI 对话同步在收到回复后立即触发。如果长时间不同步，尝试在手机端打开 App 并等待几秒。"),
            ])),
            HelpItem(title: "如何配置 AI 对话功能？", content: HelpArticle(blocks: [
                .h1("如何配置 AI 对话功能？"),
                .body("BolaBola 不内置 AI 服务账号，你需要自行准备 API 访问凭证。"),
                .h2("配置步骤"),
                .boldLeadBody("1. 获取 API 密钥：", "注册 OpenAI、智谱（Zhipu）或其他兼容 OpenAI 格式的 AI 服务，获取 API Key。"),
                .boldLeadBody("2. 打开设置：", "在 BolaBola iPhone 端，进入「设置 › 连接 › 对话 API」。"),
                .boldLeadBody("3. 填写信息：", "输入 API 密钥。如果使用自建中转或非官方服务商，还需填写 Base URL（接口地址）。"),
                .boldLeadBody("4. 同步到手表：", "设置保存后，手表端会在下次连接时自动拉取密钥，无需手动操作。"),
                .body("密钥保存在本机钥匙串中，不会离开你的设备。"),
            ])),
            HelpItem(title: "健康数据全是 0 或无法读取？", content: HelpArticle(blocks: [
                .h1("健康数据全是 0 或无法读取？"),
                .body("如果 BolaBola 中的健康数据显示为 0 或「—」，通常是权限问题。"),
                .h2("解决步骤"),
                .boldLeadBody("1. 检查权限：", "前往 iPhone「设置 › 隐私与安全性 › 健康 › BolaBola」，确认步数、活跃能量、锻炼时间、站立时间、睡眠分析均已开启。"),
                .boldLeadBody("2. 重新读取：", "回到 BolaBola 的「设置 › 健康数据」部分，点击「我已经改好健康权限，立即重新读取」。"),
                .boldLeadBody("3. 检查数据源：", "在 Apple 健康 App 中确认你的设备（手表、手机）确实在记录对应数据。如果健康 App 里也没有数据，则是设备端的问题，而非 BolaBola 的问题。"),
                .body("如果问题依然存在，可以在「设置 › Debug · 日志」中开启日志，查看具体的错误信息。"),
            ])),
        ]
    )

    // MARK: 服务协议

    private static let legal = HelpSection(
        title: "服务协议",
        items: [
            HelpItem(title: "用户使用条款", content: HelpArticle(blocks: [
                .h1("用户使用条款"),
                .body("最后更新：2026 年 4 月"),
                .divider,
                .h2("1. 接受条款"),
                .body("使用 BolaBola（以下简称「本应用」）即表示你同意本使用条款。如不同意，请停止使用本应用。"),
                .h2("2. 服务描述"),
                .body("BolaBola 是一款数字宠物陪伴应用，通过 Apple Watch 和 iPhone 提供服务。本应用读取 Apple HealthKit 数据（需经用户授权）并可选接入第三方 AI 服务。"),
                .h2("3. 用户责任"),
                .body("你负责保管自己配置的 API 密钥。你使用 AI 功能所产生的费用由你与 AI 服务商之间直接结算，与 BolaBola 无关。"),
                .h2("4. 数据与隐私"),
                .body("BolaBola 的健康数据仅在本地处理和存储，不会上传到我们的服务器。AI 对话数据直接发送至你配置的服务商，BolaBola 不存储对话内容。详见《隐私政策》。"),
                .h2("5. 免责声明"),
                .body("本应用提供的健康相关信息仅供参考，不构成医疗建议。如有健康疑虑，请咨询专业医疗人员。"),
                .h2("6. 条款变更"),
                .body("我们可能不时更新本条款。继续使用本应用即视为接受更新后的条款。"),
            ])),
            HelpItem(title: "隐私政策", content: HelpArticle(blocks: [
                .h1("隐私政策"),
                .body("最后更新：2026 年 4 月"),
                .divider,
                .h2("我们收集哪些数据？"),
                .body("BolaBola 不收集、不存储、不上传任何个人数据到我们的服务器。"),
                .boldLeadBody("健康数据：", "仅在本地读取和展示，从不离开你的设备。"),
                .boldLeadBody("AI 对话内容：", "直接从你的设备发送到你配置的第三方 AI 服务商，BolaBola 不参与存储或中转。"),
                .boldLeadBody("API 密钥：", "保存在本机 iOS 钥匙串中，仅在必要时同步到配对的 Apple Watch。"),
                .boldLeadBody("生活记录与日记：", "仅保存在本地设备，支持 iCloud 备份（如你已开启 iCloud 备份功能）。"),
                .h2("第三方服务"),
                .body("BolaBola 使用 Firebase 进行匿名崩溃日志收集（仅 iPhone 端）。Firebase 收集的数据不包含任何个人身份信息或健康数据。"),
                .body("如你配置了第三方 AI 服务（如 OpenAI、智谱），你的对话内容将受对应服务商的隐私政策约束，请自行了解。"),
                .h2("儿童隐私"),
                .body("本应用不面向 13 岁以下用户。"),
                .h2("联系我们"),
                .body("如有隐私相关问题，请通过 App Store 中的「反馈 App」功能与我们联系。"),
            ])),
        ]
    )
}
