//
//  IOSSettingsView.swift
//

import SwiftUI
import UIKit
import UserNotifications

/// 设置列表（由根视图以 Sheet + `NavigationStack` 呈现，或单独再包一层导航栈）。
struct IOSSettingsListView: View {
    /// Sheet 里需要「完成」关闭；仅 `NavigationStack` 包一层时可关。
    var includeDismissToolbar: Bool = true

    @Environment(\.dismiss) private var dismiss
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var confirmResetLifeRecords = false
    @State private var confirmResetGrowth = false
    @State private var growthSummary: String = ""
    @State private var selectedPersonality = BolaPersonalitySelectionStore.validated()

    var body: some View {
        List {
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

            Section {
                HStack {
                    Text("通知权限")
                    Spacer()
                    Text(notificationStatusLabel)
                        .foregroundStyle(.secondary)
                }
                Button("前往系统设置…") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("再次请求通知授权") {
                    Task { @MainActor in
                        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                        await refreshNotificationStatus()
                    }
                }
            } header: {
                Text("通知")
            } footer: {
                Text("「尚未询问」表示还没在系统弹窗里选择过是否允许通知，与健康数据无关；健康在 设置 › 隐私与安全性 › 健康。")
                    .font(.caption)
            }

            Section {
                Button("恢复默认生活卡片…", role: .destructive) {
                    confirmResetLifeRecords = true
                }
            } header: {
                Text("生活记录")
            } footer: {
                Text("删除除「天气」外的所有生活卡片，用于清理测试数据；操作后无法撤销。")
            }

            Section {
                // 当前状态展示
                HStack {
                    Text("等级 / XP")
                    Spacer()
                    Text(growthSummary)
                        .foregroundStyle(.secondary)
                        .font(.caption.monospacedDigit())
                }
                // XP 操作
                Button("+10 XP（模拟任务完成）") {
                    BolaXPEngine.grantTaskXP()
                    refreshGrowthSummary()
                }
                Button("+20 XP（模拟首次对话）") {
                    BolaXPEngine.completeMilestone(.firstIOSChat)
                    refreshGrowthSummary()
                }
                Button("+100 XP（模拟陪伴满百）") {
                    BolaXPEngine.completeMilestone(.companion100)
                    refreshGrowthSummary()
                }
                Button("等级 +1（调试）") {
                    debugLevelUpOnce()
                }
                Button("解锁所有称号词条") {
                    var state = BolaGrowthStore.load()
                    // 临时设高 XP + 所有里程碑，触发解锁
                    state.totalXP = max(state.totalXP, BolaLevelFormula.cumulativeXP(forLevel: 20))
                    state.completedMilestones = BolaGrowthMilestone.allCases.map(\.rawValue)
                    state.personalityType = BolaPersonalityType.tsundere.rawValue
                    BolaGrowthStore.save(state)
                    TitleUnlockManager.refreshUnlocks(
                        state: state,
                        currentCompanionValue: 100,
                        maxEverCompanionValue: 100
                    )
                    BolaWCSessionCoordinator.shared.pushLocalCompanionTowardWatchFromDefaults()
                    refreshGrowthSummary()
                    refreshPersonalitySelection()
                }
                // 任务调试
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
                Text("Debug · 成长")
            } footer: {
                Text("仅供调试，不影响真实健康数据。里程碑奖励为一次性，重置后可再次触发。")
            }
            .onAppear { refreshGrowthSummary() }

            Section {
                HStack {
                    Text("当前人格")
                    Spacer()
                    Text(personalityStatusText)
                        .foregroundStyle(.secondary)
                }

                Picker("人格", selection: $selectedPersonality) {
                    Text(BolaPersonalitySelection.default.displayName).tag(BolaPersonalitySelection.default as BolaPersonalitySelection)
                    Text(BolaPersonalitySelection.tsundere.displayName).tag(BolaPersonalitySelection.tsundere as BolaPersonalitySelection)
                }
                .pickerStyle(.segmented)
                .disabled(!isTsundereUnlocked)
            } header: {
                Text("人格")
            } footer: {
                Text(isTsundereUnlocked
                     ? "已解锁傲娇人格。默认保持现在的 Bola 风格，切到傲娇后会同步影响 iPhone 与手表对话。"
                     : "Lv.5 解锁傲娇人格。解锁前会保持当前默认风格。")
            }

            Section {
                HStack {
                    Text("应用名称")
                    Spacer()
                    Text("BolaBola")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("版本")
                    Spacer()
                    Text(appVersionString)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            } header: {
                Text("关于")
            } footer: {
                Text("性格与用户档案等功能将后续在此扩展。")
            }
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
            refreshPersonalitySelection()
        }
        .onAppear {
            Task { await refreshNotificationStatus() }
            refreshPersonalitySelection()
        }
        .onChange(of: selectedPersonality) { _, newValue in
            applyPersonalitySelection(newValue)
        }
        .onReceive(NotificationCenter.default.publisher(for: .bolaGrowthStateDidChange)) { _ in
            refreshGrowthSummary()
            refreshPersonalitySelection()
        }
        .confirmationDialog(
            "将删除除「天气」外的所有生活卡片，且无法撤销。",
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
                refreshPersonalitySelection()
            }
            Button("取消", role: .cancel) {}
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
        refreshPersonalitySelection()
    }

    private var isTsundereUnlocked: Bool {
        BolaPersonalitySelectionStore.isTsundereUnlocked()
    }

    private var personalityStatusText: String {
        isTsundereUnlocked ? selectedPersonality.displayName : "未解锁"
    }

    private func refreshPersonalitySelection() {
        selectedPersonality = BolaPersonalitySelectionStore.validated()
    }

    private func applyPersonalitySelection(_ selection: BolaPersonalitySelection) {
        BolaPersonalitySelectionStore.save(selection)
        let stored = BolaPersonalitySelectionStore.validated()
        if selectedPersonality != stored {
            selectedPersonality = stored
        }
        BolaWCSessionCoordinator.shared.pushLocalCompanionTowardWatchFromDefaults()
    }

    private var notificationStatusLabel: String {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral: return "已开启"
        case .denied: return "已拒绝"
        // 与「健康」无关：表示系统尚未记录你对通知的选择（未弹窗或从未点过允许/拒绝）。
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

/// 独立打开设置时使用的带导航栈包装（预览/深链等）。
struct IOSSettingsView: View {
    var body: some View {
        NavigationStack {
            IOSSettingsListView(includeDismissToolbar: false)
        }
    }
}
