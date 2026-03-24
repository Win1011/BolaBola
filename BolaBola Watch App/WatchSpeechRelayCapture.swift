//
//  WatchSpeechRelayCapture.swift
//  按住说话：录音 → transferFile → iPhone 转写 → 回传文本（替代手表本地 Speech）。
//

import Foundation
import WatchConnectivity

final class WatchSpeechRelayCapture {
    static let shared = WatchSpeechRelayCapture()

    private init() {}

    /// 手表端始终走 iPhone 中继，不依赖 `Speech` 框架是否链入。
    static var isSupported: Bool { true }

    func requestSpeechAuthorization(_ done: @escaping (Bool) -> Void) {
        WatchSpeechRelayRecorder.shared.requestMicPermission(done)
    }

    func startListening() {
        do {
            try WatchSpeechRelayRecorder.shared.startRecording()
        } catch {
            // 失败时 stop 会得到 nil URL
        }
    }

    /// 手表已录好的文件交给 iPhone 转写（云端 ASR 失败时的退路）
    @discardableResult
    func transferExistingFileForPhoneTranscription(url: URL, completion: @escaping (String) -> Void) -> Bool {
        let session = WCSession.default
        guard session.activationState == .activated, session.isCompanionAppInstalled else {
            return false
        }
        let requestId = UUID().uuidString
        BolaWCSessionCoordinator.shared.prepareSpeechRelay(requestId: requestId) { text in
            completion(text ?? "")
        }
        session.transferFile(
            url,
            metadata: [
                WCSyncPayload.speechRelayRequestId: requestId,
                WCSyncPayload.speechRelayKind: "speechRelay"
            ]
        )
        return true
    }

    func stopAndFinalize(completion: @escaping (String) -> Void) {
        guard let url = WatchSpeechRelayRecorder.shared.stopRecording() else {
            completion("")
            return
        }
        let session = WCSession.default
        guard session.activationState == .activated, session.isCompanionAppInstalled else {
            completion("")
            return
        }
        let requestId = UUID().uuidString
        BolaWCSessionCoordinator.shared.prepareSpeechRelay(requestId: requestId) { text in
            completion(text ?? "")
        }
        session.transferFile(
            url,
            metadata: [
                WCSyncPayload.speechRelayRequestId: requestId,
                WCSyncPayload.speechRelayKind: "speechRelay"
            ]
        )
    }
}
