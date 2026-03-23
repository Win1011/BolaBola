//
//  WCSyncPayload.swift
//

import Foundation

/// Keys for `WCSession.updateApplicationContext` / `transferUserInfo`.
public enum WCSyncPayload {
    public static let companionValue = "companionValue"
    public static let companionValueUpdatedAt = "companionValueUpdatedAt"
    public static let requestSync = "requestSync"
}
