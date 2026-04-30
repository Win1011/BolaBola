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
        if !BolaOnboardingState.hasRegisteredBefore {
            IOSKeyboardPrewarmer.prewarmAfterLaunch()
        }
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

@MainActor
private enum IOSKeyboardPrewarmer {
    private static var didPrewarm = false
    private static var windowObserver: NSObjectProtocol?

    static func prewarmAfterLaunch() {
        guard !didPrewarm else { return }

        if let window = keyWindow {
            prewarm(in: window)
            return
        }

        windowObserver = NotificationCenter.default.addObserver(
            forName: UIWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let window = notification.object as? UIWindow else { return }
            Task { @MainActor in
                prewarm(in: window)
            }
        }
    }

    @MainActor
    private static func prewarm(in window: UIWindow) {
        guard !didPrewarm else { return }
        didPrewarm = true

        if let windowObserver {
            NotificationCenter.default.removeObserver(windowObserver)
            self.windowObserver = nil
        }

        DispatchQueue.main.async {
            guard window.isKeyWindow else {
                didPrewarm = false
                prewarmAfterLaunch()
                return
            }

            let field = UITextField(frame: CGRect(x: -16, y: -16, width: 1, height: 1))
            field.alpha = 0.01
            field.textContentType = .none
            field.autocorrectionType = .no
            field.spellCheckingType = .no
            field.autocapitalizationType = .none
            field.inputAssistantItem.leadingBarButtonGroups = []
            field.inputAssistantItem.trailingBarButtonGroups = []
            window.addSubview(field)

            field.becomeFirstResponder()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                field.resignFirstResponder()
                field.removeFromSuperview()
            }
        }
    }

    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
    }
}
