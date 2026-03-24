//
//  IOSpeechRelayTranscriber.swift
//  接收手表传来的录音文件，在 iPhone 上用 Speech 转写（手表端无可靠本地识别）。
//

import Foundation
import Speech

enum IOSpeechRelayTranscriberError: LocalizedError {
    case recognizerUnavailable
    case notAuthorized

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable:
            return "语音识别不可用"
        case .notAuthorized:
            return "未授权语音识别"
        }
    }
}

final class IOSpeechRelayTranscriber {
    static let shared = IOSpeechRelayTranscriber()

    private init() {}

    func transcribe(url: URL, completion: @escaping (Result<String, Error>) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            guard status == .authorized else {
                DispatchQueue.main.async {
                    completion(.failure(IOSpeechRelayTranscriberError.notAuthorized))
                }
                return
            }
            guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN")),
                  recognizer.isAvailable else {
                DispatchQueue.main.async {
                    completion(.failure(IOSpeechRelayTranscriberError.recognizerUnavailable))
                }
                return
            }
            let request = SFSpeechURLRecognitionRequest(url: url)
            request.shouldReportPartialResults = false

            var finished = false
            recognizer.recognitionTask(with: request) { result, error in
                if finished { return }
                if let error {
                    finished = true
                    DispatchQueue.main.async {
                        completion(.failure(error))
                    }
                    return
                }
                guard let result, result.isFinal else { return }
                finished = true
                let text = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                DispatchQueue.main.async {
                    completion(.success(text))
                }
            }
        }
    }
}
