//
//  IOSMainHomeView.swift
//  主界面：手表预览 + 陪伴值（不含健康习惯与提醒）。
//

import SwiftUI

struct IOSMainHomeView: View {
    @Binding var companion: Double
    @State private var isWatchSyncing = false
    @State private var showWatchAppMissingHint = false

    private var bolaDefaults: UserDefaults { BolaSharedDefaults.resolved() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BolaTheme.spacingSection) {
                WatchS10MockupView(companion: companion, maxHeight: 240)
                syncWatchSection
                companionCard
            }
            .padding(.horizontal, BolaTheme.paddingHorizontal)
            .padding(.top, 0)
            .padding(.bottom, 24)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .onAppear { refreshWatchInstallHint() }
        .onReceive(NotificationCenter.default.publisher(for: .bolaWatchInstallabilityDidChange)) { _ in
            refreshWatchInstallHint()
        }
    }

    private var syncWatchSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Spacer(minLength: 0)
                Button {
                    Task { await performWatchSync() }
                } label: {
                    HStack(spacing: 8) {
                        if isWatchSyncing {
                            ProgressView()
                                .tint(BolaTheme.onAccentForeground)
                        }
                        Text("同步手表")
                            .font(.subheadline.weight(.semibold))
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(BolaTheme.accent))
                    .foregroundStyle(BolaTheme.onAccentForeground)
                }
                .buttonStyle(.plain)
                .disabled(isWatchSyncing)
                Spacer(minLength: 0)
            }
            if showWatchAppMissingHint {
                Text("系统显示手表端尚未安装 BolaBola（watchAppInstalled=false），手机无法下发数据。请在 iPhone 的「Watch」App →「我的手表」→ 向下找到 BolaBola 并安装；或用 Xcode 选择含 Watch 的 Scheme 运行到真机手表。安装后在手表上打开一次本应用。")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func refreshWatchInstallHint() {
        showWatchAppMissingHint = BolaWCSessionCoordinator.shared.shouldShowWatchAppMissingHint()
    }

    private var companionCard: some View {
        VStack(alignment: .leading, spacing: BolaTheme.spacingItem) {
            Text("与手表同步")
                .font(.headline)
            HStack {
                Button {
                    adjustCompanion(-1)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(BolaTheme.accent)
                }
                .buttonStyle(.borderless)
                Spacer()
                Text("\(Int(companion.rounded()))")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Spacer()
                Button {
                    adjustCompanion(1)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(BolaTheme.accent)
                }
                .buttonStyle(.borderless)
            }
            Text(
                showWatchAppMissingHint
                    ? "当前无法推送到手表：系统显示表端尚未安装 BolaBola，数值只保存在本机。请在「Watch」App 中安装并在手表上打开一次。"
                    : "修改后会通过 WatchConnectivity 推送到已配对的 Apple Watch。"
            )
                .font(.caption)
                .foregroundStyle(showWatchAppMissingHint ? .orange : .secondary)
        }
        .padding(BolaTheme.spacingItem)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: BolaTheme.cornerCard, style: .continuous)
                .fill(BolaTheme.surfaceElevated)
        )
    }

    private func adjustCompanion(_ delta: Int) {
        let next = min(100, max(0, Int(companion.rounded()) + delta))
        companion = Double(next)
        BolaWCSessionCoordinator.shared.pushCompanionValue(companion)
    }

    @MainActor
    private func performWatchSync() async {
        isWatchSyncing = true
        defer { isWatchSyncing = false }
        BolaWCSessionCoordinator.shared.pushLocalCompanionTowardWatchFromDefaults()
        BolaWCSessionCoordinator.shared.pushStoredLLMConfigurationToWatchIfConfigured()
        try? await Task.sleep(nanoseconds: 800_000_000)
        refreshWatchInstallHint()
        if bolaDefaults.object(forKey: CompanionPersistenceKeys.companionValue) != nil {
            companion = bolaDefaults.double(forKey: CompanionPersistenceKeys.companionValue)
        }
    }
}
