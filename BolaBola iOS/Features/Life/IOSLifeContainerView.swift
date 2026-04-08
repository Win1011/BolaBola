//
//  IOSLifeContainerView.swift
//  生活 Tab：半圆弧主视觉 + 双列（提醒/健康）+ 今日记录。
//

import Combine
import SwiftUI
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
    static let healthCardRowHeight: CGFloat = 152
    /// 两卡之间的垂直间距。
    static let healthStackSpacing: CGFloat = 12
    /// 右列总高度 = 睡眠 + 间距 + 运动；左列「正在关心的事」白卡与之严格同高。
    static var dashboardColumnHeight: CGFloat {
        healthCardRowHeight * 2 + healthStackSpacing
    }
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
            lifeScroll
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            reloadDigest()
            weather.requestAndFetch()
            Task { await rhythm.refresh() }
        }
        .task {
            await healthHabits.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .bolaLifeRecordsDidReset)) { _ in
            lifeRecords = LifeRecordListStore.load()
        }
        .sheet(isPresented: $showDigestEditor) {
            digestEditorSheet
        }
        .sheet(isPresented: $showAddRecordSheet) {
            addLifeRecordSheet
        }
        .alert("节奏条", isPresented: $showRhythmInfo) {
            Button("好的", role: .cancel) {}
        } message: {
            Text("基于今日心率变异性（HRV）样本按小时汇总，仅作状态参考，非医疗诊断。")
        }
    }

    // MARK: - 滚动主体

    private var lifeScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // 1. 全宽半圆弧主视觉（负 padding 出血到屏边）
                heroArcSection
                    .padding(.horizontal, -BolaTheme.paddingHorizontal)

                // 2. 双列：提醒（左）+ 健康快捷卡（右）
                middleTwoColumnSection

                // 3. 今日生活记录
                lifeRecordsFigma
            }
            .padding(.horizontal, BolaTheme.paddingHorizontal)
            .padding(.top, 6)
            .padding(.bottom, 28)
        }
        .background(Color.clear)
        .scrollIndicators(.hidden)
        .refreshable {
            reloadDigest()
            weather.requestAndFetch()
            await rhythm.refresh()
            await healthHabits.refresh()
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
            let heroSectionLiftY: CGFloat = 16
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
                .offset(y: heroContentDropY)

                // 节奏条标签（左下角）
                HStack(spacing: 4) {
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
                .padding(.leading, BolaTheme.paddingHorizontal + 4)
                .padding(.bottom, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: w, height: geo.size.height, alignment: .bottom)
            .offset(y: -heroSectionLiftY)
            // 语音气泡：浮在弧内上方
            .overlay(alignment: .top) {
                heroBubble
                    .padding(.horizontal, BolaTheme.paddingHorizontal + 12)
                    .padding(.top, 22)
                    .offset(y: heroContentDropY)
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

    // MARK: - Section 2：双列（提醒 + 健康快捷卡）

    private var middleTwoColumnSection: some View {
        HStack(alignment: .top, spacing: 12) {
            IOSRemindersSectionView(reminders: $reminders, style: .figmaLife)
                .frame(maxWidth: .infinity)
                .frame(height: LifeMiddleCardMetrics.dashboardColumnHeight, alignment: .topLeading)

            VStack(spacing: LifeMiddleCardMetrics.healthStackSpacing) {
                compactSleepCard
                    .frame(height: LifeMiddleCardMetrics.healthCardRowHeight)
                compactExerciseCard
                    .frame(height: LifeMiddleCardMetrics.healthCardRowHeight)
            }
            .frame(maxWidth: .infinity)
            .frame(height: LifeMiddleCardMetrics.dashboardColumnHeight, alignment: .top)
        }
        .padding(.top, 24)
    }

    // MARK: - 睡眠紧凑卡

    private var compactSleepCard: some View {
        NavigationLink {
            IOSHealthSleepDetailView(model: healthHabits)
        } label: {
            compactSleepContent
        }
        .buttonStyle(.plain)
    }

    private var compactSleepContent: some View {
        let hours = IOSHealthHabitSnapshot.todaySleepHoursValue(healthHabits)
        let fraction = min(1.0, max(0.0, hours / IOSHealthRingGoals.sleepHoursTarget))

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Image(systemName: "moon.zzz.fill")
                    .font(.subheadline)
                    .foregroundStyle(BolaTheme.listRowIcon)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }

            Spacer().frame(height: 6)

            Text("睡眠")
                .font(.system(size: 17, weight: .semibold))

            Spacer(minLength: 8)

            // 进度条
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

            Spacer().frame(height: 6)

            Text(hours > 0.01 ? "\(String(format: "%.1f", hours)) 小时" : "暂无数据")
                .font(.caption2)
                .foregroundStyle(hours > 0.01 ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
        }
        .padding(12)
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

    // MARK: - 运动紧凑卡

    private var compactExerciseCard: some View {
        NavigationLink {
            IOSHealthActivityDetailView(model: healthHabits)
        } label: {
            compactExerciseContent
        }
        .buttonStyle(.plain)
    }

    private var compactExerciseContent: some View {
        let steps = IOSHealthHabitSnapshot.todayStepsValue(healthHabits)
        let fraction = min(1.0, max(0.0, steps / IOSHealthRingGoals.stepsPerDay))
        let hasData = steps > 0

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Image(systemName: "figure.walk")
                    .font(.subheadline)
                    .foregroundStyle(BolaTheme.listRowIcon)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }

            Spacer().frame(height: 6)

            Text("运动")
                .font(.system(size: 17, weight: .semibold))

            Spacer(minLength: 8)

            // 圆环
            ZStack {
                Circle()
                    .stroke(Color.green.opacity(0.13), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(
                        LinearGradient(
                            colors: [Color.green.opacity(0.65), Color.green],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 52, height: 52)
            .frame(maxWidth: .infinity)

            Spacer().frame(height: 6)

            Text(hasData ? "\(IOSHealthHabitSnapshot.intString(from: steps)) 步" : "暂无数据")
                .font(.caption2)
                .foregroundStyle(hasData ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(12)
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
                Text("今日生活记录")
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
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(lifeRecords) { card in
                    lifeRecordTile(card)
                }
            }
        }
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
