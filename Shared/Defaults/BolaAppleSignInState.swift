//
//  BolaAppleSignInState.swift
//

import Foundation

public enum BolaAppleSignInState {
    private static let service = "com.GathXRTeam.BolaBolaApp.auth.apple"
    private static let userIdentifierAccount = "appleUserIdentifier"
    private static let fullNameKey = "bola_apple_sign_in_full_name_v1"
    private static let emailKey = "bola_apple_sign_in_email_v1"
    private static let signedInKey = "bola_apple_sign_in_completed_v1"

    public static var isSignedIn: Bool {
        UserDefaults.standard.bool(forKey: signedInKey)
    }

    public static var userIdentifier: String? {
        KeychainHelper.get(service: service, account: userIdentifierAccount)
    }

    public static func markSignedIn(
        userIdentifier: String,
        fullName: PersonNameComponents?,
        email: String?
    ) {
        KeychainHelper.set(userIdentifier, service: service, account: userIdentifierAccount)
        UserDefaults.standard.set(true, forKey: signedInKey)

        if let fullName {
            let formatter = PersonNameComponentsFormatter()
            let displayName = formatter.string(from: fullName).trimmingCharacters(in: .whitespacesAndNewlines)
            if !displayName.isEmpty {
                UserDefaults.standard.set(displayName, forKey: fullNameKey)
            }
        }

        if let email, !email.isEmpty {
            UserDefaults.standard.set(email, forKey: emailKey)
        }
    }

    public static func reset() {
        KeychainHelper.remove(service: service, account: userIdentifierAccount)
        UserDefaults.standard.set(false, forKey: signedInKey)
        UserDefaults.standard.removeObject(forKey: fullNameKey)
        UserDefaults.standard.removeObject(forKey: emailKey)
    }
}
