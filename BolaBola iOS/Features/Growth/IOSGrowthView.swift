//
//  IOSGrowthView.swift
//  成长 Tab：等级值、主视觉、每日任务（含翻转卡）、解锁图鉴。
//

import SwiftUI
import UIKit
import Lottie

struct IOSGrowthView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var dailyTasksVM = GrowthDailyTasksViewModel.shared
    @StateObject private var levelVM = GrowthLevelViewModel.shared
    @State private var showLevelInfo = false
    @State private var hasPerformedInitialLoad = false

    private var topRowDefinitions: [GrowthDailyTaskCardInstance] {
        Array(dailyTasksVM.dailyCards.prefix(2))
    }

    private var bottomRowDefinitions: [GrowthDailyTaskCardInstance] {
        Array(dailyTasksVM.dailyCards.suffix(3))
    }

    private var companionDisplayName: String { CompanionDisplayNameStore.resolved() }

    private var heroBubbleText: String {
        GrowthTaskHeroCopy.heroBubbleText(
            dailyCards: dailyTasksVM.dailyCards,
            surfacedCompletedCount: dailyTasksVM.surfacedCompletedCount,
            surfacedPendingCards: dailyTasksVM.surfacedPendingCards,
            allRandomTasksRevealed: dailyTasksVM.allRandomTasksRevealed,
            companionDisplayName: companionDisplayName
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            BolaGrowthAmbientBackground()
                .ignoresSafeArea(edges: [.top, .bottom])

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    /// 岛图 `offset` 会向上叠到等级条区域：等级条需更高 zIndex，避免被图挡在下面。
                    GrowthLevelValuePill(
                        companionDisplayName: companionDisplayName,
                        level: levelVM.level,
                        progressCurrent: levelVM.xpInLevel,
                        progressTarget: levelVM.xpForNextLevel,
                        onInfoTap: { showLevelInfo = true }
                    )
                    .padding(.top, -6)
                    .zIndex(2)

                    Spacer()
                        .frame(height: 5)

                    GrowthHeroSection(text: heroBubbleText)
                        .zIndex(0)

                    GrowthGroupedSection {
                        ZStack(alignment: .topTrailing) {
                            Image("backgroundstar")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 100)
                                .opacity(0.10)
                                .offset(x: 27, y: -1)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                            GrowthDailyTasksSection(viewModel: dailyTasksVM, topRow: topRowDefinitions, bottomRow: bottomRowDefinitions)
                                .padding(.bottom, 12)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: BolaTheme.cornerCard, style: .continuous))
                    .padding(.top, -14)

                    Spacer()
                        .frame(height: 36)

                    GrowthRewardGallerySection()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, BolaTheme.paddingHorizontal)
                .padding(.top, 0)
                .padding(.bottom, 28)
            }
            .contentMargins(.top, 0, for: .scrollContent)
            .background(Color.clear)
            .scrollIndicators(.hidden)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                dailyTasksVM.refreshRandomFlipStateIfNeeded()
                Task { await dailyTasksVM.refreshProgress() }
            }
        }
        .task {
            guard !hasPerformedInitialLoad else { return }
            hasPerformedInitialLoad = true
            await dailyTasksVM.refreshProgress()
        }
        .sheet(isPresented: $showLevelInfo) {
            NavigationStack {
                ScrollView {
                    Text("等级值用于解锁成长奖励与图鉴内容。任务、对话与里程碑会提升等级；当陪伴值达到 80 以上时，手表 App 打开期间的成长速度会额外加快。")
                        .font(.body)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
                .navigationTitle("等级值说明")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { showLevelInfo = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

}

// MARK: - 等级值条

private struct GrowthLevelValuePill: View {
    var companionDisplayName: String = "Bola"
    let level: Int
    let progressCurrent: Int
    let progressTarget: Int
    var onInfoTap: () -> Void = {}

    @State private var showProgressNumbers = false

    private var progressFraction: Double {
        let t = max(1, progressTarget)
        return min(1, max(0, Double(progressCurrent) / Double(t)))
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Button(action: onInfoTap) {
                HStack {
                    Spacer(minLength: 0)
                    GrowthLVStrokedLabel(level: level, fontSize: 22)
                    Spacer(minLength: 0)
                }
                .frame(width: 66, alignment: .center)
                .padding(.leading, 12)
                .padding(.trailing, 4)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            Rectangle()
                .fill(Color(uiColor: .separator).opacity(0.35))
                .frame(width: 1, height: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(companionDisplayName)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity, alignment: .leading)
                GeometryReader { geo in
                    let w = geo.size.width
                    let h: CGFloat = 11
                    let fillW = max(0, w * progressFraction)
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color(uiColor: .tertiarySystemFill))
                            .frame(width: w, height: h)
                        Capsule()
                            .fill(BolaTheme.accent)
                            .frame(width: fillW, height: h)
                    }
                    .frame(width: w, height: h, alignment: .leading)
                    .contentShape(Capsule())
                    .onTapGesture {
                        showProgressNumbers.toggle()
                    }
                    .overlay {
                        if showProgressNumbers {
                            Text("\(progressCurrent)/\(progressTarget)")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                                .monospacedDigit()
                                .shadow(color: .white.opacity(0.85), radius: 0, x: 0, y: 0)
                                .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1)
                                .allowsHitTesting(false)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("等级进度")
                    .accessibilityValue("\(progressCurrent) / \(progressTarget)")
                    .accessibilityAddTraits(.isButton)
                }
                .frame(height: 11)
            }
            .padding(.leading, 12)
            .padding(.trailing, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(BolaTheme.surfaceBubble)
                .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.25), lineWidth: 0.5)
        )
    }
}

private struct GrowthLVStrokedLabel: View {
    let level: Int
    var fontSize: CGFloat = 22
    private var text: String { "LV.\(level)" }
    private var font: Font { .system(size: fontSize, weight: .bold, design: .rounded) }

    var body: some View {
        ZStack {
            ForEach(0 ..< Self.offsets.count, id: \.self) { i in
                let o = Self.offsets[i]
                Text(text)
                    .font(font)
                    .foregroundStyle(Color.black.opacity(0.28))
                    .offset(x: o.width, y: o.height)
            }
            Text(text)
                .font(font)
                .foregroundStyle(BolaTheme.accent)
        }
    }

    private static let offsets: [CGSize] = [
        CGSize(width: -0.7, height: 0), CGSize(width: 0.7, height: 0),
        CGSize(width: 0, height: -0.7), CGSize(width: 0, height: 0.7),
        CGSize(width: -0.55, height: -0.55), CGSize(width: 0.55, height: -0.55),
        CGSize(width: -0.55, height: 0.55), CGSize(width: 0.55, height: 0.55)
    ]
}

// MARK: - 主界面同款浅灰分区底

private struct GrowthGroupedSection<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: BolaTheme.cornerCard, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            }
    }
}

// MARK: - 主视觉 + 气泡

private struct GrowthHeroSection: View {
    let text: String

    var body: some View {
        ZStack(alignment: .top) {
            Image("GrowthHeroIsland")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 288)
                .frame(maxWidth: .infinity)
                .offset(x: 12, y: -35)
                .accessibilityLabel("Bola 与树岛")
                .background(alignment: .center) {
                    // 渐变球：透明→主题色，不参与布局，仅视觉层
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.clear, BolaTheme.accent.opacity(0.65)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 440, height: 440)
                        .offset(y: -60)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .hidden()
                }

            GrowthSpeechBubble(text: text)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
                .zIndex(1)
        }
    }
}

private struct GrowthSpeechBubble: View {
    let text: String

    var body: some View {
        ZStack(alignment: .bottom) {
            Text(text)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 15)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .fill(BolaTheme.surfaceBubble)
                        .shadow(color: .black.opacity(0.07), radius: 8, x: 0, y: 2)
                )

            BubbleTail()
                .fill(BolaTheme.surfaceBubble)
                .frame(width: 16, height: 9)
                .offset(y: 4)
                .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 2)
        }
        .padding(.bottom, 2)
    }
}

private struct BubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

// MARK: - 每日任务

private struct GrowthDailyTasksSection: View {
    @ObservedObject var viewModel: GrowthDailyTasksViewModel
    let topRow: [GrowthDailyTaskCardInstance]
    let bottomRow: [GrowthDailyTaskCardInstance]
    private let rowSpacing: CGFloat = 10
    @State private var showAnimatedStar = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 0) {
                // 左：标题 + 副标题（固定不截断）
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 2) {
                        Text("每日任务")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.primary)
                            .fixedSize()
                        Group {
                            if showAnimatedStar {
                                LottieView(animation: LottieAnimation.named("GrowthDailyTasksStar"))
                                    .configure { $0.contentMode = .scaleAspectFill }
                                    .playing(loopMode: .loop)
                                    .resizable()
                            } else {
                                Image(systemName: "sparkle")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(BolaTheme.accent)
                            }
                        }
                        .frame(width: 28, height: 28)
                        .clipped()
                        .scaleEffect(x: -1, y: 1)
                        .offset(x: -6, y: -6)
                        .accessibilityHidden(true)
                    }
                    Text("今日 \(viewModel.surfacedCompletedCount)/\(viewModel.dailyCards.count) 完成")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(BolaTheme.figmaMutedBody.opacity(0.68))
                        .fixedSize()
                }

                Spacer().frame(width: 12)

                // 右：五个盖章
                HStack(spacing: 5) {
                    ForEach(0 ..< viewModel.dailyCards.count, id: \.self) { i in
                        GrowthTaskStamp(completed: i < viewModel.surfacedCompletedCount)
                    }
                }
                .padding(.leading, -9)
            }

            GrowthDailyTaskCardsGrid(
                viewModel: viewModel,
                topRow: topRow,
                bottomRow: bottomRow,
                rowSpacing: rowSpacing
            )
        }
        .onAppear {
            viewModel.refreshRandomFlipStateIfNeeded()
            guard !showAnimatedStar else { return }
            Task { @MainActor in
                await Task.yield()
                showAnimatedStar = true
            }
        }
    }
}

/// 与下方三列同宽，上方两张在整行内水平居中。使用自定义 `Layout` 给出稳定高度，避免 ScrollView 内 GeometryReader 高度为 0 导致与下方 section 重叠。
private struct GrowthDailyTaskCardsGrid: View {
    @ObservedObject var viewModel: GrowthDailyTasksViewModel
    let topRow: [GrowthDailyTaskCardInstance]
    let bottomRow: [GrowthDailyTaskCardInstance]
    let rowSpacing: CGFloat

    var body: some View {
        GrowthDailyTaskFiveCardLayout(rowSpacing: rowSpacing, horizontalSpacing: rowSpacing) {
            topCardView(index: 0)
            topCardView(index: 1)
            bottomCardView(index: 0)
            bottomCardView(index: 1)
            bottomCardView(index: 2)
        }
    }

    @ViewBuilder
    private func topCardView(index: Int) -> some View {
        GrowthPortraitTaskCard(
            card: topRow[index],
            progress: viewModel.progress(for: topRow[index].id)
        )
    }

    @ViewBuilder
    private func bottomCardView(index: Int) -> some View {
        GrowthFlippableTaskCard(
            card: bottomRow[index],
            progress: viewModel.progress(for: bottomRow[index].id),
            isRevealed: viewModel.isRandomTaskRevealed(id: bottomRow[index].id),
            onReveal: { viewModel.markRandomTaskRevealed(id: bottomRow[index].id) }
        )
    }
}

private struct GrowthDailyTaskFiveCardLayout: Layout {
    var rowSpacing: CGFloat
    var horizontalSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 5 else {
            return CGSize(width: proposal.width ?? 0, height: 1)
        }
        let w = proposal.width ?? 0
        guard w > 0 else {
            return CGSize(width: w, height: 1)
        }
        let cellW = (w - 2 * horizontalSpacing) / 3
        let cardH = cellW / GrowthDailyTaskModels.cardAspectRatio
        return CGSize(width: w, height: cardH * 2 + rowSpacing)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 5 else { return }
        let w = bounds.width
        let s = horizontalSpacing
        let cellW = (w - 2 * s) / 3
        let cardH = cellW / GrowthDailyTaskModels.cardAspectRatio
        let topLeftX = (w - 2 * cellW - s) / 2
        let prop = ProposedViewSize(width: cellW, height: cardH)

        subviews[0].place(at: CGPoint(x: bounds.minX + topLeftX, y: bounds.minY), anchor: .topLeading, proposal: prop)
        subviews[1].place(at: CGPoint(x: bounds.minX + topLeftX + cellW + s, y: bounds.minY), anchor: .topLeading, proposal: prop)

        let y2 = bounds.minY + cardH + rowSpacing
        subviews[2].place(at: CGPoint(x: bounds.minX, y: y2), anchor: .topLeading, proposal: prop)
        subviews[3].place(at: CGPoint(x: bounds.minX + cellW + s, y: y2), anchor: .topLeading, proposal: prop)
        subviews[4].place(at: CGPoint(x: bounds.minX + 2 * (cellW + s), y: y2), anchor: .topLeading, proposal: prop)
    }
}

// MARK: - 3:4 卡牌模版（分类底色 + 纹理；下半叠透明白 + 文案与完成度）

private enum GrowthTaskCardPalette {
    /// 聊天类沿用之前的亮黄色卡面。
    static let topYellow = Color(red: 1, green: 0.925, blue: 0.2)
    /// 下半区叠在整卡底色之上，半透明白让底下黄/纹理透出来
    static let bottomFill = Color.white.opacity(0.6)
    /// 上半区高度占比（约 6 : 4）
    static let topHeightFraction: CGFloat = 0.58

    private static let interactionBase = Color(hex: 0xFFC6A4)
    private static let lifeBase = Color(hex: 0xBCEDFF)

    static func cardGradient(for kind: GrowthDailyTaskCardSurfaceKind) -> LinearGradient {
        let base: Color
        switch kind {
        case .movement:
            base = topYellow
        case .interaction:
            base = interactionBase
        case .life:
            base = lifeBase
        case .chat:
            base = BolaTheme.accent
        }

        return LinearGradient(
            colors: [
                base.opacity(0.92),
                base.opacity(0.68)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static let cardBackGradient = LinearGradient(
        colors: [
            BolaTheme.accent.opacity(0.88),
            BolaTheme.accent.opacity(0.65)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static func symbolForeground(for kind: GrowthDailyTaskCardSurfaceKind) -> Color {
        switch kind {
        case .movement:
            return Color.black.opacity(0.32)
        case .chat, .interaction, .life:
            return Color.white.opacity(0.9)
        }
    }

    static func fabChevronColor(for kind: GrowthDailyTaskCardSurfaceKind) -> Color {
        return Color(uiColor: .tertiaryLabel)
    }

    /// 炫彩背面：与正面同向，颜色顺序不同形成差异感。
    static let shinyBackGradient = LinearGradient(
        colors: [
            Color(red: 0.74, green: 0.44, blue: 1.0),   // 紫罗兰
            Color(red: 1.0, green: 0.38, blue: 0.64),   // 玫红
            BolaTheme.accent,                            // 主题色：电光黄绿
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// 炫彩正面：对角全虹彩，以主题色为核心色锚。
    /// 色号直接改这里即可，SwiftUI Color(hex:) 用法：Color(hex: 0xFF6164)
    static let shinyFrontGradient = LinearGradient(
        colors: [
            Color(hex: 0xFF4245),
            Color(hex: 0xFFFF00),   // #FF6164 玫红
            Color(hex: 0xFFFFFF),
            /*Color(hex: 0xE5FF00),*/   // #E5FF00 主题黄绿
            Color(hex: 0xE8FF67),   //
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// 炫彩卡底部文案区：珍珠白调，带淡紫蓝色调。
    static let shinyBottomFill = LinearGradient(
        colors: [
            Color(red: 0.97, green: 0.94, blue: 1.0).opacity(0.90),
            Color(red: 0.94, green: 0.97, blue: 1.0).opacity(0.92),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let shinyStroke = LinearGradient(
        colors: [
            Color(red: 1.0, green: 0.60, blue: 0.78),   // 玫红
            Color.white.opacity(0.90),
            BolaTheme.accent,                            // 主题黄绿
            Color.white.opacity(0.90),
            Color(red: 0.10, green: 0.40, blue: 0.30).opacity(0.10),   // 橙（柔化）
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

private struct GrowthTaskCardYellowPatternOverlay: View {
    /// 单张纹理铺满卡片后旋转、略缩小；不用 `.tile`，否则整张图被重复平铺会像图案叠在一起。
    private let rotationDegrees: CGFloat = -40
    private let patternScale: CGFloat = 0.65
    var patternOpacity: CGFloat = 0.26

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let overscan = max(w, h) * 0.55
            Group {
                if let decoded = ImagePrewarmCache.shared.image(named: "GrowthTaskCardYellowPattern") {
                    Image(uiImage: decoded)
                        .resizable()
                } else {
                    Image("GrowthTaskCardYellowPattern")
                        .resizable()
                }
            }
            .scaledToFill()
            .frame(width: w + overscan, height: h + overscan)
            .scaleEffect(patternScale)
            .rotationEffect(.degrees(rotationDegrees))
            .position(x: w * 0.5, y: h * 0.5)
        }
        .clipped()
        .allowsHitTesting(false)
        .opacity(patternOpacity)
    }
}

private struct GrowthTaskCardShinyFoilOverlay: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { timeline in
            GeometryReader { geo in
                let size = geo.size
                let t = timeline.date.timeIntervalSinceReferenceDate
                // 每约 4.2 秒扫一次光带
                let sweepCycle = (t / 4.2).truncatingRemainder(dividingBy: 1.0)
                // 慢速色相旋转（11 秒一圈）
                let hue = Angle.degrees(360 * (t / 11.0).truncatingRemainder(dividingBy: 1.0))
                // 光带从左侧卡外扫到右侧卡外
                let sweepX = size.width * (sweepCycle * 2.6 - 0.8)
                // 呼吸光晕
                let glowPhase = (t * 0.55).truncatingRemainder(dividingBy: .pi * 2)
                let glowAlpha = 0.48 + 0.52 * sin(glowPhase)

                ZStack {
                    // 层 1：慢速色相旋转虹彩晕染
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.45, blue: 0.78).opacity(0.22),
                            Color.white.opacity(0.06),
                            Color(red: 0.45, green: 0.82, blue: 1.0).opacity(0.22),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .hueRotation(hue)
                    .blendMode(.screen)

                    // 层 2：固定斜向高光棱（模拟全息材质的折射纹路）
                    LinearGradient(
                        colors: [
                            .clear,
                            Color.white.opacity(0.22),
                            Color.white.opacity(0.05),
                            Color.white.opacity(0.16),
                            Color.white.opacity(0.03),
                            Color.white.opacity(0.12),
                            .clear,
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .blendMode(.screen)

                    // 层 3：主扫光（彩虹色带 + blur 柔化）
                    LinearGradient(
                        colors: [
                            .clear,
                            Color(red: 1.0, green: 0.55, blue: 0.75).opacity(0.18),
                            Color(red: 1.0, green: 0.88, blue: 0.50).opacity(0.28),
                            Color.white.opacity(0.38),
                            Color(red: 0.55, green: 0.92, blue: 1.0).opacity(0.28),
                            Color(red: 0.80, green: 0.60, blue: 1.0).opacity(0.18),
                            .clear,
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: size.width * 0.85, height: size.height * 3.0)
                    .blur(radius: 10)
                    .rotationEffect(.degrees(-22))
                    .position(x: sweepX, y: size.height * 0.5)
                    .blendMode(.screen)

                    // 层 4：中心呼吸光晕（带生命感）
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.32 * glowAlpha),
                            Color.white.opacity(0.10 * glowAlpha),
                            .clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: size.width * 0.40
                    )
                    .blendMode(.screen)
                }
                .saturation(1.15)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct GrowthPortraitTaskCard: View {
    let card: GrowthDailyTaskCardInstance
    let progress: Double
    private let cornerRadius: CGFloat = 16

    @State private var showXPToast = false
    @State private var toastOpacity: Double = 0
    @State private var toastOffset: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let topH = h * GrowthTaskCardPalette.topHeightFraction
            ZStack(alignment: .topTrailing) {
                cardFullBleedBackground()
                    .allowsHitTesting(false)

                VStack(spacing: 0) {
                    cardTopContent(height: topH)
                    cardBottomHalf(height: h - topH)
                }

                /// 与卡身同一次 `clipShape`；贴齐卡片上缘与右缘（无额外 inset）。
                growthTagChip()
                    .zIndex(1)
            }
        }
        .aspectRatio(GrowthDailyTaskModels.cardAspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.75), lineWidth: 1.0)
                .shadow(color: .white.opacity(0.30), radius: 8, x: 0, y: 0)
        }
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onTapGesture {
            let tab = card.definition.surfaceKind.destinationTab
            NotificationCenter.default.post(
                name: .bolaNavigateToTab,
                object: nil,
                userInfo: ["tab": tab.rawValue]
            )
        }
        .overlay(alignment: .center) {
            if showXPToast {
                Text("+\(card.xpReward) XP")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(
                        card.rarity.isShiny
                            ? AnyShapeStyle(LinearGradient(
                                colors: [Color(hex: 0xFF6164), Color(hex: 0xE5FF00), Color(hex: 0xFF8C2E)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                              ))
                            : AnyShapeStyle(Color.white)
                    )
                    .shadow(color: .black.opacity(0.18), radius: 4, x: 0, y: 2)
                    .offset(y: toastOffset)
                    .opacity(toastOpacity)
                    .allowsHitTesting(false)
            }
        }
        .onChange(of: progress) { _, new in
            if new >= 1.0 {
                triggerXPToast()
            }
        }
    }

    private func triggerXPToast() {
        guard !showXPToast else { return }
        showXPToast = true
        toastOpacity = 1.0
        toastOffset = 0
        withAnimation(.easeOut(duration: 1.4)) {
            toastOpacity = 0
            toastOffset = -44
        } completion: {
            showXPToast = false
            toastOffset = 0
        }
    }


    @ViewBuilder
    private func cardFullBleedBackground() -> some View {
        let baseFill = card.rarity.isShiny
            ? AnyShapeStyle(GrowthTaskCardPalette.shinyFrontGradient)
            : AnyShapeStyle(GrowthTaskCardPalette.cardGradient(for: card.definition.surfaceKind))
        ZStack {
            Rectangle().fill(baseFill)
            // 炫彩卡降低底纹 opacity，避免遮盖渐变色彩
            GrowthTaskCardYellowPatternOverlay(patternOpacity: card.rarity.isShiny ? 0.07 : 0.14)
            if card.rarity.isShiny {
                GrowthTaskCardShinyFoilOverlay()
            }
        }
    }

    private func growthTagChip() -> some View {
        let chipShape = UnevenRoundedRectangle(
            cornerRadii: RectangleCornerRadii(
                topLeading: 0,
                bottomLeading: 8,
                bottomTrailing: 0,
                /// 与卡片 `cornerRadius` 一致，外缘贴齐卡片右上角圆弧。
                topTrailing: cornerRadius
            ),
            style: .continuous
        )
        return Text(card.definition.tag)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.top, 4)
            .padding(.bottom, 5)
            .background(
                chipShape.fill(
                    card.rarity.isShiny
                        ? AnyShapeStyle(.ultraThinMaterial)
                        : AnyShapeStyle(Color.black.opacity(0.22))
                )
            )
    }

    private func growthCardFAB() -> some View {
        ZStack {
            Circle()
                .fill(Color.white)
                .shadow(color: .black.opacity(0.08), radius: 3, x: 0, y: 1)
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(fabChevronColor)
        }
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
    }

    private var fabChevronColor: Color {
        GrowthTaskCardPalette.fabChevronColor(for: card.definition.surfaceKind)
    }

    private var placeholderSymbolForeground: Color {
        GrowthTaskCardPalette.symbolForeground(for: card.definition.surfaceKind)
    }

    /// 透明底插图在画布内视觉重心常偏上，相对几何中心略下移。
    private static let illustrationVisualOffsetY: CGFloat = 5

    @ViewBuilder
    private func cardTopContent(height: CGFloat) -> some View {
        ZStack {
            // 背景由外层整卡 ZStack 提供，此处仅内容。
            Group {
                if let asset = card.definition.illustrationAssetName {
                    Image(asset)
                        .resizable()
                        .scaledToFit()
                        .padding(.horizontal, 10)
                        .offset(y: Self.illustrationVisualOffsetY)
                } else {
                    Image(systemName: card.definition.placeholderSystemImage)
                        .font(.system(size: 40, weight: .medium))
                        .foregroundStyle(placeholderSymbolForeground)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

            VStack {
                Spacer(minLength: 0)
                HStack {
                    Spacer(minLength: 0)
                    growthCardFAB()
                }
                .padding(.trailing, 8)
                .padding(.bottom, 8)
            }
        }
        .frame(height: height)
        .clipped()
    }

    private func cardBottomHalf(height: CGFloat) -> some View {
        ZStack {
            GrowthTaskCardPalette.bottomFill
            VStack(alignment: .center, spacing: 0) {
                Text(card.definition.detailLine1)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                Text(card.definition.detailLine2)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(BolaTheme.figmaMutedBody)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 3)

                GrowthTaskCompletionBar(progress: progress, taskId: card.id)
                    .padding(.top, 6)
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 20)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
    }
}

private struct GrowthFlippableTaskCard: View {
    let card: GrowthDailyTaskCardInstance
    let progress: Double
    let isRevealed: Bool
    let onReveal: () -> Void

    @State private var animatedFlipDegrees: Double = 180
    @State private var isAnimatingFlip = false

    var body: some View {
        Button {
            guard !isRevealed, !isAnimatingFlip else { return }
            animatedFlipDegrees = 180
            isAnimatingFlip = true
            onReveal()
            withAnimation(.spring(response: 0.52, dampingFraction: 0.82)) {
                animatedFlipDegrees = 0
            } completion: {
                isAnimatingFlip = false
            }
        } label: {
            if isAnimatingFlip {
                ZStack {
                    GrowthPortraitTaskCard(card: card, progress: progress)
                        .opacity(animatedFlipDegrees < 90 ? 1 : 0)

                    GrowthTaskCardBack(rarity: card.rarity)
                        .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                        .opacity(animatedFlipDegrees < 90 ? 0 : 1)
                }
                .rotation3DEffect(
                    .degrees(animatedFlipDegrees),
                    axis: (x: 0, y: 1, z: 0),
                    anchor: .center,
                    anchorZ: 0,
                    perspective: 0.52
                )
            } else if isRevealed {
                GrowthPortraitTaskCard(card: card, progress: progress)
            } else {
                GrowthTaskCardBack(rarity: card.rarity)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(isRevealed ? "随机任务，已翻开" : "随机任务，轻点翻面")
    }
}

private struct GrowthTaskCardBack: View {
    let rarity: GrowthDailyTaskRarity
    private let cornerRadius: CGFloat = 16

    var body: some View {
        let backFill = rarity.isShiny
            ? AnyShapeStyle(GrowthTaskCardPalette.shinyBackGradient)
            : AnyShapeStyle(GrowthTaskCardPalette.cardBackGradient)
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(backFill)

            GrowthTaskCardYellowPatternOverlay(patternOpacity: rarity.isShiny ? 0.08 : 0.18)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

            if rarity.isShiny {
                GrowthTaskCardShinyFoilOverlay()
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }

            if rarity.isShiny {
                ZStack {
                    backSilhouetteImage(named: "GrowthCardShinyBackSilhouette")
                        .opacity(0.45)
                    Text("?")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white)
                        .shadow(color: .white.opacity(0.60), radius: 6, x: 0, y: 0)
                }
            } else {
                ZStack {
                    backSilhouetteImage(named: "GrowthCardBackSilhouette")
                    Text("?")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(BolaTheme.surfaceBubble)
                }
            }
        }
        .aspectRatio(GrowthDailyTaskModels.cardAspectRatio, contentMode: .fit)
        .shadow(
            color: .black.opacity(0.06),
            radius: 8,
            x: 0, y: 3
        )
    }

    @ViewBuilder
    private func backSilhouetteImage(named name: String) -> some View {
        if let decoded = ImagePrewarmCache.shared.image(named: name) {
            Image(uiImage: decoded)
                .resizable()
                .scaledToFit()
                .frame(width: 42, height: 42)
                .offset(y: -1)
        } else {
            Image(name)
                .resizable()
                .scaledToFit()
                .frame(width: 42, height: 42)
                .offset(y: -1)
        }
    }
}

// MARK: - 任务完成庆祝 Lottie（UIKit 直驱播放）

private enum GrowthTaskCongratulationsLottieLoader {
    /// 同步文件夹在部分打包方式下会出现在子目录，故先试子路径再回退根目录。
    static func animation() -> LottieAnimation? {
        let bundle = Bundle.main
        if let a = LottieAnimation.named("GrowthTaskCongratulations", bundle: bundle, subdirectory: "Features/Growth") {
            return a
        }
        return LottieAnimation.named("GrowthTaskCongratulations", bundle: bundle)
    }
}

/// SwiftUI `LottieView` 在部分机型上对「首帧即播放」应用不稳定；此处用 `LottieAnimationView` 显式 `play`。
/// `LottieAnimationView` 的固有尺寸等于动画画布（如 720×720），会撑破外层 `frame`；必须放进固定大小的容器并 `scaleAspectFit` 铺满。
private struct GrowthTaskCongratulationsLottiePlayer: UIViewRepresentable {
    let animation: LottieAnimation?
    /// `false` 表示只显示最后一帧（已看过或播完后的静帧）。
    let playCelebration: Bool
    let onPlaybackFinished: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPlaybackFinished: onPlaybackFinished)
    }

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.clipsToBounds = true
        container.backgroundColor = .clear

        let configuration = LottieConfiguration(
            renderingEngine: .automatic,
            reducedMotionOption: .standardMotion
        )
        let lottie = LottieAnimationView(animation: animation, configuration: configuration)
        lottie.contentMode = .scaleAspectFit
        lottie.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(lottie)

        NSLayoutConstraint.activate([
            lottie.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            lottie.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            lottie.topAnchor.constraint(equalTo: container.topAnchor),
            lottie.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        context.coordinator.lottieView = lottie
        return container
    }

    func updateUIView(_ container: UIView, context: Context) {
        guard let lottie = context.coordinator.lottieView else { return }
        if lottie.animation !== animation {
            lottie.animation = animation
        }
        guard animation != nil else { return }

        if playCelebration {
            context.coordinator.startPlaybackIfNeeded(on: lottie, container: container)
        } else {
            lottie.currentProgress = 1.0
        }
    }

    final class Coordinator {
        fileprivate var lottieView: LottieAnimationView?
        private let onPlaybackFinished: (Bool) -> Void
        private var hasStartedPlayback = false

        init(onPlaybackFinished: @escaping (Bool) -> Void) {
            self.onPlaybackFinished = onPlaybackFinished
        }

        /// 首帧 `updateUIView` 时常尚未布局，`bounds` 为 0，此时 `play` 会几乎看不到运动；延后到下一帧并等到尺寸有效后再播。
        func startPlaybackIfNeeded(on view: LottieAnimationView, container: UIView) {
            guard !hasStartedPlayback else { return }
            hasStartedPlayback = true
            view.currentProgress = 0

            DispatchQueue.main.async { [weak self, weak view, weak container] in
                guard let self, let view, let container else { return }
                self.playWhenLaidOut(view: view, container: container, attempt: 0)
            }
        }

        private func playWhenLaidOut(view: LottieAnimationView, container: UIView, attempt: Int) {
            container.superview?.layoutIfNeeded()
            container.layoutIfNeeded()
            view.layoutIfNeeded()

            let w = container.bounds.width
            let h = container.bounds.height
            if w < 0.5 || h < 0.5, attempt < 25 {
                DispatchQueue.main.async { [weak self, weak view, weak container] in
                    guard let self, let view, let container else { return }
                    self.playWhenLaidOut(view: view, container: container, attempt: attempt + 1)
                }
                return
            }

            view.play(fromProgress: 0, toProgress: 1, loopMode: .playOnce) { [onPlaybackFinished] completed in
                onPlaybackFinished(completed)
            }
        }
    }
}

// MARK: - 盖章（任务完成状态）

private struct GrowthTaskStamp: View {
    let completed: Bool

    var body: some View {
        ZStack {
            Image(completed ? "GrowthStampDone" : "GrowthStampEmpty")
                .resizable()
                .scaledToFit()
                .frame(width: 37, height: 37)

            if completed {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.green)
            }
        }
        .accessibilityHidden(true)
    }
}

private enum GrowthTaskCompletionBarMetrics {
    /// 与标题旁星星 Lottie（28pt）同量级，略放大便于看清动效。
    static let celebrationLottieSide: CGFloat = 32
}

/// 「完成度」+ 进度条，直接贴在任务文案下方，不再使用独立白底卡片。
/// 任务完成时：首次展示播放一遍 Lottie 庆祝动画，之后只展示最后一帧静帧。
private struct GrowthTaskCompletionBar: View {
    let progress: Double
    let taskId: String

    /// 播完后置为 true，驱动切到静帧；持久化见 `GrowthTaskCompletionAnimStore`。
    @State private var animationFinished: Bool = false

    /// 每次从 Store 读（debug 清空记录后才会重播），勿用仅 init 一次的 @State 缓存。
    private var seenInStore: Bool {
        GrowthTaskCompletionAnimStore.hasSeen(taskId: taskId)
    }

    /// 与进度条行同结构的占位，完成时用 `opacity(0)` 隐藏但继续参与布局，避免白底区被挤压变形。
    @ViewBuilder
    private func progressTrackRow(progress visibleProgress: Double, hidden: Bool) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text("进度")
                .font(.system(size: 7, weight: .medium))
                .foregroundStyle(Color(uiColor: .secondaryLabel))
                .fixedSize()

            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(uiColor: .tertiarySystemFill))
                        .frame(height: 5)
                    Capsule()
                        .fill(BolaTheme.accent)
                        .frame(width: max(4, w * visibleProgress), height: 5)
                }
            }
            .frame(height: 5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(hidden ? 0 : 1)
        .accessibilityHidden(hidden)
    }

    var body: some View {
        let isComplete = progress >= 1.0
        let showStatic = seenInStore || animationFinished

        progressTrackRow(progress: min(1, progress), hidden: isComplete)
            .overlay(alignment: .center) {
                if isComplete {
                    congratulationsLottieOverlay(
                        showStatic: showStatic,
                        taskId: taskId,
                        animationFinished: $animationFinished
                    )
                    .allowsHitTesting(false)
                }
            }
            .onChange(of: progress) { _, new in
                if new < 1.0 {
                    animationFinished = false
                }
            }
    }

    private func congratulationsLottieOverlay(
        showStatic: Bool,
        taskId: String,
        animationFinished: Binding<Bool>
    ) -> some View {
        GrowthTaskCongratulationsLottiePlayer(
            animation: GrowthTaskCongratulationsLottieLoader.animation(),
            playCelebration: !showStatic,
            onPlaybackFinished: { completed in
                guard completed else { return }
                GrowthTaskCompletionAnimStore.markSeen(taskId: taskId)
                animationFinished.wrappedValue = true
            }
        )
        .frame(width: GrowthTaskCompletionBarMetrics.celebrationLottieSide, height: GrowthTaskCompletionBarMetrics.celebrationLottieSide)
        .offset(y: -2)
        .id(taskId)
    }
}

// MARK: - 解锁图鉴

private struct GrowthRewardGallerySection: View {
    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]
    private let totalCellCount = 12
    @State private var unlockedOrderedIds = SpecialAnimationUnlockStore.loadUnlockedOrderedIds()
    @State private var seenIds = SpecialAnimationSeenStore.loadSeenIds()
    @State private var pendingSeenIds: Set<String> = []
    @State private var showGiftLottie = false
    #if DEBUG
    @State private var debugAllRewardsUnlocked = !SpecialAnimationUnlockStore.loadUnlockedOrderedIds().isEmpty
    #endif

    var body: some View {
        GrowthGroupedSection {
            /// 外层 `spacing`：主标题区（含副标题）与下方格子之间的距离。
            /// 内层 `spacing`：主标题行与副标题文案之间的距离。
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .center, spacing: 8) {
                        HStack(alignment: .center, spacing: 3) {
                            Text("完成任务解锁更多奖励")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(.primary)
                            Group {
                                if showGiftLottie {
                                    LottieView(animation: LottieAnimation.named("GrowthRewardGiftPremium"))
                                        .configure { $0.contentMode = .scaleAspectFill }
                                        .playing(loopMode: .loop)
                                        .resizable()
                                } else {
                                    Image(systemName: "gift.fill")
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundStyle(BolaTheme.accent)
                                }
                            }
                            .frame(width: 28, height: 28)
                            .clipped()
                            .offset(y: -3)
                            .accessibilityHidden(true)
                        }

                        Spacer(minLength: 8)

                        #if DEBUG
                        Button {
                            debugAllRewardsUnlocked.toggle()
                            if debugAllRewardsUnlocked {
                                SpecialAnimationUnlockStore.saveOrdered(
                                    SpecialAnimationRewardBank.all.map(\.id)
                                )
                            } else {
                                SpecialAnimationUnlockStore.saveOrdered([])
                                SpecialAnimationSeenStore.clear()
                            }
                            unlockedOrderedIds = SpecialAnimationUnlockStore.loadUnlockedOrderedIds()
                            seenIds = SpecialAnimationSeenStore.loadSeenIds()
                            pendingSeenIds = Set(unlockedOrderedIds).subtracting(seenIds)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: debugAllRewardsUnlocked ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("测试")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundStyle(debugAllRewardsUnlocked ? BolaTheme.accent : .secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.white.opacity(0.72))
                            )
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(Color(uiColor: .separator).opacity(0.28), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        #endif
                    }
                    Text("加油完成任务，解锁更多奖励吧！")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(BolaTheme.figmaMutedBody.opacity(0.68))
                }

                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(0 ..< totalCellCount, id: \.self) { index in
                        if let reward = rewardForCell(at: index) {
                            GrowthRewardCell(
                                reward: reward,
                                unlocked: true,
                                isNew: pendingSeenIds.contains(reward.id)
                            )
                        } else {
                            GrowthRewardLockedPlaceholderCell()
                        }
                    }
                }
            }
            .padding(.bottom, 20)
        }
        .onAppear {
            guard !showGiftLottie else { return }
            Task { @MainActor in
                await Task.yield()
                showGiftLottie = true
            }
            seenIds = SpecialAnimationSeenStore.loadSeenIds()
            pendingSeenIds = Set(unlockedOrderedIds).subtracting(seenIds)
        }
        .onDisappear {
            SpecialAnimationSeenStore.markSeen(pendingSeenIds)
            seenIds = SpecialAnimationSeenStore.loadSeenIds()
            pendingSeenIds.removeAll()
        }
        .onReceive(NotificationCenter.default.publisher(for: .bolaSpecialAnimationUnlocksDidChange)) { _ in
            unlockedOrderedIds = SpecialAnimationUnlockStore.loadUnlockedOrderedIds()
            pendingSeenIds.formUnion(Set(unlockedOrderedIds).subtracting(seenIds))
            #if DEBUG
            debugAllRewardsUnlocked = unlockedOrderedIds.count == SpecialAnimationRewardBank.all.count
            #endif
        }
        .onReceive(NotificationCenter.default.publisher(for: .bolaSpecialAnimationSeenStateDidChange)) { _ in
            seenIds = SpecialAnimationSeenStore.loadSeenIds()
            pendingSeenIds.subtract(seenIds)
        }
    }

    private func rewardForCell(at index: Int) -> SpecialAnimationRewardDefinition? {
        guard unlockedOrderedIds.indices.contains(index) else { return nil }
        return SpecialAnimationRewardBank.definition(for: unlockedOrderedIds[index])
    }
}

private struct GrowthRewardCell: View {
    let reward: SpecialAnimationRewardDefinition
    let unlocked: Bool
    let isNew: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black)
                .aspectRatio(1, contentMode: .fit)

            if unlocked {
                if UIImage(named: reward.previewAssetName) != nil {
                    Image(reward.previewAssetName)
                        .resizable()
                        .scaledToFit()
                        .padding(4)
                } else {
                    Text(reward.fallbackEmoji)
                        .font(.system(size: 28))
                }
            } else {
                Image(systemName: "lock.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .overlay(alignment: .topTrailing) {
            if isNew {
                Text("NEW")
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(.red)
                    .padding(4)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(reward.title)
        .accessibilityValue(isNew ? "新解锁" : (unlocked ? "已解锁" : "未解锁"))
    }
}

private struct GrowthRewardLockedPlaceholderCell: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black)
                .aspectRatio(1, contentMode: .fit)

            Image(systemName: "lock.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("未解锁奖励")
        .accessibilityValue("未解锁")
    }
}

#Preview("成长") {
    NavigationStack {
        IOSGrowthView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                // Preview 每次刷新重置翻面状态，方便查看背面
                GrowthRandomCardFlipStore.debugClearRandomRevealed()
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("成长")
                        .font(.system(size: 20, weight: .semibold))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    IOSNavigationGlassIconButton(
                        systemName: "gearshape.fill",
                        font: .system(size: 18, weight: .medium),
                        accessibilityLabel: "设置"
                    ) { }
                }
            }
    }
    .tint(Color(UIColor.label))
}
