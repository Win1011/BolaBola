//
//  WatchSpeechRelay.swift
//  手表语音：本地 WAV 录音（智谱 ASR）+ 可选经 WCSession 发往 iPhone 转写。
//

import AVFoundation
import Foundation
import os
import WatchConnectivity

private let watchMicLog = Logger(subsystem: "com.GathXRTeam.BolaBola", category: "WatchVoice")

// MARK: - 录音

final class WatchSpeechRelayRecorder {
    static let shared = WatchSpeechRelayRecorder()

    private var recorder: AVAudioRecorder?
    private var fileURL: URL?

    private init() {}

    func requestMicPermission(_ done: @escaping (Bool) -> Void) {
        AVAudioApplication.requestRecordPermission { ok in
            watchMicLog.info("mic permission result=\(ok, privacy: .public)")
            DispatchQueue.main.async {
                done(ok)
            }
        }
    }

    func startRecording() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("bola_voice_\(UUID().uuidString).wav")
        fileURL = url
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: [])
        recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder?.prepareToRecord()
        let started = recorder?.record() ?? false
        watchMicLog.info("recording start file=\(url.lastPathComponent, privacy: .public) record()=\(started, privacy: .public)")
    }

    func stopRecording() -> URL? {
        recorder?.stop()
        recorder = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        let url = fileURL
        fileURL = nil
        if let url {
            let n = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int($0) } ?? -1
            watchMicLog.info("recording stop file=\(url.lastPathComponent, privacy: .public) bytes=\(n, privacy: .public)")
        } else {
            watchMicLog.error("recording stop: no file URL")
        }
        return url
    }
}

// MARK: - iPhone 中继转写

final class WatchSpeechRelayCapture {
    static let shared = WatchSpeechRelayCapture()

    private init() {}

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
