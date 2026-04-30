//
//  BolaTokenStore.swift
//  BolaBola 服务器令牌安全存储
//

import Foundation

public enum BolaTokenStore {
    private static let service = "com.GathXRTeam.BolaBola.server"
    private static let accountAccessToken = "accessToken"
    private static let accountRefreshToken = "refreshToken"

    // MARK: - Access Token

    public static var accessToken: String? {
        KeychainHelper.get(service: service, account: accountAccessToken)
    }

    public static func setAccessToken(_ token: String) {
        KeychainHelper.set(token, service: service, account: accountAccessToken)
    }

    // MARK: - Refresh Token

    public static var refreshToken: String? {
        KeychainHelper.get(service: service, account: accountRefreshToken)
    }

    public static func setRefreshToken(_ token: String) {
        KeychainHelper.set(token, service: service, account: accountRefreshToken)
    }

    // MARK: - Batch Operations

    public static func storeTokens(accessToken: String, refreshToken: String) {
        setAccessToken(accessToken)
        setRefreshToken(refreshToken)
    }

    public static func clearAll() {
        KeychainHelper.remove(service: service, account: accountAccessToken)
        KeychainHelper.remove(service: service, account: accountRefreshToken)
    }

    public static var hasTokens: Bool {
        guard let access = accessToken, !access.isEmpty else { return false }
        guard let refresh = refreshToken, !refresh.isEmpty else { return false }
        return true
    }
}
