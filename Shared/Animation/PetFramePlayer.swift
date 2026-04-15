//
//  PetFramePlayer.swift
//  Shared — available on both watchOS and iOS
//
//  独立帧序列播放器：循环播放 Asset Catalog 中名如 `\(prefix)0`, `\(prefix)1`, …
//  的图片帧，不依赖 PetViewModel，可直接嵌入任意 SwiftUI 视图。
//

import SwiftUI
import Combine

/// 循环播放帧前缀为 `prefix` 的动画序列（Asset Catalog 资源名 `\(prefix)0`…`\(prefix)(maxFrames-1)`）。
public struct PetFramePlayer: View {
    public let prefix: String
    public var maxFrames: Int = 90
    public var fps: Double = 24

    @State private var frameIndex: Int = 0
    @State private var lastUpdate: Date = Date()
    @State private var timerCancellable: AnyCancellable?

    public init(prefix: String, maxFrames: Int = 90, fps: Double = 24) {
        self.prefix = prefix
        self.maxFrames = maxFrames
        self.fps = fps
    }

    public var body: some View {
        let frameName = "\(prefix)\(frameIndex)"
        Image(frameName)
            .resizable()
            .scaledToFit()
            // 强制每帧重建 Image，避免纹理缓存残留
            .id(frameName)
            // 禁用隐式动画，避免帧间过渡产生额外纹理
            .transaction { $0.animation = nil }
            .allowsHitTesting(false)
            .onAppear { resetAndStart() }
            .onDisappear { timerCancellable?.cancel() }
            .onChange(of: prefix) { resetAndStart() }
    }

    private func resetAndStart() {
        frameIndex = 0
        lastUpdate = Date()
        timerCancellable?.cancel()
        let frameDuration = 1.0 / max(fps, 1)
        timerCancellable = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common)
            .autoconnect()
            .sink { now in
                let elapsed = now.timeIntervalSince(lastUpdate)
                if elapsed >= frameDuration {
                    frameIndex = (frameIndex + 1) % max(maxFrames, 1)
                    lastUpdate = now
                }
            }
    }
}
