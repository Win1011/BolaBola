//
//  IOSGrowthView.swift
//  成长 Tab：等级值、主视觉、每日任务（含翻转卡）、解锁图鉴。
//

import SwiftUI
import UIKit
import Lottie

struct IOSGrowthView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var dailyTasksVM = GrowthDailyTasksViewModel()
    private let level: Int = 1
    /// 当前等级内已获得的进度点（占位，后续可接真实成长数值）。
    private let levelProgressCurrent: Int = 7
    /// 升到下一级所需进度点（占位）。
    private let levelProgressTarget: Int = 20
    @State private var showLevelInfo = false

    private var topRowDefinitions: [GrowthDailyTaskCardDefinition] {
        Array(dailyTasksVM.definitions.prefix(2))
    }

    private var bottomRowDefinitions: [GrowthDailyTaskCardDefinition] {
        Array(dailyTasksVM.definitions.suffix(3))
    }

    var body: some View {
        ZStack(alignment: .top) {
            BolaGrowthAmbientBackground()
                .ignoresSafeArea(edges: [.top, .bottom])

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    /// 岛图 `offset` 会向上叠到等级条区域：等级条需更高 zIndex，避免被图挡在下面。
                    GrowthLevelValuePill(
                        level: level,
                        progressCurrent: levelProgressCurrent,
                        progressTarget: levelProgressTarget,
                        onInfoTap: { showLevelInfo = true }
                    )
                    .padding(.top, -6)
                    .zIndex(2)

                    Spacer()
                        .frame(height: 5)

                    GrowthHeroSection()
                        .zIndex(0)

                    GrowthDailyTasksSection(viewModel: dailyTasksVM, topRow: topRowDefinitions, bottomRow: bottomRowDefinitions)
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
                    Text("等级值用于解锁成长奖励与图鉴内容，具体规则将在后续版本完善。")
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
            HStack {
                Spacer(minLength: 0)
                GrowthLVStrokedLabel(level: level, fontSize: 22)
                Spacer(minLength: 0)
            }
            .frame(width: 66, alignment: .center)
            .padding(.leading, 12)
            .padding(.trailing, 4)
            .padding(.vertical, 10)

            Rectangle()
                .fill(Color(uiColor: .separator).opacity(0.35))
                .frame(width: 1, height: 34)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 5) {
                    Text("等级值")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(BolaTheme.figmaMutedBody)
                    Button(action: onInfoTap) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(BolaTheme.figmaMutedBody)
                    }
                    .buttonStyle(.plain)
                }

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
            .padding(.vertical, 10)
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
            HStack(spacing: 0) {
                HStack(spacing: 0) {
                    LottieView(animation: LottieAnimation.named("GrowthDailyTasksStar"))
                        .configure { $0.contentMode = .scaleAspectFill }
                        .playing(loopMode: .loop)
                        .resizable()
                        .frame(width: 34, height: 34)
                        .clipped()
                        .accessibilityHidden(true)
                    Text("每日任务")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.primary)
                        .padding(.leading, -3)
                }
                Spacer(minLength: 0)
                Button {
                    viewModel.debugRefreshDailyTasks()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(BolaTheme.figmaMutedBody)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("刷新每日任务")
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

// MARK: - 3:4 卡牌模版（亮黄 + 纹理铺满全卡；下半叠透明白 + 文案与完成度）

private enum GrowthTaskCardPalette {
    /// 卡面底色（与纹理一起铺满整张卡）
    static let topYellow = Color(red: 1, green: 0.925, blue: 0.2)
    /// 下半区叠在整卡底色之上，半透明白让底下黄/纹理透出来
    static let bottomFill = Color.white.opacity(0.7)
    /// 上半区高度占比（约 6 : 4）
    static let topHeightFraction: CGFloat = 0.58
}

private struct GrowthTaskCardYellowPatternOverlay: View {
    /// 单张纹理铺满卡片后旋转、略缩小；不用 `.tile`，否则整张图被重复平铺会像图案叠在一起。
    private let rotationDegrees: CGFloat = -40
    private let patternScale: CGFloat = 0.65

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
        .opacity(0.26)
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
            ZStack {
                // 黄 + 纹理铺满整张卡；下半再叠半透明白，纹理会从底下透上来。
                ZStack {
                    GrowthTaskCardPalette.topYellow
                    GrowthTaskCardYellowPatternOverlay()
                }
                .allowsHitTesting(false)

                VStack(spacing: 0) {
                    cardTopContent(height: topH)
                    cardBottomHalf(height: h - topH)
                }
            }
        }
        .aspectRatio(GrowthDailyTaskModels.cardAspectRatio, contentMode: .fit)
        .overlay(alignment: .topTrailing) {
            growthTagChip()
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
    }

    private func growthTagChip() -> some View {
        Text(definition.tag)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 7)
            .background(
                UnevenRoundedRectangle(
                    cornerRadii: RectangleCornerRadii(
                        topLeading: 0,
                        bottomLeading: 10,
                        bottomTrailing: 0,
                        topTrailing: 0
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
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(red: 0.82, green: 0.72, blue: 0.05))
        }
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
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
                        .foregroundStyle(Color.black.opacity(0.32))
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

                GrowthTaskCompletionBar(progress: progress)
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
                .fill(
                    LinearGradient(
                        colors: [
                            BolaTheme.accent.opacity(0.88),
                            BolaTheme.accent.opacity(0.65)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

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

/// 「完成度」+ 进度条，直接贴在任务文案下方，不再使用独立白底卡片。
private struct GrowthTaskCompletionBar: View {
    let progress: Double

    var body: some View {
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
                        .frame(width: max(4, w * progress), height: 5)
                }
            }
            .frame(height: 5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
