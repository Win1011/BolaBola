//
//  IOSRootView.swift
//  iPhone：单一导航栈 + 右上设置；底部三项 Tab（分析 | 主界面 | 对话），选中为圆形高亮。
//

import SwiftUI
import UserNotifications

struct IOSRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: IOSMainTab = .home
    @State private var companion: Double = 50
    @State private var reminders: [BolaReminder] = ReminderListStore.load()
    @State private var showDigestSheet = false
    @State private var digestBody = ""
    @State private var showSettingsSheet = false

    private var bolaDefaults: UserDefaults { BolaSharedDefaults.resolved() }

    private var navigationTitle: String {
        switch selectedTab {
        case .home: return "主界面"
        case .analysis: return "分析"
        case .chat: return "对话"
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch selectedTab {
                case .home:
                    IOSMainHomeView(companion: $companion)
                case .analysis:
                    IOSAnalysisView(reminders: $reminders)
                case .chat:
                    IOSChatTestSection(companion: companion)
                        .padding(.horizontal, BolaTheme.paddingHorizontal)
                        .padding(.top, 0)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .background(Color(uiColor: .systemGroupedBackground))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ZStack(alignment: .bottom) {
                    tabBarBottomFade
                        .frame(height: 78)
                        .frame(maxWidth: .infinity)
                        .allowsHitTesting(false)

                    IOSCapsuleTabBar(selection: $selectedTab)
                        .padding(.horizontal, BolaTheme.paddingHorizontal)
                        .padding(.top, 2)
                        .padding(.bottom, 6)
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettingsSheet = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                    }
                    .accessibilityLabel("设置")
                }
            }
        }
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
            // `migrateStandardToGroupIfNeeded`：首次启用 App Group 时将 standard 中的陪伴相关键拷入共享 suite。
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

    private func refreshCompanionFromPersistedDefaults() {
        if bolaDefaults.object(forKey: CompanionPersistenceKeys.companionValue) != nil {
            companion = bolaDefaults.double(forKey: CompanionPersistenceKeys.companionValue)
        } else {
            companion = 50
        }
    }

    /// 底部渐变遮罩（替代不透明的 material 条）。
    private var tabBarBottomFade: some View {
        LinearGradient(
            stops: [
                .init(color: Color(uiColor: .systemGroupedBackground).opacity(0), location: 0),
                .init(color: Color(uiColor: .systemGroupedBackground).opacity(0.35), location: 0.45),
                .init(color: Color(uiColor: .systemGroupedBackground).opacity(0.72), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
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
