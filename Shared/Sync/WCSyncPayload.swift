//
//  WCSyncPayload.swift
//

import Foundation

/// Keys for `WCSession.updateApplicationContext` / `transferUserInfo`.
public enum WCSyncPayload {
    public static let companionValue = "companionValue"
    public static let companionValueUpdatedAt = "companionValueUpdatedAt"
    /// iPhone 点「同步手表」时为 true：手表端应应用数值，勿因本地 WC 时间戳较新而丢弃（context 可能晚到）。
    public static let companionSyncForcedFromPhone = "companionSyncForcedFromPhone"
    public static let requestSync = "requestSync"
    /// 与 `requestSync` 配对：手表 Keychain 无 API Key 时请求 iPhone 再推一次 LLM 配置。
    public static let requestSyncValueLLMKeychain = "llmKeychain"

    /// `transferUserInfo` 专用：同步 LLM 配置到手表 Keychain（勿记入日志）。
    public static let llmApiKey = "llmApiKey"
    public static let llmBaseURL = "llmBaseURL"
    public static let llmModelId = "llmModelId"
    public static let llmAuthBearer = "llmAuthBearer"

    /// 手表 → iPhone 语音文件中继（`transferFile` metadata / 回传 `sendMessage`）
    public static let speechRelayRequestId = "speechRelayRequestId"
    public static let speechRelayKind = "speechRelayKind"
    public static let speechRelayTranscript = "speechRelayTranscript"
    public static let speechRelayError = "speechRelayError"

    /// 聊天记录增量（`transferUserInfo`）：`[ChatTurn]` JSON 的 Base64
    public static let chatDeltaKind = "chatDeltaKind"
    public static let chatDeltaDataB64 = "chatDeltaDataB64"

    /// 手表 → iPhone：陪伴游戏状态（`UserDefaults` 可序列化子集）的二进制 plist Base64，`kind` = `companionSnapshotKindV1`。
    public static let companionSnapshotKind = "companionSnapshotKind"
    public static let companionSnapshotB64 = "companionSnapshotB64"
    public static let companionSnapshotKindV1 = "csV1"

    /// iPhone → Watch：`WatchFaceSlotsConfiguration` JSON 的 Base64（与陪伴值同批 `applicationContext`）。
    public static let watchFaceSlotsB64 = "watchFaceSlotsB64"
    /// iPhone → Watch：`BolaTitleSelection` JSON 的 Base64。
    public static let titleSelectionB64 = "titleSelectionB64"
    /// iPhone → Watch：当前人格选择（`default` / `tsundere`）。
    public static let personalitySelectionRaw = "personalitySelectionRaw"

    /// 成长系统同步（`applicationContext`）：`BolaGrowthState` JSON 的 Base64。
    public static let growthStateB64 = "growthStateB64"
    /// 称号解锁同步（`applicationContext`）：已解锁词 ID 数组 JSON 的 Base64。
    public static let titleUnlockedIdsB64 = "titleUnlockedIdsB64"
    /// iPhone → Watch：历史最高陪伴值（用于称号条件评估）。
    public static let maxEverCompanionValue = "maxEverCompanionValue"
    /// iPhone -> Watch：提醒列表 `[BolaReminder]` JSON 的 Base64。
    public static let remindersListB64 = "remindersListB64"

    /// 双向：宠物核心状态（`PetCoreState.rawValue`，如 `"idle"`、`"hungry"`）。
    public static let petCoreState = "petCoreState"

    /// iPhone → Watch：宠物交互指令（`"eat"`、`"drink"`、`"sleep"`；tap 已改为本机处理）。
    public static let petCommandKind = "petCommandKind"
    /// iPhone → Watch：指令的 UUID，用于表端去重。
    public static let petCommandId = "petCommandId"
}
