//
//  CompanionTier.swift
//

import Foundation

/// 与 `BolaDialogueLines.companionTier` 规则一致，供 Shared 内 LLM 等使用。
public enum CompanionTier {
    public static func value(for v: Int) -> Int {
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
}
