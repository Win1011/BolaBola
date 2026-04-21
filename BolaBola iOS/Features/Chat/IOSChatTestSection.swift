//
//  IOSChatTestSection.swift
//  iPhone：对话测试区；聊天记录与手表靠 WatchConnectivity 合并，并与 App Group 共享 prefs 一致时对齐。
//

import SwiftUI
import UIKit

extension Notification.Name {
    static let bolaChatJumpToLatestRequested = Notification.Name("bolaChatJumpToLatestRequested")
    static let bolaChatOpenHistoryCalendarRequested = Notification.Name("bolaChatOpenHistoryCalendarRequested")
}

private enum ChatDeliveryState {
    case sending
    case failed
}

private struct VoiceInputWaveform: View {
    let isAnimating: Bool

    private let bars: [CGFloat] = [8, 14, 20, 12, 18, 9]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(bars.enumerated()), id: \.offset) { index, height in
                Capsule()
                    .fill(Color.black.opacity(0.74))
                    .frame(width: 3, height: isAnimating ? animatedHeight(for: index, base: height) : height)
                    .animation(
                        .easeInOut(duration: 0.52 + Double(index) * 0.035).repeatForever(autoreverses: true),
                        value: isAnimating
                    )
            }
        }
        .frame(width: 34, height: 22)
        .padding(.horizontal, 8)
        .background(
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.08))
        )
    }

    private func animatedHeight(for index: Int, base: CGFloat) -> CGFloat {
        index.isMultiple(of: 2) ? base + 5 : max(7, base - 4)
    }
}

struct IOSChatTestSection: View {
    var companion: Double

    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var isInputFocused: Bool

    private var bolaDefaults: UserDefaults { BolaSharedDefaults.resolved() }
    private var dialogueCaps: BolaLevelGate.Capabilities { BolaLevelGate.capabilities() }

    @State private var turns: [ChatTurn] = []
    @State private var input: String = ""
    @State private var voiceInputPrefix: String = ""
    @State private var isLoading = false
    @State private var isLLMConfigured = false
    @State private var isRecordingVoice = false
    @State private var isPreparingVoice = false
    @State private var errorText: String?
    @State private var memoryToastText: String?
    @State private var memoryCaptureWindowEndsAt: Date?
    @State private var didCaptureDiaryInWindow = false
    @State private var didCaptureLifeRecordInWindow = false
    @State private var pendingTurn: ChatTurn?
    @State private var failedTurn: ChatTurn?
    @State private var failedPresetText: String?
    @State private var hasUserScrolledHistory = false
    @State private var showJumpToLatest = false
    @State private var showHistoryCalendar = false
    @State private var selectedHistoryDate = Date()
    @State private var voiceWavePhase = false
    @State private var hasPerformedInitialLoad = false

    private var canUseChatControls: Bool {
        dialogueCaps.canDialogue && isLLMConfigured && !isLoading
    }

    private let contentHorizontalPadding: CGFloat = 16
    private let inputBarBottomLift: CGFloat = 14
    private static let loadingScrollID = "chat-loading"

    var body: some View {
        ZStack {
            chatAmbientBackground

            VStack(alignment: .leading, spacing: 0) {
                memoryToast
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, memoryToastText == nil ? 0 : 8)

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            if !dialogueCaps.canDialogue {
                                lockedIntro
                            } else if !isLLMConfigured {
                                unconfiguredIntro
                            } else if turns.isEmpty && !isLoading {
                                guidedIntro
                            }
                            ForEach(Array(turns.enumerated()), id: \.element.id) { index, turn in
                                if shouldShowTimelineSeparator(at: index) {
                                    timelineSeparator(at: index)
                                }
                                chatBubble(turn)
                                    .id(scrollID(for: turn))
                            }
                            if let pendingTurn {
                                chatBubble(pendingTurn, deliveryState: .sending)
                                    .id(scrollID(for: pendingTurn))
                            }
                            if let failedTurn {
                                chatBubble(failedTurn, deliveryState: .failed)
                                    .id(scrollID(for: failedTurn))
                            }
                            if isLoading {
                                typingIndicator
                                    .padding(.vertical, 4)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                .id(Self.loadingScrollID)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 12)
                    }
                    .scrollIndicators(.hidden)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        dismissKeyboard()
                    }
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 8).onChanged { _ in
                            hasUserScrolledHistory = true
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(Color(uiColor: .systemBackground).opacity(0.68))
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(Color.white.opacity(0.72), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.05), radius: 22, y: 10)
                    .onAppear {
                        scrollToLatest(proxy: proxy, animated: false)
                    }
                    .onChange(of: turns.last?.id) { _, _ in
                        handleLatestMessageChange(proxy: proxy)
                    }
                    .onChange(of: isLoading) { _, loading in
                        if loading {
                            withAnimation { proxy.scrollTo(Self.loadingScrollID, anchor: .bottom) }
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .bolaChatJumpToLatestRequested)) { notification in
                        if let target = notification.object as? String {
                            scrollToTarget(target, proxy: proxy, animated: true)
                        } else {
                            scrollToLatest(proxy: proxy, animated: true)
                        }
                    }
                }

                if showJumpToLatest {
                    jumpToLatestButton
                        .padding(.top, 8)
                }

                if let errorText {
                    Text(errorText)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.top, 6)
                }

                chatInputBar
            }
            .padding(.horizontal, contentHorizontalPadding)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture {
            dismissKeyboard()
        }
        .onAppear {
            guard !hasPerformedInitialLoad else { return }
            hasPerformedInitialLoad = true
            refreshLLMConfiguration()
            reloadFromStore()
        }
        .onDisappear {
            cancelVoiceInput()
        }
        .onReceive(NotificationCenter.default.publisher(for: .bolaChatHistoryDidMerge)) { _ in
            reloadFromStore()
        }
        .onReceive(NotificationCenter.default.publisher(for: .bolaLLMConfigurationDidChange)) { _ in
            refreshLLMConfiguration()
        }
        .onReceive(NotificationCenter.default.publisher(for: .bolaDiaryEntriesDidChange)) { _ in
            markMemoryCapture(diary: true, lifeRecord: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: .bolaLifeRecordsDidChange)) { _ in
            markMemoryCapture(diary: false, lifeRecord: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .bolaChatOpenHistoryCalendarRequested)) { _ in
            selectedHistoryDate = turns.last?.createdAt ?? Date()
            showHistoryCalendar = true
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            refreshLLMConfiguration()
        }
        .sheet(isPresented: $showHistoryCalendar) {
            ChatHistoryCalendarSheet(
                selectedDate: $selectedHistoryDate,
                turns: turns,
                onJumpToDate: { date in
                    jumpToChatDate(date)
                }
            )
        }
    }

    private var chatAmbientBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    BolaTheme.accent.opacity(0.46),
                    Color(red: 0.93, green: 0.98, blue: 0.78),
                    Color(uiColor: .systemBackground)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(BolaTheme.accent.opacity(0.44))
                .frame(width: 300, height: 300)
                .blur(radius: 46)
                .offset(x: -145, y: -205)

            Circle()
                .fill(Color.white.opacity(0.76))
                .frame(width: 240, height: 240)
                .blur(radius: 34)
                .offset(x: 150, y: 60)

            Circle()
                .fill(BolaTheme.accent.opacity(0.18))
                .frame(width: 260, height: 260)
                .blur(radius: 56)
                .offset(x: 120, y: 310)

            LinearGradient(
                colors: [
                    Color.clear,
                    Color(uiColor: .systemBackground).opacity(0.62)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
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
                guidedPromptButton("今天有点累，想和你说说")
                guidedPromptButton("帮我记一下我晚饭吃了什么")
                guidedPromptButton("我想养成早睡习惯")
            }
            .padding(.top, 4)
            Spacer(minLength: 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private var lockedIntro: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 4)
            Image(systemName: "lock.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("Bola 还不会完整说话")
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)
            Text("先继续陪陪它、做任务升到 Lv.1，再来解锁对话。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
            Spacer(minLength: 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private var unconfiguredIntro: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 4)
            Image(systemName: "key.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(BolaTheme.accent)
            Text("还没有配置对话 API")
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)
            Text("先到「设置 → 对话 API」填写密钥和 Base URL，配置完成后就能和 Bola 聊天。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
            Button("前往设置配置") {
                NotificationCenter.default.post(name: .bolaOpenSettingsRequested, object: nil)
            }
            .buttonStyle(.borderedProminent)
            Spacer(minLength: 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
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
                        .fill(Color(uiColor: .systemBackground).opacity(0.74))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(BolaTheme.accent.opacity(0.38), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }

    private var typingIndicator: some View {
        HStack(alignment: .bottom, spacing: 8) {
            bolaAvatar
                .frame(width: 28, height: 28)
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Bola 正在想…")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                Capsule(style: .continuous)
                    .fill(Color(uiColor: .systemBackground).opacity(0.82))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.72), lineWidth: 1)
            )
        }
    }

    private var jumpToLatestButton: some View {
        Button {
            showJumpToLatest = false
            hasUserScrolledHistory = false
            NotificationCenter.default.post(name: .bolaChatJumpToLatestRequested, object: nil)
        } label: {
            Label("回到最新消息", systemImage: "arrow.down.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.black)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule(style: .continuous).fill(BolaTheme.accent.opacity(0.92)))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var memoryToast: some View {
        if let memoryToastText {
            HStack(spacing: 8) {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.system(size: 13, weight: .bold))
                Text(memoryToastText)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(Color.black)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                Capsule(style: .continuous)
                    .fill(BolaTheme.accent.opacity(0.92))
            )
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private var chatInputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            voiceButton

            TextField(isRecordingVoice ? "正在听你说…" : "输入消息…", text: $input, axis: .vertical)
                .lineLimit(1 ... 3)
                .font(.body)
                .textFieldStyle(.plain)
                .tint(Color(uiColor: .systemBlue))
                .focused($isInputFocused)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(minHeight: 42, alignment: .topLeading)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(uiColor: .tertiarySystemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.82), lineWidth: 1)
                )
                .disabled(!dialogueCaps.canDialogue || !isLLMConfigured)

            sendButton
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            Capsule(style: .continuous)
                .fill(Color(uiColor: .systemBackground).opacity(0.64))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.76), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 18, y: 8)
        .padding(.top, 8)
        .padding(.bottom, inputBarBottomLift)
        .overlay(alignment: .top) {
            if isRecordingVoice {
                voiceRecordingBadge
                    .offset(y: -30)
            }
        }
    }

    private var voiceRecordingBadge: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(Color.red)
                .frame(width: 6, height: 6)
            Text("正在录音，点麦克风结束")
                .font(.caption2.weight(.semibold))
            VoiceInputWaveform(isAnimating: voiceWavePhase)
        }
        .foregroundStyle(Color.black)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule(style: .continuous).fill(BolaTheme.accent.opacity(0.94)))
        .shadow(color: Color.black.opacity(0.10), radius: 10, y: 5)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var voiceButton: some View {
        Button {
            toggleVoiceInput()
        } label: {
            ZStack {
                Circle()
                    .fill(BolaTheme.accent)
                Image(systemName: isRecordingVoice ? "stop.fill" : "mic.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.black)
                if isPreparingVoice {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .frame(width: 42, height: 42)
            .overlay(
                Circle()
                    .stroke(Color.black.opacity(isRecordingVoice ? 0.28 : 0), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!canUseChatControls && !isRecordingVoice || isPreparingVoice)
        .opacity(!canUseChatControls && !isRecordingVoice || isPreparingVoice ? 0.45 : 1)
        .accessibilityLabel(isRecordingVoice ? "停止语音输入" : "语音输入")
    }

    private var sendButton: some View {
        Button {
            Task { await sendMessage(usingInputField: true) }
        } label: {
            Circle()
                .fill(BolaTheme.accent)
                .frame(width: 42, height: 42)
                .overlay {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.black)
                }
        }
        .buttonStyle(.plain)
        .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !canUseChatControls || isRecordingVoice)
        .opacity(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !canUseChatControls || isRecordingVoice ? 0.45 : 1)
        .accessibilityLabel("发送")
    }

    @ViewBuilder
    private func chatBubble(_ turn: ChatTurn, deliveryState: ChatDeliveryState? = nil) -> some View {
        let isUser = turn.role == "user"
        HStack(alignment: .top, spacing: 8) {
            if isUser { Spacer(minLength: 40) }
            if !isUser {
                bolaAvatar
                    .frame(width: 30, height: 30)
                    .padding(.top, 18)
            }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                messageMetadata(turn, isUser: isUser)
                messageBody(turn, isUser: isUser)
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = turn.content
                        } label: {
                            Label("复制", systemImage: "doc.on.doc")
                        }

                        Button {
                            addDiaryEntry(from: turn)
                        } label: {
                            Label("记入时光", systemImage: "book.pages")
                        }

                        Button {
                            addLifeRecord(from: turn)
                        } label: {
                            Label("记为生活卡片", systemImage: "sparkles.rectangle.stack")
                        }

                        if isUser {
                            Button {
                                Task { await sendMessage(preset: turn.content) }
                            } label: {
                                Label("重新发送", systemImage: "arrow.clockwise")
                            }
                        }

                        Button(role: .destructive) {
                            deleteTurn(turn)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                deliveryFooter(deliveryState)
            }
            .frame(maxWidth: 286, alignment: isUser ? .trailing : .leading)
            if !isUser { Spacer(minLength: 40) }
        }
    }

    private var bolaAvatar: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.92))
            Circle()
                .fill(BolaTheme.accent)
                .frame(width: 5, height: 5)
                .offset(x: -5, y: -2)
            Circle()
                .fill(BolaTheme.accent)
                .frame(width: 5, height: 5)
                .offset(x: 5, y: -2)
        }
        .shadow(color: Color.black.opacity(0.12), radius: 8, y: 4)
    }

    private func messageMetadata(_ turn: ChatTurn, isUser: Bool) -> some View {
        HStack(spacing: 5) {
            Text(isUser ? "你" : "Bola")
                .font(.caption2.weight(.semibold))
            Text(timestampText(for: turn.createdAt))
                .font(.caption2)
                .opacity(0.72)
        }
        .foregroundStyle(.secondary)
    }

    private func messageBody(_ turn: ChatTurn, isUser: Bool) -> some View {
        Text(turn.content)
            .font(.subheadline)
            .textSelection(.enabled)
            .multilineTextAlignment(isUser ? .trailing : .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                isUser
                    ? BolaTheme.accent.opacity(0.86)
                    : Color(uiColor: .systemBackground).opacity(0.88),
                in: UnevenRoundedRectangle(
                    topLeadingRadius: isUser ? 16 : 6,
                    bottomLeadingRadius: isUser ? 16 : 18,
                    bottomTrailingRadius: isUser ? 6 : 18,
                    topTrailingRadius: isUser ? 18 : 16,
                    style: .continuous
                )
            )
            .overlay(
                UnevenRoundedRectangle(
                    topLeadingRadius: isUser ? 16 : 6,
                    bottomLeadingRadius: isUser ? 16 : 18,
                    bottomTrailingRadius: isUser ? 6 : 18,
                    topTrailingRadius: isUser ? 18 : 16,
                    style: .continuous
                )
                .stroke(Color.white.opacity(isUser ? 0.28 : 0.74), lineWidth: 0.8)
            )
    }

    @ViewBuilder
    private func deliveryFooter(_ state: ChatDeliveryState?) -> some View {
        switch state {
        case .sending:
            HStack(spacing: 5) {
                ProgressView()
                    .controlSize(.small)
                Text("发送中")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        case .failed:
            HStack(spacing: 8) {
                Text("发送失败")
                Button("重试") {
                    if let failedPresetText {
                        Task { await sendMessage(preset: failedPresetText) }
                    }
                }
                .font(.caption2.weight(.semibold))
            }
            .font(.caption2)
            .foregroundStyle(.red)
        case nil:
            EmptyView()
        }
    }

    private func timelineSeparator(at index: Int) -> some View {
        Text(timelineSeparatorText(at: index))
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(Color(uiColor: .systemBackground).opacity(0.72))
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
    }

    private func shouldShowTimelineSeparator(at index: Int) -> Bool {
        guard turns.indices.contains(index) else { return false }
        guard index > 0 else { return true }
        let previous = turns[index - 1].createdAt
        let current = turns[index].createdAt
        return !Calendar.current.isDate(previous, inSameDayAs: current)
            || current.timeIntervalSince(previous) >= 10 * 60
    }

    private func timelineSeparatorText(at index: Int) -> String {
        guard turns.indices.contains(index) else { return "" }
        let date = turns[index].createdAt
        guard index > 0 else { return dateHeaderText(for: date) }
        let previous = turns[index - 1].createdAt
        if !Calendar.current.isDate(previous, inSameDayAs: date) {
            return dateHeaderText(for: date)
        }
        return timestampText(for: date)
    }

    private func scrollToLatest(proxy: ScrollViewProxy, animated: Bool) {
        let target: String?
        if isLoading {
            target = Self.loadingScrollID
        } else if let failedTurn {
            target = scrollID(for: failedTurn)
        } else if let pendingTurn {
            target = scrollID(for: pendingTurn)
        } else if let last = turns.last?.id {
            target = scrollID(for: last)
        } else {
            target = nil
        }
        guard let target else { return }
        scrollToTarget(target, proxy: proxy, animated: animated)
    }

    private func scrollToTarget(_ target: String, proxy: ScrollViewProxy, animated: Bool) {
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeOut(duration: 0.22)) {
                    proxy.scrollTo(target, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(target, anchor: .bottom)
            }
        }
    }

    private func handleLatestMessageChange(proxy: ScrollViewProxy) {
        if hasUserScrolledHistory {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                showJumpToLatest = true
            }
        } else {
            scrollToLatest(proxy: proxy, animated: true)
        }
    }

    private func scrollID(for turn: ChatTurn) -> String {
        scrollID(for: turn.id)
    }

    private func scrollID(for id: UUID) -> String {
        "turn-\(id.uuidString)"
    }

    private func jumpToChatDate(_ date: Date) {
        guard let firstTurn = turns.first(where: { Calendar.current.isDate($0.createdAt, inSameDayAs: date) }) else {
            return
        }
        showHistoryCalendar = false
        showJumpToLatest = true
        hasUserScrolledHistory = true
        NotificationCenter.default.post(
            name: .bolaChatJumpToLatestRequested,
            object: scrollID(for: firstTurn)
        )
    }

    private func timestampText(for date: Date) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        if calendar.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
        } else if calendar.isDateInYesterday(date) {
            formatter.dateFormat = "昨天 HH:mm"
        } else if calendar.component(.year, from: date) == calendar.component(.year, from: Date()) {
            formatter.dateFormat = "M月d日 HH:mm"
        } else {
            formatter.dateFormat = "yyyy年M月d日 HH:mm"
        }
        return formatter.string(from: date)
    }

    private func dateHeaderText(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "今天 \(shortTimeText(for: date))"
        }
        if calendar.isDateInYesterday(date) {
            return "昨天 \(shortTimeText(for: date))"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        if calendar.component(.year, from: date) == calendar.component(.year, from: Date()) {
            formatter.dateFormat = "M月d日 EEEE HH:mm"
        } else {
            formatter.dateFormat = "yyyy年M月d日 EEEE HH:mm"
        }
        return formatter.string(from: date)
    }

    private func shortTimeText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func reloadFromStore() {
        turns = ChatHistoryStore.load(from: bolaDefaults)
    }

    private func deleteTurn(_ turn: ChatTurn) {
        let updated = turns.filter { $0.id != turn.id }
        ChatHistoryStore.save(updated, to: bolaDefaults)
        reloadFromStore()
        if pendingTurn?.id == turn.id {
            pendingTurn = nil
        }
        if failedTurn?.id == turn.id {
            failedTurn = nil
            failedPresetText = nil
        }
    }

    private func addDiaryEntry(from turn: ChatTurn) {
        BolaDiaryStore.append(
            BolaDiaryEntry(
                title: String(turn.content.trimmingCharacters(in: .whitespacesAndNewlines).prefix(8)).isEmpty
                    ? "时光片段"
                    : String(turn.content.trimmingCharacters(in: .whitespacesAndNewlines).prefix(8)),
                summary: turn.content,
                emoji: turn.role == "user" ? "📝" : "🤖",
                sourceText: turn.content
            )
        )
        showMemoryToast("Bola 已记入时光日记")
    }

    private func addLifeRecord(from turn: ChatTurn) {
        var records = LifeRecordListStore.load(from: bolaDefaults)
        records.append(
            LifeRecordCard(
                kind: .event,
                title: turn.role == "user" ? "聊天记录" : "Bola 的提醒",
                subtitle: turn.content,
                detailNote: turn.content,
                iconEmoji: turn.role == "user" ? "💬" : "🤖"
            )
        )
        LifeRecordListStore.save(records, to: bolaDefaults)
        showMemoryToast("Bola 已整理成生活卡片")
    }

    private func beginMemoryCaptureWindow() {
        memoryCaptureWindowEndsAt = Date().addingTimeInterval(20)
        didCaptureDiaryInWindow = false
        didCaptureLifeRecordInWindow = false
    }

    private func markMemoryCapture(diary: Bool, lifeRecord: Bool) {
        guard let endsAt = memoryCaptureWindowEndsAt, Date() <= endsAt else { return }
        didCaptureDiaryInWindow = didCaptureDiaryInWindow || diary
        didCaptureLifeRecordInWindow = didCaptureLifeRecordInWindow || lifeRecord
        if didCaptureDiaryInWindow && didCaptureLifeRecordInWindow {
            showMemoryToast("Bola 已记入时光日记和生活卡片")
        } else if didCaptureDiaryInWindow {
            showMemoryToast("Bola 已记入时光日记")
        } else if didCaptureLifeRecordInWindow {
            showMemoryToast("Bola 已整理成生活卡片")
        }
    }

    private func showMemoryToast(_ text: String) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            memoryToastText = text
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
            guard memoryToastText == text else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                memoryToastText = nil
            }
        }
    }

    private func dismissKeyboard() {
        isInputFocused = false
    }

    private func refreshLLMConfiguration() {
        let key = KeychainHelper.get(service: LLMKeychain.service, account: LLMKeychain.accountAPIKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let devKey = LocalLLMDevSecrets.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        isLLMConfigured = !key.isEmpty || !devKey.isEmpty
    }

    private func toggleVoiceInput() {
        if isRecordingVoice {
            finishVoiceInput()
        } else {
            beginVoiceInput()
        }
    }

    private func beginVoiceInput() {
        guard canUseChatControls else { return }
        errorText = nil
        isPreparingVoice = true
        voiceInputPrefix = input.trimmingCharacters(in: .whitespacesAndNewlines)
        IOSChatSpeechCapture.shared.requestAuthorization { allowed in
            isPreparingVoice = false
            guard allowed else {
                errorText = "需要允许麦克风与语音识别权限，才能语音输入。"
                return
            }
            do {
                try IOSChatSpeechCapture.shared.startListening { partial in
                    input = combinedVoiceInput(partial)
                }
                isRecordingVoice = true
                startVoiceWaveAnimation()
            } catch {
                errorText = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
                cancelVoiceInput()
            }
        }
    }

    private func finishVoiceInput() {
        let transcript = IOSChatSpeechCapture.shared.stopAndFinalize()
        isRecordingVoice = false
        voiceWavePhase = false
        if transcript.isEmpty {
            if input.trimmingCharacters(in: .whitespacesAndNewlines) == voiceInputPrefix {
                errorText = "没有识别到语音，再试一次吧。"
            }
        } else {
            input = combinedVoiceInput(transcript)
        }
        voiceInputPrefix = ""
    }

    private func cancelVoiceInput() {
        IOSChatSpeechCapture.shared.cancel()
        isRecordingVoice = false
        isPreparingVoice = false
        voiceWavePhase = false
        voiceInputPrefix = ""
    }

    private func startVoiceWaveAnimation() {
        voiceWavePhase = false
        withAnimation(.easeInOut(duration: 0.58).repeatForever(autoreverses: true)) {
            voiceWavePhase = true
        }
    }

    private func combinedVoiceInput(_ transcript: String) -> String {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !voiceInputPrefix.isEmpty else { return text }
        guard !text.isEmpty else { return voiceInputPrefix }
        return "\(voiceInputPrefix) \(text)"
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
        guard dialogueCaps.canDialogue else { return }
        guard isLLMConfigured else { return }
        guard !isRecordingVoice else { return }

        await MainActor.run {
            errorText = nil
            isLoading = true
            memoryToastText = nil
            pendingTurn = ChatTurn(role: "user", content: text)
            failedTurn = nil
            failedPresetText = nil
            hasUserScrolledHistory = false
            showJumpToLatest = false
            beginMemoryCaptureWindow()
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
                pendingTurn = nil
                failedTurn = nil
                failedPresetText = nil
                beginMemoryCaptureWindow()
            }
        } catch {
            await MainActor.run {
                errorText = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
                isLoading = false
                failedTurn = pendingTurn
                failedPresetText = text
                pendingTurn = nil
            }
        }
    }
}

private struct ChatHistoryCalendarSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedDate: Date

    let turns: [ChatTurn]
    let onJumpToDate: (Date) -> Void

    @State private var visibleMonth = Calendar.current.startOfDay(for: Date())

    private let weekdaySymbols = ["日", "一", "二", "三", "四", "五", "六"]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                monthHeader
                weekdayHeader
                calendarGrid
                Text(selectedDateHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(18)
            .background(BolaTheme.backgroundGrouped)
            .navigationTitle("聊天日历")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        if hasChat(on: selectedDate) {
                            onJumpToDate(selectedDate)
                        } else {
                            dismiss()
                        }
                    }
                }
            }
            .onAppear {
                visibleMonth = monthStart(for: selectedDate)
            }
        }
    }

    private var monthHeader: some View {
        HStack {
            Button {
                moveMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)

            Spacer()

            Text(monthTitle(for: visibleMonth))
                .font(.headline.weight(.bold))

            Spacer()

            Button {
                moveMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }

    private var weekdayHeader: some View {
        LazyVGrid(columns: calendarColumns, spacing: 8) {
            ForEach(weekdaySymbols, id: \.self) { day in
                Text(day)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var calendarGrid: some View {
        LazyVGrid(columns: calendarColumns, spacing: 12) {
            ForEach(Array(monthCells.enumerated()), id: \.offset) { _, date in
                if let date {
                    dayButton(for: date)
                } else {
                    Color.clear
                        .frame(height: 38)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }

    private func dayButton(for date: Date) -> some View {
        let hasChat = hasChat(on: date)
        let isSelected = Calendar.current.isDate(date, inSameDayAs: selectedDate)

        return Button {
            selectedDate = date
        } label: {
            Text("\(Calendar.current.component(.day, from: date))")
                .font(.subheadline.weight(hasChat ? .bold : .medium))
                .foregroundStyle(hasChat ? Color.black : Color.primary.opacity(0.72))
                .frame(width: 38, height: 38)
                .background(
                    Circle()
                        .fill(hasChat ? BolaTheme.accent : Color.clear)
                )
                .overlay(
                    Circle()
                        .stroke(isSelected ? Color.black.opacity(0.72) : Color.clear, lineWidth: 1.4)
                )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    private var selectedDateHint: String {
        hasChat(on: selectedDate)
            ? "这天有聊天记录，点完成跳过去。"
            : "有聊天的日期会显示主题色圆形。"
    }

    private var calendarColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)
    }

    private var monthCells: [Date?] {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: visibleMonth),
              let days = calendar.range(of: .day, in: .month, for: visibleMonth) else {
            return []
        }
        let firstWeekday = calendar.component(.weekday, from: interval.start)
        let leadingEmptyCount = max(0, firstWeekday - 1)
        let dates = days.compactMap { day -> Date? in
            calendar.date(byAdding: .day, value: day - 1, to: interval.start)
        }
        return Array(repeating: nil, count: leadingEmptyCount) + dates
    }

    private func hasChat(on date: Date) -> Bool {
        turns.contains { Calendar.current.isDate($0.createdAt, inSameDayAs: date) }
    }

    private func moveMonth(by value: Int) {
        guard let next = Calendar.current.date(byAdding: .month, value: value, to: visibleMonth) else { return }
        visibleMonth = monthStart(for: next)
    }

    private func monthStart(for date: Date) -> Date {
        Calendar.current.dateInterval(of: .month, for: date)?.start ?? date
    }

    private func monthTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年 M月"
        return formatter.string(from: date)
    }
}
