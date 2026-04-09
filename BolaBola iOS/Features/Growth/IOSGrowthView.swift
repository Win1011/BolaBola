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

    private var topRowDefinitions: [GrowthDailyTaskCardDefinition] {
        Array(dailyTasksVM.definitions.prefix(2))
    }

    private var bottomRowDefinitions: [GrowthDailyTaskCardDefinition] {
        Array(dailyTasksVM.definitions.suffix(3))
    }

    private var companionDisplayName: String { CompanionDisplayNameStore.resolved() }

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

                    GrowthHeroSection()
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
            }
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

            GrowthSpeechBubble(text: "快来翻翻看今天的三个随机任务！")
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
    let topRow: [GrowthDailyTaskCardDefinition]
    let bottomRow: [GrowthDailyTaskCardDefinition]
    private let rowSpacing: CGFloat = 10

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
                        LottieView(animation: LottieAnimation.named("GrowthDailyTasksStar"))
                            .configure { $0.contentMode = .scaleAspectFill }
                            .playing(loopMode: .loop)
                            .resizable()
                            .frame(width: 28, height: 28)
                            .clipped()
                            .scaleEffect(x: -1, y: 1)
                            .offset(x: -6, y: -6)
                            .accessibilityHidden(true)
                    }
                    Text("今日 \(viewModel.completedCount)/\(viewModel.definitions.count) 完成")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(BolaTheme.figmaMutedBody.opacity(0.68))
                        .fixedSize()
                }

                Spacer().frame(width: 12)

                // 右：五个盖章
                HStack(spacing: 5) {
                    ForEach(0 ..< viewModel.definitions.count, id: \.self) { i in
                        GrowthTaskStamp(completed: i < viewModel.completedCount)
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
        }
    }
}

/// 与下方三列同宽，上方两张在整行内水平居中。使用自定义 `Layout` 给出稳定高度，避免 ScrollView 内 GeometryReader 高度为 0 导致与下方 section 重叠。
private struct GrowthDailyTaskCardsGrid: View {
    @ObservedObject var viewModel: GrowthDailyTasksViewModel
    let topRow: [GrowthDailyTaskCardDefinition]
    let bottomRow: [GrowthDailyTaskCardDefinition]
    let rowSpacing: CGFloat

    var body: some View {
        GrowthDailyTaskFiveCardLayout(rowSpacing: rowSpacing, horizontalSpacing: rowSpacing) {
            GrowthPortraitTaskCard(
                definition: topRow[0],
                progress: viewModel.progress(for: topRow[0].id)
            )
            GrowthPortraitTaskCard(
                definition: topRow[1],
                progress: viewModel.progress(for: topRow[1].id)
            )
            GrowthFlippableTaskCard(
                definition: bottomRow[0],
                progress: viewModel.progress(for: bottomRow[0].id),
                isRevealed: viewModel.isRandomTaskRevealed(id: bottomRow[0].id),
                onReveal: { viewModel.markRandomTaskRevealed(id: bottomRow[0].id) }
            )
            GrowthFlippableTaskCard(
                definition: bottomRow[1],
                progress: viewModel.progress(for: bottomRow[1].id),
                isRevealed: viewModel.isRandomTaskRevealed(id: bottomRow[1].id),
                onReveal: { viewModel.markRandomTaskRevealed(id: bottomRow[1].id) }
            )
            GrowthFlippableTaskCard(
                definition: bottomRow[2],
                progress: viewModel.progress(for: bottomRow[2].id),
                isRevealed: viewModel.isRandomTaskRevealed(id: bottomRow[2].id),
                onReveal: { viewModel.markRandomTaskRevealed(id: bottomRow[2].id) }
            )
        }
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
    /// 卡面底色（与纹理一起铺满整张卡）
    static let topYellow = Color(red: 1, green: 0.925, blue: 0.2)
    /// 下半区叠在整卡底色之上，半透明白让底下黄/纹理透出来
    static let bottomFill = Color.white.opacity(0.7)
    /// 上半区高度占比（约 6 : 4）
    static let topHeightFraction: CGFloat = 0.58

    /// 与卡背、散步卡正面一致的主色渐变。
    static let accentCardGradient = LinearGradient(
        colors: [
            BolaTheme.accent.opacity(0.88),
            BolaTheme.accent.opacity(0.65)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// 随机任务正面：偏弱主色，与亮黄卡区分。
    static let accentMutedCardGradient = LinearGradient(
        colors: [
            BolaTheme.accent.opacity(0.52),
            BolaTheme.accent.opacity(0.34)
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
            Image("GrowthTaskCardYellowPattern")
                .resizable()
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

private struct GrowthPortraitTaskCard: View {
    let definition: GrowthDailyTaskCardDefinition
    let progress: Double
    private let cornerRadius: CGFloat = 16

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
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
    }

    @ViewBuilder
    private func cardFullBleedBackground() -> some View {
        switch definition.surfaceKind {
        case .accentGradient:
            ZStack {
                Rectangle().fill(GrowthTaskCardPalette.accentCardGradient)
                GrowthTaskCardYellowPatternOverlay(patternOpacity: 0.14)
            }
        case .yellowPattern:
            ZStack {
                GrowthTaskCardPalette.topYellow
                GrowthTaskCardYellowPatternOverlay()
            }
        case .accentMuted:
            ZStack {
                Rectangle().fill(GrowthTaskCardPalette.accentMutedCardGradient)
                GrowthTaskCardYellowPatternOverlay(patternOpacity: 0.18)
            }
        }
    }

    private func growthTagChip() -> some View {
        Text(definition.tag)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.top, 4)
            .padding(.bottom, 5)
            .background(
                UnevenRoundedRectangle(
                    cornerRadii: RectangleCornerRadii(
                        topLeading: 0,
                        bottomLeading: 8,
                        bottomTrailing: 0,
                        /// 与卡片 `cornerRadius` 一致，外缘贴齐卡片右上角圆弧。
                        topTrailing: cornerRadius
                    ),
                    style: .continuous
                )
                .fill(Color.black.opacity(0.22))
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
        switch definition.surfaceKind {
        case .yellowPattern:
            return Color(red: 0.82, green: 0.72, blue: 0.05)
        case .accentGradient, .accentMuted:
            return BolaTheme.onAccentForeground.opacity(0.88)
        }
    }

    private var placeholderSymbolForeground: Color {
        switch definition.surfaceKind {
        case .yellowPattern:
            return Color.black.opacity(0.32)
        case .accentGradient, .accentMuted:
            return Color.white.opacity(0.9)
        }
    }

    /// 透明底插图在画布内视觉重心常偏上，相对几何中心略下移。
    private static let illustrationVisualOffsetY: CGFloat = 5

    @ViewBuilder
    private func cardTopContent(height: CGFloat) -> some View {
        ZStack {
            // 背景由外层整卡 ZStack 提供，此处仅内容。
            Group {
                if let asset = definition.illustrationAssetName {
                    Image(asset)
                        .resizable()
                        .scaledToFit()
                        .padding(.horizontal, 10)
                        .offset(y: Self.illustrationVisualOffsetY)
                } else {
                    Image(systemName: definition.placeholderSystemImage)
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
                Text(definition.detailLine1)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                Text(definition.detailLine2)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(BolaTheme.figmaMutedBody)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 3)

                GrowthTaskCompletionBar(progress: progress, taskId: definition.id)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 10)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
    }
}

private struct GrowthFlippableTaskCard: View {
    let definition: GrowthDailyTaskCardDefinition
    let progress: Double
    let isRevealed: Bool
    let onReveal: () -> Void

    @State private var flipDegrees: Double

    init(
        definition: GrowthDailyTaskCardDefinition,
        progress: Double,
        isRevealed: Bool,
        onReveal: @escaping () -> Void
    ) {
        self.definition = definition
        self.progress = progress
        self.isRevealed = isRevealed
        self.onReveal = onReveal
        _flipDegrees = State(initialValue: isRevealed ? 0 : 180)
    }

    var body: some View {
        Button {
            guard !isRevealed else { return }
            withAnimation(.spring(response: 0.52, dampingFraction: 0.82)) {
                flipDegrees = 0
            }
            onReveal()
        } label: {
            ZStack {
                GrowthPortraitTaskCard(definition: definition, progress: progress)
                    .opacity(flipDegrees < 90 ? 1 : 0)

                GrowthTaskCardBack()
                    .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                    .opacity(flipDegrees < 90 ? 0 : 1)
            }
            .rotation3DEffect(
                .degrees(flipDegrees),
                axis: (x: 0, y: 1, z: 0),
                anchor: .center,
                anchorZ: 0,
                perspective: 0.52
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(isRevealed ? "随机任务，已翻开" : "随机任务，轻点翻面")
        .onChange(of: isRevealed) { _, new in
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                flipDegrees = new ? 0 : 180
            }
        }
    }
}

private struct GrowthTaskCardBack: View {
    private let cornerRadius: CGFloat = 16

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(GrowthTaskCardPalette.accentCardGradient)

            GrowthTaskCardYellowPatternOverlay()
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(BolaTheme.mascotSilhouette)
                        .frame(width: 44, height: 44)
                    Text("?")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(BolaTheme.surfaceBubble)
                }
            }
        }
        .aspectRatio(GrowthDailyTaskModels.cardAspectRatio, contentMode: .fit)
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
            Text("完成度")
                .font(.system(size: 10, weight: .medium))
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

    private let cells: [(unlocked: Bool, emoji: String?)] = [
        (true, "🥳"), (true, "😢"), (true, "🎉"),
        (false, nil), (true, "💛"), (false, nil),
        (false, nil), (false, nil), (true, "✨"),
        (false, nil), (false, nil), (false, nil)
    ]

    var body: some View {
        GrowthGroupedSection {
            /// 外层 `spacing`：主标题区（含副标题）与下方格子之间的距离。
            /// 内层 `spacing`：主标题行与副标题文案之间的距离。
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .center, spacing: 3) {
                        Text("完成任务解锁更多奖励")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.primary)
                        LottieView(animation: LottieAnimation.named("GrowthRewardGiftPremium"))
                            .configure { $0.contentMode = .scaleAspectFill }
                            .playing(loopMode: .loop)
                            .resizable()
                            .frame(width: 28, height: 28)
                            .clipped()
                            .offset(y: -3)
                            .accessibilityHidden(true)
                    }
                    Text("加油完成任务，解锁更多奖励吧！")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(BolaTheme.figmaMutedBody.opacity(0.68))
                }

                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(cells.indices, id: \.self) { i in
                        GrowthRewardCell(unlocked: cells[i].unlocked, emoji: cells[i].emoji)
                    }
                }
            }
        }
    }
}

private struct GrowthRewardCell: View {
    let unlocked: Bool
    let emoji: String?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(BolaTheme.mascotSilhouette)
                .aspectRatio(1, contentMode: .fit)

            if unlocked, let emoji {
                Text(emoji)
                    .font(.system(size: 28))
            } else {
                Image(systemName: "lock.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
    }
}

#Preview("成长") {
    NavigationStack {
        IOSGrowthView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
