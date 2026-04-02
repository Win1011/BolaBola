//
//  IOSHealthHabitAnalysisSection.swift
//  分析页「健康习惯」：2×2 方形入口，详情见 IOSHealthHabitDetailViews。
//

import SwiftUI

/// 健康入口：正方形卡片（2 列网格），标题行 + 轻量可视化 + 摘要文案。
struct IOSHealthHubRichCard: View {
    enum Kind {
        case summary
        case activity
        case heart
        case sleep
    }

    let kind: Kind
    @ObservedObject var model: IOSHealthHabitAnalysisModel
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 与「提醒」行一致：大号 SF Symbol + tertiary，不用独立色块/阴影，避免和列表图标两套语言
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: iconName)
                    .font(.title2)
                    .foregroundStyle(BolaTheme.listRowIcon)
                    .symbolRenderingMode(.monochrome)
                    .frame(width: 36, height: 36, alignment: .center)

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.88)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            visualization
                .frame(maxWidth: .infinity)

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(3)
                .minimumScaleFactor(0.78)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .background(
            RoundedRectangle(cornerRadius: BolaTheme.cornerCard, style: .continuous)
                .fill(BolaTheme.surfaceCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: BolaTheme.cornerCard, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.4), lineWidth: 0.5)
        )
        .contentShape(Rectangle())
    }

    private var iconName: String {
        switch kind {
        case .summary: return "chart.pie.fill"
        case .activity: return "figure.walk"
        case .heart: return "heart.fill"
        case .sleep: return "moon.zzz.fill"
        }
    }

    @ViewBuilder
    private var visualization: some View {
        switch kind {
        case .summary:
            IOSHealthHubSummaryVisual(model: model)
        case .activity:
            IOSHealthHubActivityBarsVisual(values: IOSHealthHabitSnapshot.weekStepValuesForBars(model))
        case .heart:
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if let bpm = IOSHealthHabitSnapshot.todayHeartRateValue(model) {
                        Text("\(Int(bpm.rounded()))")
                            .font(.title.weight(.bold))
                            .foregroundStyle(.primary)
                        Text("次/分")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("—")
                            .font(.title.weight(.bold))
                            .foregroundStyle(.secondary)
                        Text("次/分")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                IOSHealthHubHeartSparklineVisual(values: IOSHealthHabitSnapshot.weekHeartValuesForSparkline(model))
            }
        case .sleep:
            IOSHealthHubSleepVisual(hours: IOSHealthHabitSnapshot.todaySleepHoursValue(model))
        }
    }
}

struct IOSHealthHabitAnalysisSection: View {
    @ObservedObject var model: IOSHealthHabitAnalysisModel

    private let gridSpacing: CGFloat = 10

    var body: some View {
        Group {
            if model.authPhase == .ready {
                VStack(alignment: .leading, spacing: 10) {
                    Text("健康习惯")
                        .font(.headline)
                    readyHubGrid
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("健康习惯")
                        .font(.headline)

                    Group {
                        switch model.authPhase {
                        case .idle, .loading:
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                        case .healthUnavailable:
                            Text("此设备无法使用「健康」数据。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        case .needsPrompt:
                            promptBlock
                        case .denied:
                            deniedBlock
                        case .ready:
                            EmptyView()
                        }
                    }
                }
                .padding(BolaTheme.spacingItem)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: BolaTheme.cornerCard, style: .continuous)
                        .fill(BolaTheme.surfaceElevated)
                )
            }
        }
    }

    private var readyHubGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: gridSpacing),
            GridItem(.flexible(), spacing: gridSpacing)
        ]

        return VStack(alignment: .leading, spacing: gridSpacing) {
            if let err = model.fetchError, !err.isEmpty {
                Text(err)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
            if !model.hasAnyChartData {
                Text("近 7 日暂时读不到可用的健康数据。可下拉本页刷新，并检查「隐私与安全性 › 健康」里各分项是否已为 BolaBola 打开。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: columns, spacing: gridSpacing) {
                NavigationLink {
                    IOSHealthSummaryDetailView(model: model)
                } label: {
                    IOSHealthHubRichCard(
                        kind: .summary,
                        model: model,
                        title: "今日摘要",
                        subtitle: IOSHealthHabitSnapshot.summarySubtitle(model)
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    IOSHealthActivityDetailView(model: model)
                } label: {
                    IOSHealthHubRichCard(
                        kind: .activity,
                        model: model,
                        title: "活动与站立",
                        subtitle: IOSHealthHabitSnapshot.activitySubtitle(model)
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    IOSHealthHeartDetailView(model: model)
                } label: {
                    IOSHealthHubRichCard(
                        kind: .heart,
                        model: model,
                        title: "心率",
                        subtitle: IOSHealthHabitSnapshot.heartSubtitle(model)
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    IOSHealthSleepDetailView(model: model)
                } label: {
                    IOSHealthHubRichCard(
                        kind: .sleep,
                        model: model,
                        title: "睡眠节奏",
                        subtitle: IOSHealthHabitSnapshot.sleepSubtitle(model)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var promptBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("查看近 7 天步数、站立时间、心率与睡眠图表，需要读取「健康」数据（非医疗用途）。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                model.requestAccess()
            } label: {
                Text("允许访问健康数据")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(BolaTheme.accent))
                    .foregroundStyle(BolaTheme.onAccentForeground)
            }
            .buttonStyle(.plain)
            Text("若你已在「隐私与安全性 › 健康」里为 BolaBola 打开过读取，但这里仍停在这一步，请点下面按钮加载图表（系统对只读权限常不更新状态）。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Button("我已在系统中开启，加载图表") {
                model.markHealthAccessHandledAndRefresh()
            }
            .font(.subheadline.weight(.medium))
        }
    }

    private var deniedBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("系统不会在「设置 › BolaBola」里显示健康权限。请到「设置 › 隐私与安全性 › 健康」，在应用列表中轻点「BolaBola」，再打开步数、活动、心率、睡眠等读取权限。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("下方按钮只会打开本 App 的系统页（通知等），健康开关仍需按上面路径进入。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Button("打开 BolaBola 设置") {
                model.openAppSettings()
            }
            .font(.subheadline.weight(.semibold))
        }
    }
}
