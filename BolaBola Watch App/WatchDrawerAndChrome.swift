//
//  WatchDrawerAndChrome.swift
//  主界面底栏：麦克风 + 横条（点开面板 Sheet）；面板 / 提醒 / 设置 与系统 Sheet 一致
//

import SwiftUI

// MARK: - 底部：麦克风 + 横条（点按打开面板，与「提醒」页同为全屏 Sheet）

struct WatchBottomChromeToolbar: View {
    static let estimatedChromeHeight: CGFloat = 52

    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var viewModel: PetViewModel
    var onOpenPanel: () -> Void

    @State private var micEngaged = false

    private let controlDiameter: CGFloat = 38

    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Spacer(minLength: 0)
                micControl
                    .frame(width: controlDiameter, height: controlDiameter)
                Spacer(minLength: 0)
            }

            pullHandleBar
        }
        .padding(.horizontal, 8)
        .padding(.top, 2)
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

    /// 与底栏同风格的圆形触控区（类似系统控件上的磨砂凸台）
    private func chromeAccessoryCircle<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack {
            Circle()
                .fill(.thinMaterial)
            Circle()
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
            content()
        }
    }

    private var micControl: some View {
        chromeAccessoryCircle {
            Image(systemName: "mic.fill")
                .font(.system(size: 16, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
        }
        .scaleEffect(micEngaged ? 0.92 : 1.0)
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: micEngaged)
        .contentShape(Circle())
        // 高优先级，避免与宠物区域手势抢触控
        .highPriorityGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !micEngaged else { return }
                    guard BolaSpeechCapture.isSpeechSupported else {
                        viewModel.showDialogue("手表系统暂不支持本地语音识别，请用 iPhone 端 Bola 对话（后续可扩展）。", duration: 5)
                        return
                    }
                    micEngaged = true
                    BolaSpeechCapture.shared.requestSpeechAuthorization { ok in
                        guard ok else {
                            micEngaged = false
                            viewModel.showDialogue("需要语音识别权限哦。", duration: 4)
                            return
                        }
                        viewModel.beginVoiceListeningSession()
                        BolaSpeechCapture.shared.startListening()
                    }
                }
                .onEnded { _ in
                    guard micEngaged else { return }
                    micEngaged = false
                    BolaSpeechCapture.shared.stopAndFinalize { text in
                        if text.isEmpty {
                            viewModel.cancelVoiceSession()
                            return
                        }
                        viewModel.setVoiceThinkingEmotion()
                        Task {
                            let v = Int(viewModel.companionValue.rounded())
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
        )
        .accessibilityLabel("按住说话")
        .accessibilityAddTraits(.allowsDirectInteraction)
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
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

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
                    }
                }
                .padding(.horizontal, 6)
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
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
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
                            Button(role: .destructive) {
                                reminders.removeAll { $0.id == r.id }
                                saveAndSync()
                            }
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
                Section("每日总结") {
                    Toggle("启用", isOn: $digestEnabled)
                    Stepper("小时 \(digestHour)", value: $digestHour, in: 0 ... 23)
                    Stepper("分钟 \(digestMinute)", value: $digestMinute, in: 0 ... 59, step: 5)
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
