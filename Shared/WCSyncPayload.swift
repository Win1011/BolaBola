//
//  WCSyncPayload.swift
//

import Foundation

/// Keys for `WCSession.updateApplicationContext` / `transferUserInfo`.
public enum WCSyncPayload {
    public static let companionValue = "companionValue"
    public static let companionValueUpdatedAt = "companionValueUpdatedAt"
    public static let requestSync = "requestSync"

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
}
