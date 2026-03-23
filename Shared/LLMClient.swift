//
//  LLMClient.swift
//

import Foundation

public enum LLMClientError: Error {
    case missingConfiguration
    case badResponse
    case httpStatus(Int)
}

public struct LLMClient: Sendable {
    public var baseURL: URL
    public var apiKey: String
    public var model: String
    public var timeoutSeconds: TimeInterval = 45

    public static let defaultBaseURLString = "https://api.openai.com/v1"

    public static func loadFromKeychain() throws -> LLMClient {
        guard let key = KeychainHelper.get(service: LLMKeychain.service, account: LLMKeychain.accountAPIKey),
              !key.isEmpty else {
            throw LLMClientError.missingConfiguration
        }
        let base = KeychainHelper.get(service: LLMKeychain.service, account: LLMKeychain.accountBaseURL)
            ?? Self.defaultBaseURLString
        guard let url = URL(string: base) else { throw LLMClientError.missingConfiguration }
        let model = KeychainHelper.get(service: LLMKeychain.service, account: LLMKeychain.accountModelId) ?? "gpt-4o-mini"
        return LLMClient(baseURL: url, apiKey: key, model: model)
    }

    public func chatCompletion(messages: [LLMChatMessage]) async throws -> String {
        let path = baseURL.absoluteString.hasSuffix("/") ? "chat/completions" : "/chat/completions"
        guard let endpoint = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw LLMClientError.missingConfiguration
        }
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = timeoutSeconds

        let body = OpenAICompatibleChatRequest(model: model, messages: messages, temperature: 0.7)
        req.httpBody = try JSONEncoder().encode(body)

        let (data, res) = try await URLSession.shared.data(for: req)
        guard let http = res as? HTTPURLResponse else { throw LLMClientError.badResponse }
        guard (200 ... 299).contains(http.statusCode) else {
            throw LLMClientError.httpStatus(http.statusCode)
        }
        let decoded = try JSONDecoder().decode(OpenAICompatibleChatResponse.self, from: data)
        let text = decoded.choices?.first?.message?.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { throw LLMClientError.badResponse }
        return text
    }
}
