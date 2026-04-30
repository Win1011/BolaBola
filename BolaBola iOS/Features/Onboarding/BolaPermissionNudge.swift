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
                .presentationDetents([.height(380)])
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
        NavigationStack {
            VStack(spacing: 18) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.black.opacity(0.78))
                    .padding(12)
                    .background(
                        Circle()
                            .fill(BolaTheme.accent.opacity(0.82))
                    )

                Text(title)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)

                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if !features.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(features) { f in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: f.icon)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.black.opacity(0.78))
                                    .padding(8)
                                    .background(Circle().fill(BolaTheme.accent.opacity(0.82)))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(f.title)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.primary)
                                    Text(f.desc)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: BolaTheme.cornerCard, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    )
                }

                Button(primaryLabel, action: primaryAction)
                    .buttonStyle(.borderedProminent)
                    .tint(BolaTheme.accent)
                    .foregroundStyle(Color.black)

                Button { dismiss() } label: {
                    Text(secondaryLabel)
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .background(
                ZStack {
                    BolaTheme.backgroundGrouped
                    LinearGradient(
                        colors: [
                            BolaTheme.accent.opacity(BolaTheme.accentGlowTopOpacity),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: UnitPoint(x: 0.5, y: 0.42)
                    )
                }
                .overlay(alignment: .top) {
                    Circle()
                        .fill(RadialGradient(
                            colors: [
                                BolaTheme.accent.opacity(0.36),
                                BolaTheme.accent.opacity(0.19),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 40,
                            endRadius: 196
                        ))
                        .frame(width: 392, height: 392)
                        .blur(radius: 18)
                        .offset(y: -130)
                        .allowsHitTesting(false)
                }
                .overlay(alignment: .bottom) {
                    Circle()
                        .fill(RadialGradient(
                            colors: [
                                BolaTheme.accent.opacity(0.36),
                                BolaTheme.accent.opacity(0.19),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 40,
                            endRadius: 127
                        ))
                        .frame(width: 254, height: 254)
                        .blur(radius: 9)
                        .offset(y: 100)
                        .allowsHitTesting(false)
                }
                .ignoresSafeArea()
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}

// MARK: - View Extension

extension View {
    func bolaLocationNudgeOnFirstAppear(weatherModel: IOSWeatherLocationModel) -> some View {
        modifier(BolaLocationNudgeModifier(weatherModel: weatherModel))
    }
}
