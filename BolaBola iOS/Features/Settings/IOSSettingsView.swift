//
//  IOSSettingsView.swift
//

import Combine
import HealthKit
import SwiftUI
import UIKit
import UserNotifications

extension Notification.Name {
    static let bolaHealthDataRefreshRequested = Notification.Name("bolaHealthDataRefreshRequested")
}

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
    @ObservedObject private var debugLog = BolaDebugLog.shared
    @StateObject private var healthDiagnostics = IOSHealthDiagnosticsModel()

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
                Text("Debug · 日志")
            } footer: {
                Text("记录 WC 通信、宠物状态、聊天/语音同步等事件，仅保存在内存最近 500 条。关闭后立即停止写入。")
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
                Button("前往系统设置中的 BolaBola…") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("我已经改好健康权限，立即重新读取") {
                    UserDefaults.standard.set(true, forKey: IOSHealthHabitAnalysisModel.healthReadPromptCompletedKey)
                    NotificationCenter.default.post(name: .bolaHealthDataRefreshRequested, object: nil)
                }
            } header: {
                Text("健康数据")
            } footer: {
                Text("iOS 不会从这里直接跳到「隐私与安全性 › 健康 › BolaBola」。若要开启健康读取，请到系统的「设置 › 隐私与安全性 › 健康 › BolaBola」里打开步数、活动、心率、睡眠等权限；改完后回到 App 点一次“立即重新读取”。")
                    .font(.caption)
            }

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
                Text("这里显示的是 App 当前直接从 HealthKit 读到的原始值。如果这里也都是 0，就不是卡片文案问题，而是该类健康数据当前确实没有可读样本。")
                    .font(.caption)
            }

            Section {
                Button("恢复默认生活卡片…", role: .destructive) {
                    confirmResetLifeRecords = true
                }
            } header: {
                Text("生活记录")
            } footer: {
                Text("删除所有生活卡片，用于清理测试数据；天气会在当天再次刷新时重新生成。")
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
                Button("重新查看引导页") {
                    BolaOnboardingState.reset()
                }
            } header: {
                Text("引导")
            } footer: {
                Text("重置 onboarding 完成标记，返回主界面后会立即重新弹出引导流程。")
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
            await healthDiagnostics.refresh()
            refreshPersonalitySelection()
        }
        .onAppear {
            Task { await refreshNotificationStatus() }
            Task { await healthDiagnostics.refresh() }
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
}

/// 独立打开设置时使用的带导航栈包装（预览/深链等）。
struct IOSSettingsView: View {
    var body: some View {
        NavigationStack {
            IOSSettingsListView(includeDismissToolbar: false)
        }
    }
}

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
            stepsText = "不可用"
            moveText = "不可用"
            exerciseText = "不可用"
            standText = "不可用"
            sleepText = "不可用"
            return
        }

        do {
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

            stepsText = stepsVal
            moveText = moveVal
            exerciseText = exerciseVal
            standText = standVal
            sleepText = sleepVal
        } catch {
            errorText = (error as NSError).localizedDescription
        }
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
                DispatchQueue.main.async {
                    cont.resume(returning: status)
                }
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

        if identifier == .stepCount {
            return "\(Int(value.rounded())) \(suffix)"
        }
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
            case .inBed, .awake:
                return false
            default:
                return sample.endDate.timeIntervalSince(sample.startDate) > 0
            }
        }
        guard let last = positive.last else { return "最近 7 天无记录" }
        let hours = last.endDate.timeIntervalSince(last.startDate) / 3600
        return String(format: "%.1f 小时", hours)
    }
}
