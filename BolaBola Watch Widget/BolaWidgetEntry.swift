import WidgetKit
import Foundation

struct BolaWidgetEntry: TimelineEntry {
    let date: Date
    let companionValue: Int

    /// Deterministic first-frame image name for the current companion value.
    var imageName: String {
        switch companionValue {
        case ...2:    return "die0"
        case 3...9:   return "sadone0"
        case 10...19: return "hurt0"
        case 20...29: return "unhappy0"
        case 30...39: return "idleone0"
        case 40...85: return "idlefour0"
        default:      return "happyidle0"  // 86–100
        }
    }

    /// Emoji representing Bola's mood — renders correctly in all watch face rendering modes.
    var moodEmoji: String {
        switch companionValue {
        case ...2:    return "💀"
        case 3...9:   return "😢"
        case 10...19: return "😞"
        case 20...29: return "😕"
        case 30...39: return "😐"
        case 40...85: return "🙂"
        default:      return "🥰"  // 86–100
        }
    }
}
