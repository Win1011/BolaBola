//
//  IOSRootView.swift
//  系统 **`TabView`**：前三项为主内容，第四项为 **对话**；圆形样式依赖 **`TabRole.search`**（尚无对话专用 role，见 `IOSRootTab.chat` 注释与 [TabRole](https://developer.apple.com/documentation/swiftui/tabrole)）。
//

import SwiftUI
import UIKit
import UserNotifications

struct IOSRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: IOSRootTab = .mine
    @State private var growthSegment: IOSGrowthSubPage = .growth
    @AppStorage("bola_life_bubble_mode_v1") private var lifeBubbleMode = false

    @State private var companion: Double = 50
    /// 主界面左上角刷新：递增触发 `IOSMainHomeView` 内同步与健康/天气刷新。
    @State private var mineRefreshSignal: Int = 0
    @State private var isMineHomeSyncing: Bool = false
    @State private var reminders: [BolaReminder] = ReminderListStore.load()
    @State private var showDigestSheet = false
    @State private var digestBody = ""
    @State private var showSettingsSheet = false
    @State private var showOnboarding = !BolaOnboardingState.isCompleted
    private var bolaDefaults: UserDefaults { BolaSharedDefaults.resolved() }

    private var lifeTabRoot: some View {
        NavigationStack {
            IOSLifeContainerView(
                bubbleMode: $lifeBubbleMode,
                reminders: $reminders,
                onRequestChat: { selectedTab = .chat }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { lifeToolbarContent }
        }
        .tint(Color(UIColor.label))
    }

    private var statusTabRoot: some View {
        NavigationStack {
            IOSGrowthContainerView(growthSegment: $growthSegment)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { growthNavigationToolbar }
        }
        .tint(Color(UIColor.label))
    }

    private var mineTabRoot: some View {
        NavigationStack {
            IOSMainHomeView(
                companion: $companion,
                refreshSignal: $mineRefreshSignal,
                isSyncing: $isMineHomeSyncing
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle("Bola的空间")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { mineToolbarContent }
        }
        .tint(Color(UIColor.label))
    }

    /// 对话即根页；圆形底栏项仍用 `TabRole.search`（系统仅此 role 提供该圆形 affordance）。
    private var chatTabRoot: some View {
        NavigationStack {
            IOSChatTestSection(companion: companion)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .navigationTitle("和 \(companionChatDisplayName) 聊天")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbar { chatToolbarContent }
        }
        .tint(Color(UIColor.label))
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            /// `TabSection` 与独立「对话」Tab 之间间距与三格胶囊宽度由系统绘制，无公开微调 API。
            TabSection {
                Tab(value: IOSRootTab.mine) {
                    mineTabRoot
                } label: {
                    Label("主界面", systemImage: "triangle.fill")
                }

                Tab(value: IOSRootTab.status) {
                    statusTabRoot
                } label: {
                    Label("成长", systemImage: "circle.fill")
                }

                Tab(value: IOSRootTab.life) {
                    lifeTabRoot
                } label: {
                    Label("生活", systemImage: "diamond.fill")
                }
            }

            Tab(value: IOSRootTab.chat, role: .search) {
                chatTabRoot
            } label: {
                Label("对话", systemImage: "bubble.left.and.bubble.right.fill")
            }
        }
        .bolaIOS26TabBarMinimizeOnScroll()
        .bolaRootTabScrollEdgeStyles()
        .ignoresSafeArea(.keyboard)
        .sheet(isPresented: $showSettingsSheet) {
            NavigationStack {
                IOSSettingsListView()
            }
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            IOSOnboardingView {
                showOnboarding = false
            }
        }
        .sheet(isPresented: $showDigestSheet) {
            NavigationStack {
                ScrollView {
                    Text(digestBody)
                        .font(.body)
                        .padding()
                }
                .navigationTitle("Bola 每日总结")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("好的") { showDigestSheet = false }
                    }
                }
            }
        }
        .onAppear {
            BolaRootTabBarTitleStyle.applyLabelColorToTabTitles()
            consumeDigestNotificationIfNeeded()
            refreshCompanionFromPersistedDefaults()
            BolaWCSessionCoordinator.shared.pushLocalCompanionTowardWatchFromDefaults()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                BolaWCSessionCoordinator.shared.reapplyLatestReceivedContext()
                BolaWCSessionCoordinator.shared.pushStoredLLMConfigurationToWatchIfConfigured()
                refreshCompanionFromPersistedDefaults()
                BolaWCSessionCoordinator.shared.pushLocalCompanionTowardWatchFromDefaults()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .bolaCompanionStateDidMergeFromWatch)) { _ in
            refreshCompanionFromPersistedDefaults()
        }
        .onReceive(NotificationCenter.default.publisher(for: .bolaOpenSettingsRequested)) { _ in
            showSettingsSheet = true
        }
        .task {
            BolaSharedDefaults.migrateStandardToGroupIfNeeded()
            ReminderBootstrap.ensureDefaults()
            reminders = ReminderListStore.load()
            refreshCompanionFromPersistedDefaults()
            BolaWCSessionCoordinator.shared.onReceiveCompanionValue = { v in
                Task { @MainActor in
                    companion = v
                }
            }
            BolaWCSessionCoordinator.shared.activate()
            await BolaReminderUNScheduler.sync(reminders: reminders)
            let digest = DailyDigestStore.load()
            await DailyDigestUNScheduler.sync(config: digest)
            await DailyDigestRefresh.regenerateIfNeeded(companionValue: Int(companion.rounded()))
        }
    }

    @ToolbarContentBuilder
    private var lifeToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            IOSNavigationGlassIconButton(
                systemName: "arrow.left.arrow.right",
                font: .system(size: 17, weight: .semibold),
                accessibilityLabel: "生活泡泡"
            ) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    lifeBubbleMode.toggle()
                }
            }
        }
        ToolbarItem(placement: .principal) {
            Text("生活")
                .font(.system(size: 20, weight: .semibold))
        }
        ToolbarItem(placement: .topBarTrailing) {
            settingsButton
        }
    }

    @ToolbarContentBuilder
    private var mineToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Group {
                if isMineHomeSyncing {
                    ProgressView()
                } else {
                    IOSNavigationGlassIconButton(
                        systemName: "arrow.clockwise",
                        font: .system(size: 17, weight: .semibold),
                        accessibilityLabel: "同步与刷新"
                    ) {
                        mineRefreshSignal += 1
                    }
                }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            settingsButton
        }
    }

    @ToolbarContentBuilder
    private var settingsOnlyToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            settingsButton
        }
    }

    @ToolbarContentBuilder
    private var chatToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            IOSNavigationGlassIconButton(
                systemName: "calendar",
                font: .system(size: 17, weight: .semibold),
                accessibilityLabel: "聊天日历"
            ) {
                NotificationCenter.default.post(name: .bolaChatOpenHistoryCalendarRequested, object: nil)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            settingsButton
        }
    }

    /// 成长 Tab：成长 / 时光分段（与生活 Tab 一致）。
    @ToolbarContentBuilder
    private var growthNavigationToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if growthSegment == .timeMoments {
                IOSNavigationGlassIconButton(
                    systemName: "calendar",
                    font: .system(size: 17, weight: .semibold),
                    accessibilityLabel: "波拉日记日历"
                ) {
                    NotificationCenter.default.post(name: .bolaDiaryOpenCalendarRequested, object: nil)
                }
            } else {
                IOSNavigationGlassIconButton(
                    systemName: "checkmark.circle",
                    font: .system(size: 18, weight: .medium),
                    accessibilityLabel: "Debug 完成任务"
                ) {
                    GrowthDailyTasksViewModel.shared.debugCompleteNextTask()
                }
            }
        }
        ToolbarItem(placement: .principal) {
            IOSGrowthSegmentLarge(growthSegment: $growthSegment)
        }
        ToolbarItem(placement: .topBarTrailing) {
            settingsButton
        }
    }

    private var settingsButton: some View {
        IOSNavigationGlassIconButton(
            systemName: "gearshape.fill",
            font: .system(size: 18, weight: .medium),
            accessibilityLabel: "设置"
        ) {
            showSettingsSheet = true
        }
    }

    private var companionChatDisplayName: String {
        let name = bolaDefaults.string(forKey: CompanionPersistenceKeys.companionDisplayName)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Bola" : name
    }

    private func refreshCompanionFromPersistedDefaults() {
        if bolaDefaults.object(forKey: CompanionPersistenceKeys.companionValue) != nil {
            companion = bolaDefaults.double(forKey: CompanionPersistenceKeys.companionValue)
        } else {
            companion = 50
        }
    }

    private func consumeDigestNotificationIfNeeded() {
        let d = bolaDefaults
        guard d.bool(forKey: BolaNotificationBridgeKeys.digestTapOpen) else { return }
        d.set(false, forKey: BolaNotificationBridgeKeys.digestTapOpen)
        digestBody = d.string(forKey: DailyDigestStorageKeys.lastDigestBody) ?? ""
        if !digestBody.isEmpty {
            showDigestSheet = true
        }
    }
}

// MARK: - 底栏标签字色（与 `.tint(accent)` 解耦：图标仍用主题色，标题保持 `label`）

private enum BolaRootTabBarTitleStyle {
    /// `TabView` 的 `.tint` 会作用于选中项标题；用 `UITabBarAppearance` 把标题固定为系统主文字色（浅模式即黑）。
    static func applyLabelColorToTabTitles() {
        let item = UITabBarItemAppearance()
        let titleColor = UIColor.label
        let attrs: [NSAttributedString.Key: Any] = [.foregroundColor: titleColor]
        item.normal.titleTextAttributes = attrs
        item.selected.titleTextAttributes = attrs
        item.focused.titleTextAttributes = attrs
        item.disabled.titleTextAttributes = attrs

        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.stackedLayoutAppearance = item
        appearance.inlineLayoutAppearance = item
        appearance.compactInlineLayoutAppearance = item

        let tabBar = UITabBar.appearance()
        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
    }
}

// MARK: - iOS 26 标签栏随滚动收起（[Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)）

private extension View {
    @ViewBuilder
    func bolaIOS26TabBarMinimizeOnScroll() -> some View {
        if #available(iOS 26.0, *) {
            self.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
    }
}

#Preview("Bola 主界面") {
    IOSRootView()
}
