//
//  BolaOnboardingState.swift
//

import Foundation

public enum BolaOnboardingState {
    public static let doneKey = "bola_onboarding_done_v1"

    public static var isCompleted: Bool {
        UserDefaults.standard.bool(forKey: doneKey)
    }

    public static func markCompleted() {
        UserDefaults.standard.set(true, forKey: doneKey)
    }
}
