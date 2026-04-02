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

struct IOSLifeContainerView: View {
    @Binding var lifeSegment: IOSLifeSubPage
    @Binding var bubbleMode: Bool
    @Binding var reminders: [BolaReminder]
    /// 点 idle 头像进入根级「对话」Tab。
    var onRequestChat: () -> Void = {}

    @StateObject private var rhythm = IOSRhythmHRVModel()
    @StateObject private var weather = IOSWeatherLocationModel()

    @State private var lifeRecords: [LifeRecordCard] = LifeRecordListStore.load()
    @State private var digestText: String = ""
    @State private var showDigestEditor = false
    @State private var draftDigest: String = ""

    @State private var showAddRecordSheet = false
    @State private var addKind: LifeRecordKind = .event
    @State private var newRecordTitle: String = ""
    @State private var newRecordSubtitle: String = ""

    var body: some View {
        ZStack(alignment: .top) {
            lifePageBackground
                .ignoresSafeArea(edges: [.top, .bottom])

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
        .onChange(of: lifeSegment) { _, new in
            if new == .dailyLife {
                reloadDigest()
            }
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
            NavigationStack {
                Form {
                    Picker("类型", selection: $addKind) {
                        Text("事件卡").tag(LifeRecordKind.event)
                        Text("习惯卡").tag(LifeRecordKind.habitTodo)
                    }
                    TextField("标题", text: $newRecordTitle)
                    TextField("副标题（可选）", text: $newRecordSubtitle)
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
                                title: newRecordTitle.isEmpty ? (addKind == .event ? "事件" : "习惯") : newRecordTitle,
                                subtitle: newRecordSubtitle.isEmpty ? nil : newRecordSubtitle
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
            }
            .padding(.horizontal, BolaTheme.paddingHorizontal)
            .padding(.top, 14)
            .padding(.bottom, 24)
        }
        .background(Color.clear)
        .refreshable {
            reloadDigest()
            weather.requestAndFetch()
            await rhythm.refresh()
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
    }

    private var lifePageBackground: some View {
        ZStack {
            BolaTheme.backgroundGrouped
            // 仅顶部向中间淡出；底部不再叠主色，避免出现「底部也有一团球」的错觉。
            LinearGradient(
                colors: [
                    BolaTheme.accent.opacity(BolaTheme.accentGlowTopOpacity),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: UnitPoint(x: 0.5, y: 0.42)
            )
        }
        // 球单独放在 overlay：不参与 ZStack 子视图的理想尺寸计算，避免牵动布局；球体本身用固定外包框 + scaleEffect。
        .overlay(alignment: .top) {
            LifeBreathingOrbLayer()
                .offset(y: -255)
        }
        // 底部氛围光球：锚在屏底；向下偏移量 200；减去底部安全区以适配不同机型。
        .overlay(alignment: .bottom) {
            GeometryReader { geo in
                LifeBreathingOrbLayer(isBottomAccent: true)
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
                    .offset(y: 200 - geo.safeAreaInsets.bottom)
            }
            .allowsHitTesting(false)
        }
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
            case .event, .habitTodo:
                genericRecordTile(card)
            }
        }
    }

    private var weatherTile: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: weatherIconName)
                    .font(.system(size: 28))
                    .foregroundStyle(BolaTheme.accent)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            Text("天气")
                .font(.system(size: 19, weight: .semibold))
            if weather.isLoading {
                ProgressView()
                    .scaleEffect(0.85)
            } else if let w = weather.weather {
                Text(String(format: "%.0f°C", w.temperatureC))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(BolaTheme.figmaSubtleCaption)
            } else if weather.lastError != nil {
                Text("无法获取")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("轻点刷新")
                    .font(.caption)
                    .foregroundStyle(BolaTheme.figmaSubtleCaption)
            }
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

    private var weatherIconName: String {
        guard let code = weather.weather?.weatherCode else {
            return "sun.max.fill"
        }
        return WeatherCodeMapper.systemImageName(code: code)
    }

    private func genericRecordTile(_ card: LifeRecordCard) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: card.kind == .event ? "star.fill" : "checklist")
                    .font(.system(size: 28))
                    .foregroundStyle(BolaTheme.accent)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            Text(card.title)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.primary)
            if let sub = card.subtitle, !sub.isEmpty {
                Text(sub)
                    .font(.caption)
                    .foregroundStyle(BolaTheme.figmaSubtleCaption)
                    .lineLimit(2)
            }
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

// MARK: - 背景呼吸球

/// 固定外包框 + 圆不变 `frame`、用 `scaleEffect` 呼吸；Timer 只刷新本 struct，避免整页随相位重布局。
/// 双层：内芯高不透明度 + 轻 blur（更亮），外晕略模糊（避免单层超大 blur 把颜色洗灰）。
/// 顶球：多频水平漂移 + 轻微随机游走，避免单一周期；底球保持简单呼吸。
private struct LifeBreathingOrbLayer: View {
    /// 底部装饰球：更弱、略错位相位，避免与顶球完全同步。
    var isBottomAccent: Bool = false

    /// 底球：单一相位。顶球：呼吸与位移拆成两路，避免「缩放过快、漂移却慢」绑在同一 phase 上。
    @State private var phase: Double = 0
    @State private var breathPhase: Double = 0
    @State private var driftPhase: Double = 0
    /// 顶球专用：小幅随机横向漂移，与正弦组合后更「活」。
    @State private var wanderX: CGFloat = 0

    var body: some View {
        let pulse: Double
        let pulseAlt: Double
        if isBottomAccent {
            pulse = Self.smoothedPulse(phase: phase, isBottomAccent: true)
            pulseAlt = Self.altPulse(phase: phase)
        } else {
            pulse = Self.smoothedPulse(phase: breathPhase, isBottomAccent: false)
            pulseAlt = Self.altPulse(phase: breathPhase)
        }
        let pulseMix = Self.mixedPulse(pulse: pulse, pulseAlt: pulseAlt, isBottomAccent: isBottomAccent)
        let scale = Self.breathScale(pulseMix: pulseMix, isBottomAccent: isBottomAccent)
        let dim: Double = isBottomAccent ? 0.5 : 1.0
        let coreA: Double
        let coreB: Double
        let haloA: Double
        let haloB: Double
        if isBottomAccent {
            coreA = (0.72 + 0.22 * pulse) * dim
            coreB = (0.38 + 0.18 * pulse) * dim
            haloA = (0.32 + 0.18 * pulse) * dim
            haloB = (0.10 + 0.12 * pulse) * dim
        } else {
            // 顶球：叠层里会再加「高亮芯」，这里外晕仍可略浓
            coreA = 0.88 + 0.12 * pulse
            coreB = 0.55 + 0.22 * pulse
            haloA = 0.48 + 0.22 * pulse
            haloB = 0.18 + 0.18 * pulse
        }
        let driftX = Self.horizontalDrift(phase: isBottomAccent ? phase : driftPhase, isBottomAccent: isBottomAccent)
        let driftY = Self.verticalDrift(phase: isBottomAccent ? phase : driftPhase, isBottomAccent: isBottomAccent)
        let outerSize: CGFloat = isBottomAccent ? 392 : 400
        let innerSize: CGFloat = isBottomAccent ? 254 : 260
        let boxW: CGFloat = isBottomAccent ? 505 : 860
        let boxH: CGFloat = isBottomAccent ? 458 : 540
        let blurOuter: Double
        let blurInner: Double
        if isBottomAccent {
            blurOuter = 18 + 10 * pulse
            blurInner = 5 + 3 * pulse
        } else {
            // 顶球：减轻 blur，否则颜色全被洗成灰雾，「变亮」看不出来
            blurOuter = 10 + 6 * pulse
            blurInner = 2.2 + 1.1 * pulse
        }
        let offsetX = driftX + (isBottomAccent ? 0 : wanderX)

        return ZStack {
            Self.haloCircle(
                haloA: haloA,
                haloB: haloB,
                side: outerSize,
                blur: blurOuter
            )
            Self.coreCircle(
                coreA: coreA,
                coreB: coreB,
                side: innerSize,
                blur: blurInner
            )
            if !isBottomAccent {
                Self.hotHighlightCore(pulse: pulse)
            }
        }
        .scaleEffect(scale)
        .offset(x: offsetX, y: driftY)
        .frame(width: boxW, height: boxH)
        .allowsHitTesting(false)
        .onReceive(Timer.publish(every: 1.0 / 45.0, on: .main, in: .common).autoconnect()) { _ in
            if isBottomAccent {
                phase += 0.045
            } else {
                // 相位增量越小，漂移/呼吸越慢；随机游走略收幅，减少「晃」的急促感。
                breathPhase += 0.009
                driftPhase += 0.026
                wanderX += CGFloat.random(in: -0.5 ... 0.5)
                wanderX *= 0.988
                wanderX = min(22, max(-22, wanderX))
            }
        }
    }

    private static func smoothedPulse(phase: Double, isBottomAccent: Bool) -> Double {
        let shifted = phase + (isBottomAccent ? 1.7 : 0)
        return (sin(shifted) + 1) * 0.5
    }

    private static func altPulse(phase: Double) -> Double {
        (sin(phase * 0.78 + 0.42) + 1) * 0.5
    }

    private static func mixedPulse(pulse: Double, pulseAlt: Double, isBottomAccent: Bool) -> Double {
        if isBottomAccent { return pulse }
        return pulse * 0.58 + pulseAlt * 0.42
    }

    private static func breathScale(pulseMix: Double, isBottomAccent: Bool) -> CGFloat {
        let base: CGFloat = isBottomAccent ? 0.88 : 0.94
        // 顶球：缩小缩放幅度，呼吸更缓（相位已单独放慢）
        let amp: CGFloat = isBottomAccent ? 0.10 : 0.075
        return base + amp * CGFloat(pulseMix)
    }

    private static func horizontalDrift(phase: Double, isBottomAccent: Bool) -> CGFloat {
        guard !isBottomAccent else { return 0 }
        let p = phase
        let a = 28 * sin(p * 0.29)
        let b = 20 * sin(p * 0.48 + 0.9)
        let c = 14 * sin(p * 0.82 + 1.7)
        let d = 10 * sin(p * 1.18 + 0.2)
        return CGFloat(a + b + c + d)
    }

    /// 顶球略上下飘，位移更容易被眼角捕捉到。
    private static func verticalDrift(phase: Double, isBottomAccent: Bool) -> CGFloat {
        guard !isBottomAccent else { return 0 }
        let p = phase
        return CGFloat(
            9 * sin(p * 0.25 + 0.4)
                + 6 * sin(p * 0.52 + 1.2)
        )
    }

    /// 几乎不糊的高亮芯，肉眼「更亮」主要来自这一层。
    private static func hotHighlightCore(pulse: Double) -> some View {
        let t = 0.9 + 0.1 * pulse
        return Circle()
            .fill(
                RadialGradient(
                    colors: [
                        BolaTheme.accent.opacity(t),
                        BolaTheme.accent.opacity(0.55),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 2,
                    endRadius: 88
                )
            )
            .frame(width: 150, height: 150)
            .blur(radius: 3)
    }

    private static func haloCircle(haloA: Double, haloB: Double, side: CGFloat, blur: Double) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        BolaTheme.accent.opacity(haloA),
                        BolaTheme.accent.opacity(haloB),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 40,
                    endRadius: 220
                )
            )
            .frame(width: side, height: side)
            .blur(radius: blur)
    }

    private static func coreCircle(coreA: Double, coreB: Double, side: CGFloat, blur: Double) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        BolaTheme.accent.opacity(coreA),
                        BolaTheme.accent.opacity(coreB),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 6,
                    endRadius: 130
                )
            )
            .frame(width: side, height: side)
            .blur(radius: blur)
    }
}
