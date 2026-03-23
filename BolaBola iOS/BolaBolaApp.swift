//
//  BolaBolaApp.swift
//  BolaBola iOS
//

import SwiftUI

@main
struct BolaBolaApp: App {
    @UIApplicationDelegateAdaptor(IOSAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            IOSRootView()
        }
    }
}
