//
//  IOSMainHomeView.swift
//  主界面：手表预览、陪伴值、自定义表盘槽位、称号（A+B）；同步与刷新由根导航栏左上角触发。
//

import SwiftUI

struct IOSMainHomeView: View {
    @Binding var companion: Double
    /// 与导航栏「刷新」联动：根视图递增即触发一次同步与健康/天气刷新。
    @Binding var refreshSignal: Int
    /// 与根导航栏左上角 `ProgressView` 共用。
    @Binding var isSyncing: Bool

    @StateObject private var healthPreview = IOSWatchFaceHealthPreviewModel()
    @StateObject private var weather = IOSWeatherLocationModel()
    @State private var showWatchAppMissingHint = false
    @State private var slotsConfig = WatchFaceSlotsStore.load()
    @State private var titleIndexA = BolaTitleSelectionStore.load().indexA
    @State private var titleIndexB = BolaTitleSelectionStore.load().indexB
    @State private var showCompanionInfo = false
    /// 为 true 时表盘显示三槽圆圈并允许拖放；「清空」亦仅在此模式下显示。
    @State private var isWatchFaceEditing = false

    private var bolaDefaults: UserDefaults { BolaSharedDefaults.resolved() }

    private var titleLine: String {
        BolaTitleSelection(indexA: titleIndexA, indexB: titleIndexB).resolvedLine()
    }

    private var weatherSymbol: String {
        weather.weather?.systemImageName ?? "cloud.sun.fill"
    }

    private var weatherTempLine: String {
        guard let w = weather.weather else { return "—" }
        return "\(Int(w.temperatureC.rounded()))°"
    }

    var body: some View {
        ZStack(alignment: .top) {
            BolaLifeAmbientBackground()
                .ignoresSafeArea(edges: [.top, .bottom])

            ScrollView {
                VStack(alignment: .leading, spacing: BolaTheme.spacingSection) {
                    watchPreviewBlock
                    if showWatchAppMissingHint {
                        Text("系统显示手表端尚未安装 BolaBola（watchAppInstalled=false），手机无法下发数据。请在 iPhone 的「Watch」App →「我的手表」→ 向下找到 BolaBola 并安装；或用 Xcode 选择含 Watch 的 Scheme 运行到真机手表。安装后在手表上打开一次本应用。")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    companionSection
                    customWatchFaceAndPaletteGroup
                    titleSectionGrouped
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, BolaTheme.paddingHorizontal)
                .padding(.top, 4)
                .padding(.bottom, 28)
            }
            .background(Color.clear)
            .scrollIndicators(.hidden)
        }
        .onAppear {
            refreshWatchInstallHint()
            healthPreview.refresh()
            weather.requestAndFetch()
        }
        .onChange(of: slotsConfig) { _, new in
            WatchFaceSlotsStore.save(new)
            BolaWCSessionCoordinator.shared.pushLocalCompanionTowardWatchFromDefaults()
        }
        .onReceive(NotificationCenter.default.publisher(for: .bolaWatchInstallabilityDidChange)) { _ in
            refreshWatchInstallHint()
        }
        .onChange(of: refreshSignal) { _, _ in
            Task { await performWatchSync() }
        }
        .sheet(isPresented: $showCompanionInfo) {
            NavigationStack {
                ScrollView {
                    Text(companionInfoPlainText)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
                .navigationTitle("陪伴值说明")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { showCompanionInfo = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private var watchPreviewBlock: some View {
        WatchS10MockupView(
            slots: $slotsConfig,
            heartRateText: healthPreview.heartRateText,
            stepsText: healthPreview.stepsText,
            weatherSystemImageName: weatherSymbol,
            weatherTempText: weatherTempLine,
            maxHeight: 318,
            horizontalNudgePoints: 1.5,
            screenContentNudgeX: -6,
            screenContentNudgeY: 9,
            showScreenMaskOutline: false,
            isEditingSlots: isWatchFaceEditing
        )
        .frame(maxWidth: .infinity)
    }

    /// 可拖入表盘三处圆圈的组件池；仅在「编辑表盘」模式下可拖拽，「清空」亦同。
    private var watchPaletteRow: some View {
        HStack(spacing: 14) {
            ForEach(WatchFaceComplicationKind.paletteKinds, id: \.self) { k in
                paletteChip(kind: k, label: nil, systemImage: nil, draggable: isWatchFaceEditing)
            }
            if isWatchFaceEditing {
                paletteChip(kind: .none, label: "清空", systemImage: "xmark.circle.fill", draggable: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func paletteChip(
        kind: WatchFaceComplicationKind,
        label: String? = nil,
        systemImage: String? = nil,
        draggable: Bool
    ) -> some View {
        VStack(spacing: 4) {
            Group {
                let icon = Image(systemName: systemImage ?? paletteSymbol(kind))
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(Color.white))
                if draggable {
                    icon.draggable(kind.rawValue)
                } else {
                    icon
                }
            }
            Text(label ?? kind.displayName)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func paletteSymbol(_ kind: WatchFaceComplicationKind) -> String {
        switch kind {
        case .none: return "plus"
        case .heartRate: return "heart.fill"
        case .weather: return "cloud.sun.fill"
        case .steps: return "figure.walk"
        }
    }

    private var companionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("陪伴值")
                    .font(.headline)
                Button {
                    showCompanionInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(Color.secondary.opacity(0.55))
                }
                .buttonStyle(.borderless)
                Spacer(minLength: 0)
            }

            GeometryReader { geo in
                let w = geo.size.width
                let p = max(0, min(1, companion / 100.0))
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(uiColor: .tertiarySystemFill))
                    Capsule()
                        .fill(BolaTheme.accent)
                        .frame(width: max(8, w * p))
                }
            }
            .frame(height: 12)
            .accessibilityLabel("陪伴值 \(Int(companion.rounded()))，满分一百")
        }
    }

    /// 自定义表盘说明 + 组件池，浅灰分区底。
    private var customWatchFaceAndPaletteGroup: some View {
        VStack(alignment: .leading, spacing: 12) {
            customWatchFaceSection
            watchPaletteRow
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: BolaTheme.cornerCard, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        }
    }

    private var customWatchFaceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("自定义表盘")
                    .font(.headline)
                Spacer(minLength: 0)
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isWatchFaceEditing.toggle()
                    }
                } label: {
                    Text(isWatchFaceEditing ? "完成" : "编辑表盘")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BolaTheme.onAccentForeground)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(BolaTheme.accent))
                }
                .buttonStyle(.plain)
            }
            Text("编辑表盘将下方图标拖到表盘上对应位置")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 称号 + 滚轮，外层浅灰分区底。
    private var titleSectionGrouped: some View {
        titleSection
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: BolaTheme.cornerCard, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            }
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("称号")
                .font(.headline)
            Text(titleLine)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            HStack(spacing: 0) {
                Picker("A", selection: $titleIndexA) {
                    ForEach(0 ..< BolaTitlePhraseBank.groupA.count, id: \.self) { i in
                        Text(BolaTitlePhraseBank.groupA[i]).tag(i)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
                .clipped()

                Text("·")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)

                Picker("B", selection: $titleIndexB) {
                    ForEach(0 ..< BolaTitlePhraseBank.groupB.count, id: \.self) { i in
                        Text(BolaTitlePhraseBank.groupB[i]).tag(i)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
                .clipped()
            }
            .frame(height: 120)
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(BolaTheme.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color(uiColor: .separator).opacity(0.25), lineWidth: 1)
            )
        }
        .onChange(of: titleIndexA) { _, _ in persistTitle() }
        .onChange(of: titleIndexB) { _, _ in persistTitle() }
        .onAppear {
            titleIndexA = min(titleIndexA, max(BolaTitlePhraseBank.groupA.count - 1, 0))
            titleIndexB = min(titleIndexB, max(BolaTitlePhraseBank.groupB.count - 1, 0))
        }
    }

    private func persistTitle() {
        let sel = BolaTitleSelection(indexA: titleIndexA, indexB: titleIndexB)
        BolaTitleSelectionStore.save(BolaTitleSelectionStore.clamped(sel))
        BolaWCSessionCoordinator.shared.pushLocalCompanionTowardWatchFromDefaults()
    }

    private var companionInfoPlainText: String {
        """
        陪伴值表示你和 Bola 当下的「亲密度」状态，范围是 0 到 100。

        多和 Bola 在手表上互动、在线相处一段时间，陪伴值会慢慢往上走。

        如果很久没打开应用，陪伴值会下降；太低时 Bola 会显得情绪低落、甚至有「很危险」的状态——多陪陪他就能恢复。

        具体加减规则会随版本微调，以手表端体验为准。
        """
    }

    private func refreshWatchInstallHint() {
        showWatchAppMissingHint = BolaWCSessionCoordinator.shared.shouldShowWatchAppMissingHint()
    }

    @MainActor
    private func performWatchSync() async {
        isSyncing = true
        defer { isSyncing = false }
        BolaWCSessionCoordinator.shared.pushLocalCompanionTowardWatchFromDefaults()
        BolaWCSessionCoordinator.shared.pushStoredLLMConfigurationToWatchIfConfigured()
        try? await Task.sleep(nanoseconds: 800_000_000)
        refreshWatchInstallHint()
        if bolaDefaults.object(forKey: CompanionPersistenceKeys.companionValue) != nil {
            companion = bolaDefaults.double(forKey: CompanionPersistenceKeys.companionValue)
        }
        healthPreview.refresh()
        weather.requestAndFetch()
    }
}
