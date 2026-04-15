//
//  IOSMainHomeView.swift
//  主界面：手表预览、陪伴值、自定义表盘槽位、称号（A+B）；同步与刷新由根导航栏左上角触发。
//

import SwiftUI

struct IOSMainHomeView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Binding var companion: Double
    /// 与导航栏「刷新」联动：根视图递增即触发一次同步与健康/天气刷新。
    @Binding var refreshSignal: Int
    /// 与根导航栏左上角 `ProgressView` 共用。
    @Binding var isSyncing: Bool

    @StateObject private var healthPreview = IOSWatchFaceHealthPreviewModel()
    @StateObject private var weather = IOSWeatherLocationModel()
    @ObservedObject private var coordinator = BolaWCSessionCoordinator.shared
    @State private var watchInstallability = BolaWCSessionCoordinator.shared.watchInstallabilityStatus()
    @State private var slotsConfig = WatchFaceSlotsStore.load()
    @State private var titleWordIdA = BolaTitleSelectionStore.load().wordIdA
    @State private var titleWordIdB = BolaTitleSelectionStore.load().wordIdB
    @State private var unlockedTitleIds: Set<String> = TitleUnlockStore.loadUnlockedIds()
    @State private var showCompanionInfo = false
    @State private var selectedPlacedStickerPosition: WatchFaceSlotPosition?
    @State private var selectedPlacedStickerKind: WatchFaceComplicationKind = .none
    @State private var hasPerformedInitialLoad = false
    @State private var showHeavyWatchPreview = false
    @State private var petTapFeedbackScale: CGFloat = 1.0

    private var bolaDefaults: UserDefaults { BolaSharedDefaults.resolved() }

    private var titleLine: String {
        BolaTitleSelection(wordIdA: titleWordIdA, wordIdB: titleWordIdB).resolvedLine()
    }

    private var unlockedPoolA: [TitleWord] {
        TitleWordBank.poolA.filter { unlockedTitleIds.contains($0.id) }
    }
    private var unlockedPoolB: [TitleWord] {
        TitleWordBank.poolB.filter { unlockedTitleIds.contains($0.id) }
    }

    private var titleUnlocked: Bool {
        let level = BolaLevelFormula.levelAndRemainder(
            fromTotalXP: BolaGrowthStore.load().totalXP).level
        return level >= 3
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
                    if let watchHintText {
                        watchConnectivityHintCard(text: watchHintText)
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
            guard !hasPerformedInitialLoad else { return }
            hasPerformedInitialLoad = true
            refreshWatchInstallHint()
            Task { @MainActor in
                await Task.yield()
                showHeavyWatchPreview = true
            }
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
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
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
        .confirmationDialog(
            selectedPlacedStickerPosition == nil ? "贴纸操作" : "处理此贴纸",
            isPresented: Binding(
                get: { selectedPlacedStickerPosition != nil },
                set: { if !$0 { selectedPlacedStickerPosition = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let position = selectedPlacedStickerPosition {
                Button("移除贴纸", role: .destructive) {
                    slotsConfig.set(position, kind: .none)
                    selectedPlacedStickerPosition = nil
                }
            }
            Button("取消", role: .cancel) {
                selectedPlacedStickerPosition = nil
            }
        }
    }

    private var petDialogueBubble: some View {
        Group {
            if !coordinator.currentPetDialogueLine.isEmpty {
                Text(coordinator.currentPetDialogueLine)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.yellow.opacity(0.22))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.yellow.opacity(0.85), lineWidth: 1.5)
                    )
                    .frame(maxWidth: 260)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: coordinator.currentPetDialogueLine)
    }

    private var petActionBar: some View {
        let prefix = coordinator.currentPetAnimationPrefix
        let showFeed = prefix.hasPrefix("idleapple") || prefix.hasPrefix("eatingwait")
        let showDrink = prefix.hasPrefix("idledrink")
        let showSleep = prefix.hasPrefix("sleepy") || prefix.hasPrefix("nightsleepwait")
        return HStack(spacing: 14) {
            if showFeed {
                petActionButton(title: "喂食", systemImage: "leaf.fill", tint: .green) {
                    BolaWCSessionCoordinator.shared.sendPetCommand(PetCommandKind.eat)
                }
            }
            if showDrink {
                petActionButton(title: "喝水", systemImage: "drop.fill", tint: .blue) {
                    BolaWCSessionCoordinator.shared.sendPetCommand(PetCommandKind.drink)
                }
            }
            if showSleep {
                petActionButton(title: "睡觉", systemImage: "moon.zzz.fill", tint: .purple) {
                    BolaWCSessionCoordinator.shared.sendPetCommand(PetCommandKind.sleep)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.18), value: prefix)
    }

    private func petActionButton(title: String, systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(tint.opacity(0.14))
            )
            .overlay(
                Capsule().stroke(tint.opacity(0.45), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var watchPreviewBlock: some View {
        VStack(spacing: 10) {
            petDialogueBubble
            watchMockupCore
                .scaleEffect(petTapFeedbackScale)
                .contentShape(Rectangle())
                .simultaneousGesture(
                    TapGesture().onEnded {
                        handlePetMockupTap()
                    }
                )
            petActionBar
        }
    }

    private func handlePetMockupTap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.18, dampingFraction: 0.55)) {
            petTapFeedbackScale = 0.94
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.65)) {
                petTapFeedbackScale = 1.0
            }
        }
        BolaWCSessionCoordinator.shared.sendPetCommand(PetCommandKind.tap)
    }

    private var watchMockupCore: some View {
        Group {
            if showHeavyWatchPreview {
                WatchS10MockupView(
                    slots: $slotsConfig,
                    heartRateText: healthPreview.heartRateText,
                    stepsText: healthPreview.stepsText,
                    weatherSystemImageName: weatherSymbol,
                    weatherTempText: weatherTempLine,
                    petAnimationPrefix: coordinator.currentPetAnimationPrefix,
                    maxHeight: 292,
                    horizontalNudgePoints: 1.5,
                    screenContentNudgeX: -6,
                    screenContentNudgeY: 9,
                    showComplicationSlotGuideCircles: false,
                    showScreenMaskOutline: false,
                    complicationSlotsRadialScale: 1.08,
                    complicationContentScale: 1.56,
                    complicationGuideCircleScale: 1.18,
                    isEditingSlots: false,
                    onTapPlacedSlot: { position, kind in
                        selectedPlacedStickerPosition = position
                        selectedPlacedStickerKind = kind
                    }
                )
            } else {
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .fill(Color.white.opacity(0.52))
                    .overlay(
                        ProgressView()
                            .tint(.secondary)
                    )
                    .frame(width: 230, height: 292)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var watchHintText: String? {
        switch watchInstallability {
        case .ready:
            return nil
        case .notPaired:
            return "当前 iPhone 未配对 Apple Watch，暂时无法进行数据同步。请先完成手表配对后再打开一次 App 继续联动。"
        case .appNotInstalled:
            return "系统显示已配对的手表上尚未安装 BolaBola。请在 iPhone 的「Watch」App →「我的手表」里找到 BolaBola 并安装；安装后在手表上打开一次本应用。"
        }
    }

    private func watchConnectivityHintCard(text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "applewatch.radiowaves.left.and.right")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.orange)
            Text(text)
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: BolaTheme.cornerCard, style: .continuous)
                .fill(Color.orange.opacity(0.10))
        }
        .overlay {
            RoundedRectangle(cornerRadius: BolaTheme.cornerCard, style: .continuous)
                .stroke(Color.orange.opacity(0.18), lineWidth: 1)
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

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(Int(companion.rounded()))")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                Text("/ 100")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(companionTierLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BolaTheme.onAccentForeground)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(BolaTheme.accent.opacity(0.88)))
            }

            CompanionAccelerationBar(
                progress: max(0, min(1, companion / 100.0)),
                isAccelerating: isGrowthAccelerating
            )
            .frame(height: isGrowthAccelerating ? 16 : 12)
            .accessibilityLabel("陪伴值 \(Int(companion.rounded()))，满分一百")
        }
    }

    /// 自定义表盘说明 + 组件池，浅灰分区底。
    private var customWatchFaceAndPaletteGroup: some View {
        NavigationLink {
            WatchStickerLibraryPage(slotsConfig: $slotsConfig)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                customWatchFaceSection
                watchStickerPreviewRow
                    .opacity(0)
                    .allowsHitTesting(false)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 140, alignment: .topLeading)
                .background {
                    ZStack {
                        RoundedRectangle(cornerRadius: BolaTheme.cornerCard, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemGroupedBackground))
                        Image("sticker_panel_bg")
                        .resizable()
                        .scaledToFill()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: BolaTheme.cornerCard, style: .continuous))
                    }
                }
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(Color.black.opacity(0.22))
                        )
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.18), lineWidth: 1)
                        )
                        .padding(.top, 16)
                        .padding(.trailing, 16)
                }
        }
        .buttonStyle(.plain)
    }

    private var customWatchFaceSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            VStack(alignment: .leading, spacing: 4) {
                Text("表盘贴纸")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.primary)

                Text("快来装饰你的表盘吧")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(BolaTheme.figmaMutedBody.opacity(0.68))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var watchStickerPreviewRow: some View {
        HStack(spacing: 10) {
            ForEach(WatchFaceComplicationKind.paletteKinds, id: \.self) { kind in
                stickerPreviewCard(kind)
            }
        }
    }

    private func stickerPreviewCard(_ kind: WatchFaceComplicationKind) -> some View {
        Menu {
            Button("放到左上") { assignSticker(kind, to: .topLeft) }
            Button("放到左下") { assignSticker(kind, to: .bottomLeft) }
            Button("放到右下") { assignSticker(kind, to: .bottomRight) }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.82))
                if let assetName = kind.stickerAssetName {
                    Image(assetName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 38, height: 38)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 66)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color(uiColor: .separator).opacity(0.22), lineWidth: 1.3)
            )
            .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .menuStyle(.borderlessButton)
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
                .font(.system(size: 20, weight: .semibold))
            HStack {
                Spacer(minLength: 0)
                TitleBadgeFrame(text: titleLine)
                Spacer(minLength: 0)
            }
            .padding(.top, 2)
            .padding(.bottom, 2)

            if titleUnlocked {
                HStack(spacing: 0) {
                    Picker("A", selection: $titleWordIdA) {
                        ForEach(unlockedPoolA, id: \.id) { w in
                            Text(w.text).tag(w.id)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                    .clipped()

                    Text("·")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)

                    Picker("B", selection: $titleWordIdB) {
                        ForEach(unlockedPoolB, id: \.id) { w in
                            Text(w.text).tag(w.id)
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
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.secondary)
                    Text("升到 Lv.3 解锁称号自定义")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 12)
            }
        }
        .onChange(of: titleWordIdA) { _, _ in persistTitle() }
        .onChange(of: titleWordIdB) { _, _ in persistTitle() }
        .onAppear {
            unlockedTitleIds = TitleUnlockStore.loadUnlockedIds()
            let validated = BolaTitleSelectionStore.validated()
            titleWordIdA = validated.wordIdA
            titleWordIdB = validated.wordIdB
        }
        .onReceive(NotificationCenter.default.publisher(for: .bolaTitleUnlocksDidChange)) { _ in
            unlockedTitleIds = TitleUnlockStore.loadUnlockedIds()
        }
    }

    private func persistTitle() {
        let sel = BolaTitleSelection(wordIdA: titleWordIdA, wordIdB: titleWordIdB)
        BolaTitleSelectionStore.save(sel)
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
        watchInstallability = BolaWCSessionCoordinator.shared.watchInstallabilityStatus()
    }

    private var companionTierLabel: String {
        let tier = CompanionTier.value(for: Int(companion.rounded()))
        switch tier {
        case 0: return "危险"
        case 1, 2: return "疏远"
        case 3, 4: return "熟悉"
        case 5: return "亲密"
        default: return "超亲密"
        }
    }

    private var isGrowthAccelerating: Bool {
        companion >= 80
    }

    private func assignSticker(_ kind: WatchFaceComplicationKind, to position: WatchFaceSlotPosition) {
        slotsConfig.set(position, kind: kind)
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

private struct TitleBadgeFrame: View {
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(uiColor: .secondaryLabel).opacity(0.72))
            Text(text)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(uiColor: .secondaryLabel).opacity(0.72))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.96),
                            BolaTheme.surfaceElevated.opacity(0.98)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
        .overlay(
            Capsule()
                .stroke(Color(uiColor: .separator).opacity(0.32), lineWidth: 1.6)
        )
        .overlay(
            Capsule()
                .inset(by: 4)
                .stroke(Color.white.opacity(0.84), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
    }
}

private struct WatchStickerLibraryPage: View {
    @Binding var slotsConfig: WatchFaceSlotsConfiguration

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(WatchFaceComplicationKind.paletteKinds, id: \.self) { kind in
                    stickerCard(kind)
                }
            }
            .padding(BolaTheme.paddingHorizontal)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .background(BolaLifeAmbientBackground().ignoresSafeArea())
        .navigationTitle("表盘贴纸")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func stickerCard(_ kind: WatchFaceComplicationKind) -> some View {
        Menu {
            Button("左上") { slotsConfig.set(.topLeft, kind: kind) }
            Button("左下") { slotsConfig.set(.bottomLeft, kind: kind) }
            Button("右下") { slotsConfig.set(.bottomRight, kind: kind) }
        } label: {
            VStack(spacing: 7) {
                if let assetName = kind.stickerAssetName {
                    Image(assetName)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 30)
                }
                Text(kind.displayName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.84))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color(uiColor: .separator).opacity(0.22), lineWidth: 1.3)
            )
        }
        .menuStyle(.borderlessButton)
    }
}

private struct CompanionAccelerationBar: View {
    let progress: Double
    let isAccelerating: Bool

    private var acceleratedDeepTint: Color {
        Color(
            UIColor(blendedTowardsLabel: UIColor(BolaTheme.accent), fraction: 0.32)
        )
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: isAccelerating ? 1.0 / 30.0 : 1.0 / 8.0)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate
            let pulse = 0.84 + 0.16 * ((sin(phase * 2.8) + 1) / 2)

            GeometryReader { geo in
                let width = geo.size.width
                let height = geo.size.height
                let clamped = max(0, min(1, progress))
                let fillWidth = max(height, width * clamped)
                let shimmerWidth = max(26, width * 0.2)
                let shimmerTravel = width + shimmerWidth * 2
                let shimmerX = -shimmerWidth + shimmerTravel * CGFloat((phase / 1.8).truncatingRemainder(dividingBy: 1))

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(uiColor: .tertiarySystemFill))

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: isAccelerating
                                    ? [
                                        BolaTheme.accent.opacity(0.82),
                                        BolaTheme.accent,
                                        BolaTheme.accent.opacity(0.76)
                                    ]
                                    : [
                                        BolaTheme.accent.opacity(0.78),
                                        BolaTheme.accent
                                    ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: fillWidth)
                        .shadow(
                            color: isAccelerating ? BolaTheme.accent.opacity(0.24 * pulse) : .clear,
                            radius: isAccelerating ? 10 : 0,
                            x: 0,
                            y: 0
                        )
                        .overlay(alignment: .leading) {
                            if isAccelerating {
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                .white.opacity(0),
                                                .white.opacity(0.16),
                                                .white.opacity(0.42),
                                                .white.opacity(0.12),
                                                .white.opacity(0)
                                            ],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: shimmerWidth)
                                    .offset(x: shimmerX)
                                    .blendMode(.screen)
                            }
                        }
                        .mask(alignment: .leading) {
                            Capsule()
                                .frame(width: fillWidth)
                        }

                    if isAccelerating {
                        Capsule()
                            .stroke(BolaTheme.accent.opacity(0.20 + 0.16 * pulse), lineWidth: 1)
                    }
                }
                .overlay(alignment: .leading) {
                    if isAccelerating {
                        Circle()
                            .fill(Color.white.opacity(0.42))
                            .frame(width: height * 0.68, height: height * 0.68)
                            .blur(radius: 2)
                            .offset(x: max(2, fillWidth - height * 0.9))
                    }
                }
                .overlay {
                    if isAccelerating {
                        HStack(spacing: 4) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 9, weight: .bold))
                            Text("成长加速中")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(acceleratedDeepTint)
                        .padding(.horizontal, 10)
                        .shadow(color: .white.opacity(0.18), radius: 1, x: 0, y: 0)
                    }
                }
            }
        }
    }
}

#Preview("Home") {
    NavigationStack {
        IOSMainHomeView(
            companion: .constant(68),
            refreshSignal: .constant(0),
            isSyncing: .constant(false)
        )
    }
}

private extension UIColor {
    convenience init(blendedTowardsLabel base: UIColor, fraction: CGFloat) {
        let target = UIColor.label

        var r1: CGFloat = 0
        var g1: CGFloat = 0
        var b1: CGFloat = 0
        var a1: CGFloat = 0
        var r2: CGFloat = 0
        var g2: CGFloat = 0
        var b2: CGFloat = 0
        var a2: CGFloat = 0

        base.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        target.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)

        self.init(
            red: r1 + (r2 - r1) * fraction,
            green: g1 + (g2 - g1) * fraction,
            blue: b1 + (b2 - b1) * fraction,
            alpha: a1 + (a2 - a1) * fraction
        )
    }
}
