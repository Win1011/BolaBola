//
//  IOSSettingsView.swift
//

import AuthenticationServices
import Combine
import HealthKit
import SwiftUI
import UIKit
import UserNotifications

extension Notification.Name {
    static let bolaHealthDataRefreshRequested = Notification.Name("bolaHealthDataRefreshRequested")
}

/// 设置列表（由根 Tab 的 `NavigationStack` 推进；`includeDismissToolbar` 仅在不使用系统返回键的临时呈现场景为 `true`）。
struct IOSSettingsListView: View {
    var includeDismissToolbar: Bool = true

    @Environment(\.dismiss) private var dismiss
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var showHelpCenter = false
    @State private var selectedPersonality = BolaPersonalitySelectionStore.validated()
    @State private var companionNameDraft = CompanionDisplayNameStore.resolved()
    @State private var isAuthenticated = BolaAuthService.isAuthenticated
    @State private var userDisplayNameCache = UserDefaults.standard.string(forKey: "bola_apple_sign_in_full_name_v1") ?? ""

    private var bolaDisplayName: String {
        companionNameDraft.isEmpty ? "Bola" : companionNameDraft
    }

    var body: some View {
        List {
            // MARK: - 我的（用户账户）
            Section {
                NavigationLink {
                    IOSAccountSettingsPage()
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(BolaTheme.accent)
                                .frame(width: 44, height: 44)
                            if isAuthenticated, !userDisplayNameCache.isEmpty {
                                Text(String(userDisplayNameCache.prefix(1)))
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.black)
                            } else {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundStyle(.black)
                            }
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            if isAuthenticated {
                                Text(userDisplayNameCache.isEmpty ? "已登录" : userDisplayNameCache)
                                    .font(.headline)
                                Text("Apple 账户 · 点击管理")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("未登录")
                                    .font(.headline)
                                Text("登录后可使用 AI 对话")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("我的")
            }

            // MARK: - 我的 Bola（伙伴设置）
            Section {
                NavigationLink {
                    IOSBolaProfileSettingsPage(
                        companionNameDraft: $companionNameDraft,
                        selectedPersonality: $selectedPersonality
                    )
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(BolaTheme.accent)
                                .frame(width: 44, height: 44)
                            Image(systemName: "pawprint.fill")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(.black)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(bolaDisplayName)
                                .font(.headline)
                            Text("你的专属伙伴 · 点击设置")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("我的\(bolaDisplayName)")
            }

            // MARK: - 功能入口（卡片行）
            Section {
                settingsCard(icon: "bell.badge.fill",                    title: "提醒",          subtitle: "喝水、站立、睡眠、餐食") { IOSRemindersSettingsPage() }
                settingsCard(icon: "bell.and.waves.left.and.right.fill", title: "通知与健康权限", subtitle: notificationStatusLabel) { IOSNotificationsAndHealthPage(notificationStatus: $notificationStatus, onRefresh: refreshNotificationStatus) }
                settingsCard(icon: "hand.raised.fill",                   title: "数据与隐私",    subtitle: "本地存储 · 清除数据") { IOSPrivacySettingsPage() }
                settingsCard(icon: "info.circle.fill",                   title: "关于 BolaBola", subtitle: appVersionString) { IOSAboutPage(showHelpCenter: $showHelpCenter) }
                settingsCard(icon: "wrench.and.screwdriver.fill",        title: "开发者工具",    subtitle: "调试日志 · 数据重置") { IOSDebugSettingsView() }
            }
        }
        .sheet(isPresented: $showHelpCenter) {
            IOSHelpCenterView()
                .presentationDragIndicator(.visible)
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if includeDismissToolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await refreshNotificationStatus()
            refreshCompanionNameDraft()
            refreshPersonalitySelection()
        }
        .onAppear {
            Task { await refreshNotificationStatus() }
            refreshCompanionNameDraft()
            refreshPersonalitySelection()
        }
        .onReceive(NotificationCenter.default.publisher(for: .bolaGrowthStateDidChange)) { _ in
            refreshPersonalitySelection()
        }
        .onReceive(NotificationCenter.default.publisher(for: .bolaCompanionDisplayNameDidChange)) { _ in
            refreshCompanionNameDraft()
        }
        .onReceive(NotificationCenter.default.publisher(for: .bolaLLMConfigurationDidChange)) { _ in
            isAuthenticated = BolaAuthService.isAuthenticated
            userDisplayNameCache = UserDefaults.standard.string(forKey: "bola_apple_sign_in_full_name_v1") ?? ""
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func settingsCard<Dest: View>(
        icon: String,
        title: String, subtitle: String,
        @ViewBuilder destination: () -> Dest
    ) -> some View {
        NavigationLink(destination: destination()) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(BolaTheme.accent)
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.black)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 4)
        }
    }

    private func refreshPersonalitySelection() {
        selectedPersonality = BolaPersonalitySelectionStore.validated()
    }

    private func refreshCompanionNameDraft() {
        companionNameDraft = CompanionDisplayNameStore.resolved()
    }

    private var notificationStatusLabel: String {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral: return "已开启"
        case .denied: return "已拒绝"
        case .notDetermined: return "尚未询问"
        @unknown default: return "未知"
        }
    }

    private var appVersionString: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        return b.isEmpty ? v : "\(v) (\(b))"
    }

    @MainActor
    private func refreshNotificationStatus() async {
        let s = await UNUserNotificationCenter.current().notificationSettings()
        notificationStatus = s.authorizationStatus
    }
}

// MARK: - Account Settings Page

struct IOSAccountSettingsPage: View {
    @State private var isSigningOut = false
    @State private var isAuthenticatingWithServer = false
    @State private var signInErrorMessage: String?
    @State private var isAuthenticated = BolaAuthService.isAuthenticated

    private var userDisplayName: String {
        UserDefaults.standard.string(forKey: "bola_apple_sign_in_full_name_v1") ?? ""
    }
    private var userEmail: String {
        UserDefaults.standard.string(forKey: "bola_apple_sign_in_email_v1") ?? ""
    }

    var body: some View {
        List {
            if isAuthenticated {
                Section {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(Color(uiColor: .systemGray5))
                                .frame(width: 44, height: 44)
                            if !userDisplayName.isEmpty {
                                Text(String(userDisplayName.prefix(1)))
                                    .font(.title3.weight(.semibold))
                            } else {
                                Image(systemName: "person.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            if !userDisplayName.isEmpty {
                                Text(userDisplayName).font(.headline)
                            }
                            if !userEmail.isEmpty {
                                Text(userEmail).font(.caption).foregroundStyle(.secondary)
                            } else {
                                Text("Apple 账户").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)

                    Button("退出登录", role: .destructive) {
                        isSigningOut = true
                    }
                    .disabled(isSigningOut)
                } header: {
                    Text("账户")
                } footer: {
                    Text("退出登录后 AI 对话将需要手动配置 API Key 才能继续使用。")
                }

                Section {
                    NavigationLink {
                        IOSAPISettingsPage()
                    } label: {
                        Label("对话 API", systemImage: "key.horizontal.fill")
                    }
                } header: {
                    Text("连接")
                } footer: {
                    Text("密钥与中转地址保存在本机钥匙串，并可同步到 Apple Watch。")
                }
            } else {
                Section {
                    SignInWithAppleButton(.signIn) { request in
                        signInErrorMessage = nil
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { result in
                        handleAppleSignIn(result)
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)

                    if isAuthenticatingWithServer {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("正在连接服务器…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let signInErrorMessage {
                        Text(signInErrorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("登录")
                } footer: {
                    Text("登录后可使用 AI 对话，无需手动配置 API Key。你的健康数据和日记不会上传。")
                }

                Section {
                    NavigationLink {
                        IOSAPISettingsPage()
                    } label: {
                        Label("对话 API", systemImage: "key.horizontal.fill")
                    }
                } header: {
                    Text("连接")
                } footer: {
                    Text("手动填写 API Key 与中转地址，保存在本机钥匙串并同步到 Apple Watch。")
                }
            }
        }
        .navigationTitle("我的账户")
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(NotificationCenter.default.publisher(for: .bolaLLMConfigurationDidChange)) { _ in
            isAuthenticated = BolaAuthService.isAuthenticated
        }
        .onChange(of: isSigningOut) { _, signingOut in
            guard signingOut else { return }
            Task {
                try? await BolaAuthService.logout()
                BolaAppleSignInState.reset()
                await MainActor.run {
                    isSigningOut = false
                    isAuthenticated = false
                    NotificationCenter.default.post(name: .bolaLLMConfigurationDidChange, object: nil)
                }
            }
        }
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let identityToken = String(data: tokenData, encoding: .utf8), !identityToken.isEmpty else {
                signInErrorMessage = "Apple 登录没有返回有效凭证。"
                return
            }
            BolaAppleSignInState.markSignedIn(
                userIdentifier: credential.user,
                fullName: credential.fullName,
                email: credential.email
            )
            isAuthenticatingWithServer = true
            signInErrorMessage = nil
            Task {
                do {
                    _ = try await BolaAuthService.signInWithApple(
                        identityToken: identityToken,
                        device: DeviceInfo(deviceId: credential.user, platform: "ios")
                    )
                    await MainActor.run {
                        isAuthenticatingWithServer = false
                        isAuthenticated = true
                        NotificationCenter.default.post(name: .bolaLLMConfigurationDidChange, object: nil)
                    }
                } catch {
                    await MainActor.run {
                        isAuthenticatingWithServer = false
                        signInErrorMessage = "服务器登录失败：\(error.localizedDescription)"
                    }
                }
            }
        case .failure(let error):
            if let e = error as? ASAuthorizationError, e.code == .canceled { return }
            signInErrorMessage = "Apple 登录未完成，请重试。"
        }
    }
}

// MARK: - Bola Profile Settings Page

struct IOSBolaProfileSettingsPage: View {
    @Binding var companionNameDraft: String
    @Binding var selectedPersonality: BolaPersonalitySelection
    @FocusState private var isNameFocused: Bool

    var body: some View {
        List {
            Section {
                TextField("Bola", text: $companionNameDraft)
                    .focused($isNameFocused)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .onChange(of: companionNameDraft) { _, newValue in
                        let sanitized = CompanionDisplayNameStore.sanitized(newValue)
                        if sanitized != newValue {
                            companionNameDraft = sanitized
                        }
                    }
                    .onSubmit { saveCompanionName() }
                HStack {
                    Button("保存名字") { saveCompanionName() }
                    Spacer()
                    Button("恢复 Bola", role: .destructive) { resetCompanionName() }
                }
            } header: {
                Text("伙伴名字")
            } footer: {
                Text("最多 8 个字。这个名字会用于聊天、生活、成长、提醒和手表端可见文案。品牌名 BolaBola 会保持不变。")
            }

            Section {
                HStack {
                    Text("当前性格")
                    Spacer()
                    Text(personalityStatusText)
                        .foregroundStyle(.secondary)
                }
                if isTsundereUnlocked {
                    Picker("性格", selection: $selectedPersonality) {
                        Text(BolaPersonalitySelection.default.displayName).tag(BolaPersonalitySelection.default as BolaPersonalitySelection)
                        Text(BolaPersonalitySelection.tsundere.displayName).tag(BolaPersonalitySelection.tsundere as BolaPersonalitySelection)
                    }
                    .pickerStyle(.segmented)
                }
            } header: {
                Text("性格")
            } footer: {
                Text(isTsundereUnlocked
                     ? "已解锁傲娇性格。切到傲娇后会同步影响 iPhone 与手表对话。"
                     : "Lv.5 解锁傲娇性格。升级后可在此切换。")
            }
        }
        .navigationTitle("Bola 设置")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: selectedPersonality) { _, newValue in
            applyPersonalitySelection(newValue)
        }
        .onReceive(NotificationCenter.default.publisher(for: .bolaGrowthStateDidChange)) { _ in
            selectedPersonality = BolaPersonalitySelectionStore.validated()
        }
    }

    private var isTsundereUnlocked: Bool { BolaPersonalitySelectionStore.isTsundereUnlocked() }
    private var personalityStatusText: String {
        isTsundereUnlocked ? selectedPersonality.displayName : "未解锁（Lv.5）"
    }

    private func saveCompanionName() {
        companionNameDraft = CompanionDisplayNameStore.save(companionNameDraft)
        BolaWCSessionCoordinator.shared.pushLocalCompanionTowardWatchFromDefaults()
        Task { await DailyDigestUNScheduler.sync(config: DailyDigestStore.load()) }
    }

    private func resetCompanionName() {
        CompanionDisplayNameStore.clear()
        companionNameDraft = CompanionDisplayNameStore.resolved()
        BolaWCSessionCoordinator.shared.pushLocalCompanionTowardWatchFromDefaults()
        Task { await DailyDigestUNScheduler.sync(config: DailyDigestStore.load()) }
    }

    private func applyPersonalitySelection(_ selection: BolaPersonalitySelection) {
        BolaPersonalitySelectionStore.save(selection)
        let stored = BolaPersonalitySelectionStore.validated()
        if selectedPersonality != stored { selectedPersonality = stored }
        BolaWCSessionCoordinator.shared.pushLocalCompanionTowardWatchFromDefaults()
    }
}

// MARK: - Notifications & Health Page

struct IOSNotificationsAndHealthPage: View {
    @Binding var notificationStatus: UNAuthorizationStatus
    let onRefresh: () async -> Void

    var body: some View {
        List {
            Section {
                HStack {
                    Text("通知权限")
                    Spacer()
                    Text(statusLabel)
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("前往系统设置", systemImage: "gear")
                        .foregroundStyle(.primary)
                }
                if notificationStatus == .notDetermined {
                    Button {
                        Task { @MainActor in
                            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                            await onRefresh()
                        }
                    } label: {
                        Label("请求通知授权", systemImage: "bell.badge")
                            .foregroundStyle(.primary)
                    }
                }
            } header: {
                Text("通知")
            } footer: {
                Text("Bola 的提醒和每日摘要依赖通知权限。如已拒绝，需在系统设置里手动开启。")
            }

            Section {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("前往系统设置", systemImage: "gear")
                        .foregroundStyle(.primary)
                }
                Button {
                    UserDefaults.standard.set(true, forKey: IOSHealthHabitAnalysisModel.healthReadPromptCompletedKey)
                    NotificationCenter.default.post(name: .bolaHealthDataRefreshRequested, object: nil)
                } label: {
                    Label("已改权限，立即重新读取", systemImage: "arrow.clockwise")
                        .foregroundStyle(.primary)
                }
            } header: {
                Text("健康数据")
            } footer: {
                Text("在「设置 › 隐私与安全性 › 健康 › BolaBola」里开启步数、心率、睡眠等权限，改完后点「立即重新读取」。")
            }
        }
        .navigationTitle("通知与健康权限")
        .navigationBarTitleDisplayMode(.inline)
        .task { await onRefresh() }
    }

    private var statusLabel: String {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral: return "已开启"
        case .denied: return "已拒绝"
        case .notDetermined: return "尚未询问"
        @unknown default: return "未知"
        }
    }
}

// MARK: - About Page

struct IOSAboutPage: View {
    @Binding var showHelpCenter: Bool

    private var appVersionString: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        return b.isEmpty ? v : "\(v) (\(b))"
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Text("应用名称")
                    Spacer()
                    Text("BolaBola").foregroundStyle(.secondary)
                }
                HStack {
                    Text("版本")
                    Spacer()
                    Text(appVersionString).foregroundStyle(.secondary).monospacedDigit()
                }
            } header: {
                Text("版本信息")
            }

            Section {
                Button {
                    showHelpCenter = true
                } label: {
                    Label("帮助中心", systemImage: "questionmark.circle")
                        .foregroundStyle(.primary)
                }
            } header: {
                Text("支持")
            }
        }
        .navigationTitle("关于 BolaBola")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Debug Settings Page

struct IOSDebugSettingsView: View {
    @ObservedObject private var debugLog = BolaDebugLog.shared
    @StateObject private var healthDiagnostics = IOSHealthDiagnosticsModel()
    @State private var growthSummary: String = ""
    @State private var confirmResetLifeRecords = false
    @State private var confirmResetGrowth = false

    var body: some View {
        List {
            // MARK: 日志
            Section {
                Toggle(isOn: $debugLog.isEnabled) {
                    Label("启用实时日志", systemImage: "doc.text.magnifyingglass")
                }
                NavigationLink {
                    IOSDebugLogSheet()
                } label: {
                    HStack {
                        Label("打开调试面板", systemImage: "ladybug")
                        Spacer()
                        Text("\(debugLog.entries.count) 条")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("日志")
            } footer: {
                Text("记录 WC 通信、宠物状态、聊天/语音同步等事件，仅保存在内存最近 500 条。关闭后立即停止写入。")
            }

            // MARK: 健康诊断
            Section {
                Button("读取当前健康原始值") {
                    Task { await healthDiagnostics.refresh() }
                }
                diagnosticRow("步数", healthDiagnostics.stepsText)
                diagnosticRow("Move", healthDiagnostics.moveText)
                diagnosticRow("锻炼", healthDiagnostics.exerciseText)
                diagnosticRow("站立", healthDiagnostics.standText)
                diagnosticRow("睡眠", healthDiagnostics.sleepText)
                if let errorText = healthDiagnostics.errorText {
                    Text(errorText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("健康数据诊断")
            } footer: {
                Text("直接从 HealthKit 读到的原始值。如果这里也都是 0，说明该类健康数据当前没有可读样本。")
                    .font(.caption)
            }

            // MARK: 成长调试
            Section {
                HStack {
                    Text("等级 / XP")
                    Spacer()
                    Text(growthSummary)
                        .foregroundStyle(.secondary)
                        .font(.caption.monospacedDigit())
                }
                Button("+10 XP（模拟任务完成）") {
                    BolaXPEngine.grantTaskXP(); refreshGrowthSummary()
                }
                Button("+20 XP（模拟首次对话）") {
                    BolaXPEngine.completeMilestone(.firstIOSChat); refreshGrowthSummary()
                }
                Button("+100 XP（模拟陪伴满百）") {
                    BolaXPEngine.completeMilestone(.companion100); refreshGrowthSummary()
                }
                Button("等级 +1") {
                    debugLevelUpOnce()
                }
                Button("解锁所有称号词条") {
                    var state = BolaGrowthStore.load()
                    state.totalXP = max(state.totalXP, BolaLevelFormula.cumulativeXP(forLevel: 20))
                    state.completedMilestones = BolaGrowthMilestone.allCases.map(\.rawValue)
                    state.personalityType = BolaPersonalityType.tsundere.rawValue
                    BolaGrowthStore.save(state)
                    TitleUnlockManager.refreshUnlocks(state: state, currentCompanionValue: 100, maxEverCompanionValue: 100)
                    BolaWCSessionCoordinator.shared.pushLocalCompanionTowardWatchFromDefaults()
                    refreshGrowthSummary()
                }
                Button("一键完成所有每日任务") {
                    GrowthDailyTasksViewModel.shared.debugCompleteAllTasks()
                }
                Button("重置每日任务进度", role: .destructive) {
                    GrowthDailyTasksViewModel.shared.debugRefreshDailyTasks()
                }
                Button("重置等级与 XP…", role: .destructive) {
                    confirmResetGrowth = true
                }
            } header: {
                Text("成长调试")
            } footer: {
                Text("仅供调试，不影响真实健康数据。里程碑奖励为一次性，重置后可再次触发。")
            }
            .onAppear { refreshGrowthSummary() }

            // MARK: 生活记录
            Section {
                Button("恢复默认生活卡片…", role: .destructive) {
                    confirmResetLifeRecords = true
                }
            } header: {
                Text("生活记录")
            } footer: {
                Text("删除所有生活卡片，用于清理测试数据；天气会在当天再次刷新时重新生成。")
            }

            // MARK: 引导
            Section {
                Button("重新查看引导页") {
                    BolaOnboardingState.reset()
                }
            } header: {
                Text("引导")
            } footer: {
                Text("重置 onboarding 完成标记，返回主界面后会立即重新弹出引导流程。")
            }
        }
        .navigationTitle("开发者工具")
        .navigationBarTitleDisplayMode(.inline)
        .task { await healthDiagnostics.refresh(); refreshGrowthSummary() }
        .onReceive(NotificationCenter.default.publisher(for: .bolaGrowthStateDidChange)) { _ in
            refreshGrowthSummary()
        }
        .confirmationDialog(
            "将删除所有生活卡片，且无法撤销。",
            isPresented: $confirmResetLifeRecords,
            titleVisibility: .visible
        ) {
            Button("恢复默认", role: .destructive) {
                LifeRecordListStore.resetToDefaultDeck()
            }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog(
            "将清零 totalXP、里程碑、性格类型，且无法撤销。",
            isPresented: $confirmResetGrowth,
            titleVisibility: .visible
        ) {
            Button("清零等级与 XP", role: .destructive) {
                BolaGrowthStore.save(BolaGrowthState())
                BolaPersonalitySelectionStore.save(.default)
                BolaWCSessionCoordinator.shared.pushLocalCompanionTowardWatchFromDefaults()
                refreshGrowthSummary()
            }
            Button("取消", role: .cancel) {}
        }
    }

    @ViewBuilder
    private func diagnosticRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func refreshGrowthSummary() {
        let state = BolaGrowthStore.load()
        let (lvl, rem) = BolaLevelFormula.levelAndRemainder(fromTotalXP: state.totalXP)
        let next = BolaLevelFormula.xpRequired(forLevel: lvl)
        growthSummary = "Lv.\(lvl)  \(rem)/\(next) XP  (总\(state.totalXP))"
    }

    private func debugLevelUpOnce() {
        var state = BolaGrowthStore.load()
        let currentLevel = BolaLevelFormula.levelAndRemainder(fromTotalXP: state.totalXP).level
        let targetLevel = min(currentLevel + 1, BolaLevelFormula.maxLevel)
        guard targetLevel > currentLevel else { return }
        state.totalXP = max(state.totalXP, BolaLevelFormula.cumulativeXP(forLevel: targetLevel))
        if targetLevel >= 5, state.personalityType == nil {
            state.personalityType = BolaPersonalityType.tsundere.rawValue
        }
        BolaGrowthStore.save(state)
        TitleUnlockManager.refreshUnlocks(state: state, currentCompanionValue: 0)
        BolaWCSessionCoordinator.shared.pushLocalCompanionTowardWatchFromDefaults()
        refreshGrowthSummary()
    }
}

// MARK: - Settings Wrapper

/// 独立打开设置时使用的带导航栈包装（预览/深链等）。
struct IOSSettingsView: View {
    var body: some View {
        NavigationStack {
            IOSSettingsListView(includeDismissToolbar: false)
        }
    }
}

// MARK: - Health Diagnostics Model

@MainActor
private final class IOSHealthDiagnosticsModel: ObservableObject {
    @Published private(set) var stepsText = "—"
    @Published private(set) var moveText = "—"
    @Published private(set) var exerciseText = "—"
    @Published private(set) var standText = "—"
    @Published private(set) var sleepText = "—"
    @Published private(set) var errorText: String?

    private let store = HKHealthStore()

    func refresh() async {
        errorText = nil
        guard HKHealthStore.isHealthDataAvailable() else {
            stepsText = "不可用"; moveText = "不可用"
            exerciseText = "不可用"; standText = "不可用"; sleepText = "不可用"
            return
        }

        let requestStatus = await authorizationRequestStatus()
        guard requestStatus == .unnecessary else {
            errorText = "尚未完成统一健康授权；请在 onboarding 或健康入口里一次性授权。"
            return
        }
        async let steps = queryTodaySum(.stepCount, unit: .count(), suffix: "步")
        async let move = queryTodaySum(.activeEnergyBurned, unit: .kilocalorie(), suffix: "kcal")
        async let exercise = queryTodaySum(.appleExerciseTime, unit: .minute(), suffix: "分")
        async let stand = queryTodaySum(.appleStandTime, unit: .minute(), suffix: "分")
        async let sleep = queryLatestSleep()
        let (stepsVal, moveVal, exerciseVal, standVal, sleepVal) = await (steps, move, exercise, stand, sleep)
        stepsText = stepsVal; moveText = moveVal
        exerciseText = exerciseVal; standText = standVal; sleepText = sleepVal
    }

    private func authorizationRequestStatus() async -> HKAuthorizationRequestStatus {
        var read = Set<HKObjectType>()
        if let t = HKQuantityType.quantityType(forIdentifier: .stepCount) { read.insert(t) }
        if let t = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) { read.insert(t) }
        if let t = HKQuantityType.quantityType(forIdentifier: .appleExerciseTime) { read.insert(t) }
        if let t = HKQuantityType.quantityType(forIdentifier: .appleStandTime) { read.insert(t) }
        if let t = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { read.insert(t) }
        return await withCheckedContinuation { cont in
            store.getRequestStatusForAuthorization(toShare: [], read: read) { status, _ in
                DispatchQueue.main.async { cont.resume(returning: status) }
            }
        }
    }

    private func queryTodaySum(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, suffix: String) async -> String {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return "不支持" }
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        let value: Double = await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
                cont.resume(returning: stats?.sumQuantity()?.doubleValue(for: unit) ?? 0)
            }
            store.execute(q)
        }
        if identifier == .stepCount { return "\(Int(value.rounded())) \(suffix)" }
        return value > 0.01 ? "\(Int(value.rounded())) \(suffix)" : "0 \(suffix)"
    }

    private func queryLatestSleep() async -> String {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return "不支持" }
        let start = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let samples: [HKCategorySample] = await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, results, _ in
                cont.resume(returning: (results as? [HKCategorySample]) ?? [])
            }
            store.execute(q)
        }
        let positive = samples.filter { sample in
            guard let value = HKCategoryValueSleepAnalysis(rawValue: sample.value) else { return false }
            switch value {
            case .inBed, .awake: return false
            default: return sample.endDate.timeIntervalSince(sample.startDate) > 0
            }
        }
        guard let last = positive.last else { return "最近 7 天无记录" }
        let hours = last.endDate.timeIntervalSince(last.startDate) / 3600
        return String(format: "%.1f 小时", hours)
    }
}
