//
//  IOSLifeContainerView.swift
//  生活 Tab：对齐 Figma「iPhone 17 - 15」6068:3708。
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
    /// 生活记录卡左上角：emoji / SF Symbol 统一视觉尺寸（原 28）。
    static let leadingIconSize: CGFloat = 36
    /// 通用卡「内容」单行占位高度，无内容时也占位，主标题纵向对齐一致。
    static let subtitleReservedHeight: CGFloat = 22
}

struct IOSLifeContainerView: View {
    @Binding var lifeSegment: IOSLifeSubPage
    @Binding var bubbleMode: Bool
    @Binding var reminders: [BolaReminder]
    /// 点 idle 头像进入根级「对话」Tab。
    var onRequestChat: () -> Void = {}

    @StateObject private var rhythm = IOSRhythmHRVModel()
    @StateObject private var weather = IOSWeatherLocationModel()
    @StateObject private var healthHabits = IOSHealthHabitAnalysisModel()

    @State private var lifeRecords: [LifeRecordCard] = LifeRecordListStore.load()
    @State private var digestText: String = ""
    @State private var showDigestEditor = false
    @State private var draftDigest: String = ""

    @State private var showAddRecordSheet = false
    @State private var addKind: LifeRecordKind = .event
    @State private var newRecordTitle: String = ""
    @State private var newRecordSubtitle: String = ""
    /// 空字符串表示使用类型默认图标；否则为所选预设或手动输入的一个 emoji。
    @State private var newRecordIconEmoji: String = ""

    var body: some View {
        ZStack(alignment: .top) {
            lifePageBackground
                .ignoresSafeArea(edges: [.top, .bottom])

            /// 生活 / 时光用 `switch` 切换单列纵向 `ScrollView`：内层分页 `TabView`/横向 `ScrollView` 会破坏安全区或阻断根级 `tabBarMinimizeBehavior`，故仅保留导航栏分段切换。
            Group {
                switch lifeSegment {
                case .dailyLife:
                    lifeScroll
                case .timeMoments:
                    timeMomentsScroll
                }
            }
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
        .onChange(of: lifeSegment) { _, new in
            if new == .dailyLife {
                reloadDigest()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .bolaLifeRecordsDidReset)) { _ in
            lifeRecords = LifeRecordListStore.load()
        }
        .sheet(isPresented: $showDigestEditor) {
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
        .sheet(isPresented: $showAddRecordSheet) {
            addLifeRecordSheet
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
                .onChange(of: addKind) { _, _ in
                    newRecordIconEmoji = ""
                }
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

    /// 生活页主列：Section1（今日看到+节奏条）/ Section2（正在关心）/ Section3（生活记录）之间 **等距**。
    private var lifePageMainSectionSpacing: CGFloat {
        bubbleMode ? 40 : 36
    }

    private var lifeScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: lifePageMainSectionSpacing) {
                bolaTodayFigma
                remindersSection
                lifeRecordsFigma
                IOSHealthHabitAnalysisSection(model: healthHabits)
            }
            .padding(.horizontal, BolaTheme.paddingHorizontal)
            .padding(.top, 14)
            .padding(.bottom, 24)
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

    private var timeMomentsScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                IOSLifeTimePageView(bubbleMode: bubbleMode, useLifePageBackdrop: true)
            }
            .padding(.horizontal, BolaTheme.paddingHorizontal)
            .padding(.top, 14)
            .padding(.bottom, 24)
        }
        .background(Color.clear)
        .scrollIndicators(.hidden)
    }

    private var lifePageBackground: some View {
        BolaLifeAmbientBackground()
    }

    // MARK: - Section 1（Figma：开放排版，非整张大灰卡）

    private var bolaTodayFigma: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                Text("Bola今日看到…")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                Button {
                    draftDigest = digestText
                    showDigestEditor = true
                } label: {
                    HStack(spacing: 5) {
                        LifeAccentChromePlusIcon()
                        Text("修改")
                            .font(.system(size: LifeAccentChromeButtonMetrics.fontSize, weight: .semibold))
                            .foregroundStyle(BolaTheme.onAccentForeground)
                    }
                    .padding(.horizontal, LifeAccentChromeButtonMetrics.hPad)
                    .padding(.vertical, LifeAccentChromeButtonMetrics.vPad)
                    .background(Capsule().fill(BolaTheme.accent))
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 2) {
                    VStack(spacing: 0) {
                        Button {
                            onRequestChat()
                        } label: {
                            LifeIdleOneAvatarView()
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("打开对话")

                        Text("和Bola聊聊")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(BolaTheme.figmaSubtleCaption)
                            .multilineTextAlignment(.center)
                            .frame(width: LifeIdleOneAvatarView.displayWidth)
                            .offset(y: -22)
                    }
                    .frame(width: LifeIdleOneAvatarView.displayWidth, alignment: .center)
                    .offset(x: -6, y: -13)

                    VStack(alignment: .leading, spacing: 10) {
                        Text(speechLine)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: BolaTheme.cornerLifePageCard, style: .continuous)
                                    .fill(BolaTheme.surfaceBubble)
                                    .shadow(color: Color.black.opacity(0.06), radius: 4, y: 2)
                            )

                        figmaBulletGrid
                    }
                    .offset(x: -12)
                }
                .padding(bubbleMode ? 12 : 0)
                .background {
                    if bubbleMode {
                        RoundedRectangle(cornerRadius: BolaTheme.cornerLifePageCard, style: .continuous)
                            .fill(BolaTheme.surfaceElevated)
                            .shadow(color: Color.black.opacity(0.1), radius: 16, y: 6)
                    }
                }

                IOSRhythmBarSection(model: rhythm, bubbleMode: bubbleMode)
                    .offset(y: -26)
                    .padding(.bottom, -26)
            }
        }
    }

    private var speechLine: String {
        let t = digestText.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return "节奏不错！继续保持哦~" }
        return primaryDigestLine
    }

    private var primaryDigestLine: String {
        let t = digestText.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return "" }
        if let first = t.split(separator: "。").first, !first.isEmpty {
            return String(first) + "。"
        }
        return t
    }

    private var figmaBulletGrid: some View {
        let lines = digestBulletLines(from: digestText)
        return LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
            alignment: .leading,
            spacing: 8
        ) {
            ForEach(lines.indices, id: \.self) { i in
                HStack(alignment: .top, spacing: 6) {
                    Circle()
                        .fill(BolaTheme.accent)
                        .frame(width: 5, height: 5)
                        .overlay {
                            Circle().strokeBorder(Color.black.opacity(0.88), lineWidth: 0.6)
                        }
                        .padding(.top, 4)
                    Text(lines[i])
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(BolaTheme.figmaMutedBody)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func digestBulletLines(from raw: String) -> [String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return ["下午一直在走动", "下午一直在走动", "心情有点起伏…", "心情有点起伏…"]
        }
        let parts = trimmed.split(whereSeparator: { $0 == "。" || $0 == "；" || $0 == "\n" })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let rest = Array(parts.dropFirst())
        if rest.isEmpty { return [] }
        return Array(rest.prefix(4))
    }

    // MARK: - Section 3

    private var remindersSection: some View {
        IOSRemindersSectionView(reminders: $reminders, style: .figmaLife)
    }

    // MARK: - Section 4

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
                // WeatherKit：`condition` → emoji；Open-Meteo：WMO `weather_code` → emoji。
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
                ProgressView()
                    .scaleEffect(0.85)
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

    /// 默认事件 ⭐️、习惯 ✅；用户在表单里填的 `iconEmoji` 优先。
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
                .accessibilityLabel(lifeRecordKindAccessibilityLabel(for: card.kind))
        }
    }

    private func lifeRecordKindAccessibilityLabel(for kind: LifeRecordKind) -> String {
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

    /// 保存时只取用户输入的第一个完整字素（避免误存整句）。
    private func lifeRecordFirstGrapheme(from raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let ch = t.first else { return nil }
        return String(ch)
    }
}

// MARK: - 「和Bola聊聊」头像

/// 使用 `UIImage.withRenderingMode(.alwaysOriginal)`，避免 Asset 被当成 Template 整块染成前景色（黑矩形）。
/// 显示尺寸较资源略小，为右侧文案让出横向空间；比例与原先 228×156 一致。
private struct LifeIdleOneAvatarView: View {
    /// 布局宽度固定，`contentZoom` + `scaledToFill` 在框内再放大，多余裁掉。
    static let displayWidth: CGFloat = 136
    static let displayHeight: CGFloat = 110
    private static let contentZoom: CGFloat = 1.48

    var body: some View {
        Group {
            if let base = UIImage(named: "idleone0") {
                Image(uiImage: base.withRenderingMode(.alwaysOriginal))
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .scaleEffect(Self.contentZoom, anchor: .center)
                    .frame(width: Self.displayWidth, height: Self.displayHeight)
                    .clipped()
            } else {
                Image(systemName: "face.smiling.fill")
                    .font(.system(size: 50))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(BolaTheme.accent)
            }
        }
        .frame(width: Self.displayWidth, height: Self.displayHeight)
        .clipShape(RoundedRectangle(cornerRadius: BolaTheme.cornerLifePageCard, style: .continuous))
    }
}

