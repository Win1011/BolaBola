//
//  WatchDrawerAndChrome.swift
//  主界面底栏：麦克风 + 横条（点开面板 Sheet）；面板 / 提醒 / 设置 与系统 Sheet 一致
//

import SwiftUI
import os

private let watchChromeVoiceLog = Logger(subsystem: "com.gathxr.BolaBola", category: "WatchVoice")

/// watchOS 26+ → Liquid Glass；低版本 → ultraThinMaterial 圆角矩形
private struct WatchGlassRoundedRect12: ViewModifier {
    private let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

    func body(content: Content) -> some View {
        if #available(watchOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content
                .background { shape.fill(.ultraThinMaterial) }
                .clipShape(shape)
        }
    }
}

// MARK: - 底部：麦克风 + 横条（点按打开面板，与「提醒」页同为全屏 Sheet）

struct WatchBottomChromeToolbar: View {
    /// 含麦克风 + 可选录音指示点 + 横条占位
    static let estimatedChromeHeight: CGFloat = 60

    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var viewModel: PetViewModel
    var onOpenPanel: () -> Void

    @State private var isRecording = false
    @State private var isAwaitingMicPermission = false

    private let controlDiameter: CGFloat = 38
    /// 录音中指示（#E5FF00）
    private let recordingIndicatorColor = Color(red: 229 / 255, green: 1, blue: 0)

    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Spacer(minLength: 0)
                micControl
                Spacer(minLength: 0)
            }
            .offset(y: -6)

            pullHandleBar
                .padding(.top, 8)
        }
        .padding(.horizontal, 10)
        .padding(.top, 0)
        .padding(.bottom, 0)
        .frame(maxWidth: .infinity)
    }

    /// 普通纯色横条：居中短条。opacity(0.1) 在表盘/OLED 上几乎与背景融为一体，故用略高但仍偏淡的值。
    private var pullHandleBar: some View {
        HStack {
            Spacer(minLength: 0)
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.28) : Color.black.opacity(0.22))
                .frame(width: 46, height: 3)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .accessibilityLabel("打开面板")
        .accessibilityAddTraits(.isButton)
        .onTapGesture(perform: onOpenPanel)
    }

    /// Liquid Glass 圆形触控区（watchOS 26+）；低版本回退磨砂圆
    @ViewBuilder
    private func chromeAccessoryCircle<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        let core = ZStack {
            content()
        }
        .frame(width: controlDiameter, height: controlDiameter)

        if #available(watchOS 26.0, *) {
            core.glassEffect(.regular, in: Circle())
        } else {
            core.background {
                Circle().fill(.ultraThinMaterial)
            }
            .clipShape(Circle())
        }
    }

    private var micControl: some View {
        VStack(spacing: 5) {
            if isRecording {
                Circle()
                    .fill(recordingIndicatorColor)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
            }

            chromeAccessoryCircle {
                Image(systemName: "mic.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
            }
            .contentShape(Circle())
            .highPriorityGesture(TapGesture().onEnded { toggleMicTap() })
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isRecording ? "录音中，再点一次结束" : "点按开始录音")
        .accessibilityAddTraits(.allowsDirectInteraction)
    }

    private func toggleMicTap() {
        guard WatchSpeechRelayCapture.isSupported else {
            watchChromeVoiceLog.error("toggleMic: WatchSpeechRelayCapture not supported (unexpected)")
            return
        }
        if isRecording {
            watchChromeVoiceLog.info("toggleMic: stop → upload/ASR pipeline")
            isRecording = false
            guard let url = WatchSpeechRelayRecorder.shared.stopRecording() else {
                watchChromeVoiceLog.error("toggleMic: stopRecording returned nil")
                viewModel.cancelVoiceSession()
                viewModel.showDialogue("录音未成功，请再试。", duration: 4)
                return
            }
            viewModel.setVoiceThinkingEmotion()
            let v = Int(viewModel.companionValue.rounded())
            Task {
                do {
                    let reply = try await ConversationService.replyToUserFromRecordedAudio(fileURL: url, companionValue: v)
                    watchChromeVoiceLog.info("toggleMic: cloud path OK")
                    await MainActor.run {
                        viewModel.playVoiceAssistantReply(reply)
                    }
                    try? FileManager.default.removeItem(at: url)
                } catch {
                    let err = error
                    watchChromeVoiceLog.error("toggleMic: cloud path failed \(String(describing: err), privacy: .public)")
                    let fallbackOk = await MainActor.run { () -> Bool in
                        watchChromeVoiceLog.info("toggleMic: trying iPhone ASR fallback (transferFile)")
                        return WatchSpeechRelayCapture.shared.transferExistingFileForPhoneTranscription(url: url) { text in
                            Task { @MainActor in
                                if text.isEmpty {
                                    watchChromeVoiceLog.error("toggleMic: iPhone fallback empty transcript")
                                    viewModel.cancelVoiceSession()
                                    let msg = (err as? LocalizedError)?.errorDescription ?? "语音未识别"
                                    viewModel.showDialogue(msg, duration: 6)
                                } else {
                                    watchChromeVoiceLog.info("toggleMic: iPhone fallback OK chars=\(text.count, privacy: .public)")
                                    viewModel.setVoiceThinkingEmotion()
                                    Task {
                                        let reply: String
                                        do {
                                            reply = try await ConversationService.replyToUser(utterance: text, companionValue: v)
                                        } catch {
                                            reply = ConversationService.templateReply(utterance: text, companionValue: v)
                                        }
                                        await MainActor.run {
                                            viewModel.playVoiceAssistantReply(reply)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    if !fallbackOk {
                        watchChromeVoiceLog.error("toggleMic: iPhone fallback not available (WC inactive or no companion app)")
                        await MainActor.run {
                            viewModel.cancelVoiceSession()
                            viewModel.showDialogue(
                                (err as? LocalizedError)?.errorDescription ?? "语音未识别。可打开 iPhone 上的 Bola 再试。",
                                duration: 6
                            )
                        }
                        try? FileManager.default.removeItem(at: url)
                    }
                }
            }
            return
        }
        guard !isAwaitingMicPermission else {
            watchChromeVoiceLog.info("toggleMic: ignored (still awaiting mic permission)")
            return
        }
        watchChromeVoiceLog.info("toggleMic: request start recording")
        isAwaitingMicPermission = true
        WatchSpeechRelayRecorder.shared.requestMicPermission { ok in
            isAwaitingMicPermission = false
            guard ok else {
                watchChromeVoiceLog.error("toggleMic: mic permission denied")
                viewModel.showDialogue("需要麦克风权限哦。", duration: 4)
                return
            }
            do {
                try WatchSpeechRelayRecorder.shared.startRecording()
                isRecording = true
                viewModel.beginVoiceListeningSession()
                watchChromeVoiceLog.info("toggleMic: recording UI active")
            } catch {
                watchChromeVoiceLog.error("toggleMic: startRecording threw \(error.localizedDescription, privacy: .public)")
                viewModel.showDialogue("无法开始录音。", duration: 4)
            }
        }
    }
}

// MARK: - 面板 Sheet（布局与 WatchRemindersListView 一致：NavigationStack + 完成）

struct WatchPanelSheetView: View {
    @ObservedObject var viewModel: PetViewModel
    @Environment(\.dismiss) private var dismiss
    @Binding var showRemindersSheet: Bool
    @Binding var showSettingsSheet: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("调试陪伴值")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)

                    HStack(alignment: .center, spacing: 3) {
                        Button {
                            viewModel.adjustCompanionValueManual(by: -2)
                        } label: {
                            Image(systemName: "minus")
                                .font(.system(size: 8, weight: .semibold))
                                .frame(minWidth: 28, minHeight: 22)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text("陪伴值")
                                Text("\(Int(viewModel.companionValue.rounded()))")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            .font(.caption2)

                            ProgressView(value: viewModel.companionValue / 100.0)
                                .frame(height: 3)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Button {
                            viewModel.adjustCompanionValueManual(by: 2)
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 8, weight: .semibold))
                                .frame(minWidth: 28, minHeight: 22)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .modifier(WatchGlassRoundedRect12())

                    Button {
                        viewModel.enterEatingState()
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "fork.knife")
                                .font(.caption2)
                            Text("调试吃东西")
                                .font(.caption2.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        panelCard(title: "心率", subtitle: "\(viewModel.latestHeartRateText) BPM") {
                            viewModel.refreshLatestHeartRateForDisplay()
                        }
                        panelCard(title: "提醒", subtitle: "管理") {
                            dismiss()
                            DispatchQueue.main.async {
                                showRemindersSheet = true
                            }
                        }
                        panelCard(title: "设置", subtitle: "总结") {
                            dismiss()
                            DispatchQueue.main.async {
                                showSettingsSheet = true
                            }
                        }
                        NavigationLink {
                            WatchChatHistoryView()
                        } label: {
                            panelCardLabel(title: "对话记录", subtitle: "与 Bola")
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
            .navigationTitle("面板")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func panelCard(title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            panelCardLabel(title: title, subtitle: subtitle)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func panelCardLabel(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .padding(8)
        .modifier(WatchGlassRoundedRect12())
    }
}

// MARK: - 提醒列表（手表）

struct WatchRemindersListView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var reminders = ReminderListStore.load()
    @State private var titleDraft = ""
    @State private var bodyDraft = ""

    var body: some View {
        NavigationStack {
            List {
                Section("快速添加") {
                    TextField("标题", text: $titleDraft)
                    TextField("通知内容", text: $bodyDraft)
                    Button("添加间隔提醒 2h") {
                        addInterval(hours: 2)
                    }
                    .disabled(titleDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Section("已有") {
                    ForEach(reminders) { r in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.title).font(.caption.weight(.semibold))
                            Text(r.notificationBody).font(.caption2).foregroundStyle(.secondary)
                        }
                        .swipeActions {
                            Button {
                                reminders.removeAll { $0.id == r.id }
                                saveAndSync()
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                            .tint(.red)
                        }
                    }
                }
            }
            .navigationTitle("提醒")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func addInterval(hours: Int) {
        let t = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = bodyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "到点啦，看看 Bola～"
            : bodyDraft
        let r = BolaReminder(title: t, notificationBody: b, schedule: .interval(TimeInterval(hours * 3600)))
        reminders.append(r)
        titleDraft = ""
        bodyDraft = ""
        saveAndSync()
    }

    private func saveAndSync() {
        ReminderListStore.save(reminders)
        Task {
            await BolaReminderUNScheduler.sync(reminders: reminders)
        }
    }
}

// MARK: - 设置（每日总结）

struct WatchSettingsView: View {
    @ObservedObject var viewModel: PetViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var digestEnabled = false
    @State private var digestHour = 21
    @State private var digestMinute = 0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("启用", isOn: $digestEnabled)
                        .font(.caption2)
                    Stepper("小时 \(digestHour)", value: $digestHour, in: 0 ... 23)
                        .font(.caption2)
                    Stepper("分钟 \(digestMinute)", value: $digestMinute, in: 0 ... 59, step: 5)
                        .font(.caption2)
                    Button("保存并刷新通知") {
                        let c = DailyDigestConfig(
                            isEnabled: digestEnabled,
                            hour: digestHour,
                            minute: digestMinute,
                            includeHealthSummaryInPrompt: false
                        )
                        DailyDigestStore.save(c)
                        Task {
                            await DailyDigestRefresh.regenerateIfNeeded(companionValue: Int(viewModel.companionValue.rounded()))
                            await MainActor.run { dismiss() }
                        }
                    }
                    .font(.caption2)
                } header: {
                    Text("每日总结")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("设置")
            .onAppear {
                let c = DailyDigestStore.load()
                digestEnabled = c.isEnabled
                digestHour = c.hour
                digestMinute = c.minute
            }
        }
    }
}
