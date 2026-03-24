//
//  IOSAPISettingsPage.swift
//

import SwiftUI

struct IOSAPISettingsPage: View {
    var body: some View {
        ScrollView {
            IOSLLMSettingsSection()
                .padding(.horizontal, BolaTheme.paddingHorizontal)
                .padding(.vertical, 12)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("对话 API")
        .navigationBarTitleDisplayMode(.inline)
    }
}
