//
//  IOSRootView.swift
//  系统 **`TabView`**：前三项为主内容，第四项为 **对话**；圆形样式依赖 **`TabRole.search`**（尚无对话专用 role，见 `IOSRootTab.chat` 注释与 [TabRole](https://developer.apple.com/documentation/swiftui/tabrole)）。
//

import SwiftUI
import UIKit
import UserNotifications

struct IOSRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: IOSRootTab = .life
    @State private var lifeSegment: IOSLifeSubPage = .dailyLife
    @AppStorage("bola_life_bubble_mode_v1") private var lifeBubbleMode = false

    @State private var companion: Double = 50
    @State private var reminders: [BolaReminder] = ReminderListStore.load()
    @State private var showDigestSheet = false
    @State private var digestBody = ""
    @State private var showSettingsSheet = false

    private var bolaDefaults: UserDefaults { BolaSharedDefaults.resolved() }

    private var lifeTabRoot: some View {
        NavigationStack {
            IOSLifeContainerView(
                lifeSegment: $lifeSegment,
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
            IOSStatusView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle("状态")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { settingsOnlyToolbar }
        }
        .tint(Color(UIColor.label))
    }

    private var mineTabRoot: some View {
        NavigationStack {
            IOSMainHomeView(companion: $companion)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle("主界面")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { settingsOnlyToolbar }
        }
        .tint(Color(UIColor.label))
    }

    /// 对话即根页；圆形底栏项仍用 `TabRole.search`（系统仅此 role 提供该圆形 affordance）。
    private var chatTabRoot: some View {
        NavigationStack {
            IOSChatTestSection(companion: companion)
                .padding(.horizontal, BolaTheme.paddingHorizontal)
                .padding(.top, 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(BolaTheme.backgroundGrouped)
                .navigationTitle("对话")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { settingsOnlyToolbar }
        }
        .tint(Color(UIColor.label))
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            /// `TabSection` 与独立「对话」Tab 之间系统会多留一点间距（相对四个平铺 Tab）。
            TabSection {
                Tab(value: IOSRootTab.life) {
                    lifeTabRoot
                } label: {
                    Label("生活", systemImage: "diamond.fill")
                }

                Tab(value: IOSRootTab.status) {
                    statusTabRoot
                } label: {
                    Label("状态", systemImage: "circle.fill")
                }

                Tab(value: IOSRootTab.mine) {
                    mineTabRoot
                } label: {
                    Label("主界面", systemImage: "triangle.fill")
                }
            }

            Tab(value: IOSRootTab.chat, role: .search) {
                chatTabRoot
            } label: {
                Label("对话", systemImage: "bubble.left.and.bubble.right.fill")
            }
        }
        .tint(BolaTheme.accent)
        .bolaIOS26TabBarMinimizeOnScroll()
        .bolaRootTabScrollEdgeStyles()
        .ignoresSafeArea(.keyboard)
        .sheet(isPresented: $showSettingsSheet) {
            NavigationStack {
                IOSSettingsListView()
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
            consumeDigestNotificationIfNeeded()
            refreshCompanionFromPersistedDefaults()
            BolaWCSessionCoordinator.shared.pushLocalCompanionTowardWatchFromDefaults()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            BolaWCSessionCoordinator.shared.reapplyLatestReceivedContext()
            BolaWCSessionCoordinator.shared.pushStoredLLMConfigurationToWatchIfConfigured()
            refreshCompanionFromPersistedDefaults()
            BolaWCSessionCoordinator.shared.pushLocalCompanionTowardWatchFromDefaults()
        }
        .onReceive(NotificationCenter.default.publisher(for: .bolaCompanionStateDidMergeFromWatch)) { _ in
            refreshCompanionFromPersistedDefaults()
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
            let center = UNUserNotificationCenter.current()
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
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
            IOSLifeSegmentLarge(lifeSegment: $lifeSegment)
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

    private var settingsButton: some View {
        IOSNavigationGlassIconButton(
            systemName: "gearshape.fill",
            font: .system(size: 18, weight: .medium),
            accessibilityLabel: "设置"
        ) {
            showSettingsSheet = true
        }
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
