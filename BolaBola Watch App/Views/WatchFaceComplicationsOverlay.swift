//
//  WatchFaceComplicationsOverlay.swift
//  在宠物主界面上缘展示与 iPhone 一致的三角落组件（数据在 Bola App 内，非系统表盘）。
//

import SwiftUI

struct WatchFaceComplicationsOverlay: View {
    @ObservedObject var viewModel: PetViewModel
    @State private var slots = WatchFaceSlotsStore.load()
    @State private var titleSelection = BolaTitleSelectionStore.validated()
    private let watchTitleScale: CGFloat = 0.96

    private var selectedTitleFrame: TitleFrameDefinition {
        TitleFrameBank.frame(id: titleSelection.frameId)
            ?? TitleFrameBank.frame(id: TitleFrameBank.fallbackFrameId)
            ?? TitleFrameBank.all[0]
    }

    private var titleForegroundColor: Color {
        switch selectedTitleFrame.assetName {
        case "TitleFrame0to5":
            return Color.black.opacity(0.68)
        case "TitleFrame5to10":
            return Color(red: 254 / 255, green: 214 / 255, blue: 189 / 255)
        default:
            return .white.opacity(0.9)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if titleSelection.showsOnWatchFace {
                ZStack {
                    if let assetName = selectedTitleFrame.assetName {
                        Image(assetName)
                            .resizable()
                            .scaledToFit()
                    } else {
                        Capsule()
                            .fill(Color.black.opacity(0.12))
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.12), lineWidth: 0.6)
                            )
                    }

                    Text(titleSelection.resolvedLine())
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(titleForegroundColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.48)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 2)
                }
                .frame(width: 116, height: 27)
                .scaleEffect(watchTitleScale)
                .offset(y: -10)
                .padding(.top, 2)
            }

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
            titleSelection = BolaTitleSelectionStore.validated()
        }
        .onAppear {
            slots = WatchFaceSlotsStore.load()
            titleSelection = BolaTitleSelectionStore.validated()
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
