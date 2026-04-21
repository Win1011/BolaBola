//
//  BolaOnboardingState.swift
//

import Foundation

public enum BolaOnboardingState {
    public static let doneKey = "bola_onboarding_done_v1"

    /// Posted (on main thread) when onboarding is reset so the root view can re-present it.
    public static let didRequestReplayNotification = Notification.Name("bolaOnboardingDidRequestReplay")

    public static var isCompleted: Bool {
        UserDefaults.standard.bool(forKey: doneKey)
    }

    public static func markCompleted() {
        UserDefaults.standard.set(true, forKey: doneKey)
    }

    /// Clears the completion flag and notifies the root view to re-present onboarding.
    public static func reset() {
        UserDefaults.standard.set(false, forKey: doneKey)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: didRequestReplayNotification, object: nil)
        }
    }
}
