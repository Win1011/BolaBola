//
//  IOSLLMSettingsSection.swift
//  iPhone：中转 / 兼容 chat 接口的密钥与地址写入 Keychain，并同步到手表。
//

import SwiftUI

struct IOSLLMSettingsSection: View {
    @State private var apiKey: String = ""
    @State private var baseURL: String = ""
    @State private var modelId: String = ""
    @State private var showKey: Bool = false
    @State private var useBearerAuth: Bool = true
    @State private var saveMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("对话 API（中转站）")
                .font(.headline)

            Text("Base URL 填到「chat/completions 前」的路径：OpenAI 兼容多为 …/v1；智谱官方为 …/api/paas/v4。若留空未保存，将默认使用 OpenAI 地址，智谱密钥会 401。模型名如 glm-4.6v。密钥勿发聊天、勿提交 Git。")
                .font(.caption)
                .foregroundStyle(.secondary)

            Group {
                HStack {
                    if showKey {
                        TextField("API Key", text: $apiKey)
                            .textContentType(.password)
                            .autocorrectionDisabled()
                    } else {
                        SecureField("API Key", text: $apiKey)
                            .textContentType(.password)
                    }
                    Button(showKey ? "隐藏" : "显示") { showKey.toggle() }
                        .font(.caption)
                }
                TextField("Base URL（例：…/v1 或 …/api/paas/v4）", text: $baseURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                TextField("模型名（按中转站）", text: $modelId)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Toggle("Authorization 使用 Bearer 前缀", isOn: $useBearerAuth)
                    .font(.subheadline)
                Text("若出现 401，可关闭此项再试（部分中转要求整段 Key 作为 Authorization，不加 Bearer）。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)

            Button("保存并同步到手表") {
                saveMessage = nil
                persistToKeychain()
                BolaWCSessionCoordinator.shared.pushLLMConfigurationToWatch(
                    apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
                    baseURL: baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
                    model: modelId.trimmingCharacters(in: .whitespacesAndNewlines),
                    useBearerAuth: useBearerAuth
                )
                NotificationCenter.default.post(name: .bolaLLMConfigurationDidChange, object: nil)
                saveMessage = "已保存。手表会通过无线同步收到 Key；若仍提示未配置，请 iPhone 与手表都打开本 App 稍等，或在手表再试一次麦克风。"
            }
            .buttonStyle(.borderedProminent)

            if let saveMessage {
                Text(saveMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            loadFromKeychain()
        }
    }

    private func loadFromKeychain() {
        apiKey = KeychainHelper.get(service: LLMKeychain.service, account: LLMKeychain.accountAPIKey) ?? ""
        baseURL = KeychainHelper.get(service: LLMKeychain.service, account: LLMKeychain.accountBaseURL)
            ?? LLMClient.defaultBaseURLString
        modelId = KeychainHelper.get(service: LLMKeychain.service, account: LLMKeychain.accountModelId)
            ?? "gpt-4o-mini"
        useBearerAuth = KeychainHelper.get(service: LLMKeychain.service, account: LLMKeychain.accountAuthBearer) != "0"
    }

    private func persistToKeychain() {
        let k = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let m = modelId.trimmingCharacters(in: .whitespacesAndNewlines)

        if k.isEmpty {
            KeychainHelper.remove(service: LLMKeychain.service, account: LLMKeychain.accountAPIKey)
        } else {
            KeychainHelper.set(k, service: LLMKeychain.service, account: LLMKeychain.accountAPIKey)
        }
        if b.isEmpty {
            KeychainHelper.remove(service: LLMKeychain.service, account: LLMKeychain.accountBaseURL)
        } else {
            KeychainHelper.set(b, service: LLMKeychain.service, account: LLMKeychain.accountBaseURL)
        }
        if m.isEmpty {
            KeychainHelper.remove(service: LLMKeychain.service, account: LLMKeychain.accountModelId)
        } else {
            KeychainHelper.set(m, service: LLMKeychain.service, account: LLMKeychain.accountModelId)
        }
        KeychainHelper.set(useBearerAuth ? "1" : "0", service: LLMKeychain.service, account: LLMKeychain.accountAuthBearer)
    }
}
