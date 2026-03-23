//
//  LLMModels.swift
//

import Foundation

public struct LLMChatMessage: Codable, Sendable {
    public let role: String
    public let content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

/// OpenAI-compatible chat completion request body (adjust path per provider).
public struct OpenAICompatibleChatRequest: Encodable, Sendable {
    public let model: String
    public let messages: [LLMChatMessage]
    public let temperature: Double?

    public init(model: String, messages: [LLMChatMessage], temperature: Double? = 0.7) {
        self.model = model
        self.messages = messages
        self.temperature = temperature
    }
}

public struct OpenAICompatibleChatResponse: Decodable, Sendable {
    public struct Choice: Decodable, Sendable {
        public struct Message: Decodable, Sendable {
            public let role: String?
            public let content: String?
        }
        public let message: Message?
    }
    public let choices: [Choice]?
}

public enum LLMKeychain {
    public static let service = "com.gathxr.BolaBola.llm"
    public static let accountAPIKey = "apiKey"
    public static let accountBaseURL = "baseURL"
    public static let accountModelId = "modelId"
}
