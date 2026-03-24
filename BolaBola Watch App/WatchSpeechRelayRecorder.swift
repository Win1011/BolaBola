//
//  WatchSpeechRelayRecorder.swift
//  手表麦克风录音：优先智谱云端 ASR（WAV）；亦可经 WCSession 发往 iPhone 转写。
//

import AVFoundation
import Foundation

final class WatchSpeechRelayRecorder {
    static let shared = WatchSpeechRelayRecorder()

    private var recorder: AVAudioRecorder?
    private var fileURL: URL?

    private init() {}

    func requestMicPermission(_ done: @escaping (Bool) -> Void) {
        AVAudioSession.sharedInstance().requestRecordPermission { ok in
            DispatchQueue.main.async {
                done(ok)
            }
        }
    }

    func startRecording() throws {
        // 智谱语音转写文档常见支持 wav/mp3；线性 PCM WAV 兼容性最好
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
        recorder?.record()
    }

    func stopRecording() -> URL? {
        recorder?.stop()
        recorder = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        let url = fileURL
        fileURL = nil
        return url
    }
}
