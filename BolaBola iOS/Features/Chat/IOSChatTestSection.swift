//
//  IOSChatTestSection.swift
//  iPhone：对话测试区；聊天记录与手表靠 WatchConnectivity 合并，并与 App Group 共享 prefs 一致时对齐。
//

import SwiftUI

struct IOSChatTestSection: View {
    var companion: Double

    private var bolaDefaults: UserDefaults { BolaSharedDefaults.resolved() }

    @State private var turns: [ChatTurn] = []
    @State private var input: String = ""
    @State private var isLoading = false
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Text("多轮对话会保存在本机并与手表同步；API 请在「设置 → 对话 API」中配置。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    ChatHistoryStore.clear(defaults: bolaDefaults)
                    turns = []
                    errorText = nil
                } label: {
                    Label("清空", systemImage: "trash")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(.secondary)
                .controlSize(.regular)
                .disabled(isLoading)
            }
            .padding(.bottom, 10)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if turns.isEmpty && !isLoading {
                            guidedIntro
                        }
                        ForEach(turns) { turn in
                            chatBubble(turn)
                                .id(turn.id)
                        }
                        if isLoading {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Bola 正在想…")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                            .id("loading")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: BolaTheme.cornerCompact, style: .continuous))
                .onChange(of: turns.count) { _, _ in
                    if let last = turns.last?.id {
                        withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                    }
                }
                .onChange(of: isLoading) { _, loading in
                    if loading {
                        withAnimation { proxy.scrollTo("loading", anchor: .bottom) }
                    }
                }
            }

            if let errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.top, 6)
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField("输入消息…", text: $input, axis: .vertical)
                    .lineLimit(1 ... 3)
                    .font(.body)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(minHeight: 38, alignment: .topLeading)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(uiColor: .tertiarySystemBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color(uiColor: .separator), lineWidth: 0.5)
                    )

                Button {
                    Task { await sendMessage(usingInputField: true) }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(BolaTheme.accent)
                        .frame(width: 40, height: 40)
                }
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                .buttonStyle(.borderless)
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            reloadFromStore()
        }
        .onReceive(NotificationCenter.default.publisher(for: .bolaChatHistoryDidMerge)) { _ in
            reloadFromStore()
        }
    }

    private var guidedIntro: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 4)
            ZStack {
                Circle()
                    .fill(Color(red: 0.88, green: 0.94, blue: 0.78))
                    .frame(width: 76, height: 76)
                Image(systemName: "cpu")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(Color(red: 0.12, green: 0.38, blue: 0.22))
            }

            Text("认识 Bola，你的健康 AI")
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)

            Text("可以询问睡眠、营养或今天如何完成活动目标。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 12)

            VStack(spacing: 10) {
                guidedPromptButton("我昨晚睡得怎么样？")
                guidedPromptButton("分析我的心率趋势")
                guidedPromptButton("帮我安排今天的运动")
            }
            .padding(.top, 4)
            Spacer(minLength: 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private func guidedPromptButton(_ title: String) -> some View {
        Button {
            Task { await sendMessage(preset: title) }
        } label: {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color(uiColor: .tertiarySystemFill))
                )
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }

    @ViewBuilder
    private func chatBubble(_ turn: ChatTurn) -> some View {
        let isUser = turn.role == "user"
        HStack {
            if isUser { Spacer(minLength: 40) }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                Text(isUser ? "你" : "Bola")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(turn.content)
                    .font(.subheadline)
                    .textSelection(.enabled)
                    .multilineTextAlignment(isUser ? .trailing : .leading)
                    .padding(10)
                    .background(
                        isUser
                            ? Color.accentColor.opacity(0.2)
                            : Color(.tertiarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
            }
            if !isUser { Spacer(minLength: 40) }
        }
    }

    private func reloadFromStore() {
        turns = ChatHistoryStore.load(from: bolaDefaults)
    }

    /// - Parameter usingInputField: 为 true 时读取并清空输入框；否则使用 `preset` 文案。
    private func sendMessage(usingInputField: Bool = false, preset: String? = nil) async {
        let text: String = {
            if let preset {
                return preset.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return input.trimmingCharacters(in: .whitespacesAndNewlines)
        }()
        guard !text.isEmpty else { return }

        await MainActor.run {
            errorText = nil
            isLoading = true
            if usingInputField {
                input = ""
            }
        }
        let v = Int(companion.rounded())
        do {
            _ = try await ConversationService.replyToUser(utterance: text, companionValue: v)
            await MainActor.run {
                reloadFromStore()
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorText = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
                isLoading = false
            }
        }
    }
}
