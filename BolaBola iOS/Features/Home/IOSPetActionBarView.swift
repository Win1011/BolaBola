import SwiftUI

struct IOSPetActionBarView: View {
    @ObservedObject var handler: IOSPetInteractionHandler

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 14) {
                petActionButton(title: "喂食", systemImage: "leaf.fill", tint: .green) {
                    handler.handleFeedButton()
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
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(tint.opacity(0.14))
            )
            .overlay(
                Capsule().stroke(tint.opacity(0.45), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
