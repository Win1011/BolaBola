//
//  BolaOnboardingState.swift
//

import Foundation

public enum BolaOnboardingState {
    public static let doneKey = "bola_onboarding_done_v1"
    /// Set once on first completion; never cleared. Distinguishes returning users from new ones.
    public static let registeredKey = "bola_registered_before_v1"

    /// Posted (on main thread) when onboarding is reset so the root view can re-present it.
    public static let didRequestReplayNotification = Notification.Name("bolaOnboardingDidRequestReplay")

    public static var isCompleted: Bool {
        UserDefaults.standard.bool(forKey: doneKey)
    }

    /// True once the user has ever finished onboarding. Never reset, even after sign-out.
    public static var hasRegisteredBefore: Bool {
        UserDefaults.standard.bool(forKey: registeredKey)
    }

    public static func markCompleted() {
        UserDefaults.standard.set(true, forKey: doneKey)
        UserDefaults.standard.set(true, forKey: registeredKey)
    }

    /// Clears the completion flag and notifies the root view to re-present onboarding.
    public static func reset() {
        UserDefaults.standard.set(false, forKey: doneKey)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: didRequestReplayNotification, object: nil)
        }
    }
}
