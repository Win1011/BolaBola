//
//  WatchFaceComplicationsOverlay.swift
//  在宠物主界面上缘展示与 iPhone 一致的三角落组件（数据在 Bola App 内，非系统表盘）。
//

import SwiftUI

struct WatchFaceComplicationsOverlay: View {
    @ObservedObject var viewModel: PetViewModel
    @State private var slots = WatchFaceSlotsStore.load()

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                slotMini(position: .topLeft)
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
            HStack(alignment: .bottom) {
                slotMini(position: .bottomLeft)
                Spacer(minLength: 0)
                slotMini(position: .bottomRight)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 3)
        .padding(.top, 2)
        .onReceive(NotificationCenter.default.publisher(for: .bolaWatchHomeScreenPayloadDidUpdate)) { _ in
            slots = WatchFaceSlotsStore.load()
        }
        .onAppear {
            slots = WatchFaceSlotsStore.load()
        }
    }

    private func slotMini(position: WatchFaceSlotPosition) -> some View {
        let kind = slots.kind(at: position)
        return VStack(spacing: 1) {
            Image(systemName: symbol(for: kind))
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(kind == .none ? Color.secondary.opacity(0.35) : Color.primary)
            Text(valueLine(for: kind))
                .font(.system(size: 7, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .frame(minWidth: 28)
        .padding(.vertical, 2)
        .padding(.horizontal, 2)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }

    private func symbol(for kind: WatchFaceComplicationKind) -> String {
        switch kind {
        case .none: return "circle.dotted"
        case .heartRate: return "heart.fill"
        case .weather: return "cloud.sun.fill"
        case .steps: return "figure.walk"
        case .stickerApple: return "apple.logo"
        case .stickerBottle: return "waterbottle.fill"
        case .stickerHeart: return "heart.circle.fill"
        case .stickerBola: return "face.smiling.inverse"
        case .stickerBadge: return "seal.fill"
        }
    }

    private func valueLine(for kind: WatchFaceComplicationKind) -> String {
        switch kind {
        case .none: return " "
        case .heartRate: return viewModel.latestHeartRateText
        case .weather: return "—"
        case .steps: return "—"
        case .stickerApple, .stickerBottle, .stickerHeart, .stickerBola, .stickerBadge:
            return " "
        }
    }
}
