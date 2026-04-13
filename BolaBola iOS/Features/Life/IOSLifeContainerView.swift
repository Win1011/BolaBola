//
//  IOSLifeContainerView.swift
//  生活 Tab：半圆弧主视觉 + 双列（提醒/健康）+ 今日记录。
//

import Combine
import SwiftUI
import UniformTypeIdentifiers
import UIKit

private enum LifeAccentChromeButtonMetrics {
    static let hPad: CGFloat = 12
    static let vPad: CGFloat = 7
    static let fontSize: CGFloat = 12
}

private enum LifeRecordTileMetrics {
    static let leadingIconSize: CGFloat = 36
    static let subtitleReservedHeight: CGFloat = 22
}

private enum LifeMiddleCardMetrics {
    /// 右侧单张健康卡（睡眠 / 运动）固定高度，按内容预留，不裁剪、不 clip。
    static let healthCardRowHeight: CGFloat = 148
    /// 两卡之间的垂直间距。
    static let healthStackSpacing: CGFloat = 12
    /// 右列总高度 = 睡眠 + 间距 + 运动；左列「正在关心的事」白卡与之严格同高。
    static var dashboardColumnHeight: CGFloat {
        healthCardRowHeight * 2 + healthStackSpacing
    }

    static let compactHealthCardRowHeight: CGFloat = 68
    static let wideReminderCardHeight: CGFloat = 178
    /// 竖形态提醒卡固定高度 = 两张标准健康卡 + 间距。
    static let featuredReminderCardHeight: CGFloat = 308
    static let dashboardHeaderSpacing: CGFloat = 12
    static let activityRingsBaseSize: CGFloat = 120
    static let featuredActivityRingsSize: CGFloat = 54
    static let compactActivityRingsSize: CGFloat = 38
}

// MARK: - 半圆弧 Shape（圆心在矩形底部中心）

private struct SemiCircleArcShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addArc(
            center: CGPoint(x: rect.midX, y: rect.maxY),
            radius: rect.width / 2,
            startAngle: .degrees(180),
            endAngle: .degrees(0),
            clockwise: false
        )
        return p
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

private enum LifePreviewMocks {
    static let reminders: [BolaReminder] = [
        BolaReminder(
            title: "喝水",
            notificationBody: "记得补充水分",
            schedule: .interval(60 * 60),
            kind: .water,
            isEnabled: true
        ),
        BolaReminder(
            title: "活动一下",
            notificationBody: "起来走一走",
            schedule: .calendar(hour: 15, minute: 30, weekdays: []),
            kind: .move,
            isEnabled: true
        ),
        BolaReminder(
            title: "睡前放松",
            notificationBody: "准备休息",
            schedule: .calendar(hour: 22, minute: 30, weekdays: []),
            kind: .sleep,
            isEnabled: false
        ),
    ]
}

private struct IOSLifeContainerPreviewHost: View {
    @State private var reminders: [BolaReminder] = LifePreviewMocks.reminders

    var body: some View {
        IOSLifeContainerView(
            bubbleMode: .constant(false),
            reminders: $reminders
        )
    }
}

#Preview("Life") {
    IOSLifeContainerPreviewHost()
}

// MARK: - 主视图

struct IOSLifeContainerView: View {
    @Binding var bubbleMode: Bool
    @Binding var reminders: [BolaReminder]
    var onRequestChat: () -> Void = {}

    @StateObject private var rhythm = IOSRhythmHRVModel()
    @StateObject private var weather = IOSWeatherLocationModel()
    @StateObject private var healthHabits = IOSHealthHabitAnalysisModel()

    @State private var lifeRecords: [LifeRecordCard] = LifeRecordListStore.load()
    @State private var digestText: String = ""
    @State private var showDigestEditor = false
    @State private var draftDigest: String = ""
    @State private var showRhythmInfo = false

    @State private var showAddRecordSheet = false
    @State private var addKind: LifeRecordKind = .event
    @State private var newRecordTitle: String = ""
    @State private var newRecordSubtitle: String = ""
    @State private var newRecordIconEmoji: String = ""
    @State private var selectedBubbleRecord: LifeRecordCard?
    @State private var dashboardLayout: [LifeDashboardTileLayout] = LifeDashboardLayoutStore.load()
    @State private var isEditingDashboard = false
    @State private var selectedDashboardDate: Date = Date()
    @State private var visibleDashboardMonth: Date = Date()
    @State private var showDashboardCalendar = false
    @State private var draggedDashboardKind: LifeDashboardTileKind?
    @State private var dashboardResizePreview: [LifeDashboardTileKind: LifeDashboardTileVariant] = [:]
    @State private var dashboardJigglePhase = false
    @State private var hasPerformedInitialLoad = false
    @State private var showAddDashboardCardHint = false

    /// 半圆节奏进度（0...1）：优先用当前小时 HRV，若当前小时无样本则回退今日均值。
    private var rhythmArcProgress: Double {
        let hour = Calendar.current.component(.hour, from: Date())
        let values = rhythm.hourlyNormalized
        let current = values.indices.contains(hour) ? values[hour] : 0
        if current > 0.001 { return min(1, max(0, current)) }
        let positives = values.filter { $0 > 0.001 }
        guard !positives.isEmpty else { return 0 }
        let avg = positives.reduce(0, +) / Double(positives.count)
        return min(1, max(0, avg))
    }

    var body: some View {
        ZStack(alignment: .top) {
            lifePageBackground
                .ignoresSafeArea(edges: [.top, .bottom])
            if bubbleMode {
                lifeBubbleBoard
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            } else {
                lifeScroll
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: bubbleMode)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            guard !hasPerformedInitialLoad else { return }
            hasPerformedInitialLoad = true
            lifeRecords = LifeRecordListStore.load()
            reloadDigest()
            weather.requestAndFetch()
            Task {
                await rhythm.refresh()
                await healthHabits.refresh(requestIfNeeded: true)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .bolaLifeRecordsDidChange)) { _ in
            lifeRecords = LifeRecordListStore.load()
        }
        .onReceive(NotificationCenter.default.publisher(for: .bolaLifeRecordsDidReset)) { _ in
            lifeRecords = LifeRecordListStore.load()
        }
        .onChange(of: isEditingDashboard) { _, isEditing in
            if isEditing {
                dashboardResizePreview.removeAll()
                withAnimation(.easeInOut(duration: 0.14).repeatForever(autoreverses: true)) {
                    dashboardJigglePhase = true
                }
            } else {
                dashboardResizePreview.removeAll()
                draggedDashboardKind = nil
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    dashboardJigglePhase = false
                }
            }
        }
        .sheet(isPresented: $showDigestEditor) {
            digestEditorSheet
        }
        .sheet(isPresented: $showAddRecordSheet) {
            addLifeRecordSheet
        }
        .sheet(isPresented: $showDashboardCalendar) {
            LifeDashboardCalendarSheet(
                selectedDate: $selectedDashboardDate,
                visibleMonth: $visibleDashboardMonth
            )
        }
        .sheet(item: $selectedBubbleRecord) { record in
            LifeRecordBubbleDetailSheet(record: record)
        }
        .alert("节奏条", isPresented: $showRhythmInfo) {
            Button("好的", role: .cancel) {}
        } message: {
            Text("基于今日心率变异性（HRV）样本按小时汇总，仅作状态参考，非医疗诊断。")
        }
        .alert("更多卡片即将支持", isPresented: $showAddDashboardCardHint) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("后续这里会加入更多身体数据和生活卡片入口。")
        }
    }

    private var lifeBubbleBoard: some View {
        LifeBubbleView(
            records: lifeRecords,
            onAdd: {
                addKind = .event
                newRecordTitle = ""
                newRecordSubtitle = ""
                newRecordIconEmoji = ""
                showAddRecordSheet = true
            },
            onSelect: { record in
                selectedBubbleRecord = record
            }
        )
    }

    // MARK: - 滚动主体

    private var lifeScroll: some View {
        ScrollView {
            ZStack(alignment: .topLeading) {
                // 编辑模式背景点击层：只有穿透到这里的点击才退出编辑
                if isEditingDashboard {
                    Color.black.opacity(0.001)
                        .onTapGesture {
                            endDashboardEditing()
                        }
                }

                VStack(alignment: .leading, spacing: 0) {
                    dashboardDateStrip
                        .padding(.top, 6)

                    // 1. 全宽半圆弧主视觉（负 padding 出血到屏边）
                    heroArcSection
                        .padding(.top, 18)
                        .padding(.horizontal, -BolaTheme.paddingHorizontal)

                    // 2. 可编辑仪表板
                    middleDashboardSection
                        .padding(.top, 22)

                    // 3. 今日生活记录
                    lifeRecordsFigma
                        .padding(.top, 28)
                }
                .padding(.horizontal, BolaTheme.paddingHorizontal)
                .padding(.top, 0)
                .padding(.bottom, 28)
            }
        }
        .background(Color.clear)
        .scrollIndicators(.hidden)
        .refreshable {
            reloadDigest()
            weather.requestAndFetch()
            await rhythm.refresh()
            await healthHabits.refresh(requestIfNeeded: true)
        }
    }

    private var lifePageBackground: some View {
        BolaLifeAmbientBackground()
    }

    // MARK: - Section 1：半圆弧主视觉

    private var heroArcSection: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let arcSizeReduce: CGFloat = 52
            let arcTrackLiftY: CGFloat = 16
            let heroContentDropY: CGFloat = 50
            let heroBubbleDropY: CGFloat = 20
            let heroSectionLiftY: CGFloat = 33
            let strokeW: CGFloat = 12
            let arcWidth = max(0, w - arcSizeReduce)
            // 弧半径：令弧端点贴近屏边，留半个描边宽度避免裁切
            let arcR = (arcWidth - strokeW) / 2
            // 弧框高度 = 半径 + 描边半宽 + 2pt 余量
            let arcFrameH = arcR + strokeW / 2 + 2
            let progress = rhythmArcProgress
            let theta = CGFloat.pi * (1 - CGFloat(progress))
            let markerX = arcWidth / 2 + arcR * cos(theta)
            let markerY = arcFrameH - arcR * sin(theta)
            let markerOutset: CGFloat = 5
            let radialX = markerX - arcWidth / 2
            let radialY = markerY - arcFrameH
            let radialLen = max(0.001, sqrt(radialX * radialX + radialY * radialY))
            let markerOutsetX = radialX / radialLen * markerOutset
            let markerOutsetY = radialY / radialLen * markerOutset

            ZStack(alignment: .bottom) {
                // 灰色背景轨道
                SemiCircleArcShape()
                    .stroke(
                        Color(uiColor: .systemFill),
                        style: StrokeStyle(lineWidth: strokeW, lineCap: .round)
                    )
                    .frame(width: arcWidth, height: arcFrameH)
                    .offset(y: -arcTrackLiftY)

                // 黄绿渐变弧
                SemiCircleArcShape()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color(red: 1.00, green: 0.63, blue: 0.25),
                                Color(red: 0.86, green: 0.99, blue: 0.18),
                                Color(red: 0.10, green: 0.82, blue: 0.26)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: strokeW, lineCap: .round)
                    )
                    .frame(width: arcWidth, height: arcFrameH)
                    .overlay(alignment: .topLeading) {
                        Circle()
                            .fill(BolaTheme.surfaceBubble)
                            .frame(width: 18, height: 18)
                            .offset(
                                x: markerX + markerOutsetX - 9,
                                y: markerY + markerOutsetY - 9
                            )
                            .shadow(color: .black.opacity(0.12), radius: 3, x: 0, y: 1)
                    }
                    .offset(y: -arcTrackLiftY)

                // 岛图居中，底部对齐弧底部
                Button {
                    onRequestChat()
                } label: {
                    Image("GrowthHeroIsland")
                        .resizable()
                        .scaledToFit()
                        .frame(width: min(w * 0.54, 204))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("打开对话")
                .padding(.bottom, strokeW / 2 + 2)
                .offset(x: 10)
                .offset(y: heroContentDropY)

                // 节奏条标签（左下角）
                HStack(spacing: 0) {
                    Text("节奏条")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Button {
                        showRhythmInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, BolaTheme.paddingHorizontal + 20)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: w, height: geo.size.height, alignment: .bottom)
            .offset(y: -heroSectionLiftY)
            // 语音气泡：浮在弧内上方
            .overlay(alignment: .top) {
                heroBubble
                    .padding(.horizontal, BolaTheme.paddingHorizontal + 12)
                    .padding(.top, 22)
                    .offset(y: heroBubbleDropY)
            }
        }
        .frame(height: heroArcTotalHeight)
    }

    /// 整个弧区高度 = 弧半径 + 描边 + 上方气泡空间
    private var heroArcTotalHeight: CGFloat {
        let w = UIScreen.main.bounds.width
        let arcR = (w - 52 - 12) / 2
        return arcR + 60
    }

    private var heroBubble: some View {
        ZStack(alignment: .bottom) {
            Text(speechLine)
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

    private var speechLine: String {
        let t = digestText.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return "节奏不错！继续保持哦~" }
        if let first = t.split(separator: "。").first, !first.isEmpty {
            return String(first) + "。"
        }
        return t
    }

    // MARK: - Section 2：可编辑仪表板

    private var dashboardDateStrip: some View {
        LifeDashboardWeekStrip(
            selectedDate: $selectedDashboardDate,
            onOpenMonth: {
                visibleDashboardMonth = selectedDashboardDate
                showDashboardCalendar = true
            }
        )
    }

    private var middleDashboardSection: some View {
        VStack(spacing: 12) {
            Group {
                if dashboardUsesSplitLayout {
                    splitDashboardLayout
                } else {
                    flexibleDashboardRows
                }
            }

            if isEditingDashboard {
                addDashboardCardBar
            }
        }
    }

    private var dashboardUsesSplitLayout: Bool {
        dashboardVariant(for: .reminders) == .featured
    }

    private var splitDashboardLayout: some View {
        let fixedHeight = LifeMiddleCardMetrics.featuredReminderCardHeight

        return HStack(alignment: .top, spacing: 12) {
            // 左列：提醒卡固定高度
            dashboardTileContainer(kind: .reminders) {
                IOSRemindersSectionView(reminders: $reminders, style: .figmaLife)
                    .frame(maxWidth: .infinity)
                    .frame(height: fixedHeight, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity)
            .frame(height: fixedHeight, alignment: .topLeading)

            // 右列：健康卡各自独立高度，顶部对齐
            VStack(spacing: LifeMiddleCardMetrics.healthStackSpacing) {
                dashboardTileContainer(kind: .sleep) {
                    compactSleepCardContent(compact: dashboardVariant(for: .sleep) == .compact)
                }
                .frame(height: dashboardTileHeight(for: .sleep))

                dashboardTileContainer(kind: .activity) {
                    compactExerciseCardContent(compact: dashboardVariant(for: .activity) == .compact)
                }
                .frame(height: dashboardTileHeight(for: .activity))
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    private var flexibleDashboardRows: some View {
        VStack(spacing: 12) {
            ForEach(dashboardRows.indices, id: \.self) { rowIndex in
                let row = dashboardRows[rowIndex]
                HStack(alignment: .top, spacing: 12) {
                    ForEach(row) { tile in
                        dashboardTileView(tile)
                    }
                    if row.count == 1, row.first?.kind != .reminders {
                        Color.clear
                            .frame(maxWidth: .infinity, minHeight: dashboardTileHeight(for: row[0]))
                    }
                }
            }
        }
    }

    private var dashboardRows: [[LifeDashboardTileLayout]] {
        var rows: [[LifeDashboardTileLayout]] = []
        var pending: [LifeDashboardTileLayout] = []

        for tile in effectiveDashboardLayout where !(dashboardUsesSplitLayout && tile.kind == .reminders) {
            if dashboardTileUsesFullWidth(tile) {
                if !pending.isEmpty {
                    rows.append(pending)
                    pending.removeAll()
                }
                rows.append([tile])
            } else {
                pending.append(tile)
                if pending.count == 2 {
                    rows.append(pending)
                    pending.removeAll()
                }
            }
        }

        if !pending.isEmpty {
            rows.append(pending)
        }

        return rows
    }

    private func dashboardTileUsesFullWidth(_ tile: LifeDashboardTileLayout) -> Bool {
        tile.kind == .reminders && tile.variant == .compact
    }

    private func dashboardTileHeight(for tile: LifeDashboardTileLayout) -> CGFloat {
        dashboardTileHeight(for: tile.kind)
    }

    private func dashboardTileHeight(for kind: LifeDashboardTileKind) -> CGFloat {
        let variant = dashboardVariant(for: kind)
        switch (kind, variant) {
        case (.reminders, .featured):
            return LifeMiddleCardMetrics.featuredReminderCardHeight
        case (.reminders, .compact):
            return LifeMiddleCardMetrics.wideReminderCardHeight
        case (_, .featured):
            return LifeMiddleCardMetrics.healthCardRowHeight
        case (_, .compact):
            return LifeMiddleCardMetrics.compactHealthCardRowHeight
        }
    }

    private func dashboardVariant(for kind: LifeDashboardTileKind) -> LifeDashboardTileVariant {
        effectiveDashboardLayout.first(where: { $0.kind == kind })?.variant ?? .featured
    }

    private var effectiveDashboardLayout: [LifeDashboardTileLayout] {
        let previewed = dashboardLayout.map { tile in
            var updated = tile
            if let preview = dashboardResizePreview[tile.kind] {
                updated.variant = preview
            }
            return updated
        }
        return LifeDashboardLayoutStore.normalized(previewed)
    }

    @ViewBuilder
    private func dashboardTileView(_ tile: LifeDashboardTileLayout) -> some View {
        switch tile.kind {
        case .reminders:
            dashboardTileContainer(kind: .reminders) {
                IOSRemindersSectionView(
                    reminders: $reminders,
                    style: .figmaLife
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity)
            .frame(height: dashboardTileHeight(for: tile))
        case .sleep:
            dashboardTileContainer(kind: .sleep) {
                compactSleepCardContent(compact: tile.variant == .compact)
            }
            .frame(maxWidth: .infinity)
            .frame(height: dashboardTileHeight(for: tile))
        case .activity:
            dashboardTileContainer(kind: .activity) {
                compactExerciseCardContent(compact: tile.variant == .compact)
            }
            .frame(maxWidth: .infinity)
            .frame(height: dashboardTileHeight(for: tile))
        }
    }

    private var addDashboardCardBar: some View {
        Button {
            showAddDashboardCardHint = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .bold))
                Text("添加更多卡片")
                    .font(.system(size: 15, weight: .semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                RoundedRectangle(cornerRadius: BolaTheme.cornerLifePageCard, style: .continuous)
                    .fill(BolaTheme.surfaceBubble.opacity(0.92))
            )
            .overlay(
                RoundedRectangle(cornerRadius: BolaTheme.cornerLifePageCard, style: .continuous)
                    .stroke(Color(uiColor: .separator).opacity(0.28), style: StrokeStyle(lineWidth: 1.2, dash: [7, 5]))
            )
        }
        .buttonStyle(.plain)
    }

    private func dashboardTileContainer<Content: View>(
        kind: LifeDashboardTileKind,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack(alignment: .bottomTrailing) {
            content()
                .allowsHitTesting(!isEditingDashboard)
                .opacity(draggedDashboardKind == kind ? 0.55 : 1)
                .scaleEffect(draggedDashboardKind == kind ? 0.97 : 1)
                .rotationEffect(.degrees(isEditingDashboard ? (dashboardJigglePhase ? wiggleAngle(for: kind) : -wiggleAngle(for: kind)) : 0))

            if isEditingDashboard {
                // 编辑态边框
                RoundedRectangle(cornerRadius: BolaTheme.cornerLifePageCard, style: .continuous)
                    .stroke(Color.primary.opacity(0.16), lineWidth: 2)
                    .allowsHitTesting(false)

                LifeDashboardResizeButton(
                    variant: dashboardVariant(for: kind),
                    onToggle: {
                        let current = dashboardVariant(for: kind)
                        let target: LifeDashboardTileVariant = current == .featured ? .compact : .featured
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        commitDashboardVariant(target, for: kind)
                    }
                )
                .offset(x: 4, y: 4)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: BolaTheme.cornerLifePageCard, style: .continuous))
        .contentShape(.dragPreview, RoundedRectangle(cornerRadius: BolaTheme.cornerLifePageCard, style: .continuous))
        .contentShape(.interaction, RoundedRectangle(cornerRadius: BolaTheme.cornerLifePageCard, style: .continuous))
        .onDrag {
            if !isEditingDashboard {
                // 长按触发：进入编辑模式，取消本次拖拽
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                DispatchQueue.main.async {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                        isEditingDashboard = true
                    }
                }
                return NSItemProvider()
            }
            draggedDashboardKind = kind
            return NSItemProvider(object: NSString(string: kind.rawValue))
        }
        .onDrop(
            of: [UTType.plainText],
            delegate: LifeDashboardTileDropDelegate(
                destination: kind,
                dashboardLayout: $dashboardLayout,
                draggedKind: $draggedDashboardKind
            )
        )
    }

    // MARK: - 睡眠紧凑卡

    private var compactSleepCard: some View {
        compactSleepCardContent(compact: false)
    }

    private func compactSleepCardContent(compact: Bool) -> some View {
        NavigationLink {
            IOSHealthSleepDetailView(model: healthHabits)
        } label: {
            compactSleepContent(compact: compact)
        }
        .buttonStyle(.plain)
    }

    private func compactSleepContent(compact: Bool) -> some View {
        let hours = IOSHealthHabitSnapshot.todaySleepHoursValue(healthHabits)
        let fraction = min(1.0, max(0.0, hours / IOSHealthRingGoals.sleepHoursTarget))
        let hasData = hours > 0.01

        if compact {
            return AnyView(
                compactHealthCardShell(
                    title: "睡眠",
                    systemImage: "moon.zzz.fill",
                    valueText: hasData ? "\(String(format: "%.1f", hours)) 小时" : "暂无数据",
                    valueStyle: hasData ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary)
                ) {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(hasData ? "目标 8h" : "同步中")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tertiary)
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.indigo.opacity(0.13))
                                .frame(height: 5)
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.indigo.opacity(0.6), Color.indigo],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(0, 80 * fraction), height: 5)
                        }
                        .frame(width: 80)
                    }
                    .frame(width: 80, alignment: .trailing)
                }
            )
        }

        return AnyView(
            featuredHealthCardShell(
                title: "睡眠",
                systemImage: "moon.zzz.fill",
                valueText: hasData ? "\(String(format: "%.1f", hours)) 小时" : "暂无数据",
                valueStyle: hasData ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary),
                footerText: hasData ? "昨夜估算睡眠时长" : "等待睡眠数据同步",
                footerStyle: hasData ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary)
            ) {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.indigo.opacity(0.13))
                            .frame(height: 7)
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color.indigo.opacity(0.6), Color.indigo],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(0, g.size.width * fraction), height: 7)
                    }
                }
                .frame(height: 7)
                .frame(maxHeight: .infinity, alignment: .center)
                .padding(.horizontal, 2)
            }
        )
    }

    // MARK: - 运动紧凑卡

    private var compactExerciseCard: some View {
        compactExerciseCardContent(compact: false)
    }

    private func compactExerciseCardContent(compact: Bool) -> some View {
        NavigationLink {
            IOSHealthActivityDetailView(model: healthHabits)
        } label: {
            compactExerciseContent(compact: compact)
        }
        .buttonStyle(.plain)
    }

    private func compactExerciseContent(compact: Bool) -> some View {
        let move = IOSHealthHabitSnapshot.todayMoveEnergyValue(healthHabits)
        let exercise = IOSHealthHabitSnapshot.todayExerciseMinutesValue(healthHabits)
        let stand = IOSHealthHabitSnapshot.todayStandMinutesValue(healthHabits)
        let moveProgress = IOSHealthHabitSnapshot.moveGoalProgress(healthHabits)
        let exerciseProgress = IOSHealthHabitSnapshot.exerciseGoalProgress(healthHabits)
        let standProgress = IOSHealthHabitSnapshot.standGoalProgress(healthHabits)
        let hasData = move > 0 || exercise > 0 || stand > 0

        if compact {
            return AnyView(
                compactHealthCardShell(
                    title: "运动",
                    systemImage: "figure.walk",
                    valueText: hasData ? "\(IOSHealthHabitSnapshot.intString(from: move)) kcal" : "暂无数据",
                    valueStyle: hasData ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary)
                ) {
                    IOSHealthTodayRingsBlock(
                        moveProgress: moveProgress,
                        exerciseProgress: exerciseProgress,
                        standProgress: standProgress
                    )
                    .scaleEffect(42.0 / LifeMiddleCardMetrics.activityRingsBaseSize)
                    .frame(width: 42, height: 42)
                }
            )
        }

        return AnyView(
            featuredHealthCardShell(
                title: "运动",
                systemImage: "figure.walk",
                valueText: hasData ? "\(IOSHealthHabitSnapshot.intString(from: move)) kcal" : "暂无数据",
                valueStyle: hasData ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary),
                footerText: hasData ? "锻炼 \(Int(exercise)) 分 · 站立 \(Int(stand)) 分" : "等待运动数据同步",
                footerStyle: hasData ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary)
            ) {
                HStack {
                    Spacer()
                    IOSHealthTodayRingsBlock(
                        moveProgress: moveProgress,
                        exerciseProgress: exerciseProgress,
                        standProgress: standProgress
                    )
                    .scaleEffect(72.0 / LifeMiddleCardMetrics.activityRingsBaseSize)
                    .frame(width: 72, height: 72)
                }
            }
        )
    }

    private func featuredHealthCardShell<Visual: View>(
        title: String,
        systemImage: String,
        valueText: String,
        valueStyle: AnyShapeStyle,
        footerText: String,
        footerStyle: AnyShapeStyle,
        @ViewBuilder visual: () -> Visual
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center) {
                Image(systemName: systemImage)
                    .font(.subheadline)
                    .foregroundStyle(BolaTheme.listRowIcon)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }

            Text(title)
                .font(.system(size: 17, weight: .semibold))

            Text(valueText)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(valueStyle)
                .lineLimit(1)

            visual()
                .frame(maxWidth: .infinity)
                .frame(height: 30, alignment: .center)

            Text(footerText)
                .font(.caption2)
                .foregroundStyle(footerStyle)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: BolaTheme.cornerLifePageCard, style: .continuous)
                .fill(BolaTheme.surfaceBubble)
        )
        .overlay(
            RoundedRectangle(cornerRadius: BolaTheme.cornerLifePageCard, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.25), lineWidth: 1)
        )
    }

    private func compactHealthCardShell<Trailing: View>(
        title: String,
        systemImage: String,
        valueText: String,
        valueStyle: AnyShapeStyle,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Label(title, systemImage: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .labelStyle(.titleAndIcon)
                Text(valueText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(valueStyle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 0)

            trailing()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxHeight: .infinity, alignment: .center)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: BolaTheme.cornerLifePageCard, style: .continuous)
                .fill(BolaTheme.surfaceBubble)
        )
        .overlay(
            RoundedRectangle(cornerRadius: BolaTheme.cornerLifePageCard, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - Section 3：今日生活记录

    private var lifeRecordsFigma: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(lifeRecordsSectionTitle)
                    .font(.system(size: 17, weight: .semibold))
                Spacer(minLength: 0)
                Button {
                    addKind = .event
                    newRecordTitle = ""
                    newRecordSubtitle = ""
                    newRecordIconEmoji = ""
                    showAddRecordSheet = true
                } label: {
                    HStack(spacing: 5) {
                        LifeAccentChromePlusIcon()
                        Text("添加")
                            .font(.system(size: LifeAccentChromeButtonMetrics.fontSize, weight: .semibold))
                            .foregroundStyle(BolaTheme.onAccentForeground)
                    }
                    .padding(.horizontal, LifeAccentChromeButtonMetrics.hPad)
                    .padding(.vertical, LifeAccentChromeButtonMetrics.vPad)
                    .background(Capsule().fill(BolaTheme.accent))
                }
                .buttonStyle(.plain)
            }

            let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
            if filteredLifeRecords.isEmpty {
                emptyLifeRecordsCard
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(filteredLifeRecords) { card in
                        lifeRecordTile(card)
                    }
                }
            }
        }
    }

    private var lifeRecordsSectionTitle: String {
        let cal = Calendar.current
        if cal.isDateInToday(selectedDashboardDate) {
            return "今日生活记录"
        }
        return Self.lifeSectionDateFormatter.string(from: selectedDashboardDate)
    }

    private var filteredLifeRecords: [LifeRecordCard] {
        let cal = Calendar.current
        return lifeRecords.filter { cal.isDate($0.createdAt, inSameDayAs: selectedDashboardDate) }
    }

    private var emptyLifeRecordsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("这一天还没有生活记录")
                .font(.system(size: 16, weight: .semibold))
            Text("可以切换日期继续看，也可以手动添加一张新的生活卡片。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: BolaTheme.cornerLifePageCard, style: .continuous)
                .fill(BolaTheme.surfaceBubble)
        )
        .overlay(
            RoundedRectangle(cornerRadius: BolaTheme.cornerLifePageCard, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.25), lineWidth: 1)
        )
    }

    private func lifeRecordTile(_ card: LifeRecordCard) -> some View {
        Group {
            switch card.kind {
            case .weather:
                weatherTile
            default:
                genericRecordTile(card)
            }
        }
    }

    private var weatherTile: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(weatherEmoji)
                    .font(.system(size: LifeRecordTileMetrics.leadingIconSize))
                    .fixedSize(horizontal: true, vertical: true)
                    .frame(minWidth: 40, minHeight: 40, alignment: .leading)
                    .accessibilityLabel("天气状况")
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            Text("天气")
                .font(.system(size: 19, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
            weatherDetailLine
                .frame(maxWidth: .infinity, minHeight: LifeRecordTileMetrics.subtitleReservedHeight, alignment: .leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 148, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: BolaTheme.cornerLifePageCard, style: .continuous)
                .fill(BolaTheme.surfaceBubble)
        )
        .overlay(
            RoundedRectangle(cornerRadius: BolaTheme.cornerLifePageCard, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.25), lineWidth: 1)
        )
        .onTapGesture {
            weather.requestAndFetch()
        }
    }

    @ViewBuilder
    private var weatherDetailLine: some View {
        if weather.isLoading {
            HStack(spacing: 8) {
                ProgressView().scaleEffect(0.85)
                Text("加载中·—")
                    .font(.caption)
                    .foregroundStyle(BolaTheme.figmaSubtleCaption)
            }
            .lineLimit(1)
        } else if let w = weather.weather {
            Text("\(w.conditionText)·\(String(format: "%.0f", w.temperatureC))°C")
                .font(.caption)
                .foregroundStyle(BolaTheme.figmaSubtleCaption)
                .lineLimit(1)
                .truncationMode(.tail)
        } else if weather.lastError != nil {
            Text("无法获取·—")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else {
            Text("轻点刷新·—")
                .font(.caption)
                .foregroundStyle(BolaTheme.figmaSubtleCaption)
                .lineLimit(1)
        }
    }

    private var weatherEmoji: String {
        weather.weather?.emoji ?? "☀️"
    }

    private func genericRecordTile(_ card: LifeRecordCard) -> some View {
        let sub = card.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                lifeRecordLeadingIcon(for: card)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            Text(card.title)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
            Text(sub.isEmpty ? " " : sub)
                .font(.caption)
                .foregroundStyle(BolaTheme.figmaSubtleCaption)
                .lineLimit(1)
                .truncationMode(.tail)
                .opacity(sub.isEmpty ? 0 : 1)
                .frame(maxWidth: .infinity, minHeight: LifeRecordTileMetrics.subtitleReservedHeight, alignment: .leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 148, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: BolaTheme.cornerLifePageCard, style: .continuous)
                .fill(BolaTheme.surfaceBubble)
        )
        .overlay(
            RoundedRectangle(cornerRadius: BolaTheme.cornerLifePageCard, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.25), lineWidth: 1)
        )
    }

    private func toggleDashboardVariant(for kind: LifeDashboardTileKind) {
        guard let index = dashboardLayout.firstIndex(where: { $0.kind == kind }) else { return }
        dashboardLayout[index].variant = dashboardLayout[index].variant == .featured ? .compact : .featured
        dashboardLayout = LifeDashboardLayoutStore.normalized(dashboardLayout)
        LifeDashboardLayoutStore.save(dashboardLayout)
    }

    private func setDashboardVariant(_ variant: LifeDashboardTileVariant, for kind: LifeDashboardTileKind) {
        guard let index = dashboardLayout.firstIndex(where: { $0.kind == kind }) else { return }
        guard dashboardLayout[index].variant != variant else { return }
        dashboardLayout[index].variant = variant
        dashboardLayout = LifeDashboardLayoutStore.normalized(dashboardLayout)
        LifeDashboardLayoutStore.save(dashboardLayout)
    }

    private func previewDashboardVariant(_ variant: LifeDashboardTileVariant?, for kind: LifeDashboardTileKind) {
        withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 1.0, blendDuration: 0.05)) {
            if let variant {
                dashboardResizePreview[kind] = variant
            } else {
                dashboardResizePreview.removeValue(forKey: kind)
            }
        }
    }

    private func commitDashboardVariant(_ variant: LifeDashboardTileVariant, for kind: LifeDashboardTileKind) {
        previewDashboardVariant(nil, for: kind)
        withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
            setDashboardVariant(variant, for: kind)
        }
        // 布局切换（split ↔ flexible）会重建视图树导致 repeatForever 动画丢失，重新触发
        if isEditingDashboard {
            dashboardJigglePhase = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                withAnimation(.easeInOut(duration: 0.14).repeatForever(autoreverses: true)) {
                    dashboardJigglePhase = true
                }
            }
        }
    }

    private func shiftDashboardTile(_ kind: LifeDashboardTileKind, delta: Int) {
        guard let index = dashboardLayout.firstIndex(where: { $0.kind == kind }) else { return }
        let newIndex = max(0, min(dashboardLayout.count - 1, index + delta))
        guard newIndex != index else { return }
        let item = dashboardLayout.remove(at: index)
        dashboardLayout.insert(item, at: newIndex)
        dashboardLayout = LifeDashboardLayoutStore.normalized(dashboardLayout)
        LifeDashboardLayoutStore.save(dashboardLayout)
    }

    private func moveDashboardTile(_ kind: LifeDashboardTileKind, to index: Int) {
        guard let oldIndex = dashboardLayout.firstIndex(where: { $0.kind == kind }) else { return }
        let target = max(0, min(dashboardLayout.count - 1, index))
        guard target != oldIndex else { return }
        let item = dashboardLayout.remove(at: oldIndex)
        dashboardLayout.insert(item, at: target)
        dashboardLayout = LifeDashboardLayoutStore.normalized(dashboardLayout)
        LifeDashboardLayoutStore.save(dashboardLayout)
    }

    private func endDashboardEditing() {
        withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
            isEditingDashboard = false
        }
    }

    private func wiggleAngle(for kind: LifeDashboardTileKind) -> Double {
        switch kind {
        case .reminders:
            return 0.65
        case .sleep:
            return 0.82
        case .activity:
            return 0.74
        }
    }

    // MARK: - Sheets

    private var digestEditorSheet: some View {
        NavigationStack {
            Form {
                Section("今日小结") {
                    TextField("Bola 口吻的一句话", text: $draftDigest, axis: .vertical)
                        .lineLimit(3 ... 8)
                }
            }
            .navigationTitle("修改")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showDigestEditor = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let d = BolaSharedDefaults.resolved()
                        d.set(draftDigest, forKey: DailyDigestStorageKeys.lastDigestBody)
                        digestText = draftDigest
                        showDigestEditor = false
                    }
                }
            }
        }
    }

    private var addLifeRecordSheet: some View {
        NavigationStack {
            Form {
                Picker("类型", selection: $addKind) {
                    Text("事件").tag(LifeRecordKind.event)
                    Text("习惯").tag(LifeRecordKind.habitTodo)
                    Text("美食").tag(LifeRecordKind.food)
                    Text("出行").tag(LifeRecordKind.travel)
                    Text("运动").tag(LifeRecordKind.fitness)
                    Text("观影").tag(LifeRecordKind.movie)
                    Text("购物").tag(LifeRecordKind.shopping)
                }
                .onChange(of: addKind) { _, _ in newRecordIconEmoji = "" }
                Section {
                    LifeRecordEmojiPaletteView(kind: addKind, selection: $newRecordIconEmoji)
                } header: {
                    Text("图标")
                }
                TextField("标题", text: $newRecordTitle)
                TextField("内容（可选）", text: $newRecordSubtitle, axis: .vertical)
                    .lineLimit(3 ... 6)
            }
            .navigationTitle("添加卡片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        showAddRecordSheet = false
                        resetAddForm()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") {
                        let card = LifeRecordCard(
                            kind: addKind,
                            title: newRecordTitle.isEmpty ? defaultTitle(for: addKind) : newRecordTitle,
                            subtitle: newRecordSubtitle.isEmpty ? nil : newRecordSubtitle,
                            detailNote: newRecordSubtitle.isEmpty ? nil : newRecordSubtitle,
                            iconEmoji: lifeRecordFirstGrapheme(from: newRecordIconEmoji)
                        )
                        lifeRecords.append(card)
                        LifeRecordListStore.save(lifeRecords)
                        showAddRecordSheet = false
                        resetAddForm()
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func reloadDigest() {
        digestText = BolaSharedDefaults.resolved().string(forKey: DailyDigestStorageKeys.lastDigestBody) ?? ""
    }

    private func resetAddForm() {
        newRecordTitle = ""
        newRecordSubtitle = ""
        newRecordIconEmoji = ""
    }

    private static let lifeSectionDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 生活记录"
        return formatter
    }()

    private func defaultTitle(for kind: LifeRecordKind) -> String {
        switch kind {
        case .weather: return "天气"
        case .event: return "事件"
        case .habitTodo: return "习惯"
        case .food: return "美食"
        case .travel: return "出行"
        case .fitness: return "运动"
        case .movie: return "观影"
        case .shopping: return "购物"
        }
    }

    @ViewBuilder
    private func lifeRecordLeadingIcon(for card: LifeRecordCard) -> some View {
        let trimmed = card.iconEmoji?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let ch = trimmed.first {
            Text(String(ch))
                .font(.system(size: LifeRecordTileMetrics.leadingIconSize))
                .fixedSize(horizontal: true, vertical: true)
                .frame(minWidth: 40, minHeight: 40, alignment: .leading)
                .accessibilityLabel("卡片图标")
        } else {
            Text(lifeRecordDefaultEmoji(for: card.kind))
                .font(.system(size: LifeRecordTileMetrics.leadingIconSize))
                .fixedSize(horizontal: true, vertical: true)
                .frame(minWidth: 40, minHeight: 40, alignment: .leading)
                .accessibilityLabel(lifeRecordKindLabel(for: card.kind))
        }
    }

    private func lifeRecordKindLabel(for kind: LifeRecordKind) -> String {
        switch kind {
        case .weather: return "天气"
        case .event: return "事件"
        case .habitTodo: return "习惯"
        case .food: return "美食"
        case .travel: return "出行"
        case .fitness: return "运动"
        case .movie: return "观影"
        case .shopping: return "购物"
        }
    }

    private func lifeRecordDefaultEmoji(for kind: LifeRecordKind) -> String {
        switch kind {
        case .event: return "⭐️"
        case .habitTodo: return "✅"
        case .weather: return "🌤️"
        case .food: return "🍜"
        case .travel: return "✈️"
        case .fitness: return "🏃"
        case .movie: return "🎬"
        case .shopping: return "🛍️"
        }
    }

    private func lifeRecordFirstGrapheme(from raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let ch = t.first else { return nil }
        return String(ch)
    }
}

private struct LifeBubbleView: View {
    let records: [LifeRecordCard]
    let onAdd: () -> Void
    let onSelect: (LifeRecordCard) -> Void

    private var visibleRecords: [LifeRecordCard] {
        records.sorted { lhs, rhs in
            if lhs.kind == .weather { return true }
            if rhs.kind == .weather { return false }
            return lhs.createdAt > rhs.createdAt
        }
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                ForEach(Array(visibleRecords.enumerated()), id: \.element.id) { index, record in
                    let diameter = bubbleDiameter(at: index, in: size)
                    Button {
                        onSelect(record)
                    } label: {
                        bubble(record, diameter: diameter)
                    }
                    .buttonStyle(.plain)
                    .position(bubblePosition(at: index, diameter: diameter, in: size))
                    .transition(.scale.combined(with: .opacity))
                }

                if visibleRecords.isEmpty {
                    VStack(spacing: 12) {
                        Text("还没有生活泡泡")
                            .font(.headline)
                        Text("和 Bola 聊聊今天，或先手动添加一张生活卡片。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("添加第一张") {
                            onAdd()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(24)
                }

                VStack {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("生活泡泡")
                                .font(.title3.weight(.bold))
                            Text("轻点一个泡泡，回看今天的小片段")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            onAdd()
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(BolaTheme.onAccentForeground)
                                .frame(width: 34, height: 34)
                                .background(Circle().fill(BolaTheme.accent))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("添加生活卡片")
                    }
                    .padding(.horizontal, BolaTheme.paddingHorizontal)
                    .padding(.top, 18)
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func bubble(_ record: LifeRecordCard, diameter: CGFloat) -> some View {
        VStack(spacing: 6) {
            Text(record.iconEmoji ?? defaultEmoji(for: record.kind))
                .font(.system(size: max(28, diameter * 0.28)))
            Text(record.title)
                .font(.system(size: max(12, diameter * 0.12), weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.76)
            if let subtitle = record.subtitle, !subtitle.isEmpty, diameter > 116 {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(.horizontal, diameter * 0.12)
        .frame(width: diameter, height: diameter)
        .background(
            Circle()
                .fill(
                    RadialGradient(
                        colors: [bubbleColor(for: record.kind).opacity(0.95), bubbleColor(for: record.kind).opacity(0.56)],
                        center: .topLeading,
                        startRadius: 8,
                        endRadius: diameter
                    )
                )
        )
        .overlay(alignment: .topLeading) {
            Circle()
                .fill(.white.opacity(0.55))
                .frame(width: max(14, diameter * 0.16), height: max(14, diameter * 0.16))
                .offset(x: diameter * 0.2, y: diameter * 0.18)
        }
        .overlay(
            Circle()
                .stroke(.white.opacity(0.58), lineWidth: 1)
        )
        .shadow(color: bubbleColor(for: record.kind).opacity(0.28), radius: 18, y: 10)
    }

    private func bubbleDiameter(at index: Int, in size: CGSize) -> CGFloat {
        let base = min(size.width, size.height)
        let variants: [CGFloat] = [0.35, 0.28, 0.31, 0.24, 0.29, 0.22, 0.26]
        return min(148, max(86, base * variants[index % variants.count]))
    }

    private func bubblePosition(at index: Int, diameter: CGFloat, in size: CGSize) -> CGPoint {
        let positions: [(CGFloat, CGFloat)] = [
            (0.30, 0.28), (0.70, 0.24), (0.52, 0.43), (0.25, 0.55),
            (0.76, 0.58), (0.46, 0.72), (0.18, 0.78), (0.82, 0.82)
        ]
        let anchor = positions[index % positions.count]
        let cycle = CGFloat(index / positions.count)
        let xNudge = (cycle.truncatingRemainder(dividingBy: 2) == 0 ? 1 : -1) * min(28, cycle * 8)
        let yNudge = min(46, cycle * 18)
        let safeTop = diameter / 2 + 86
        let safeBottom = max(safeTop, size.height - diameter / 2 - 26)
        let x = min(max(size.width * anchor.0 + xNudge, diameter / 2 + 12), size.width - diameter / 2 - 12)
        let y = min(max(size.height * anchor.1 + yNudge, safeTop), safeBottom)
        return CGPoint(x: x, y: y)
    }

    private func bubbleColor(for kind: LifeRecordKind) -> Color {
        switch kind {
        case .weather: return Color(red: 0.64, green: 0.86, blue: 1.0)
        case .event: return Color(red: 1.0, green: 0.86, blue: 0.42)
        case .habitTodo: return Color(red: 0.72, green: 0.94, blue: 0.55)
        case .food: return Color(red: 1.0, green: 0.64, blue: 0.42)
        case .travel: return Color(red: 0.66, green: 0.78, blue: 1.0)
        case .fitness: return Color(red: 0.53, green: 0.92, blue: 0.72)
        case .movie: return Color(red: 0.84, green: 0.72, blue: 1.0)
        case .shopping: return Color(red: 1.0, green: 0.72, blue: 0.86)
        }
    }

    private func defaultEmoji(for kind: LifeRecordKind) -> String {
        switch kind {
        case .event: return "⭐️"
        case .habitTodo: return "✅"
        case .weather: return "🌤️"
        case .food: return "🍜"
        case .travel: return "✈️"
        case .fitness: return "🏃"
        case .movie: return "🎬"
        case .shopping: return "🛍️"
        }
    }
}

private struct LifeRecordBubbleDetailSheet: View {
    let record: LifeRecordCard
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text(record.iconEmoji ?? defaultEmoji(for: record.kind))
                    .font(.system(size: 52))
                VStack(alignment: .leading, spacing: 8) {
                    Text(record.title)
                        .font(.title2.weight(.bold))
                    Text(Self.dateFormatter.string(from: record.createdAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let detail = record.detailNote ?? record.subtitle, !detail.isEmpty {
                    Text(detail)
                        .font(.body)
                        .lineSpacing(5)
                } else {
                    Text("这是一张还没写详情的小卡片。")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .navigationTitle(kindLabel(for: record.kind))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func kindLabel(for kind: LifeRecordKind) -> String {
        switch kind {
        case .weather: return "天气"
        case .event: return "事件"
        case .habitTodo: return "习惯"
        case .food: return "美食"
        case .travel: return "出行"
        case .fitness: return "运动"
        case .movie: return "观影"
        case .shopping: return "购物"
        }
    }

    private func defaultEmoji(for kind: LifeRecordKind) -> String {
        switch kind {
        case .event: return "⭐️"
        case .habitTodo: return "✅"
        case .weather: return "🌤️"
        case .food: return "🍜"
        case .travel: return "✈️"
        case .fitness: return "🏃"
        case .movie: return "🎬"
        case .shopping: return "🛍️"
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()
}

private struct LifeDashboardWeekStrip: View {
    @Binding var selectedDate: Date
    var onOpenMonth: () -> Void

    @Namespace private var selectionAnimation
    @State private var pressedDate: Date?
    @State private var isCalendarPressed = false

    private var weekDates: [Date] {
        let cal = Calendar.current
        let interval = cal.dateInterval(of: .weekOfYear, for: selectedDate) ?? DateInterval(start: selectedDate, duration: 86400 * 7)
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: interval.start) }
    }

    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 8
            let circleSize = max(34, min(42, (geo.size.width - spacing * 7) / 8))

            HStack(spacing: spacing) {
                ForEach(weekDates, id: \.self) { date in
                    Button {
                        withAnimation(.spring(response: 0.24, dampingFraction: 0.8)) {
                            selectedDate = date
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(dayBackgroundColor(for: date))

                            if isSelected(date) {
                                Circle()
                                    .fill(BolaTheme.accent.opacity(0.96))
                                    .matchedGeometryEffect(id: "life-dashboard-selected-day", in: selectionAnimation)
                                    .shadow(color: BolaTheme.accent.opacity(0.22), radius: 10, x: 0, y: 4)
                            }

                            VStack(spacing: 4) {
                                Text(weekdayString(for: date))
                                    .font(.system(size: max(9, circleSize * 0.22), weight: .semibold))
                                    .foregroundStyle(dayForegroundStyle(for: date))
                                Text(dayString(for: date))
                                    .font(.system(size: max(12, circleSize * 0.31), weight: .bold))
                                    .foregroundStyle(dayForegroundStyle(for: date))
                                    .contentTransition(.numericText())
                            }
                            .offset(y: -1)
                        }
                        .frame(width: circleSize, height: circleSize)
                        .overlay(
                            Circle()
                                .stroke(Color(uiColor: .separator).opacity(circleStrokeOpacity(for: date)), lineWidth: 1)
                        )
                        .scaleEffect(pressedDate.map { Calendar.current.isDate($0, inSameDayAs: date) } == true ? 0.9 : 1)
                        .rotationEffect(.degrees(pressedDate.map { Calendar.current.isDate($0, inSameDayAs: date) } == true ? -2 : 0))
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in
                                pressedDate = date
                            }
                            .onEnded { _ in
                                pressedDate = nil
                            }
                    )
                }

                Button {
                    onOpenMonth()
                } label: {
                    Image(systemName: "calendar")
                        .font(.system(size: max(14, circleSize * 0.36), weight: .bold))
                        .foregroundStyle(.primary)
                        .frame(width: circleSize, height: circleSize)
                        .background(
                            Circle()
                                .fill(BolaTheme.accent.opacity(0.18))
                        )
                        .overlay(
                            Circle()
                                .stroke(Color(uiColor: .separator).opacity(0.18), lineWidth: 1)
                        )
                        .scaleEffect(isCalendarPressed ? 0.92 : 1)
                        .rotationEffect(.degrees(isCalendarPressed ? -4 : 0))
                }
                .buttonStyle(.plain)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            isCalendarPressed = true
                        }
                        .onEnded { _ in
                            isCalendarPressed = false
                        }
                )
            }
        }
        .frame(height: 42)
        .animation(.spring(response: 0.22, dampingFraction: 0.74), value: selectedDate)
        .animation(.spring(response: 0.18, dampingFraction: 0.7), value: pressedDate)
        .animation(.spring(response: 0.18, dampingFraction: 0.7), value: isCalendarPressed)
    }

    private func isSelected(_ date: Date) -> Bool {
        Calendar.current.isDate(date, inSameDayAs: selectedDate)
    }

    private func weekdayString(for date: Date) -> String {
        let weekday = Calendar.current.component(.weekday, from: date)
        let symbols = ["日", "一", "二", "三", "四", "五", "六"]
        return symbols[max(0, min(symbols.count - 1, weekday - 1))]
    }

    private func dayString(for date: Date) -> String {
        String(Calendar.current.component(.day, from: date))
    }

    private func dayBackgroundColor(for date: Date) -> Color {
        if isSelected(date) {
            return BolaTheme.accent.opacity(0.88)
        }
        if Calendar.current.isDateInToday(date) {
            return BolaTheme.accent.opacity(0.34)
        }
        return BolaTheme.accent.opacity(0.18)
    }

    private func dayForegroundStyle(for date: Date) -> AnyShapeStyle {
        if isSelected(date) {
            return AnyShapeStyle(.black)
        }
        if Calendar.current.isDateInToday(date) {
            return AnyShapeStyle(.black)
        }
        return AnyShapeStyle(.primary.opacity(0.6))
    }

    private func circleStrokeOpacity(for date: Date) -> Double {
        if isSelected(date) {
            return 0
        }
        if Calendar.current.isDateInToday(date) {
            return 0.12
        }
        return 0.18
    }
}

private struct LifeDashboardCalendarSheet: View {
    @Binding var selectedDate: Date
    @Binding var visibleMonth: Date
    @Environment(\.dismiss) private var dismiss

    private var calendarColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Button {
                        shiftMonth(by: -1)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.headline)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Text(monthTitle)
                        .font(.headline)

                    Spacer()

                    Button {
                        shiftMonth(by: 1)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.headline)
                    }
                    .buttonStyle(.plain)
                }

                LazyVGrid(columns: calendarColumns, spacing: 12) {
                    ForEach(weekdaySymbols, id: \.self) { symbol in
                        Text(symbol)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }

                    ForEach(monthCells.indices, id: \.self) { index in
                        if let date = monthCells[index] {
                            Button {
                                selectedDate = date
                            } label: {
                                Text(dayLabel(for: date))
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Calendar.current.isDate(date, inSameDayAs: selectedDate) ? AnyShapeStyle(.black) : AnyShapeStyle(.primary))
                                    .frame(maxWidth: .infinity, minHeight: 38)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(Calendar.current.isDate(date, inSameDayAs: selectedDate) ? BolaTheme.accent : .clear)
                                    )
                            }
                            .buttonStyle(.plain)
                        } else {
                            Color.clear
                                .frame(height: 38)
                        }
                    }
                }

                Spacer()
            }
            .padding(20)
            .navigationTitle("选择日期")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var weekdaySymbols: [String] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.shortStandaloneWeekdaySymbols
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月"
        return formatter.string(from: visibleMonth)
    }

    private var monthCells: [Date?] {
        let cal = Calendar.current
        guard let interval = cal.dateInterval(of: .month, for: visibleMonth),
              let days = cal.range(of: .day, in: .month, for: visibleMonth) else {
            return []
        }

        let firstWeekday = cal.component(.weekday, from: interval.start)
        let leading = max(0, firstWeekday - cal.firstWeekday)
        let prefixCount = leading < 0 ? leading + 7 : leading
        let prefix = Array(repeating: Optional<Date>.none, count: prefixCount)
        let dates = days.compactMap { day in
            cal.date(byAdding: .day, value: day - 1, to: interval.start)
        }.map(Optional.some)
        return prefix + dates
    }

    private func shiftMonth(by offset: Int) {
        visibleMonth = Calendar.current.date(byAdding: .month, value: offset, to: visibleMonth) ?? visibleMonth
    }

    private func dayLabel(for date: Date) -> String {
        String(Calendar.current.component(.day, from: date))
    }
}

/// 编辑态右下角缩放按钮：圆形毛玻璃 + 放大/缩小 icon，点击切换 featured / compact。
private struct LifeDashboardResizeButton: View {
    let variant: LifeDashboardTileVariant
    var onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 30, height: 30)
                    .shadow(color: .black.opacity(0.10), radius: 4, y: 2)

                Image(systemName: variant == .featured
                      ? "arrow.down.right.and.arrow.up.left"
                      : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 44, height: 44)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

private struct LifeDashboardCornerHandleShape: Shape {
    let inset: CGFloat

    func path(in rect: CGRect) -> Path {
        let startX = rect.maxX - inset
        let startY = rect.maxY - 10 - inset
        let radius = max(3, 10 - inset)
        var path = Path()
        path.move(to: CGPoint(x: startX, y: startY))
        path.addArc(
            center: CGPoint(x: rect.maxX - radius - inset, y: rect.maxY - radius - inset),
            radius: radius,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        return path
    }
}

private struct LifeDashboardTileDropDelegate: DropDelegate {
    let destination: LifeDashboardTileKind
    @Binding var dashboardLayout: [LifeDashboardTileLayout]
    @Binding var draggedKind: LifeDashboardTileKind?

    func dropEntered(info: DropInfo) {
        guard let draggedKind, draggedKind != destination,
              let fromIndex = dashboardLayout.firstIndex(where: { $0.kind == draggedKind }),
              let toIndex = dashboardLayout.firstIndex(where: { $0.kind == destination }) else { return }

        withAnimation(.spring(response: 0.26, dampingFraction: 0.86)) {
            let moved = dashboardLayout.remove(at: fromIndex)
            dashboardLayout.insert(moved, at: toIndex)
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedKind = nil
        dashboardLayout = LifeDashboardLayoutStore.normalized(dashboardLayout)
        LifeDashboardLayoutStore.save(dashboardLayout)
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {}
}
? {
        DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {}
}
