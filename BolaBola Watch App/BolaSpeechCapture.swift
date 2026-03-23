//
//  BolaSpeechCapture.swift
//  按住说话：`Speech` + `AVAudioEngine`（仅 iOS / 支持 Speech 的平台）。
//  watchOS 不提供 `Speech` 模块时，使用占位实现（不崩溃、可提示用户）。
//

import Foundation

#if canImport(Speech)
import AVFoundation
import Speech

final class BolaSpeechCapture: NSObject {
    static let shared = BolaSpeechCapture()

    /// 当前编译目标是否链入了系统语音识别。
    static var isSpeechSupported: Bool { true }

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var lastTranscript: String = ""

    private override init() {
        super.init()
    }

    func requestSpeechAuthorization(_ done: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                done(status == .authorized)
            }
        }
    }

    func startListening(locale: Locale = Locale(identifier: "zh-CN")) {
        stopInternal()
        lastTranscript = ""
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else { return }

        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try? audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        request = SFSpeechAudioBufferRecognitionRequest()
        guard let request else { return }
        request.shouldReportPartialResults = true

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            return
        }

        task = recognizer.recognitionTask(with: request) { [weak self] result, _ in
            guard let self, let result else { return }
            self.lastTranscript = result.bestTranscription.formattedString
        }
    }

    func stopAndFinalize(completion: @escaping (String) -> Void) {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        request = nil
        task?.cancel()
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        let text = lastTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        lastTranscript = ""
        completion(text)
    }

    private func stopInternal() {
        if engine.isRunning {
            engine.stop()
        }
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        request = nil
        task?.cancel()
        task = nil
    }
}

#else

/// watchOS 等无 `Speech` 模块时的占位：不执行识别，立即结束。
final class BolaSpeechCapture: NSObject {
    static let shared = BolaSpeechCapture()

    static var isSpeechSupported: Bool { false }

    private override init() {
        super.init()
    }

    func requestSpeechAuthorization(_ done: @escaping (Bool) -> Void) {
        DispatchQueue.main.async { done(false) }
    }

    func startListening(locale: Locale = Locale(identifier: "zh-CN")) {}

    func stopAndFinalize(completion: @escaping (String) -> Void) {
        DispatchQueue.main.async {
            completion("")
        }
    }
}

#endif
