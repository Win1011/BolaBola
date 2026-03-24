//
//  LLMClient.swift
//

import Foundation
import os

private let bolaWatchVoiceLog = Logger(subsystem: "com.gathxr.BolaBola", category: "WatchVoice")

public enum LLMClientError: Error {
    case missingConfiguration
    case badResponse
    case httpStatus(Int, String?)
    /// 当前 Base URL 不支持手表直连语音转写（仅智谱 open.bigmodel.cn 的 ASR 已对接）
    case unsupportedAudioTranscription
}

extension LLMClientError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            return "未配置 API Key。可在 iPhone 设置里保存，或在 Shared/LocalLLMDevSecrets.swift 里填写 apiKey。"
        case .badResponse:
            return "响应格式异常"
        case .unsupportedAudioTranscription:
            return "当前对话 API 地址不是智谱开放平台，手表无法用云端转写。请改用智谱 Base URL，或保持 iPhone 上 Bola 打开以使用本机转写。"
        case .httpStatus(let code, let body):
            var msg: String
            if let b = body, !b.isEmpty {
                msg = "HTTP \(code)：\(String(b.prefix(500)))"
            } else {
                msg = "HTTP \(code)"
            }
            // OpenAI 错误里会带 platform.openai.com；说明当前请求打到了 OpenAI，智谱 Key 会被判无效。
            if code == 401, let b = body, b.contains("platform.openai.com") {
                msg += "\n\n提示：若你使用智谱 GLM，请在设置里将 Base URL 设为 https://open.bigmodel.cn/api/paas/v4（并保存），模型填 glm-4.6v 等。未保存 Base URL 时会默认使用 OpenAI 地址，密钥不可混用。"
            }
            return msg
        }
    }
}

public struct LLMClient: Sendable {
    public var baseURL: URL
    public var apiKey: String
    public var model: String
    public var timeoutSeconds: TimeInterval = 45
    /// `true`：`Authorization: Bearer <key>`；`false`：`<key>` 整段作为 Authorization（部分中转 401 时可关）。
    public var useBearerAuth: Bool = true

    /// OpenAI 官方：`https://api.openai.com/v1`（本客户端会再拼 `/chat/completions`）。
    /// 智谱「大模型开放平台」：`https://open.bigmodel.cn/api/paas/v4`（见 [GLM-4.6V](https://docs.bigmodel.cn/cn/guide/models/vlm/glm-4.6v)）。
    public static let defaultBaseURLString = "https://api.openai.com/v1"

    public init(
        baseURL: URL,
        apiKey: String,
        model: String,
        timeoutSeconds: TimeInterval = 45,
        useBearerAuth: Bool = true
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.timeoutSeconds = timeoutSeconds
        self.useBearerAuth = useBearerAuth
    }

    /// 优先 Keychain（含 iPhone 同步）；若无有效 Key，再读 `LocalLLMDevSecrets.swift` 里的手填项。
    public static func loadFromKeychain() throws -> LLMClient {
        if let raw = KeychainHelper.get(service: LLMKeychain.service, account: LLMKeychain.accountAPIKey) {
            let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty {
                let storedBase = KeychainHelper.get(service: LLMKeychain.service, account: LLMKeychain.accountBaseURL)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let baseStr = storedBase.isEmpty ? Self.defaultBaseURLString : storedBase
                guard let url = URL(string: baseStr) else {
                    bolaWatchVoiceLog.error("loadFromKeychain: invalid base URL string (length=\(baseStr.count))")
                    throw LLMClientError.missingConfiguration
                }
                let storedModel = KeychainHelper.get(service: LLMKeychain.service, account: LLMKeychain.accountModelId)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let modelStr = storedModel.isEmpty ? "gpt-4o-mini" : storedModel
                let useBearer = KeychainHelper.get(service: LLMKeychain.service, account: LLMKeychain.accountAuthBearer) != "0"
                let zhipu = Self.hostIsZhipuOpenPlatform(url)
                bolaWatchVoiceLog.info("loadFromKeychain OK host=\(url.host ?? "?", privacy: .public) zhipuHost=\(zhipu, privacy: .public) chatModel=\(modelStr, privacy: .public) bearer=\(useBearer, privacy: .public)")
                return LLMClient(baseURL: url, apiKey: key, model: modelStr, useBearerAuth: useBearer)
            }
        }

        let devKey = LocalLLMDevSecrets.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !devKey.isEmpty {
            let baseRaw = LocalLLMDevSecrets.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            let baseStr = baseRaw.isEmpty ? Self.defaultBaseURLString : baseRaw
            guard let url = URL(string: baseStr) else {
                bolaWatchVoiceLog.error("loadFromKeychain: LocalLLMDevSecrets.baseURL invalid")
                throw LLMClientError.missingConfiguration
            }
            let modelRaw = LocalLLMDevSecrets.modelId.trimmingCharacters(in: .whitespacesAndNewlines)
            let modelStr = modelRaw.isEmpty ? "gpt-4o-mini" : modelRaw
            let client = LLMClient(
                baseURL: url,
                apiKey: devKey,
                model: modelStr,
                useBearerAuth: LocalLLMDevSecrets.useBearerAuth
            )
            let zhipu = Self.hostIsZhipuOpenPlatform(client.baseURL)
            bolaWatchVoiceLog.info("loadFromKeychain: using LocalLLMDevSecrets.swift host=\(client.baseURL.host ?? "?", privacy: .public) zhipuHost=\(zhipu, privacy: .public) chatModel=\(client.model, privacy: .public)")
            return client
        }

        bolaWatchVoiceLog.error("loadFromKeychain: Keychain empty and LocalLLMDevSecrets.apiKey empty")
        throw LLMClientError.missingConfiguration
    }

    /// 智谱开放平台：`POST .../audio/transcriptions`（multipart，与官方「语音转文本」一致）
    public nonisolated static let zhipuDefaultASRModelId = "glm-asr-2512"

    private static func hostIsZhipuOpenPlatform(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "open.bigmodel.cn" || host.hasSuffix(".open.bigmodel.cn")
    }

    /// 将本地音频转为文字（当前仅支持智谱 `open.bigmodel.cn` + `glm-asr-*`）。
    public func transcribeAudio(fileURL: URL, asrModel: String = LLMClient.zhipuDefaultASRModelId) async throws -> String {
        guard Self.hostIsZhipuOpenPlatform(baseURL) else {
            bolaWatchVoiceLog.error("transcribeAudio: unsupported host (need open.bigmodel.cn) host=\(self.baseURL.host ?? "nil", privacy: .public)")
            throw LLMClientError.unsupportedAudioTranscription
        }
        let fileData = try Data(contentsOf: fileURL)
        guard !fileData.isEmpty else {
            bolaWatchVoiceLog.error("transcribeAudio: empty file \(fileURL.lastPathComponent, privacy: .public)")
            throw LLMClientError.badResponse
        }

        let endpoint = baseURL.appendingPathComponent("audio/transcriptions")
        bolaWatchVoiceLog.info("transcribeAudio POST file=\(fileURL.lastPathComponent, privacy: .public) bytes=\(fileData.count, privacy: .public) asrModel=\(asrModel, privacy: .public) path=/audio/transcriptions")
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        applyAuthorization(to: &req)
        req.timeoutInterval = max(timeoutSeconds, 60)

        let boundary = "Boundary-\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func appendField(name: String, value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append(value.data(using: .utf8)!)
            body.append("\r\n".data(using: .utf8)!)
        }
        appendField(name: "model", value: asrModel)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        let filename = fileURL.lastPathComponent.isEmpty ? "audio.wav" : fileURL.lastPathComponent
        body.append(
            "Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\nContent-Type: audio/wav\r\n\r\n"
                .data(using: .utf8)!
        )
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        let data: Data
        let res: URLResponse
        do {
            (data, res) = try await URLSession.shared.data(for: req)
        } catch {
            bolaWatchVoiceLog.error("transcribeAudio URLSession error \(error.localizedDescription, privacy: .public)")
            throw error
        }
        guard let http = res as? HTTPURLResponse else {
            bolaWatchVoiceLog.error("transcribeAudio: no HTTPURLResponse")
            throw LLMClientError.badResponse
        }
        guard (200 ... 299).contains(http.statusCode) else {
            let snippet = String(data: data, encoding: .utf8).map { String($0.prefix(2000)).trimmingCharacters(in: .whitespacesAndNewlines) }
            bolaWatchVoiceLog.error("transcribeAudio HTTP \(http.statusCode, privacy: .public) bodyPrefix=\(snippet ?? "", privacy: .public)")
            throw LLMClientError.httpStatus(http.statusCode, snippet)
        }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let t = json["text"] as? String, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let out = t.trimmingCharacters(in: .whitespacesAndNewlines)
                bolaWatchVoiceLog.info("transcribeAudio OK via key=text chars=\(out.count, privacy: .public)")
                return out
            }
            if let t = json["result"] as? String, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let out = t.trimmingCharacters(in: .whitespacesAndNewlines)
                bolaWatchVoiceLog.info("transcribeAudio OK via key=result chars=\(out.count, privacy: .public)")
                return out
            }
            if let dataObj = json["data"] as? [String: Any],
               let t = dataObj["text"] as? String,
               !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let out = t.trimmingCharacters(in: .whitespacesAndNewlines)
                bolaWatchVoiceLog.info("transcribeAudio OK via data.text chars=\(out.count, privacy: .public)")
                return out
            }
            let keys = json.keys.sorted().joined(separator: ",")
            bolaWatchVoiceLog.error("transcribeAudio: 2xx JSON but no text field keys=[\(keys, privacy: .public)]")
        } else {
            bolaWatchVoiceLog.error("transcribeAudio: 2xx non-JSON body len=\(data.count, privacy: .public)")
        }
        throw LLMClientError.badResponse
    }

    public func chatCompletion(messages: [LLMChatMessage]) async throws -> String {
        let endpoint = baseURL.appendingPathComponent("chat/completions")
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuthorization(to: &req)
        req.timeoutInterval = timeoutSeconds

        let body = OpenAICompatibleChatRequest(model: model, messages: messages, temperature: 0.7)
        req.httpBody = try JSONEncoder().encode(body)

        let (data, res) = try await URLSession.shared.data(for: req)
        guard let http = res as? HTTPURLResponse else { throw LLMClientError.badResponse }
        guard (200 ... 299).contains(http.statusCode) else {
            let snippet = String(data: data, encoding: .utf8).map { String($0.prefix(2000)).trimmingCharacters(in: .whitespacesAndNewlines) }
            throw LLMClientError.httpStatus(http.statusCode, snippet)
        }
        let decoded = try JSONDecoder().decode(OpenAICompatibleChatResponse.self, from: data)
        let text = decoded.choices?.first?.message?.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { throw LLMClientError.badResponse }
        return text
    }

    private func applyAuthorization(to req: inout URLRequest) {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if useBearerAuth {
            var token = trimmed
            if token.lowercased().hasPrefix("bearer ") {
                token = String(token.dropFirst(7)).trimmingCharacters(in: .whitespaces)
            }
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            req.setValue(trimmed, forHTTPHeaderField: "Authorization")
        }
    }
}
