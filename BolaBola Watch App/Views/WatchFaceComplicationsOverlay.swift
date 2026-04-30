//
//  WatchFaceComplicationsOverlay.swift
//  在宠物主界面上缘展示与 iPhone 一致的三角落组件（数据在 Bola App 内，非系统表盘）。
//

import SwiftUI

struct WatchFaceComplicationsOverlay: View {
    @ObservedObject var viewModel: PetViewModel
    @State private var slots = WatchFaceSlotsStore.load()
    @State private var titleSelection = BolaTitleSelectionStore.validated()

    private let stickerSlotXInsetFraction: CGFloat = 0.22
    private let stickerSlotTopYFraction: CGFloat = 0.29
    private let stickerSlotBottomYFraction: CGFloat = 0.73
    private let stickerSlotBaseSize: CGFloat = 27

    private var watchTitleConfiguration: TitleBadgeSceneConfiguration {
        TitleBadgeSizing.configuration(for: .realWatch)
    }

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

    private var resolvedTitleText: String {
        titleSelection.resolvedLine()
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                if titleSelection.showsOnWatchFace {
                    titleBadge
                        .position(x: size.width / 2, y: -18)
                }

                ForEach(WatchFaceSlotPosition.allCases, id: \.self) { position in
                    slotMini(position: position)
                        .position(stickerSlotCenter(for: position, in: size))
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(NotificationCenter.default.publisher(for: .bolaWatchHomeScreenPayloadDidUpdate)) { _ in
            slots = WatchFaceSlotsStore.load()
            titleSelection = BolaTitleSelectionStore.validated()
        }
        .onAppear {
            slots = WatchFaceSlotsStore.load()
            titleSelection = BolaTitleSelectionStore.validated()
        }
    }

    private var titleBadge: some View {
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

            Text(resolvedTitleText)
                .font(.system(size: watchTitleConfiguration.fontSize(for: resolvedTitleText), weight: .semibold, design: .rounded))
                .tracking(watchTitleConfiguration.tracking(for: resolvedTitleText))
                .foregroundStyle(titleForegroundColor)
                .lineLimit(1)
                .minimumScaleFactor(watchTitleConfiguration.box.minimumScaleFactor)
                .padding(.horizontal, watchTitleConfiguration.box.horizontalPadding)
                .padding(.vertical, watchTitleConfiguration.box.verticalPadding)
        }
        .frame(
            width: watchTitleConfiguration.box.minWidth,
            height: watchTitleConfiguration.box.height
        )
    }

    private func stickerSlotCenter(for position: WatchFaceSlotPosition, in size: CGSize) -> CGPoint {
        let leftX = size.width * stickerSlotXInsetFraction
        let rightX = size.width * (1 - stickerSlotXInsetFraction)
        let topY = size.height * stickerSlotTopYFraction
        let bottomY = size.height * stickerSlotBottomYFraction

        switch position {
        case .topLeft:
            return CGPoint(x: leftX, y: topY)
        case .bottomLeft:
            return CGPoint(x: leftX, y: bottomY)
        case .bottomRight:
            return CGPoint(x: rightX, y: bottomY)
        }
    }

    private func slotMini(position: WatchFaceSlotPosition) -> some View {
        let kind = slots.kind(at: position)
        let stickerSize = stickerSlotBaseSize * kind.stickerSlotScaleMultiplier

        return Group {
            if kind == .none {
                EmptyView()
            } else if let assetName = kind.stickerAssetName {
                Image(assetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: stickerSize, height: stickerSize)
            } else {
                VStack(spacing: 1) {
                    Image(systemName: symbol(for: kind))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.primary)
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
        }
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
