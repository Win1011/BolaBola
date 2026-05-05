import SwiftUI

struct IOSPetActionBarView: View {
    @ObservedObject var handler: IOSPetInteractionHandler
    @Binding var companion: Double

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 20) {
                petActionButton(title: "喂食", systemImage: "leaf.fill", tint: .green) {
                    handler.handleFeedButton(companion: &companion)
                }
                petActionButton(title: "喝水", systemImage: "drop.fill", tint: .blue) {
                    handler.handleDrinkButton()
                }
                petActionButton(title: "睡觉", systemImage: "moon.zzz.fill", tint: .purple) {
                    handler.handleSleepButton()
                }
            }
            .frame(maxWidth: .infinity)

            if let text = handler.actionToastText {
                Text(text)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.25), value: handler.actionToastText)
            }
        }
    }

    private func petActionButton(title: String, systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.06), radius: 9, y: 4)
                Circle()
                    .stroke(BolaTheme.accent, lineWidth: 1.5)
                VStack(spacing: 3) {
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(tint)
                    Text(title)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.primary)
                }
            }
            .frame(width: 52, height: 52)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}
