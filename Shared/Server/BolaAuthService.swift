//
//  BolaAuthService.swift
//  处理 Apple Sign In → 服务器认证、令牌刷新、登出
//

import Foundation
import os

private let bolaAuthLog = Logger(subsystem: "com.GathXRTeam.BolaBolaApp", category: "Auth")

public enum BolaAuthError: Error, LocalizedError {
    case missingIdentityToken
    case serverUnreachable(Error)
    case invalidResponse
    case httpError(Int, String?)
    case refreshFailed(String?)

    public var errorDescription: String? {
        switch self {
        case .missingIdentityToken:
            return "Apple 登录未返回身份令牌，请重试。"
        case .serverUnreachable(let error):
            return "无法连接服务器：\(error.localizedDescription)"
        case .invalidResponse:
            return "服务器返回了异常响应。"
        case .httpError(let code, let body):
            if let body, !body.isEmpty {
                return "服务器错误 \(code)：\(String(body.prefix(200)))"
            }
            return "服务器错误 \(code)"
        case .refreshFailed(let detail):
            if let detail, !detail.isEmpty {
                return "令牌刷新失败：\(detail)"
            }
            return "令牌刷新失败，请重新登录。"
        }
    }
}

public struct BolaAuthUser: Sendable {
    public let id: String
    public let appleSub: String
    public let appAccountToken: String

    public init(id: String, appleSub: String, appAccountToken: String) {
        self.id = id
        self.appleSub = appleSub
        self.appAccountToken = appAccountToken
    }
}

public enum BolaAuthService {
    // MARK: - Sign In with Apple → Server

    /// 用 Apple identityToken 向 BolaBola 服务器换取 accessToken + refreshToken
    public static func signInWithApple(
        identityToken: String,
        nonce: String? = nil,
        device: DeviceInfo? = nil
    ) async throws -> BolaAuthUser {
        let url = BolaServerConfig.baseURL.appendingPathComponent("/api/v1/auth/apple")

        var body: [String: Any] = ["identityToken": identityToken]
        if let nonce { body["nonce"] = nonce }
        if let device {
            body["device"] = [
                "deviceId": device.deviceId,
                "platform": device.platform,
                "appVersion": device.appVersion as Any,
                "buildNumber": device.buildNumber as Any,
            ].compactMapValues { $0 }
        }

        let data = try await postJSON(url: url, body: body, accessToken: nil)
        let response = try parseAppleLoginResponse(data)

        BolaTokenStore.storeTokens(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken
        )

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .bolaLLMConfigurationDidChange, object: nil)
        }

        bolaAuthLog.info("signInWithApple OK userId=\(response.user.id, privacy: .public) appleSub=\(response.user.appleSub.prefix(8), privacy: .public)...")

        return response.user
    }

    // MARK: - Token Refresh

    /// 用 refreshToken 换取新的 accessToken + refreshToken（rotation）
    @discardableResult
    public static func refreshTokens() async throws -> (accessToken: String, refreshToken: String) {
        guard let currentRefresh = BolaTokenStore.refreshToken, !currentRefresh.isEmpty else {
            throw BolaAuthError.refreshFailed("没有保存的刷新令牌")
        }

        let url = BolaServerConfig.baseURL.appendingPathComponent("/api/v1/auth/refresh")
        let body: [String: Any] = ["refreshToken": currentRefresh]

        let data: Data
        do {
            data = try await postJSON(url: url, body: body, accessToken: nil)
        } catch let error as BolaAuthError {
            if case .httpError(let code, _) = error, code == 401 {
                BolaTokenStore.clearAll()
                bolaAuthLog.error("refreshTokens: 401 — refresh token 已失效，清除本地令牌")
            }
            throw BolaAuthError.refreshFailed(error.errorDescription)
        }

        struct RefreshResponse: Decodable {
            let accessToken: String?
            let refreshToken: String?
            enum CodingKeys: String, CodingKey {
                case accessToken, refreshToken
            }
        }

        guard let json = try? JSONDecoder().decode(RefreshResponse.self, from: data),
              let newAccess = json.accessToken, !newAccess.isEmpty,
              let newRefresh = json.refreshToken, !newRefresh.isEmpty else {
            throw BolaAuthError.invalidResponse
        }

        BolaTokenStore.storeTokens(accessToken: newAccess, refreshToken: newRefresh)
        bolaAuthLog.info("refreshTokens OK")
        return (newAccess, newRefresh)
    }

    // MARK: - Logout

    public static func logout(logoutAll: Bool = false) async throws {
        guard let accessToken = BolaTokenStore.accessToken else {
            BolaTokenStore.clearAll()
            return
        }

        let url = BolaServerConfig.baseURL.appendingPathComponent("/api/v1/auth/logout")
        let body: [String: Any] = ["logoutAll": logoutAll]
        _ = try? await postJSON(url: url, body: body, accessToken: accessToken)

        BolaTokenStore.clearAll()
        bolaAuthLog.info("logout OK logoutAll=\(logoutAll, privacy: .public)")
    }

    // MARK: - Auth State

    public static var isAuthenticated: Bool {
        BolaTokenStore.hasTokens
    }

    /// 带自动刷新的 accessToken 获取：如果当前 token 为空则尝试 refresh
    public static func getValidAccessToken() async throws -> String {
        if let token = BolaTokenStore.accessToken, !token.isEmpty {
            return token
        }
        let result = try await refreshTokens()
        return result.accessToken
    }

    // MARK: - Networking

    private static func postJSON(
        url: URL,
        body: [String: Any],
        accessToken: String?
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = accessToken, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 15

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw BolaAuthError.serverUnreachable(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw BolaAuthError.invalidResponse
        }
        guard (200 ... 299).contains(http.statusCode) else {
            let snippet = String(data: data, encoding: .utf8).map { String($0.prefix(500)) }
            bolaAuthLog.error("BolaAuthService HTTP \(http.statusCode, privacy: .public) url=\(url.path, privacy: .public)")
            throw BolaAuthError.httpError(http.statusCode, snippet)
        }
        return data
    }

    private static func parseAppleLoginResponse(_ data: Data) throws -> (
        accessToken: String, refreshToken: String, user: BolaAuthUser
    ) {
        struct Response: Decodable {
            let accessToken: String?
            let refreshToken: String?
            let user: UserInfo?
            enum CodingKeys: String, CodingKey {
                case accessToken, refreshToken, user
            }
            struct UserInfo: Decodable {
                let id: String?
                let appleSub: String?
                let appAccountToken: String?
                enum CodingKeys: String, CodingKey {
                    case id, appleSub, appAccountToken
                }
            }
        }

        guard let json = try? JSONDecoder().decode(Response.self, from: data),
              let accessToken = json.accessToken, !accessToken.isEmpty,
              let refreshToken = json.refreshToken, !refreshToken.isEmpty,
              let userInfo = json.user,
              let userId = userInfo.id, !userId.isEmpty,
              let appleSub = userInfo.appleSub, !appleSub.isEmpty,
              let appAccountToken = userInfo.appAccountToken, !appAccountToken.isEmpty else {
            bolaAuthLog.error("parseAppleLoginResponse: unexpected JSON structure")
            throw BolaAuthError.invalidResponse
        }

        let user = BolaAuthUser(
            id: userId,
            appleSub: appleSub,
            appAccountToken: appAccountToken
        )
        return (accessToken, refreshToken, user)
    }
}

public struct DeviceInfo: Sendable {
    public let deviceId: String
    public let platform: String
    public let appVersion: String?
    public let buildNumber: String?

    public init(deviceId: String, platform: String = "ios", appVersion: String? = nil, buildNumber: String? = nil) {
        self.deviceId = deviceId
        self.platform = platform
        self.appVersion = appVersion
        self.buildNumber = buildNumber
    }
}
