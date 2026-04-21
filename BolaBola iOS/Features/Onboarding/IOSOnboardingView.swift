//
//  IOSOnboardingView.swift
//

import CoreLocation
import HealthKit
import SwiftUI
import UserNotifications

// MARK: - Root

struct IOSOnboardingView: View {
    var onDone: () -> Void

    @State private var stepIndex = 0
    @StateObject private var weatherModel = IOSWeatherLocationModel()
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var healthRequested = false

    private let healthStore = HKHealthStore()
    private let totalSteps = 6

    var body: some View {
        ZStack(alignment: .top) {
            BolaGrowthAmbientBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // 进度点
                HStack(spacing: 6) {
                    ForEach(0 ..< totalSteps, id: \.self) { i in
                        Capsule()
                            .fill(i <= stepIndex ? BolaTheme.accent : Color.primary.opacity(0.12))
                            .frame(width: i == stepIndex ? 22 : 7, height: 7)
                            .animation(.spring(response: 0.32, dampingFraction: 0.72), value: stepIndex)
                    }
                }
                .padding(.top, 56)
                .padding(.bottom, 4)

                TabView(selection: $stepIndex) {
                    OnboardingWelcomePage(onNext: { stepIndex = 1 })
                        .tag(0)
                    OnboardingCompanionPage(onNext: { stepIndex = 2 })
                        .tag(1)
                    OnboardingGrowthPage(onNext: { stepIndex = 3 })
                        .tag(2)
                    OnboardingNotifPage(
                        status: notificationStatus,
                        onNext: requestNotifications,
                        onSkip: { stepIndex = 4 }
                    )
                    .tag(3)
                    OnboardingHealthPage(
                        requested: healthRequested,
                        onNext: requestHealthAccess,
                        onSkip: { stepIndex = 5 }
                    )
                    .tag(4)
                    OnboardingLocationPage(
                        weatherModel: weatherModel,
                        onDone: finishOnboarding
                    )
                    .tag(5)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
        }
        .task {
            let s = await UNUserNotificationCenter.current().notificationSettings()
            notificationStatus = s.authorizationStatus
        }
    }

    // MARK: Actions

    private func requestNotifications() {
        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            let s = await UNUserNotificationCenter.current().notificationSettings()
            await MainActor.run {
                notificationStatus = s.authorizationStatus
                stepIndex = 4
            }
        }
    }

    private func requestHealthAccess() {
        guard HKHealthStore.isHealthDataAvailable() else { stepIndex = 5; return }
        // 与 IOSHealthHabitAnalysisModel.readTypes 保持完全一致，避免后续 tab 再次弹系统授权窗
        var types = Set<HKObjectType>()
        if let t = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) { types.insert(t) }
        if let t = HKQuantityType.quantityType(forIdentifier: .appleExerciseTime) { types.insert(t) }
        if let t = HKQuantityType.quantityType(forIdentifier: .stepCount) { types.insert(t) }
        if let t = HKQuantityType.quantityType(forIdentifier: .heartRate) { types.insert(t) }
        if let t = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) { types.insert(t) }
        if let t = HKQuantityType.quantityType(forIdentifier: .appleStandTime) { types.insert(t) }
        if let t = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { types.insert(t) }
        healthStore.requestAuthorization(toShare: [], read: types) { _, _ in
            DispatchQueue.main.async {
                healthRequested = true
                UserDefaults.standard.set(true, forKey: IOSHealthHabitAnalysisModel.healthReadPromptCompletedKey)
                stepIndex = 5
            }
        }
    }

    private func finishOnboarding() {
        BolaOnboardingState.markCompleted()
        onDone()
    }
}

// MARK: - 通用页面框架

/// 每页统一布局：图标区（顶部）→ 标题+副标题 → 中间内容 → 底部按钮
private struct OnboardingPage<Middle: View>: View {
    let icon: String
    let iconTint: Color
    let title: String
    let subtitle: String
    let primaryLabel: String
    let primaryAction: () -> Void
    var secondaryLabel: String? = nil
    var secondaryAction: (() -> Void)? = nil
    @ViewBuilder var middle: () -> Middle

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // 图标
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(iconTint.opacity(0.13))
                        .frame(width: 72, height: 72)
                    Image(systemName: icon)
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(iconTint)
                }
                .padding(.top, 28)
                .padding(.bottom, 22)

                Text(title)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.primary)
                    .padding(.bottom, 10)

                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
                    .padding(.bottom, 28)

                middle()

                Spacer(minLength: 32)
            }
            .padding(.horizontal, BolaTheme.paddingHorizontal)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                Button(action: primaryAction) {
                    Text(primaryLabel)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(BolaTheme.onAccentForeground)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(BolaTheme.accent)
                        .clipShape(Capsule())
                }
                if let sec = secondaryLabel, let secAction = secondaryAction {
                    Button(action: secAction) {
                        Text(sec)
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                    }
                    .frame(height: 36)
                }
            }
            .padding(.horizontal, BolaTheme.paddingHorizontal)
            .padding(.bottom, 24)
            .background(
                LinearGradient(
                    colors: [BolaTheme.backgroundGrouped.opacity(0), BolaTheme.backgroundGrouped],
                    startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.35)
                )
                .ignoresSafeArea()
            )
        }
    }
}

// MARK: - 功能行（卡片内 feature row）

private struct FeatureRow: View {
    let icon: String
    let tint: Color
    let title: String
    let desc: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint.opacity(0.13))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(desc)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - 分组卡片容器（与成长页同款）

private struct InfoCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BolaTheme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: BolaTheme.cornerCard, style: .continuous))
    }
}

// MARK: - Page 0 欢迎

private struct OnboardingWelcomePage: View {
    let onNext: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()

            VStack(alignment: .leading, spacing: 14) {
                Text("BolaBola")
                    .font(.system(size: 52, weight: .black))
                    .foregroundStyle(BolaTheme.accent)
                    .shadow(color: BolaTheme.accent.opacity(0.35), radius: 18, x: 0, y: 4)

                Text("你的手腕上，\n有只 Bola 在等你。")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineSpacing(6)
            }

            Spacer(minLength: 24)

            Text("Bola 住在 Apple Watch 上，跟着你的生活一起成长。\n先用几步把基础准备好。")
                .font(.body)
                .foregroundStyle(.secondary)
                .lineSpacing(5)

            Spacer()

            Button(action: onNext) {
                Text("开始")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(BolaTheme.onAccentForeground)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(BolaTheme.accent)
                    .clipShape(Capsule())
            }
            .padding(.bottom, 40)
        }
        .padding(.horizontal, BolaTheme.paddingHorizontal)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Page 1 陪伴值

private struct OnboardingCompanionPage: View {
    let onNext: () -> Void

    var body: some View {
        OnboardingPage(
            icon: "heart.fill",
            iconTint: Color.pink,
            title: "陪伴值",
            subtitle: "衡量你和 Bola 之间亲密程度的数值，0 到 100。互动越多，关系越深。",
            primaryLabel: "下一步",
            primaryAction: onNext,
            middle: {
                VStack(spacing: 14) {
                    // 档位可视化
                    InfoCard {
                        CompanionTierBar()
                    }

                    InfoCard {
                        FeatureRow(
                            icon: "hand.tap.fill",
                            tint: BolaTheme.accent,
                            title: "互动带来积累",
                            desc: "在 Watch 上点击 Bola、发起对话，陪伴值都会增加。"
                        )
                        Divider()
                        FeatureRow(
                            icon: "moon.zzz.fill",
                            tint: .indigo,
                            title: "长时间冷落会下降",
                            desc: "超过一天没有互动，陪伴值会缓慢减少。"
                        )
                        Divider()
                        FeatureRow(
                            icon: "face.smiling.inverse",
                            tint: .orange,
                            title: "影响 Bola 的情绪与表情",
                            desc: "陪伴值越高，Bola 越开心，互动越默契。"
                        )
                    }
                }
            }
        )
    }
}

private struct CompanionTierBar: View {
    private let tiers: [(name: String, range: String, color: Color)] = [
        ("陌生", "0–30", .gray),
        ("朋友", "30–60", .cyan),
        ("伙伴", "60–85", .green),
        ("默契", "85+", BolaTheme.accent),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("陪伴档位")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                ForEach(tiers.indices, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(tiers[i].color.opacity(0.65))
                        .frame(height: 8)
                }
            }

            HStack(spacing: 4) {
                ForEach(tiers.indices, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(tiers[i].name)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(tiers[i].color)
                        Text(tiers[i].range)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

// MARK: - Page 2 成长等级

private struct OnboardingGrowthPage: View {
    let onNext: () -> Void

    var body: some View {
        OnboardingPage(
            icon: "sparkles",
            iconTint: BolaTheme.accent,
            title: "成长与等级",
            subtitle: "完成每日任务获得经验值（XP），积累 XP 提升等级，解锁专属称号。",
            primaryLabel: "下一步",
            primaryAction: onNext,
            middle: {
                VStack(spacing: 14) {
                    InfoCard {
                        GrowthXPPreview()
                    }

                    InfoCard {
                        FeatureRow(
                            icon: "checklist",
                            tint: BolaTheme.accent,
                            title: "每日任务",
                            desc: "走够 6000 步、保持心率稳定、早睡等习惯，每完成一项获得 XP。"
                        )
                        Divider()
                        FeatureRow(
                            icon: "trophy.fill",
                            tint: .orange,
                            title: "等级 1 – 20",
                            desc: "每升一级所需 XP 递增。Lv.20 代表极高的生活一致性。"
                        )
                        Divider()
                        FeatureRow(
                            icon: "tag.fill",
                            tint: .purple,
                            title: "解锁专属称号",
                            desc: "特定等级或里程碑解锁称号词条，组合后展示在 Watch 表盘上。"
                        )
                    }
                }
            }
        )
    }
}

private struct GrowthXPPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Lv.5")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(BolaTheme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(BolaTheme.accent.opacity(0.12))
                    .clipShape(Capsule())
                Text("健康探索者")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer()
                Text("230 / 300 XP")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(uiColor: .tertiarySystemFill))
                        .frame(height: 8)
                    Capsule()
                        .fill(BolaTheme.accent)
                        .frame(width: geo.size.width * 0.77, height: 8)
                }
            }
            .frame(height: 8)
        }
    }
}

// MARK: - Page 3 通知

private struct OnboardingNotifPage: View {
    let status: UNAuthorizationStatus
    let onNext: () -> Void
    let onSkip: () -> Void

    var body: some View {
        OnboardingPage(
            icon: "bell.badge.fill",
            iconTint: .orange,
            title: "通知提醒",
            subtitle: "允许后，Bola 可以提醒你喝水、活动，并发送每日健康总结。",
            primaryLabel: status == .authorized ? "继续" : "允许通知",
            primaryAction: onNext,
            secondaryLabel: "跳过",
            secondaryAction: onSkip,
            middle: {
                InfoCard {
                    FeatureRow(
                        icon: "drop.fill",
                        tint: .blue,
                        title: "喝水与活动提醒",
                        desc: "久坐或未达到活动量时，Bola 会轻推你一下。"
                    )
                    Divider()
                    FeatureRow(
                        icon: "chart.bar.doc.horizontal.fill",
                        tint: BolaTheme.accent,
                        title: "每日健康总结",
                        desc: "每天早上 9 点推送昨日步数、睡眠等数据摘要。"
                    )
                }
            }
        )
    }
}

// MARK: - Page 4 健康数据

private struct OnboardingHealthPage: View {
    let requested: Bool
    let onNext: () -> Void
    let onSkip: () -> Void

    var body: some View {
        OnboardingPage(
            icon: "heart.text.clipboard.fill",
            iconTint: .red,
            title: "健康数据",
            subtitle: "读取 Apple 健康数据，让成长任务和生活页正常运作。数据保留在本机，不会上传。",
            primaryLabel: requested ? "继续" : "允许健康读取",
            primaryAction: onNext,
            secondaryLabel: "跳过",
            secondaryAction: onSkip,
            middle: {
                InfoCard {
                    FeatureRow(
                        icon: "figure.walk",
                        tint: BolaTheme.accent,
                        title: "步数",
                        desc: "用于「走够 6000 步」等每日成长任务。"
                    )
                    Divider()
                    FeatureRow(
                        icon: "flame.fill",
                        tint: .orange,
                        title: "活动能量 & 锻炼时间",
                        desc: "生活页运动卡和活动圆环需要读取此数据。"
                    )
                    Divider()
                    FeatureRow(
                        icon: "waveform.path.ecg",
                        tint: .red,
                        title: "心率 & HRV",
                        desc: "心率过高时 Bola 会有特殊反应；HRV 用于评估恢复状态。"
                    )
                    Divider()
                    FeatureRow(
                        icon: "bed.double.fill",
                        tint: .purple,
                        title: "睡眠",
                        desc: "睡眠时长影响每日精力评分，连续早睡可获得额外 XP。"
                    )
                }
            }
        )
    }
}

// MARK: - Page 5 位置

private struct OnboardingLocationPage: View {
    @ObservedObject var weatherModel: IOSWeatherLocationModel
    let onDone: () -> Void

    private var granted: Bool {
        weatherModel.authorizationStatus == .authorizedAlways ||
            weatherModel.authorizationStatus == .authorizedWhenInUse
    }

    var body: some View {
        OnboardingPage(
            icon: "cloud.sun.fill",
            iconTint: .cyan,
            title: "位置与天气",
            subtitle: "允许位置访问后，生活页会显示你所在地区的实时天气。",
            primaryLabel: granted ? "完成，进入 BolaBola" : "允许位置访问",
            primaryAction: requestAndFinish,
            secondaryLabel: "跳过，直接进入",
            secondaryAction: onDone,
            middle: {
                InfoCard {
                    FeatureRow(
                        icon: "location.fill",
                        tint: .cyan,
                        title: "仅用于天气显示",
                        desc: "只读取当前地区，不记录轨迹，不上传任何位置数据。"
                    )
                }
            }
        )
    }

    private func requestAndFinish() {
        weatherModel.requestAndFetch(requestAuthorizationIfNeeded: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { onDone() }
    }
}
