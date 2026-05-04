//
//  IOSSplashLaunchRoot.swift
//  冷启动全屏 App Logo（与系统静态启动图衔接），短暂展示后淡出。
//

import SwiftUI

/// 根窗口外包一层：先盖 `BolaLogo` 全屏，再露出 `IOSRootView`。
struct IOSSplashLaunchRoot: View {
    @State private var showSplash = true

    var body: some View {
        ZStack {
            IOSRootView()
            if showSplash {
                splashLayer
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(850))
            withAnimation(.easeOut(duration: 0.38)) {
                showSplash = false
            }
        }
    }

    private var splashLayer: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()
            Image("BolaLogo")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(maxWidth: 148, maxHeight: 148)
                // 与系统主屏图标观感一致：圆角矩形裁切，避免方形 raw asset 顶满屏中。
                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                .accessibilityLabel("BolaBola")
        }
    }
}
