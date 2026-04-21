//
//  BolaPermissionNudge.swift
//  Tab 首次进入时触发的位置权限补充说明 sheet（onboarding 跳过后）。
//

import CoreLocation
import SwiftUI

// MARK: - Key 常量

enum BolaPermissionNudgeKeys {
    static let locationTabNudgeDone = "bola_location_tab_nudge_v1"
}

// MARK: - 位置权限 Nudge（生活 tab）

struct BolaLocationNudgeModifier: ViewModifier {
    @AppStorage(BolaPermissionNudgeKeys.locationTabNudgeDone)
    private var locationNudgeDone: Bool = false

    @ObservedObject var weatherModel: IOSWeatherLocationModel

    @State private var showSheet = false

    private var locationGranted: Bool {
        weatherModel.authorizationStatus == .authorizedAlways ||
            weatherModel.authorizationStatus == .authorizedWhenInUse
    }

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard !locationNudgeDone, !locationGranted else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    if !locationNudgeDone, !locationGranted {
                        showSheet = true
                    }
                }
            }
            .sheet(isPresented: $showSheet) {
                BolaPermissionNudgeSheet(
                    icon: "cloud.sun.fill",
                    iconTint: .cyan,
                    title: "需要位置权限",
                    subtitle: "开启后，生活页可以显示你所在地区的实时天气信息。",
                    features: [
                        .init(icon: "location.fill", tint: .cyan, title: "仅用于天气", desc: "只读取当前所在地区，不记录轨迹，不上传任何数据。"),
                    ],
                    primaryLabel: "允许位置访问",
                    primaryAction: requestLocation,
                    secondaryLabel: "稍后再说"
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
            }
    }

    private func requestLocation() {
        locationNudgeDone = true
        showSheet = false
        weatherModel.requestAndFetch(requestAuthorizationIfNeeded: true)
    }
}

// MARK: - 通用 Nudge Sheet UI

struct BolaPermissionNudgeSheet: View {
    struct Feature: Identifiable {
        let id = UUID()
        let icon: String
        let tint: Color
        let title: String
        let desc: String
    }

    let icon: String
    let iconTint: Color
    let title: String
    let subtitle: String
    let features: [Feature]
    let primaryLabel: String
    let primaryAction: () -> Void
    let secondaryLabel: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule()
                .fill(Color(uiColor: .tertiaryLabel))
                .frame(width: 36, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
                .padding(.bottom, 20)

            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(iconTint.opacity(0.13))
                        .frame(width: 56, height: 56)
                    Image(systemName: icon)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(iconTint)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, BolaTheme.paddingHorizontal)
            .padding(.bottom, 20)

            if !features.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(features) { f in
                        HStack(alignment: .top, spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(f.tint.opacity(0.13))
                                    .frame(width: 36, height: 36)
                                Image(systemName: f.icon)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(f.tint)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(f.title)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.primary)
                                Text(f.desc)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                                    .lineSpacing(3)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.vertical, 10)
                        if f.id != features.last?.id {
                            Divider().padding(.leading, 50)
                        }
                    }
                }
                .padding(.horizontal, BolaTheme.paddingHorizontal)
                .padding(.vertical, 4)
                .background(BolaTheme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: BolaTheme.cornerCard, style: .continuous))
                .padding(.horizontal, BolaTheme.paddingHorizontal)
                .padding(.bottom, 24)
            }

            Spacer(minLength: 0)

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
                Button { dismiss() } label: {
                    Text(secondaryLabel)
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }
                .frame(height: 36)
            }
            .padding(.horizontal, BolaTheme.paddingHorizontal)
            .padding(.bottom, 20)
        }
    }
}

// MARK: - View Extension

extension View {
    func bolaLocationNudgeOnFirstAppear(weatherModel: IOSWeatherLocationModel) -> some View {
        modifier(BolaLocationNudgeModifier(weatherModel: weatherModel))
    }
}
