//
//  BolaServerConfig.swift
//  BolaBola 服务器地址配置
//

import Foundation

public enum BolaServerConfig {
    // MARK: - Keychain 存储 key

    private static let service = "com.GathXRTeam.BolaBola.server"
    private static let accountBaseURL = "baseURL"

    // MARK: - 默认值

    /// 开发环境默认地址
    public static let defaultBaseURLString = "http://localhost:8000"

    /// 服务器 AI 代理路径（OpenAI 兼容，LLMClient 拼上 /chat/completions 即可）
    public static let aiProxyPath = "/api/v1/ai/v1"

    // MARK: - 读取 / 写入

    public static var baseURLString: String {
        let stored = KeychainHelper.get(service: service, account: accountBaseURL)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return stored.isEmpty ? defaultBaseURLString : stored
    }

    public static var baseURL: URL {
        guard let url = URL(string: baseURLString) else {
            return URL(string: defaultBaseURLString)!
        }
        return url
    }

    /// 用于 LLMClient 的 AI 代理 Base URL（LLMClient 会再拼 /chat/completions）
    public static var aiProxyBaseURL: URL {
        baseURL.appendingPathComponent(String(aiProxyPath.drop(while: { $0 == "/" })))
    }

    public static func setBaseURL(_ string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            KeychainHelper.remove(service: service, account: accountBaseURL)
        } else {
            KeychainHelper.set(trimmed, service: service, account: accountBaseURL)
        }
    }
}
