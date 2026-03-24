//
//  IOSChatTestSection.swift
//  iPhone：对话测试区（与手表共用 App Group 里的 ChatHistoryStore）。
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
            HStack {
                Text("和 Bola 聊天")
                    .font(.headline)
                Spacer()
                Button("清空") {
                    ChatHistoryStore.clear(defaults: bolaDefaults)
                    turns = []
                    errorText = nil
                }
                .font(.caption)
                .disabled(isLoading)
            }
            .padding(.bottom, 8)

            Text("多轮对话会保存在本机并与手表同步；API 请在「设置 → 对话 API」中配置。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if turns.isEmpty && !isLoading {
                            Text("发一条消息开始测试。")
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 24)
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
                .frame(minHeight: 220, maxHeight: 360)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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

            HStack(alignment: .center, spacing: 12) {
                TextField("输入消息…", text: $input, axis: .vertical)
                    .lineLimit(1 ... 5)
                    .font(.body)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(minHeight: 44, alignment: .topLeading)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(uiColor: .tertiarySystemBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color(uiColor: .separator), lineWidth: 0.5)
                    )

                Button {
                    Task { await send() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(BolaTheme.accent)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                .buttonStyle(.borderless)
            }
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            reloadFromStore()
        }
        .onReceive(NotificationCenter.default.publisher(for: .bolaChatHistoryDidMerge)) { _ in
            reloadFromStore()
        }
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

    private func send() async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        await MainActor.run {
            errorText = nil
            isLoading = true
            input = ""
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
