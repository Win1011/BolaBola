//
//  IOSStatusView.swift
//  状态：HealthKit 习惯与图表（原分析页健康部分）。
//

import SwiftUI

struct IOSStatusView: View {
    @StateObject private var healthHabits = IOSHealthHabitAnalysisModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BolaTheme.spacingSection) {
                IOSHealthHabitAnalysisSection(model: healthHabits)
            }
            .padding(.horizontal, BolaTheme.paddingHorizontal)
            .padding(.top, 0)
            .padding(.bottom, 24)
        }
        .refreshable {
            await healthHabits.refresh()
        }
        .task {
            await healthHabits.refresh()
        }
        .background(BolaTheme.backgroundGrouped)
    }
}
