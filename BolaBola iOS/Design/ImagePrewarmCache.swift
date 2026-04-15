//
//  ImagePrewarmCache.swift
//  在后台线程用 UIImage.byPreparingForDisplay() 预解码 PNG，
//  SwiftUI 收到已解码的 UIImage 后跳过 Core Animation Commit 阶段的主线程解码，
//  消除首次显示大图时的卡顿。
//

import UIKit

@MainActor
final class ImagePrewarmCache {
    static let shared = ImagePrewarmCache()

    private var cache: [String: UIImage] = [:]

    /// 在后台线程预解码指定名称的图片并存入缓存。
    func prewarm(named names: [String]) {
        for name in names {
            guard cache[name] == nil else { continue }
            Task.detached(priority: .userInitiated) {
                guard let raw = UIImage(named: name),
                      let decoded = await raw.byPreparingForDisplay() else { return }
                await MainActor.run {
                    ImagePrewarmCache.shared.cache[name] = decoded
                }
            }
        }
    }

    /// 返回已预解码的 UIImage，若尚未就绪则返回 nil（调用方回退到 Image("name")）。
    func image(named name: String) -> UIImage? {
        cache[name]
    }
}
