//
//  BolaBolaApp.swift
//  BolaBola Watch App
//
//  Created by Nan on 3/15/26.
//

import SwiftUI

@main
struct BolaBola_Watch_AppApp: App {
    /// 尽早激活 WCSession（与 iOS `IOSAppDelegate` 对称），避免表端 UI 尚未创建时 `didReceiveUserInfo` 已到达却无法投递给 delegate。
    init() {
        BolaWCSessionCoordinator.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
