//
//  IOSMainHomeView.swift
//  主界面：手表预览 + 陪伴值（不含健康习惯与提醒）。
//

import SwiftUI

struct IOSMainHomeView: View {
    @Binding var companion: Double
    @State private var isWatchSyncing = false
    @State private var showWatchAppMissingHint = false
    @AppStorage(HomeWatchFaceLayout.appStorageKey) private var layoutRaw: String = HomeWatchFaceLayout.minimal.rawValue

    private var bolaDefaults: UserDefaults { BolaSharedDefaults.resolved() }

    private var selectedWatchLayout: HomeWatchFaceLayout {
        HomeWatchFaceLayout(rawValue: layoutRaw) ?? .minimal
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BolaTheme.spacingSection) {
                WatchS10MockupView(companion: companion, maxHeight: 240, layout: selectedWatchLayout)
                syncWatchSection
                watchFaceLayoutPickerSection
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

    /// 类似系统表盘库：选择主界面手表预览上的组件排布（当前为占位，后续可接入真实小组件）。
    private var watchFaceLayoutPickerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("主界面布局")
                .font(.headline)
            Text("选择表盘式排布，后续可将小组件放入手表画面中的预留区域。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(HomeWatchFaceLayout.allCases) { layout in
                        Button {
                            layoutRaw = layout.rawValue
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(BolaTheme.surfaceElevated)
                                    HomeWatchFaceLayoutThumbnail(layout: layout)
                                        .padding(12)
                                }
                                .frame(width: 118, height: 128)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(
                                            selectedWatchLayout == layout ? BolaTheme.accent : Color(uiColor: .separator).opacity(0.45),
                                            lineWidth: selectedWatchLayout == layout ? 2.5 : 1
                                        )
                                )

                                Text(layout.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(layout.subtitle)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(width: 124, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
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
                    .font(.system(size: 34, weight: .bold))
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

// MARK: - 表盘布局缩略图（与 WatchS10MockupView 内逻辑呼应的示意）

private struct HomeWatchFaceLayoutThumbnail: View {
    let layout: HomeWatchFaceLayout

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black.opacity(0.9))

            switch layout {
            case .minimal:
                Circle()
                    .fill(BolaTheme.accent.opacity(0.55))
                    .frame(width: 22, height: 22)
            case .modular:
                VStack(spacing: 5) {
                    HStack {
                        tinySlot
                        Spacer(minLength: 0)
                        tinySlot
                    }
                    Spacer(minLength: 0)
                    Capsule()
                        .fill(BolaTheme.accent.opacity(0.45))
                        .frame(width: 36, height: 10)
                    Spacer(minLength: 0)
                    HStack(spacing: 6) {
                        wideSlot
                        wideSlot
                    }
                }
                .padding(10)
            case .corners:
                ZStack {
                    Capsule()
                        .fill(BolaTheme.accent.opacity(0.4))
                        .frame(width: 28, height: 10)
                    VStack {
                        HStack {
                            cornerDot
                            Spacer()
                            cornerDot
                        }
                        Spacer()
                        HStack {
                            cornerDot
                            Spacer()
                            cornerDot
                        }
                    }
                    .padding(6)
                }
            case .focus:
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(BolaTheme.accent.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                        .padding(8)
                    Circle()
                        .fill(BolaTheme.accent.opacity(0.45))
                        .frame(width: 20, height: 20)
                }
            }
        }
    }

    private var tinySlot: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .stroke(Color.white.opacity(0.38), lineWidth: 1)
            .frame(width: 18, height: 12)
    }

    private var wideSlot: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .stroke(Color.white.opacity(0.38), lineWidth: 1)
            .frame(height: 14)
            .frame(maxWidth: .infinity)
    }

    private var cornerDot: some View {
        Circle()
            .stroke(Color.white.opacity(0.45), lineWidth: 1)
            .frame(width: 12, height: 12)
    }
}
