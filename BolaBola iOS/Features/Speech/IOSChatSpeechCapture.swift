//
//  IOSChatSpeechCapture.swift
//  iPhone Chat tab speech-to-text input.
//

import AVFoundation
import Foundation
import Speech

enum IOSChatSpeechCaptureError: LocalizedError {
    case recognizerUnavailable
    case audioEngineStartFailed

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable:
            return "语音识别暂时不可用"
        case .audioEngineStartFailed:
            return "麦克风启动失败"
        }
    }
}

final class IOSChatSpeechCapture {
    static let shared = IOSChatSpeechCapture()

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var lastTranscript = ""
    private var onPartialResult: ((String) -> Void)?

    private init() {}

    func requestAuthorization(_ done: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { speechStatus in
            guard speechStatus == .authorized else {
                DispatchQueue.main.async { done(false) }
                return
            }

            let finishMic: (Bool) -> Void = { allowed in
                DispatchQueue.main.async { done(allowed) }
            }
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission(completionHandler: finishMic)
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission(finishMic)
            }
        }
    }

    func startListening(
        locale: Locale = Locale(identifier: "zh-CN"),
        onPartialResult: @escaping (String) -> Void
    ) throws {
        cancel()
        lastTranscript = ""
        self.onPartialResult = onPartialResult

        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw IOSChatSpeechCaptureError.recognizerUnavailable
        }

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.request = request

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
            cleanupAudioSession()
            throw IOSChatSpeechCaptureError.audioEngineStartFailed
        }

        task = recognizer.recognitionTask(with: request) { [weak self] result, _ in
            guard let self, let result else { return }
            let transcript = result.bestTranscription.formattedString
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !transcript.isEmpty else { return }
            self.lastTranscript = transcript
            DispatchQueue.main.async {
                self.onPartialResult?(transcript)
            }
        }
    }

    func stopAndFinalize() -> String {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        request = nil
        task?.cancel()
        task = nil
        cleanupAudioSession()
        onPartialResult = nil
        let text = lastTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        lastTranscript = ""
        return text
    }

    func cancel() {
        if engine.isRunning {
            engine.stop()
        }
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        request = nil
        task?.cancel()
        task = nil
        cleanupAudioSession()
        onPartialResult = nil
        lastTranscript = ""
    }

    private func cleanupAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
