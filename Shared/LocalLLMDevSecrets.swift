//
//  LocalLLMDevSecrets.swift
//  同步未好时：在下面把 apiKey 粘进引号里保存即可先用。
//  Keychain（iPhone 设置里保存）仍优先；只有 Keychain 没有 Key 时才用这里。
//

import Foundation

public enum LocalLLMDevSecrets {
    /// 在智谱开放平台控制台复制的 **API Key**（一长串字母数字），不要填文档网页链接。
    public static let apiKey: String = ""

    public static let baseURL: String = "https://open.bigmodel.cn/api/paas/v4"

    public static let modelId: String = "glm-4-FlashX"

    public static let useBearerAuth: Bool = true
}
