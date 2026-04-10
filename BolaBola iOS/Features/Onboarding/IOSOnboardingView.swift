//
//  IOSOnboardingView.swift
//

import CoreLocation
import HealthKit
import SwiftUI
import UserNotifications

struct IOSOnboardingView: View {
    var onDone: () -> Void

    @State private var stepIndex = 0
    @StateObject private var weatherModel = IOSWeatherLocationModel()
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var healthRequested = false

    private let healthStore = HKHealthStore()

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                TabView(selection: $stepIndex) {
                    page(
                        title: "欢迎来到 BolaBola",
                        body: "先用 4 步把基础权限和体验准备好。所有权限都可以先跳过，之后也能在设置里补。",
                        primaryTitle: "开始",
                        primaryAction: { stepIndex = 1 },
                        secondaryTitle: "稍后再说",
                        secondaryAction: finishOnboarding
                    )
                    .tag(0)

                    page(
                        title: "通知权限",
                        body: "打开后，Bola 才能提醒你喝水、活动和查看每日总结。",
                        primaryTitle: notificationStatus == .authorized ? "继续" : "允许通知",
                        primaryAction: requestNotifications,
                        secondaryTitle: "跳过",
                        secondaryAction: { stepIndex = 2 }
                    )
                    .tag(1)

                    page(
                        title: "健康数据",
                        body: "开启后，成长任务和生活页才能读取步数、心率、睡眠等健康信息。",
                        primaryTitle: healthRequested ? "继续" : "允许健康读取",
                        primaryAction: requestHealthAccess,
                        secondaryTitle: "跳过",
                        secondaryAction: { stepIndex = 3 }
                    )
                    .tag(2)

                    page(
                        title: "位置与天气",
                        body: "开启后，生活页可以显示你当前所在地区的天气信息。",
                        primaryTitle: locationPrimaryTitle,
                        primaryAction: requestLocationAccess,
                        secondaryTitle: "完成",
                        secondaryAction: finishOnboarding
                    )
                    .tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
            }
            .padding(.vertical, 20)
            .navigationBarHidden(true)
        }
        .task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            notificationStatus = settings.authorizationStatus
        }
    }

    @ViewBuilder
    private func page(
        title: String,
        body: String,
        primaryTitle: String,
        primaryAction: @escaping () -> Void,
        secondaryTitle: String,
        secondaryAction: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            Text(title)
                .font(.system(size: 30, weight: .bold))
            Text(body)
                .font(.body)
                .foregroundStyle(.secondary)
                .lineSpacing(4)
            Spacer()
            Button(primaryTitle, action: primaryAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            Button(secondaryTitle, action: secondaryAction)
                .buttonStyle(.bordered)
                .controlSize(.large)
        }
        .padding(.horizontal, BolaTheme.paddingHorizontal)
    }

    private var locationPrimaryTitle: String {
        switch weatherModel.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return "继续"
        default:
            return "允许位置"
        }
    }

    private func requestNotifications() {
        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            await MainActor.run {
                notificationStatus = settings.authorizationStatus
                stepIndex = 2
            }
        }
    }

    private func requestHealthAccess() {
        guard HKHealthStore.isHealthDataAvailable() else {
            stepIndex = 3
            return
        }
        var types = Set<HKObjectType>()
        if let t = HKQuantityType.quantityType(forIdentifier: .stepCount) { types.insert(t) }
        if let t = HKQuantityType.quantityType(forIdentifier: .heartRate) { types.insert(t) }
        if let t = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) { types.insert(t) }
        if let t = HKQuantityType.quantityType(forIdentifier: .appleStandTime) { types.insert(t) }
        if let t = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { types.insert(t) }

        healthStore.requestAuthorization(toShare: [], read: types) { _, _ in
            DispatchQueue.main.async {
                healthRequested = true
                UserDefaults.standard.set(true, forKey: IOSHealthHabitAnalysisModel.healthReadPromptCompletedKey)
                stepIndex = 3
            }
        }
    }

    private func requestLocationAccess() {
        weatherModel.requestAndFetch(requestAuthorizationIfNeeded: true)
        if weatherModel.authorizationStatus == .authorizedAlways || weatherModel.authorizationStatus == .authorizedWhenInUse {
            finishOnboarding()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                finishOnboarding()
            }
        }
    }

    private func finishOnboarding() {
        BolaOnboardingState.markCompleted()
        onDone()
    }
}
