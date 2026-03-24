//
//  IOSNotificationRouter.swift
//

import FirebaseCore
import UIKit
import UserNotifications

final class IOSNotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = IOSNotificationRouter()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.notification.request.identifier == "bola_digest_daily" {
            BolaSharedDefaults.resolved().set(true, forKey: BolaNotificationBridgeKeys.digestTapOpen)
        }
        completionHandler()
    }
}

final class IOSAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()
        UNUserNotificationCenter.current().delegate = IOSNotificationRouter.shared
        BolaWCSessionCoordinator.shared.activate()
        return true
    }
}
