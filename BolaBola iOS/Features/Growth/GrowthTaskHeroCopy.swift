//
//  GrowthTaskHeroCopy.swift
//  集中管理成长页「每日任务」气泡文案。
//

import Foundation

enum GrowthTaskHeroCopy {
    static func heroBubbleText(
        dailyCards: [GrowthDailyTaskCardInstance],
        surfacedCompletedCount: Int,
        surfacedPendingCards: [GrowthDailyTaskCardInstance],
        allRandomTasksRevealed: Bool,
        companionDisplayName: String
    ) -> String {
        let total = dailyCards.count
        let completed = surfacedCompletedCount
        let pendingVisibleCards = surfacedPendingCards

        if completed >= total, total > 0 {
            return pickLine(
                from: [
                    "今天的任务全都完成啦！我们一起成长了一点点。",
                    "今天的任务都被拿下了，成长值也在悄悄往上走。",
                    "任务清单已经清空啦，今天的我要给你一个大大的夸夸。"
                ],
                salt: "complete",
                dailyCards: dailyCards,
                progressKey: progressKey(for: dailyCards)
            )
        }

        if !allRandomTasksRevealed {
            if completed > 0 {
                return pickLine(
                    from: [
                        "已经完成 \(completed) 个任务啦，剩下的任务也翻开看看吧。",
                        "我们已经有进度啦，再翻翻剩下的卡，说不定会抽到你刚好想做的任务。",
                        "继续翻牌吧，今天的成长奖励还在前面等着我们。"
                    ],
                    salt: "hidden-progress-\(completed)",
                    dailyCards: dailyCards,
                    progressKey: progressKey(for: dailyCards)
                )
            }
            return pickLine(
                from: [
                    "快来翻翻看今天的三个随机任务！",
                    "今天的任务已经准备好了，快把下面的随机卡翻开看看吧。",
                    "新的成长任务在等我们哦！翻开三张随机卡看看。"
                ],
                salt: "hidden-start",
                dailyCards: dailyCards,
                progressKey: progressKey(for: dailyCards)
            )
        }

        if pendingVisibleCards.isEmpty {
            return pickLine(
                from: [
                    "今天已经没有待完成的任务啦，做得真棒～",
                    "任务栏干干净净，我们今天收工得很漂亮。",
                    "今天的成长目标都达成啦，可以安心去玩一会儿。"
                ],
                salt: "all-visible-complete",
                dailyCards: dailyCards,
                progressKey: progressKey(for: dailyCards)
            )
        }

        if pendingVisibleCards.count == 1, let lastCard = pendingVisibleCards.first {
            return pickLine(
                from: lastTaskLines(for: lastCard),
                salt: "last-\(lastCard.id)",
                dailyCards: dailyCards,
                progressKey: progressKey(for: dailyCards)
            )
        }

        if let focusCard = pendingVisibleCards.first {
            return pickLine(
                from: progressLines(
                    for: focusCard,
                    remainingCount: pendingVisibleCards.count,
                    companionDisplayName: companionDisplayName
                ),
                salt: "progress-\(focusCard.id)-\(pendingVisibleCards.count)",
                dailyCards: dailyCards,
                progressKey: progressKey(for: dailyCards)
            )
        }

        return "继续做做今天的任务吧，我们会一起慢慢成长的。"
    }

    static func progressLines(
        for card: GrowthDailyTaskCardInstance,
        remainingCount: Int,
        companionDisplayName: String
    ) -> [String] {
        let countText = "还剩 \(remainingCount) 个任务没完成"
        switch card.id {
        case "share_mood":
            return [
                "\(countText)，也记得和我说说你今天的心情哦。",
                "先聊聊今天的心情吧，\(companionDisplayName) 很想听你说说。",
                "把心情告诉我，我们一起把剩下的任务慢慢做完～"
            ]
        case "chat_meal":
            return [
                "\(countText)，顺便告诉我你今天吃了什么吧。",
                "还想听你聊聊今天的饭饭，吃了什么好东西呀？",
                "说说今天吃了什么，我们的任务进度也会再往前走一点。"
            ]
        case "walk_5000":
            return [
                "\(countText)，要不要带我一起再散散步？",
                "今天再走一走吧，5000 步的任务还在等我们。",
                "出去动一动也很好呀，散步任务完成后我们会更靠近升级。"
            ]
        case "exercise_15m":
            return [
                "\(countText)，抽 15 分钟动一动也算很棒的进展。",
                "要不要和我一起完成今天的运动任务？",
                "今天再活动一下吧，运动任务做完会很有成就感。"
            ]
        case "complete_reminder_once":
            return [
                "\(countText)，如果你有事怕忘记，也可以让我帮你设个提醒。",
                "需要记住的事情就交给我吧，记得完成一个提醒任务。",
                "让我提醒你一件事吧，这个任务很适合顺手完成。"
            ]
        case "life_record_two_cards":
            return [
                "\(countText)，也可以把今天的小事记成两张生活卡片。",
                "今天发生的事别忘了记下来呀，两张生活卡就能完成任务。",
                "顺手记录一下今天的生活碎片吧，之后回看会很有意思。"
            ]
        case "praise_bola":
            return [
                "\(countText)，要是愿意的话，也给我一句夸夸吧。",
                "我也想听夸夸啦，说一句好听的给我听听嘛。",
                "夸夸我也是任务的一部分哦，我会偷偷开心很久。"
            ]
        default:
            return [
                "\(countText)，继续一起努力吧。",
                "再完成几个小目标，我们今天就会更漂亮的成长了。",
                "快完成任务啦，我们一起把今天的进度往前推一推。"
            ]
        }
    }

    static func lastTaskLines(for card: GrowthDailyTaskCardInstance) -> [String] {
        switch card.id {
        case "share_mood":
            return [
                "就差最后一个任务啦，来和我说说你今天的心情吧。",
                "最后一步啦，把今天的心情告诉我，我们就收工。",
                "只剩心情任务啦，我在认真等你开口。"
            ]
        case "chat_meal":
            return [
                "只差最后一个任务啦，告诉我你今天吃了什么吧。",
                "最后一项就是饭饭话题啦，快和我分享一下今天的菜单。",
                "冲最后一个任务吧，说说今天吃了什么，我们就完成啦。"
            ]
        case "walk_5000":
            return [
                "只差最后一个散步任务啦，再走一走我们今天就圆满了。",
                "最后一步啦，把 5000 步拿下，今天的任务就全清空了。",
                "还差这一张散步卡，完成它我们就可以一起庆祝啦。"
            ]
        case "complete_reminder_once":
            return [
                "最后一个任务啦，让我帮你设个提醒，我们今天就毕业。",
                "只剩提醒任务了，有什么事想交给我记住吗？",
                "收尾就差一个提醒啦，顺手设一下就能全部完成。"
            ]
        default:
            return [
                "只差最后一个任务啦，我们一起冲一下终点。",
                "还剩最后一步，做完今天就会是满满当当的一天。",
                "马上全完成啦，再坚持一下下。"
            ]
        }
    }

    private static func progressKey(for dailyCards: [GrowthDailyTaskCardInstance]) -> String {
        dailyCards
            .map { "\($0.id):\(Int(GrowthDailyTasksViewModel.shared.progress(for: $0.id) * 100))" }
            .joined(separator: "|")
    }

    private static func pickLine(
        from options: [String],
        salt: String,
        dailyCards: [GrowthDailyTaskCardInstance],
        progressKey: String
    ) -> String {
        guard !options.isEmpty else { return "" }
        let taskKey = dailyCards.map(\.id).joined(separator: "|")
        let seed = "\(GrowthDayBoundary.currentPeriodStart().timeIntervalSince1970)-\(salt)-\(taskKey)-\(progressKey)"
        let index = stableIndex(for: seed, modulo: options.count)
        return options[index]
    }

    private static func stableIndex(for seed: String, modulo: Int) -> Int {
        guard modulo > 0 else { return 0 }
        let value = seed.unicodeScalars.reduce(0) { partial, scalar in
            (partial &* 31 &+ Int(scalar.value)) & 0x7fffffff
        }
        return value % modulo
    }
}
