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
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

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
        // 后台预解码大图，避免 Core Animation Commit 阶段在主线程同步解压 PNG 导致卡顿。
        Task { @MainActor in
            ImagePrewarmCache.shared.prewarm(named: [
                "GrowthHeroIsland",
                "backgroundstar",
                "GrowthTaskCardYellowPattern",
                "GrowthCardBackSilhouette",
                "GrowthCardShinyBackSilhouette",
                "sticker_panel_bg",
            ])
        }
        return true
    }
}
